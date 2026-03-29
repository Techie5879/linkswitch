import Foundation

/// Discovers Zen **container** identities from `containers.json` on the active profile.
///
/// This is intentionally separate from `BrowserProfileDiscoveryFactory`'s Firefox-family
/// `profiles.ini` path: for Zen, user-facing routing is usually by container, not by the
/// underlying Firefox-style profile directory most operators ignore.
enum ZenContainerDiscoveryError: Error, Equatable {
    case profilesIniNotFound(URL)
    case noProfiles(URL)
    case containersNotFound(URL)
    case containersReadFailed(URL, String)
    case containersDecodingFailed(URL, String)
}

struct ZenContainerDiscovery: BrowserProfileDiscovering {
    private struct RegistryProfile {
        let path: String
        let isDefault: Bool
    }

    private struct ContainersDocument: Decodable {
        struct Identity: Decodable {
            let name: String?
            let l10nId: String?
            let userContextId: Int
            let `public`: Bool?
        }

        let identities: [Identity]
    }

    private let appSupportURL: URL

    init(appSupportURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        self.appSupportURL = appSupportURL
    }

    func discoverProfiles() throws -> [BrowserProfile] {
        let zenRootURL = appSupportURL.appendingPathComponent("zen", isDirectory: true)
        let profilesIniURL = zenRootURL.appendingPathComponent("profiles.ini")
        let installsIniURL = zenRootURL.appendingPathComponent("installs.ini")

        AppLogger.info(
            "ZenContainerDiscovery reading profile registry from \(profilesIniURL.path(percentEncoded: false))",
            category: .app
        )

        guard FileManager.default.fileExists(atPath: profilesIniURL.path(percentEncoded: false)) else {
            AppLogger.error(
                "ZenContainerDiscovery profiles.ini not found at \(profilesIniURL.path(percentEncoded: false))",
                category: .app
            )
            throw ZenContainerDiscoveryError.profilesIniNotFound(profilesIniURL)
        }

        let profilesRaw = try String(contentsOf: profilesIniURL, encoding: .utf8)
        let profiles = parseProfilesIni(profilesRaw)
        guard !profiles.isEmpty else {
            AppLogger.error(
                "ZenContainerDiscovery found no profiles in \(profilesIniURL.path(percentEncoded: false))",
                category: .app
            )
            throw ZenContainerDiscoveryError.noProfiles(profilesIniURL)
        }

        let activeProfilePath =
            resolveInstalledDefaultProfilePath(from: installsIniURL)
            ?? profiles.first(where: \.isDefault)?.path
            ?? profiles[0].path

        let activeProfileURL: URL
        if activeProfilePath.hasPrefix("/") {
            activeProfileURL = URL(fileURLWithPath: activeProfilePath, isDirectory: true)
        } else {
            activeProfileURL = zenRootURL.appendingPathComponent(activeProfilePath, isDirectory: true)
        }

        let containersURL = activeProfileURL
            .appendingPathComponent("containers.json")

        AppLogger.info(
            "ZenContainerDiscovery reading containers from \(containersURL.path(percentEncoded: false))",
            category: .app
        )

        guard FileManager.default.fileExists(atPath: containersURL.path(percentEncoded: false)) else {
            AppLogger.error(
                "ZenContainerDiscovery containers.json not found at \(containersURL.path(percentEncoded: false))",
                category: .app
            )
            throw ZenContainerDiscoveryError.containersNotFound(containersURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: containersURL)
        } catch {
            AppLogger.error(
                "ZenContainerDiscovery failed to read containers.json at \(containersURL.path(percentEncoded: false)): \(error)",
                category: .app
            )
            throw ZenContainerDiscoveryError.containersReadFailed(containersURL, String(describing: error))
        }

        let document: ContainersDocument
        do {
            document = try JSONDecoder().decode(ContainersDocument.self, from: data)
        } catch {
            AppLogger.error(
                "ZenContainerDiscovery failed to decode containers.json at \(containersURL.path(percentEncoded: false)): \(error)",
                category: .app
            )
            throw ZenContainerDiscoveryError.containersDecodingFailed(containersURL, String(describing: error))
        }

        var seenNames = Set<String>()
        let containers = document.identities.compactMap { identity -> BrowserProfile? in
            guard identity.public == true else {
                return nil
            }
            guard let displayName = resolveDisplayName(for: identity), !displayName.isEmpty else {
                AppLogger.error(
                    "ZenContainerDiscovery could not resolve a display name for public container userContextId=\(identity.userContextId)",
                    category: .app
                )
                return nil
            }
            guard seenNames.insert(displayName).inserted else {
                return nil
            }
            return BrowserProfile(profileKey: displayName, displayName: displayName)
        }

        AppLogger.info(
            "ZenContainerDiscovery found \(containers.count) container(s): \(containers.map(\.displayName).joined(separator: ", "))",
            category: .app
        )

        return containers
    }

    private func resolveInstalledDefaultProfilePath(from installsIniURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: installsIniURL.path(percentEncoded: false)),
              let raw = try? String(contentsOf: installsIniURL, encoding: .utf8)
        else {
            return nil
        }

        for section in parseIniSections(raw) {
            if let profilePath = section["Default"], !profilePath.isEmpty {
                return profilePath
            }
        }

        return nil
    }

    private func parseProfilesIni(_ content: String) -> [RegistryProfile] {
        parseIniSections(content).compactMap { section in
            guard let sectionName = section["__section__"],
                  sectionName.lowercased().hasPrefix("profile"),
                  sectionName.dropFirst("profile".count).allSatisfy(\.isNumber),
                  let path = section["Path"],
                  !path.isEmpty
            else {
                return nil
            }

            return RegistryProfile(path: path, isDefault: section["Default"] == "1")
        }
    }

    private func parseIniSections(_ content: String) -> [[String: String]] {
        var results: [[String: String]] = []
        var currentSection: String?
        var currentKeys: [String: String] = [:]

        func flushSection() {
            guard let currentSection else {
                return
            }
            currentKeys["__section__"] = currentSection
            results.append(currentKeys)
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flushSection()
                currentSection = String(line.dropFirst().dropLast())
                currentKeys = [:]
                continue
            }

            if let eqRange = line.range(of: "=") {
                let key = String(line[line.startIndex..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                currentKeys[key] = value
            }
        }

        flushSection()
        return results
    }

    private func resolveDisplayName(for identity: ContainersDocument.Identity) -> String? {
        if let name = identity.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        switch identity.l10nId {
        case "user-context-personal":
            return "Personal"
        case "user-context-work":
            return "Work"
        case "user-context-banking":
            return "Banking"
        case "user-context-shopping":
            return "Shopping"
        default:
            return nil
        }
    }
}
