import AppKit
import UniformTypeIdentifiers

// MARK: - CardView

/// A rounded, bordered container view that respects the system appearance for its border colour.
private final class CardView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

// MARK: - FlippedView

/// An NSView subclass with a flipped coordinate system so the scroll view's
/// content starts at the top and extends downward.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - PreferencesViewController

@MainActor
final class PreferencesViewController: NSViewController {
    private enum StatusStyle {
        case normal
        case warning
        case error
    }

    // Tags used in the fallback browser popup to distinguish item kinds.
    private enum PopupItemTag: Int {
        /// A discovered browser: the tag value is its index in model.discoveredBrowsers.
        /// Discovered items use non-negative tags matching their index.
        case otherBrowser = -2
        case customCurrentBrowser = -1
    }

    private static let preferredContentSize = NSSize(width: 820, height: 680)

    private let model: PreferencesModel
    private let iconProvider = AppIconProvider()

    // MARK: Fallback browser card controls
    private let fallbackBrowserIconView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let fallbackBrowserNameLabel = NSTextField(labelWithString: "")
    private let fallbackBrowserBundleLabel = NSTextField(labelWithString: "")
    private let fallbackBrowserPopup = NSPopUpButton()

    // MARK: Handler status card controls
    private let handlerStatusImageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let handlerPrimaryLabel = NSTextField(labelWithString: "")
    private let handlerSecondaryLabel = NSTextField(wrappingLabelWithString: "")

    private lazy var registerHandlerButton: NSButton = makeButton(
        title: "Set LinkSwitch as HTTP/HTTPS Handler",
        action: #selector(registerLinkSwitchAsDefaultHandler(_:)),
        accessibilityIdentifier: "preferences.registerHandlerButton"
    )

    private lazy var setFallbackAsDefaultHandlerButton: NSButton = makeButton(
        title: "Set Fallback Browser as Default Handler",
        action: #selector(setFallbackBrowserAsDefaultHandler(_:)),
        accessibilityIdentifier: "preferences.setFallbackAsDefaultHandlerButton"
    )

    // MARK: Misc controls
    private let configPathLabel = NSTextField(wrappingLabelWithString: "")
    private let sampleURLField = NSTextField(string: "")
    private let rulesStackView = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    // MARK: Init

    init(model: PreferencesModel) throws {
        self.model = model
        try model.load()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View lifecycle

    override func loadView() {
        view = NSView(
            frame: NSRect(origin: .zero, size: Self.preferredContentSize)
        )
        configureView()
        refreshUI()
    }

    func configureWindow(_ window: NSWindow) {
        window.title = "LinkSwitch"
        window.center()
        window.setContentSize(Self.preferredContentSize)
        window.minSize = NSSize(width: 700, height: 520)
    }

    // MARK: Layout construction

    private func configureView() {
        let scrollView = makeScrollView()
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let rootStack = makeRootStack()
        documentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            // Pin document view width to the clip view width — vertical-only scroll.
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            // Root stack fills the document view with inset margins.
            rootStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
        ])

        return scrollView
    }

    private func makeRootStack() -> NSStackView {
        // Router config header
        let headerStack = makeHeaderSection()

        // Two-column cards row
        let topCardsRow = makeTopCardsRow()

        // Rules section
        let rulesSectionHeader = makeRulesSectionHeader()

        rulesStackView.orientation = .vertical
        rulesStackView.alignment = .leading
        rulesStackView.spacing = 10
        rulesStackView.translatesAutoresizingMaskIntoConstraints = false

        // Footer
        let footer = makeFooter()

        let rootStack = NSStackView(views: [headerStack, topCardsRow, rulesSectionHeader, rulesStackView, footer])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 20

        // These children must fill the full stack width.
        NSLayoutConstraint.activate([
            topCardsRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            rulesSectionHeader.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            rulesStackView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
        ])

        return rootStack
    }

    private func makeHeaderSection() -> NSStackView {
        let titleLabel = makeSectionLabel("Router Config")

        configPathLabel.maximumNumberOfLines = 0
        configPathLabel.textColor = .secondaryLabelColor
        configPathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [titleLabel, configPathLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func makeTopCardsRow() -> NSStackView {
        let fallbackCard = makeFallbackBrowserCard()
        let handlerCard = makeHandlerStatusCard()

        let row = NSStackView(views: [fallbackCard, handlerCard])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 16
        return row
    }

    // MARK: Fallback browser card

    private func makeFallbackBrowserCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeSectionLabel("Fallback Browser")

        // 48×48 icon
        fallbackBrowserIconView.setContentHuggingPriority(.required, for: .horizontal)
        fallbackBrowserIconView.setContentHuggingPriority(.required, for: .vertical)
        fallbackBrowserIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        fallbackBrowserNameLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        fallbackBrowserNameLabel.lineBreakMode = .byTruncatingMiddle

        fallbackBrowserBundleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        fallbackBrowserBundleLabel.textColor = .secondaryLabelColor
        fallbackBrowserBundleLabel.lineBreakMode = .byTruncatingMiddle

        let nameStack = NSStackView(views: [fallbackBrowserNameLabel, fallbackBrowserBundleLabel])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 2

        let browserInfoRow = NSStackView(views: [fallbackBrowserIconView, nameStack])
        browserInfoRow.orientation = .horizontal
        browserInfoRow.alignment = .centerY
        browserInfoRow.spacing = 12

        fallbackBrowserPopup.target = self
        fallbackBrowserPopup.action = #selector(fallbackBrowserPopupChanged(_:))
        fallbackBrowserPopup.setAccessibilityIdentifier("preferences.fallbackBrowserPopup")

        let testButton = makeButton(
            title: "Test",
            action: #selector(testFallbackBrowser(_:)),
            accessibilityIdentifier: "preferences.testFallbackBrowserButton"
        )

        let actionsRow = NSStackView(views: [fallbackBrowserPopup, testButton])
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 8

        let contentStack = NSStackView(views: [titleLabel, browserInfoRow, actionsRow])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12

        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            fallbackBrowserIconView.widthAnchor.constraint(equalToConstant: 48),
            fallbackBrowserIconView.heightAnchor.constraint(equalToConstant: 48),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            fallbackBrowserPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        return card
    }

    // MARK: Handler status card

    private func makeHandlerStatusCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeSectionLabel("URL Handler Status")

        handlerPrimaryLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        handlerPrimaryLabel.textColor = .labelColor

        handlerSecondaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        handlerSecondaryLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [handlerPrimaryLabel, handlerSecondaryLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let statusRow = NSStackView(views: [handlerStatusImageView, textStack])
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.orientation = .horizontal
        statusRow.alignment = .top
        statusRow.spacing = 12

        let buttonsStack = NSStackView(views: [registerHandlerButton, setFallbackAsDefaultHandlerButton])
        buttonsStack.orientation = .vertical
        buttonsStack.alignment = .leading
        buttonsStack.spacing = 8

        let contentStack = NSStackView(views: [titleLabel, statusRow, buttonsStack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12

        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            handlerStatusImageView.widthAnchor.constraint(equalToConstant: 32),
            handlerStatusImageView.heightAnchor.constraint(equalToConstant: 32),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        return card
    }

    // MARK: Rules section header

    private func makeRulesSectionHeader() -> NSStackView {
        let titleLabel = makeSectionLabel("Source-App Rules")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let addButton = makeButton(
            title: "+ Add Rule",
            action: #selector(addRule(_:)),
            accessibilityIdentifier: "preferences.addRuleButton"
        )

        let row = NSStackView(views: [titleLabel, spacer, addButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    // MARK: Footer

    private func makeFooter() -> NSStackView {
        let urlLabel = NSTextField(labelWithString: "Test URL")
        urlLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        sampleURLField.target = self
        sampleURLField.action = #selector(sampleURLChanged(_:))
        sampleURLField.placeholderString = "https://example.com"
        sampleURLField.setAccessibilityIdentifier("preferences.sampleURLField")

        let urlRow = NSStackView(views: [urlLabel, sampleURLField])
        urlRow.orientation = .horizontal
        urlRow.alignment = .centerY
        urlRow.spacing = 8
        urlRow.distribution = .fill

        let reloadButton = makeButton(
            title: "Reload",
            action: #selector(reloadPreferences(_:)),
            accessibilityIdentifier: "preferences.reloadButton"
        )
        let saveButton = makeButton(
            title: "Save",
            action: #selector(savePreferences(_:)),
            accessibilityIdentifier: "preferences.saveButton"
        )

        statusLabel.maximumNumberOfLines = 0
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actionsRow = NSStackView(views: [reloadButton, saveButton, spacer, statusLabel])
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 12

        let footer = NSStackView(views: [urlRow, actionsRow])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 12

        // Both rows fill the footer width.
        NSLayoutConstraint.activate([
            urlRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
            actionsRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
        ])

        return footer
    }

    // MARK: refreshUI

    private func refreshUI() {
        configPathLabel.stringValue = "Config file: \(model.configFileURLDescription)"
        sampleURLField.stringValue = model.sampleURLString

        refreshFallbackBrowserDisplay()
        refreshFallbackBrowserPopup()
        refreshHandlerStatusDisplay()

        refreshRules()
    }

    private func refreshHandlerStatusDisplay() {
        let selfBundleID = Bundle.main.bundleIdentifier
        let httpID = model.currentHandlerBundleID(forURLScheme: "http")
        let httpsID = model.currentHandlerBundleID(forURLScheme: "https")
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)

        let linkSwitchIsDefault =
            selfBundleID != nil && httpID == selfBundleID && httpsID == selfBundleID

        AppLogger.info(
            "Handler status refresh: linkSwitchIsDefault=\(linkSwitchIsDefault) http=\(httpID ?? "nil") https=\(httpsID ?? "nil")",
            category: .app
        )

        if linkSwitchIsDefault {
            if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
                handlerStatusImageView.image = img.withSymbolConfiguration(symbolConfig)
            }
            handlerStatusImageView.contentTintColor = .systemGreen
            handlerPrimaryLabel.stringValue = "LinkSwitch is the default web browser"
            handlerSecondaryLabel.stringValue = "Handles http and https links."
            registerHandlerButton.isHidden = true
            setFallbackAsDefaultHandlerButton.isHidden = false
            let hasFallback = model.fallbackBrowserAppURL != nil && !model.fallbackBrowserBundleID.isEmpty
            let fallbackAlreadyDefault =
                (httpID == model.fallbackBrowserBundleID && httpsID == model.fallbackBrowserBundleID)
            setFallbackAsDefaultHandlerButton.isEnabled = hasFallback && !fallbackAlreadyDefault
        } else {
            if let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
                handlerStatusImageView.image = img.withSymbolConfiguration(symbolConfig)
            }
            handlerStatusImageView.contentTintColor = .systemOrange
            handlerPrimaryLabel.stringValue = "LinkSwitch is not the default handler"
            if let h = httpID, let s = httpsID, h != s {
                handlerSecondaryLabel.stringValue =
                    "http and https point to different apps. Set LinkSwitch below to route links through LinkSwitch."
            } else {
                handlerSecondaryLabel.stringValue =
                    "Set LinkSwitch as the default handler to open links through LinkSwitch."
            }
            registerHandlerButton.isHidden = false
            setFallbackAsDefaultHandlerButton.isHidden = true
        }
    }

    private func refreshFallbackBrowserDisplay() {
        if let appURL = model.fallbackBrowserAppURL {
            fallbackBrowserIconView.image = iconProvider.icon(forAppURL: appURL)
            // Derive display name: try the discovered list first, then the bundle, then the filename.
            if let discovered = model.discoveredBrowsers.first(where: { $0.bundleID == model.fallbackBrowserBundleID }) {
                fallbackBrowserNameLabel.stringValue = discovered.name
            } else if let name = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
                fallbackBrowserNameLabel.stringValue = name
            } else {
                fallbackBrowserNameLabel.stringValue = appURL.deletingPathExtension().lastPathComponent
            }
            fallbackBrowserBundleLabel.stringValue = model.fallbackBrowserBundleID
        } else {
            fallbackBrowserIconView.image = NSImage(named: NSImage.applicationIconName)
            fallbackBrowserNameLabel.stringValue = "No browser selected"
            fallbackBrowserBundleLabel.stringValue = "Choose a fallback browser below"
        }
    }

    private func refreshFallbackBrowserPopup() {
        fallbackBrowserPopup.removeAllItems()

        let discovered = model.discoveredBrowsers
        let currentBundleID = model.fallbackBrowserBundleID
        let currentAppURL = model.fallbackBrowserAppURL
        let isCurrentInDiscovered = discovered.contains { $0.bundleID == currentBundleID }

        // If the currently-configured browser is not in the discovered list, show it as a
        // special first entry so the user can see what is selected.
        if !isCurrentInDiscovered && !currentBundleID.isEmpty, let appURL = currentAppURL {
            let icon = iconProvider.icon(forAppURL: appURL)
            let name: String
            if let displayName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                              ?? Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
                name = displayName
            } else {
                name = appURL.deletingPathExtension().lastPathComponent
            }
            let item = makePopupMenuItem(title: "\(name) (custom)", icon: icon, tag: PopupItemTag.customCurrentBrowser.rawValue)
            fallbackBrowserPopup.menu?.addItem(item)
            fallbackBrowserPopup.menu?.addItem(.separator())
        }

        // Discovered browsers
        for (index, browser) in discovered.enumerated() {
            let icon = iconProvider.icon(forAppURL: browser.appURL)
            let item = makePopupMenuItem(title: browser.name, icon: icon, tag: index)
            fallbackBrowserPopup.menu?.addItem(item)
        }

        // "Other…" to pick manually
        fallbackBrowserPopup.menu?.addItem(.separator())
        let otherItem = NSMenuItem(title: "Other…", action: nil, keyEquivalent: "")
        otherItem.tag = PopupItemTag.otherBrowser.rawValue
        fallbackBrowserPopup.menu?.addItem(otherItem)

        // Select the current browser in the popup
        if isCurrentInDiscovered, let index = discovered.firstIndex(where: { $0.bundleID == currentBundleID }) {
            fallbackBrowserPopup.selectItem(withTag: index)
        } else if !currentBundleID.isEmpty {
            fallbackBrowserPopup.selectItem(withTag: PopupItemTag.customCurrentBrowser.rawValue)
        }
    }

    private func refreshRules() {
        rulesStackView.arrangedSubviews.forEach { view in
            rulesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if model.ruleDrafts.isEmpty {
            let emptyLabel = NSTextField(wrappingLabelWithString: "No source-app rules configured yet. Add one to route a sender such as Slack to Helium.")
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
            rulesStackView.addArrangedSubview(emptyLabel)
            return
        }

        for draft in model.ruleDrafts {
            let row = PreferencesRuleRowView(
                draft: draft,
                discoveredApplications: model.discoveredApplications,
                iconProvider: iconProvider,
                fallbackBrowserAppURL: model.fallbackBrowserAppURL,
                onSourceBundleIDChange: { [weak self] value in
                    self?.model.updateRuleSourceBundleID(id: draft.id, value: value)
                },
                onSourcePickerNeedsUIRefresh: { [weak self] in
                    self?.refreshUI()
                },
                onTargetKindChange: { [weak self] targetKind in
                    self?.model.updateRuleTargetKind(id: draft.id, targetKind: targetKind)
                    self?.refreshUI()
                },
                onHeliumProfileDirectoryChange: { [weak self] value in
                    self?.model.updateRuleHeliumProfileDirectory(id: draft.id, value: value)
                },
                onRemove: { [weak self] in
                    self?.model.removeRule(id: draft.id)
                    self?.refreshUI()
                    self?.setStatus("Removed rule.")
                },
                onTest: { [weak self] in
                    self?.testRule(id: draft.id)
                }
            )
            rulesStackView.addArrangedSubview(row)
        }
    }

    // MARK: Actions

    @objc private func fallbackBrowserPopupChanged(_ sender: Any?) {
        guard let tag = fallbackBrowserPopup.selectedItem?.tag else { return }

        if tag == PopupItemTag.otherBrowser.rawValue {
            // Reset the popup to the previously selected item before opening the panel,
            // so the display doesn't jump to "Other…" while the panel is open.
            refreshFallbackBrowserPopup()
            chooseFallbackBrowserFromPanel()
        } else if tag == PopupItemTag.customCurrentBrowser.rawValue {
            // Already current; nothing to do.
        } else if tag >= 0 && tag < model.discoveredBrowsers.count {
            let browser = model.discoveredBrowsers[tag]
            AppLogger.info("Fallback browser changed to \(browser.bundleID) via popup", category: .app)
            model.setFallbackBrowser(discoveredBrowser: browser)
            refreshFallbackBrowserDisplay()
            refreshHandlerStatusDisplay()
        }
    }

    private func chooseFallbackBrowserFromPanel() {
        guard let hostWindow = view.window else {
            AppLogger.error("Preferences browser picker requested without a host window", category: .app)
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the fallback browser app."

        panel.beginSheetModal(for: hostWindow) { [weak self] response in
            guard response == .OK, let applicationURL = panel.url else { return }
            do {
                try self?.model.setFallbackBrowser(applicationURL: applicationURL)
                self?.refreshUI()
                self?.setStatus("Selected fallback browser at \(applicationURL.path()).")
            } catch {
                self?.presentPreferencesError(error, message: "Could not use the selected browser app.")
            }
        }
    }

    @objc private func addRule(_ sender: Any?) {
        _ = model.addRule()
        refreshUI()
        setStatus("Added new rule.")
    }

    @objc private func reloadPreferences(_ sender: Any?) {
        do {
            try model.load()
            iconProvider.clearCache()
            refreshUI()
            setStatus("Reloaded preferences from disk.")
        } catch {
            presentPreferencesError(error, message: "Could not reload the router config.")
        }
    }

    @objc private func savePreferences(_ sender: Any?) {
        syncSampleURLField()
        do {
            try model.save()
            setStatus("Saved router config to disk.")
        } catch {
            presentPreferencesError(error, message: "Could not save the router config.")
        }
    }

    @objc private func testFallbackBrowser(_ sender: Any?) {
        syncSampleURLField()
        Task { @MainActor [weak self] in
            do {
                try await self?.model.testFallbackBrowser()
                self?.setStatus("Opened the sample URL in the fallback browser.")
            } catch {
                self?.presentPreferencesError(error, message: "Could not test the fallback browser launch.")
            }
        }
    }

    @objc private func sampleURLChanged(_ sender: Any?) {
        syncSampleURLField()
    }

    @objc private func registerLinkSwitchAsDefaultHandler(_ sender: Any?) {
        let applicationURL = Bundle.main.bundleURL

        Task { @MainActor [weak self] in
            do {
                let result = try await self?.model.registerLinkSwitchAsDefaultHandler(applicationURL: applicationURL)
                self?.refreshUI()
                switch result {
                case .registered:
                    self?.setStatus("Registered LinkSwitch as the default handler for http and https.")
                case .alreadyRegistered:
                    self?.setStatus(
                        "LinkSwitch is already the current handler for http and https.",
                        style: .warning
                    )
                case nil:
                    break
                }
            } catch {
                self?.presentPreferencesError(error, message: "Could not register LinkSwitch as the default handler.")
            }
        }
    }

    @objc private func setFallbackBrowserAsDefaultHandler(_ sender: Any?) {
        AppLogger.info("User requested setting fallback browser as default http/https handler", category: .app)
        Task { @MainActor [weak self] in
            do {
                let result = try await self?.model.registerFallbackBrowserAsDefaultHandler()
                self?.refreshUI()
                switch result {
                case .registered:
                    self?.setStatus("Set the fallback browser as the default handler for http and https.")
                case .alreadyRegistered:
                    self?.setStatus(
                        "The fallback browser is already the default handler for http and https.",
                        style: .warning
                    )
                case nil:
                    break
                }
            } catch {
                self?.presentPreferencesError(
                    error,
                    message: "Could not set the fallback browser as the default handler."
                )
            }
        }
    }

    private func testRule(id: UUID) {
        syncSampleURLField()
        Task { @MainActor [weak self] in
            do {
                try await self?.model.testRule(id: id)
                self?.setStatus("Opened the sample URL with rule.")
            } catch {
                self?.presentPreferencesError(error, message: "Could not test the selected rule.")
            }
        }
    }

    // MARK: Helpers

    private func syncSampleURLField() {
        model.sampleURLString = sampleURLField.stringValue
    }

    private func setStatus(_ message: String, style: StatusStyle = .normal) {
        statusLabel.stringValue = message
        switch style {
        case .normal:
            statusLabel.textColor = .secondaryLabelColor
        case .warning:
            statusLabel.textColor = .systemYellow
        case .error:
            statusLabel.textColor = .systemRed
        }
    }

    private func presentPreferencesError(_ error: Error, message: String) {
        AppLogger.error("\(message) \(error)", category: .app)
        setStatus(message, style: .error)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        if let hostWindow = view.window {
            alert.beginSheetModal(for: hostWindow)
        } else {
            alert.runModal()
        }
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        return label
    }

    private func makeButton(title: String, action: Selector, accessibilityIdentifier: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        return button
    }

    private func makePopupMenuItem(title: String, icon: NSImage, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menuIcon = icon.copy() as! NSImage
        menuIcon.size = NSSize(width: 16, height: 16)
        item.image = menuIcon
        item.tag = tag
        return item
    }
}

// MARK: - PreferencesRuleRowView

@MainActor
private final class PreferencesRuleRowView: NSView, NSTextFieldDelegate {
    private enum SourcePopupTag {
        static let selectPlaceholder = -999
        static let customBundleID = -998
        static let chooseFromFinder = -997
        static let enterBundleIDManually = -996
    }

    private let sourceAppPopUpButton: NSPopUpButton
    private let manualBundleIDField: NSTextField
    private let manualBundleIDLabel: NSTextField
    private let manualBundleIDStack: NSStackView
    private let sourceIconView: NSImageView
    private let targetKindPopupButton: NSPopUpButton
    private let targetIconView: NSImageView
    private let heliumProfileDirectoryField: NSTextField
    private let profileContainerView: NSStackView

    private let draft: PreferencesRuleDraft
    private let discoveredApplications: [DiscoveredApplication]
    private let iconProvider: AppIconProvider
    private var fallbackBrowserAppURL: URL?

    private let onSourceBundleIDChange: (String) -> Void
    private let onSourcePickerNeedsUIRefresh: () -> Void
    private let onTargetKindChange: (PreferencesRuleTargetKind) -> Void
    private let onHeliumProfileDirectoryChange: (String) -> Void
    private let onRemove: () -> Void
    private let onTest: () -> Void

    private var iconUpdateTimer: Timer?
    /// Tracks the latest source bundle ID (model may update without row reload).
    private var lastAppliedSourceBundleID: String

    init(
        draft: PreferencesRuleDraft,
        discoveredApplications: [DiscoveredApplication],
        iconProvider: AppIconProvider,
        fallbackBrowserAppURL: URL?,
        onSourceBundleIDChange: @escaping (String) -> Void,
        onSourcePickerNeedsUIRefresh: @escaping () -> Void,
        onTargetKindChange: @escaping (PreferencesRuleTargetKind) -> Void,
        onHeliumProfileDirectoryChange: @escaping (String) -> Void,
        onRemove: @escaping () -> Void,
        onTest: @escaping () -> Void
    ) {
        self.draft = draft
        self.discoveredApplications = discoveredApplications
        self.iconProvider = iconProvider
        self.fallbackBrowserAppURL = fallbackBrowserAppURL
        self.onSourceBundleIDChange = onSourceBundleIDChange
        self.onSourcePickerNeedsUIRefresh = onSourcePickerNeedsUIRefresh
        self.onTargetKindChange = onTargetKindChange
        self.onHeliumProfileDirectoryChange = onHeliumProfileDirectoryChange
        self.onRemove = onRemove
        self.onTest = onTest

        lastAppliedSourceBundleID = draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        sourceAppPopUpButton = NSPopUpButton()
        manualBundleIDField = NSTextField(string: draft.sourceBundleID)
        manualBundleIDLabel = NSTextField(labelWithString: "Bundle ID:")
        manualBundleIDLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        manualBundleIDLabel.textColor = .secondaryLabelColor

        targetKindPopupButton = NSPopUpButton()
        heliumProfileDirectoryField = NSTextField(string: draft.heliumProfileDirectory)

        sourceIconView = Self.makeIconView(size: 32)
        targetIconView = Self.makeIconView(size: 32)

        profileContainerView = NSStackView()

        let manualRow = NSStackView(views: [manualBundleIDLabel, manualBundleIDField])
        manualRow.orientation = .horizontal
        manualRow.alignment = .centerY
        manualRow.spacing = 8
        manualBundleIDStack = NSStackView(views: [manualRow])
        manualBundleIDStack.orientation = .vertical
        manualBundleIDStack.alignment = .leading

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        buildLayout(draft: draft)
        populateSourceMenu()
        applyManualFieldVisibilityForInitialState()
        updateSourceIcon(bundleID: draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines))
        updateTargetIcon(targetKind: draft.targetKind)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    // MARK: Source app menu

    private func populateSourceMenu() {
        sourceAppPopUpButton.removeAllItems()
        guard let menu = sourceAppPopUpButton.menu else { return }

        let placeholder = NSMenuItem(title: "Select source app…", action: nil, keyEquivalent: "")
        placeholder.tag = SourcePopupTag.selectPlaceholder
        menu.addItem(placeholder)

        let trimmed = draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchIndex = discoveredApplications.firstIndex(where: { $0.bundleID == trimmed })

        if !trimmed.isEmpty, matchIndex == nil {
            let custom = NSMenuItem(title: "Custom: \(trimmed)", action: nil, keyEquivalent: "")
            custom.tag = SourcePopupTag.customBundleID
            menu.addItem(custom)
        }

        for (index, app) in discoveredApplications.enumerated() {
            let icon = iconProvider.icon(forAppURL: app.appURL)
            let item = Self.makeMenuItem(title: app.name, icon: icon, tag: index)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let finderItem = NSMenuItem(title: "Choose from Finder…", action: nil, keyEquivalent: "")
        finderItem.tag = SourcePopupTag.chooseFromFinder
        menu.addItem(finderItem)

        let manualItem = NSMenuItem(title: "Enter bundle ID manually…", action: nil, keyEquivalent: "")
        manualItem.tag = SourcePopupTag.enterBundleIDManually
        menu.addItem(manualItem)

        if let idx = matchIndex {
            sourceAppPopUpButton.selectItem(withTag: idx)
        } else if !trimmed.isEmpty {
            sourceAppPopUpButton.selectItem(withTag: SourcePopupTag.customBundleID)
        } else {
            sourceAppPopUpButton.selectItem(withTag: SourcePopupTag.selectPlaceholder)
        }
    }

    private func applyManualFieldVisibilityForInitialState() {
        let trimmed = draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let inList = discoveredApplications.contains(where: { $0.bundleID == trimmed })
        manualBundleIDField.stringValue = trimmed
        manualBundleIDStack.isHidden = trimmed.isEmpty || inList
    }

    private static func makeMenuItem(title: String, icon: NSImage, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menuIcon = icon.copy() as! NSImage
        menuIcon.size = NSSize(width: 16, height: 16)
        item.image = menuIcon
        item.tag = tag
        return item
    }

    // MARK: Layout

    private func buildLayout(draft: PreferencesRuleDraft) {
        sourceAppPopUpButton.target = self
        sourceAppPopUpButton.action = #selector(sourcePopupChanged(_:))
        sourceAppPopUpButton.setAccessibilityIdentifier("preferences.rule.sourceAppPopup")

        manualBundleIDField.placeholderString = "com.example.SourceApp"
        manualBundleIDField.delegate = self
        manualBundleIDField.setAccessibilityIdentifier("preferences.rule.sourceBundleIDField")

        let sourcePickerRow = NSStackView(views: [sourceIconView, sourceAppPopUpButton])
        sourcePickerRow.orientation = .horizontal
        sourcePickerRow.alignment = .centerY
        sourcePickerRow.spacing = 8

        let sourceLabelRow = NSStackView(views: [NSTextField(labelWithString: "Source App")])
        (sourceLabelRow.arrangedSubviews[0] as? NSTextField)?.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        (sourceLabelRow.arrangedSubviews[0] as? NSTextField)?.textColor = .secondaryLabelColor

        // Arrow (only on the picker row, aligned with icon + popup rows — not with section titles)
        let arrowLabel = NSTextField(labelWithString: "→")
        arrowLabel.font = .systemFont(ofSize: 20, weight: .light)
        arrowLabel.textColor = .tertiaryLabelColor
        arrowLabel.setContentHuggingPriority(.required, for: .horizontal)
        arrowLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Target section: [icon] [popup button]
        targetKindPopupButton.addItems(withTitles: PreferencesRuleTargetKind.allCases.map(\.displayName))
        targetKindPopupButton.selectItem(at: draft.targetKind == .fallbackBrowser ? 0 : 1)
        targetKindPopupButton.target = self
        targetKindPopupButton.action = #selector(targetKindChanged(_:))
        targetKindPopupButton.setAccessibilityIdentifier("preferences.rule.targetKindPopup")
        updateTargetPopupIcons()

        let targetPickerRow = NSStackView(views: [targetIconView, targetKindPopupButton])
        targetPickerRow.orientation = .horizontal
        targetPickerRow.alignment = .centerY
        targetPickerRow.spacing = 8

        heliumProfileDirectoryField.placeholderString = "Profile directory name"
        heliumProfileDirectoryField.delegate = self
        heliumProfileDirectoryField.setAccessibilityIdentifier("preferences.rule.heliumProfileField")

        let profileLabel = NSTextField(labelWithString: "Profile:")
        profileContainerView.orientation = .horizontal
        profileContainerView.alignment = .centerY
        profileContainerView.spacing = 6
        profileContainerView.addArrangedSubview(profileLabel)
        profileContainerView.addArrangedSubview(heliumProfileDirectoryField)
        profileContainerView.isHidden = draft.targetKind != .helium

        let targetLabelRow = NSStackView(views: [NSTextField(labelWithString: "Routes To")])
        (targetLabelRow.arrangedSubviews[0] as? NSTextField)?.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        (targetLabelRow.arrangedSubviews[0] as? NSTextField)?.textColor = .secondaryLabelColor

        // Three-row grid so labels sit above the arrow column and the arrow aligns with the picker row.
        let arrowColumnWidth: CGFloat = 28
        let arrowColumnTopSpacer = NSView()
        arrowColumnTopSpacer.translatesAutoresizingMaskIntoConstraints = false
        let arrowColumnBottomSpacer = NSView()
        arrowColumnBottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arrowColumnTopSpacer.widthAnchor.constraint(equalToConstant: arrowColumnWidth),
            arrowColumnBottomSpacer.widthAnchor.constraint(equalToConstant: arrowColumnWidth),
        ])

        let labelsRow = NSStackView(views: [sourceLabelRow, arrowColumnTopSpacer, targetLabelRow])
        labelsRow.orientation = .horizontal
        labelsRow.alignment = .centerY
        labelsRow.spacing = 16

        let pickerRow = NSStackView(views: [sourcePickerRow, arrowLabel, targetPickerRow])
        pickerRow.orientation = .horizontal
        pickerRow.alignment = .centerY
        pickerRow.spacing = 16

        let bottomRow = NSStackView(views: [manualBundleIDStack, arrowColumnBottomSpacer, profileContainerView])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 16

        let contentColumn = NSStackView(views: [labelsRow, pickerRow, bottomRow])
        contentColumn.orientation = .vertical
        contentColumn.alignment = .leading
        contentColumn.spacing = 4

        // Action buttons (right-aligned)
        let testButton = NSButton(title: "Test Rule", target: self, action: #selector(testRule(_:)))
        testButton.bezelStyle = .rounded
        testButton.setAccessibilityIdentifier("preferences.rule.testButton")

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeRule(_:)))
        removeButton.bezelStyle = .rounded
        removeButton.setAccessibilityIdentifier("preferences.rule.removeButton")

        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonsRow = NSStackView(views: [buttonSpacer, testButton, removeButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.spacing = 8

        let rootStack = NSStackView(views: [contentColumn, buttonsRow])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12

        addSubview(rootStack)

        // Both rows fill the card width.
        NSLayoutConstraint.activate([
            contentColumn.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            buttonsRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
        ])
        NSLayoutConstraint.activate([
            sourceIconView.widthAnchor.constraint(equalToConstant: 32),
            sourceIconView.heightAnchor.constraint(equalToConstant: 32),
            targetIconView.widthAnchor.constraint(equalToConstant: 32),
            targetIconView.heightAnchor.constraint(equalToConstant: 32),
            sourceAppPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            manualBundleIDField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            heliumProfileDirectoryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    // MARK: Icon helpers

    private static func makeIconView(size: CGFloat) -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentHuggingPriority(.required, for: .vertical)
        return iv
    }

    private func updateSourceIcon(bundleID: String) {
        if bundleID.isEmpty {
            sourceIconView.image = NSImage(named: NSImage.applicationIconName)
            return
        }
        sourceIconView.image = iconProvider.icon(forBundleID: bundleID)
    }

    private func updateTargetIcon(targetKind: PreferencesRuleTargetKind) {
        switch targetKind {
        case .fallbackBrowser:
            if let appURL = fallbackBrowserAppURL {
                targetIconView.image = iconProvider.icon(forAppURL: appURL)
            } else {
                targetIconView.image = NSImage(named: NSImage.applicationIconName)
            }
        case .helium:
            targetIconView.image = iconProvider.icon(forBundleID: BrowserLauncher.heliumBundleID)
        }
    }

    private func updateTargetPopupIcons() {
        guard let menu = targetKindPopupButton.menu else { return }
        let kinds = PreferencesRuleTargetKind.allCases
        for (index, item) in menu.items.enumerated() where index < kinds.count {
            let kind = kinds[index]
            let icon: NSImage
            switch kind {
            case .fallbackBrowser:
                if let appURL = fallbackBrowserAppURL {
                    icon = iconProvider.icon(forAppURL: appURL)
                } else {
                    icon = NSImage(named: NSImage.applicationIconName) ?? NSImage()
                }
            case .helium:
                icon = iconProvider.icon(forBundleID: BrowserLauncher.heliumBundleID)
            }
            let menuIcon = icon.copy() as! NSImage
            menuIcon.size = NSSize(width: 16, height: 16)
            item.image = menuIcon
        }
    }

    // MARK: Actions

    @objc private func sourcePopupChanged(_ sender: NSPopUpButton) {
        guard let tag = sender.selectedItem?.tag else { return }

        if tag == SourcePopupTag.selectPlaceholder {
            return
        }

        if tag == SourcePopupTag.chooseFromFinder {
            populateSourceMenu()
            chooseSourceAppFromFinder()
            return
        }

        if tag == SourcePopupTag.enterBundleIDManually {
            manualBundleIDStack.isHidden = false
            manualBundleIDField.stringValue = lastAppliedSourceBundleID
            window?.makeFirstResponder(manualBundleIDField)
            AppLogger.info("Source rule row: manual bundle ID entry shown", category: .app)
            return
        }

        if tag == SourcePopupTag.customBundleID {
            manualBundleIDStack.isHidden = false
            return
        }

        if tag >= 0, tag < discoveredApplications.count {
            let app = discoveredApplications[tag]
            manualBundleIDStack.isHidden = true
            lastAppliedSourceBundleID = app.bundleID
            onSourceBundleIDChange(app.bundleID)
            updateSourceIcon(bundleID: app.bundleID)
            AppLogger.info("Source rule row: selected installed app \(app.bundleID) (\(app.name))", category: .app)
        }
    }

    private func chooseSourceAppFromFinder() {
        guard let hostWindow = window else {
            AppLogger.error("Choose source app from Finder requested without a host window", category: .app)
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the source application for this rule."

        panel.beginSheetModal(for: hostWindow) { [weak self] response in
            guard let self else { return }
            if response == .OK, let applicationURL = panel.url {
                guard let bundleID = Bundle(url: applicationURL)?.bundleIdentifier, !bundleID.isEmpty else {
                    AppLogger.error("Selected source app did not expose a bundle ID: \(applicationURL.path())", category: .app)
                    self.populateSourceMenu()
                    return
                }
                self.onSourceBundleIDChange(bundleID)
                self.onSourcePickerNeedsUIRefresh()
                AppLogger.info("Source rule row: set source app from Finder to \(bundleID)", category: .app)
            } else {
                self.populateSourceMenu()
                AppLogger.debug("Choose source app from Finder cancelled; restored menu selection", category: .app)
            }
        }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        if textField === manualBundleIDField {
            let bundleID = textField.stringValue
            lastAppliedSourceBundleID = bundleID
            onSourceBundleIDChange(bundleID)

            iconUpdateTimer?.invalidate()
            iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.updateSourceIcon(bundleID: bundleID.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else if textField === heliumProfileDirectoryField {
            onHeliumProfileDirectoryChange(textField.stringValue)
        }
    }

    @objc private func targetKindChanged(_ sender: Any?) {
        let targetKind: PreferencesRuleTargetKind = targetKindPopupButton.indexOfSelectedItem == 0 ? .fallbackBrowser : .helium
        profileContainerView.isHidden = targetKind != .helium
        updateTargetIcon(targetKind: targetKind)
        onTargetKindChange(targetKind)
    }

    @objc private func removeRule(_ sender: Any?) {
        onRemove()
    }

    @objc private func testRule(_ sender: Any?) {
        onTest()
    }
}

// MARK: - PreferencesRuleTargetKind display names

private extension PreferencesRuleTargetKind {
    var displayName: String {
        switch self {
        case .fallbackBrowser: return "Fallback Browser"
        case .helium: return "Helium"
        }
    }
}
