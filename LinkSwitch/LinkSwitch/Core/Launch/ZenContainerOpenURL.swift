import Foundation

enum ZenContainerOpenURLError: Error, Equatable {
    case emptyContainerName
    case encodingFailed(String)
    case invalidOpenURL(String)
}

struct ZenContainerOpenURL {
    private static let allowedQueryValueCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-._~")
    )

    static func make(url: URL, containerName: String) throws -> URL {
        let trimmedName = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            AppLogger.error("ZenContainerOpenURL requires a non-empty container name", category: .launch)
            throw ZenContainerOpenURLError.emptyContainerName
        }

        guard let encodedName = encodeQueryValue(trimmedName) else {
            AppLogger.error("ZenContainerOpenURL could not percent-encode container name \(trimmedName)", category: .launch)
            throw ZenContainerOpenURLError.encodingFailed(trimmedName)
        }
        guard let encodedURL = encodeQueryValue(url.absoluteString) else {
            AppLogger.error("ZenContainerOpenURL could not percent-encode nested URL \(url.absoluteString)", category: .launch)
            throw ZenContainerOpenURLError.encodingFailed(url.absoluteString)
        }
        let rawURL = "ext+container:name=\(encodedName)&url=\(encodedURL)"

        guard let containerURL = URL(string: rawURL) else {
            AppLogger.error("ZenContainerOpenURL could not build a valid ext+container URL from \(rawURL)", category: .launch)
            throw ZenContainerOpenURLError.invalidOpenURL(rawURL)
        }

        AppLogger.info(
            "ZenContainerOpenURL built \(containerURL.absoluteString) for container \(trimmedName)",
            category: .launch
        )
        return containerURL
    }

    private static func encodeQueryValue(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: allowedQueryValueCharacters)
    }
}
