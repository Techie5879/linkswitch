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

// MARK: - ProfileCardButton

/// A lightweight selectable card used for browser profile choices.
private final class ProfileCardButton: NSButton {
    var isSelectedCard = false {
        didSet {
            updateAppearance()
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        lineBreakMode = .byTruncatingTail
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 20, height: max(28, base.height + 8))
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    private func updateAppearance() {
        let textColor: NSColor
        if isSelectedCard {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1
            textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            textColor = .secondaryLabelColor
        }
        layer?.cornerRadius = 10
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: isSelectedCard ? .semibold : .medium),
                .foregroundColor: textColor,
            ]
        )
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
        case success
        case warning
        case error
    }

    // Tags used in the default browser popup to distinguish item kinds.
    private enum PopupItemTag: Int {
        /// A discovered browser: the tag value is its index in model.discoveredBrowsers.
        /// Discovered items use non-negative tags matching their index.
        case otherBrowser = -2
        case customCurrentBrowser = -1
    }

    private static let preferredContentSize = NSSize(width: 820, height: 760)

    private let model: PreferencesModel
    private let iconProvider = AppIconProvider()

    // MARK: Default browser card controls
    private let defaultBrowserIconView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let defaultBrowserPopup = DefaultBrowserAccessibilityPopUpButton()

    private let defaultProfileSectionLabel = NSTextField(labelWithString: "Profile")
    private let defaultProfileCardsStack = NSStackView()
    private let defaultProfileDiscoveryErrorLabel = NSTextField(labelWithString: "")
    private let defaultProfileContainerView = NSStackView()
    private var defaultBrowserDisplayedProfiles: [BrowserProfile] = []

    // MARK: Handler status card controls
    private let handlerStatusImageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let handlerPrimaryLabel = NSTextField(labelWithString: "")
    private let handlerSecondaryLabel = NSTextField(wrappingLabelWithString: "")
    private let openAtLoginStatusLabel = NSTextField(wrappingLabelWithString: "")

    private lazy var openAtLoginCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Open LinkSwitch at login", target: self, action: #selector(toggleOpenAtLogin(_:)))
        button.setAccessibilityIdentifier("preferences.openAtLoginCheckbox")
        return button
    }()

    private lazy var registerHandlerButton: NSButton = makeButton(
        title: "Set LinkSwitch as HTTP/HTTPS Handler",
        action: #selector(registerLinkSwitchAsDefaultHandler(_:)),
        accessibilityIdentifier: "preferences.registerHandlerButton"
    )

    private lazy var setDefaultBrowserAsDefaultHandlerButton: NSButton = makeButton(
        title: "Set Default Browser as HTTP/HTTPS Handler",
        action: #selector(setDefaultBrowserAsDefaultHandler(_:)),
        accessibilityIdentifier: "preferences.setDefaultBrowserAsDefaultHandlerButton"
    )

    private lazy var reloadButton: NSButton = makeButton(
        title: "Reload",
        action: #selector(reloadPreferences(_:)),
        accessibilityIdentifier: "preferences.reloadButton"
    )

    private lazy var saveButton: NSButton = makeButton(
        title: "Save",
        action: #selector(savePreferences(_:)),
        accessibilityIdentifier: "preferences.saveButton"
    )

    private lazy var openLoginItemsSettingsButton: NSButton = makeButton(
        title: "Open Login Items Settings",
        action: #selector(openLoginItemsSettings(_:)),
        accessibilityIdentifier: "preferences.openLoginItemsSettingsButton"
    )

    // MARK: Misc controls
    private let configPathLabel = NSTextField(wrappingLabelWithString: "")
    private let sampleURLField = NSTextField(string: "")
    private let rulesStackView = NSStackView()
    private let rulesInfoLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let rawConfigCard = CardView()
    private let rawConfigValidationLabel = NSTextField(wrappingLabelWithString: "")
    private let rawConfigContentStack = NSStackView()
    private let rawConfigScrollView = NSScrollView()
    private let rawConfigTextView = NSTextView()
    private var isRawConfigExpanded = false
    private var autoSaveTimer: Timer?
    private var lastSaveTimestamp: Date?
    private var saveBadgeCooldownTimer: Timer?

    private static let saveTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    private lazy var toggleRawConfigButton: NSButton = makeButton(
        title: "View Raw Config",
        action: #selector(toggleRawConfigVisibility(_:)),
        accessibilityIdentifier: "preferences.toggleRawConfigButton"
    )

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
        window.minSize = NSSize(width: 700, height: 480)
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
        let rawConfigCard = makeRawConfigCard()

        let rootStack = NSStackView(views: [headerStack, topCardsRow, rulesSectionHeader, rulesStackView, footer, rawConfigCard])
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
            rawConfigCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
        ])

        return rootStack
    }

    private func makeHeaderSection() -> NSStackView {
        let titleLabel = makeSectionLabel("Router Config")
        let stack = NSStackView(views: [titleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func makeTopCardsRow() -> NSStackView {
        let defaultCard = makeDefaultBrowserCard()
        let handlerCard = makeHandlerStatusCard()

        let row = NSStackView(views: [defaultCard, handlerCard])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 16
        return row
    }

    // MARK: Default browser card

    private func makeDefaultBrowserCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeSectionLabel("Default Browser")

        defaultBrowserIconView.setContentHuggingPriority(.required, for: .horizontal)
        defaultBrowserIconView.setContentHuggingPriority(.required, for: .vertical)
        defaultBrowserIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        defaultBrowserPopup.target = self
        defaultBrowserPopup.action = #selector(defaultBrowserPopupChanged(_:))

        let testButton = makeButton(
            title: "Test",
            action: #selector(testDefaultBrowser(_:)),
            accessibilityIdentifier: "preferences.testDefaultBrowserButton"
        )

        let actionsRow = NSStackView(views: [defaultBrowserIconView, defaultBrowserPopup, testButton])
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 8

        defaultProfileSectionLabel.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        defaultProfileSectionLabel.textColor = .secondaryLabelColor

        defaultProfileCardsStack.orientation = .horizontal
        defaultProfileCardsStack.alignment = .centerY
        defaultProfileCardsStack.spacing = 8
        defaultProfileCardsStack.setAccessibilityIdentifier("preferences.defaultBrowser.profileCardsStack")

        defaultProfileDiscoveryErrorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        defaultProfileDiscoveryErrorLabel.textColor = .systemOrange
        defaultProfileDiscoveryErrorLabel.isHidden = true

        defaultProfileContainerView.orientation = .vertical
        defaultProfileContainerView.alignment = .leading
        defaultProfileContainerView.spacing = 6
        defaultProfileContainerView.addArrangedSubview(defaultProfileSectionLabel)
        defaultProfileContainerView.addArrangedSubview(defaultProfileCardsStack)
        defaultProfileContainerView.addArrangedSubview(defaultProfileDiscoveryErrorLabel)
        defaultProfileContainerView.isHidden = true

        let contentStack = NSStackView(views: [titleLabel, actionsRow, defaultProfileContainerView])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12

        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            defaultBrowserIconView.widthAnchor.constraint(equalToConstant: 24),
            defaultBrowserIconView.heightAnchor.constraint(equalToConstant: 24),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            defaultBrowserPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            defaultProfileCardsStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
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

        let buttonsStack = NSStackView(views: [registerHandlerButton, setDefaultBrowserAsDefaultHandlerButton])
        buttonsStack.orientation = .vertical
        buttonsStack.alignment = .leading
        buttonsStack.spacing = 8

        openAtLoginStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        openAtLoginStatusLabel.textColor = .secondaryLabelColor
        openAtLoginStatusLabel.maximumNumberOfLines = 0

        let openAtLoginSection = NSStackView(views: [openAtLoginCheckbox, openAtLoginStatusLabel, openLoginItemsSettingsButton])
        openAtLoginSection.orientation = .vertical
        openAtLoginSection.alignment = .leading
        openAtLoginSection.spacing = 8

        let contentStack = NSStackView(views: [titleLabel, statusRow, buttonsStack, openAtLoginSection])
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
        rulesInfoLabel.maximumNumberOfLines = 0
        rulesInfoLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        rulesInfoLabel.textColor = .secondaryLabelColor
        rulesInfoLabel.setAccessibilityIdentifier("preferences.rulesInfoLabel")

        let titleStack = NSStackView(views: [titleLabel, rulesInfoLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleStack, spacer, reloadButton, saveButton])
        row.orientation = .horizontal
        row.alignment = .top
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

        statusLabel.maximumNumberOfLines = 0
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let footer = NSStackView(views: [urlRow, statusLabel])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 12

        NSLayoutConstraint.activate([
            urlRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: footer.widthAnchor),
        ])

        return footer
    }

    private func makeRawConfigCard() -> NSView {
        rawConfigCard.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeSectionLabel("Raw Config")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerRow = NSStackView(views: [titleLabel, spacer, toggleRawConfigButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        configPathLabel.maximumNumberOfLines = 0
        configPathLabel.textColor = .secondaryLabelColor
        configPathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        rawConfigValidationLabel.maximumNumberOfLines = 0
        rawConfigValidationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        rawConfigTextView.isEditable = false
        rawConfigTextView.isSelectable = true
        rawConfigTextView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        rawConfigTextView.textColor = .textColor
        rawConfigTextView.backgroundColor = .textBackgroundColor
        rawConfigTextView.isVerticallyResizable = true
        rawConfigTextView.isHorizontallyResizable = true
        rawConfigTextView.autoresizingMask = [.width]
        rawConfigTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        rawConfigTextView.textContainer?.widthTracksTextView = false
        rawConfigTextView.setAccessibilityIdentifier("preferences.rawConfigTextView")

        rawConfigScrollView.translatesAutoresizingMaskIntoConstraints = false
        rawConfigScrollView.hasVerticalScroller = true
        rawConfigScrollView.hasHorizontalScroller = true
        rawConfigScrollView.autohidesScrollers = true
        rawConfigScrollView.borderType = .bezelBorder
        rawConfigScrollView.documentView = rawConfigTextView

        rawConfigContentStack.orientation = .vertical
        rawConfigContentStack.alignment = .leading
        rawConfigContentStack.spacing = 12
        rawConfigContentStack.addArrangedSubview(rawConfigValidationLabel)
        rawConfigContentStack.addArrangedSubview(rawConfigScrollView)

        let contentStack = NSStackView(views: [headerRow, configPathLabel, rawConfigContentStack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8

        rawConfigCard.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rawConfigCard.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: rawConfigCard.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: rawConfigCard.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: rawConfigCard.bottomAnchor, constant: -16),
            headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            configPathLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            rawConfigContentStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            rawConfigValidationLabel.widthAnchor.constraint(equalTo: rawConfigContentStack.widthAnchor),
            rawConfigScrollView.widthAnchor.constraint(equalTo: rawConfigContentStack.widthAnchor),
            rawConfigScrollView.heightAnchor.constraint(equalToConstant: 280),
        ])

        refreshRawConfigVisibility()
        return rawConfigCard
    }

    // MARK: refreshUI

    private func refreshUI() {
        configPathLabel.stringValue = "Config file: \(model.configFileURLDescription)"
        sampleURLField.stringValue = model.sampleURLString

        refreshDefaultBrowserDisplay()
        refreshDefaultBrowserPopup()
        refreshDefaultProfileBrowserSection()
        refreshHandlerStatusDisplay()
        refreshOpenAtLoginDisplay()

        refreshRules()
        refreshRawConfigPreview()
    }

    private func refreshRawConfigPreview() {
        let validationMessage = model.configValidationMessage()
        if let validationMessage {
            rulesInfoLabel.stringValue = validationMessage
            rulesInfoLabel.textColor = .systemOrange
            rawConfigValidationLabel.stringValue = validationMessage
            rawConfigValidationLabel.textColor = .systemOrange
            rawConfigValidationLabel.isHidden = false
            saveButton.isEnabled = false
        } else {
            if let ts = lastSaveTimestamp {
                let timeStr = Self.saveTimestampFormatter.string(from: ts)
                rulesInfoLabel.stringValue = "Saved at \(timeStr)"
                rulesInfoLabel.textColor = .systemGreen
            } else {
                rulesInfoLabel.stringValue = "Changes save automatically."
                rulesInfoLabel.textColor = .secondaryLabelColor
            }
            rawConfigValidationLabel.stringValue = ""
            rawConfigValidationLabel.isHidden = true
            saveButton.isEnabled = true
        }
        rawConfigTextView.string = model.rawConfigPreview()
    }

    private func refreshRawConfigVisibility() {
        rawConfigContentStack.isHidden = !isRawConfigExpanded
        toggleRawConfigButton.title = isRawConfigExpanded ? "Collapse Raw Config" : "View Raw Config"
    }

    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutoSave()
            }
        }
    }

    private func performAutoSave() {
        refreshRawConfigPreview()
        guard model.configValidationMessage() == nil else {
            setStatus("Auto-save paused until the config is valid.", style: .warning)
            return
        }

        do {
            try model.save()
            lastSaveTimestamp = Date()
            refreshRawConfigPreview()
            setStatus("Saved automatically.")
            scheduleSaveBadgeCooldown()
        } catch {
            AppLogger.error("Auto-save failed: \(error.localizedDescription)", category: .app)
            refreshRawConfigPreview()
            setStatus("Auto-save failed: \(error.localizedDescription)", style: .error)
        }
    }

    private func scheduleSaveBadgeCooldown() {
        saveBadgeCooldownTimer?.invalidate()
        saveBadgeCooldownTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastSaveTimestamp = nil
                self.refreshRawConfigPreview()
            }
        }
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
            setDefaultBrowserAsDefaultHandlerButton.isHidden = false
            let hasDefaultBrowser = model.defaultBrowserAppURL != nil && !model.defaultBrowserBundleID.isEmpty
            let defaultBrowserAlreadyDefault =
                (httpID == model.defaultBrowserBundleID && httpsID == model.defaultBrowserBundleID)
            setDefaultBrowserAsDefaultHandlerButton.isEnabled = hasDefaultBrowser && !defaultBrowserAlreadyDefault
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
            setDefaultBrowserAsDefaultHandlerButton.isHidden = true
        }
    }

    private func refreshOpenAtLoginDisplay() {
        let status = model.launchAtLoginStatus()
        openAtLoginCheckbox.state = status.isToggleOn ? .on : .off
        openLoginItemsSettingsButton.isHidden = status != .requiresApproval

        switch status {
        case .enabled:
            openAtLoginStatusLabel.stringValue = "LinkSwitch is set to open automatically when you log in."
            openAtLoginStatusLabel.textColor = .systemGreen
        case .requiresApproval:
            openAtLoginStatusLabel.stringValue =
                "LinkSwitch was added to Login Items, but macOS still needs approval in System Settings."
            openAtLoginStatusLabel.textColor = .systemOrange
        case .notRegistered:
            openAtLoginStatusLabel.stringValue = "LinkSwitch is not set to open automatically when you log in."
            openAtLoginStatusLabel.textColor = .secondaryLabelColor
        case .notFound:
            openAtLoginStatusLabel.stringValue =
                "macOS could not find a stable login-item registration for this app. Reinstall the dev app and try again."
            openAtLoginStatusLabel.textColor = .systemOrange
        case .unsupported:
            openAtLoginStatusLabel.stringValue =
                "macOS reported an unsupported Login Items state for LinkSwitch."
            openAtLoginStatusLabel.textColor = .systemRed
        }
    }

    private func refreshDefaultBrowserDisplay() {
        if let appURL = model.defaultBrowserAppURL {
            defaultBrowserIconView.image = iconProvider.icon(forAppURL: appURL)
        } else {
            defaultBrowserIconView.image = NSImage(named: NSImage.applicationIconName)
        }
    }

    private func refreshDefaultBrowserPopup() {
        defaultBrowserPopup.removeAllItems()

        let discovered = model.discoveredBrowsers
        let currentBundleID = model.defaultBrowserBundleID
        let currentAppURL = model.defaultBrowserAppURL
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
            defaultBrowserPopup.menu?.addItem(item)
            defaultBrowserPopup.menu?.addItem(.separator())
        }

        // Discovered browsers
        for (index, browser) in discovered.enumerated() {
            let icon = iconProvider.icon(forAppURL: browser.appURL)
            let item = makePopupMenuItem(title: browser.name, icon: icon, tag: index)
            defaultBrowserPopup.menu?.addItem(item)
        }

        // "Other…" to pick manually
        defaultBrowserPopup.menu?.addItem(.separator())
        let otherItem = NSMenuItem(title: "Other…", action: nil, keyEquivalent: "")
        otherItem.tag = PopupItemTag.otherBrowser.rawValue
        defaultBrowserPopup.menu?.addItem(otherItem)

        // Select the current browser in the popup
        if isCurrentInDiscovered, let index = discovered.firstIndex(where: { $0.bundleID == currentBundleID }) {
            defaultBrowserPopup.selectItem(withTag: index)
        } else if !currentBundleID.isEmpty {
            defaultBrowserPopup.selectItem(withTag: PopupItemTag.customCurrentBrowser.rawValue)
        }
    }

    private func refreshDefaultProfileBrowserSection() {
        let bundleID = model.defaultBrowserBundleID
        let mode = BrowserProfileRouteSelectionMode.mode(forDefaultBrowserBundleID: bundleID)
        defaultProfileSectionLabel.stringValue = mode.sectionTitle

        guard model.defaultBrowserAppURL != nil, !bundleID.isEmpty, mode != .none else {
            defaultProfileContainerView.isHidden = true
            defaultBrowserDisplayedProfiles = []
            clearDefaultProfileCards()
            return
        }

        defaultProfileContainerView.isHidden = false
        let result = BrowserProfileRoutePicker.loadProfileCards(mode: mode, browserBundleID: bundleID)
        defaultBrowserDisplayedProfiles = result.displayedProfiles
        if let errorMessage = result.errorMessage {
            defaultProfileDiscoveryErrorLabel.stringValue = errorMessage
            defaultProfileDiscoveryErrorLabel.isHidden = false
        } else {
            defaultProfileDiscoveryErrorLabel.isHidden = true
        }

        rebuildDefaultProfileCards()
        AppLogger.info(
            "Default browser profile section (\(result.logContext)): \(defaultBrowserDisplayedProfiles.count) card(s), selected key '\(currentDefaultRouteSelectionKey())'",
            category: .app
        )
    }

    private func currentDefaultRouteSelectionKey() -> String {
        switch model.defaultBrowserRoute {
        case .plain:
            return ""
        case let .chromiumProfile(profileDirectory):
            return profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .firefoxProfile(profileKey):
            return profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .zenContainer(containerName):
            return containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func rebuildDefaultProfileCards() {
        clearDefaultProfileCards()
        for (index, profile) in defaultBrowserDisplayedProfiles.enumerated() {
            let button = ProfileCardButton(title: profile.displayName)
            button.tag = index
            button.target = self
            button.action = #selector(defaultProfileCardSelected(_:))
            button.setAccessibilityIdentifier("preferences.defaultBrowser.profileCard.\(index)")
            defaultProfileCardsStack.addArrangedSubview(button)
        }
        applyDefaultProfileCardSelection()
    }

    private func clearDefaultProfileCards() {
        defaultProfileCardsStack.arrangedSubviews.forEach { view in
            defaultProfileCardsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func applyDefaultProfileCardSelection() {
        let key = currentDefaultRouteSelectionKey()
        for (index, view) in defaultProfileCardsStack.arrangedSubviews.enumerated() {
            guard let button = view as? ProfileCardButton, defaultBrowserDisplayedProfiles.indices.contains(index) else { continue }
            button.isSelectedCard = defaultBrowserDisplayedProfiles[index].profileKey == key
        }
    }

    @objc private func defaultProfileCardSelected(_ sender: NSButton) {
        guard defaultBrowserDisplayedProfiles.indices.contains(sender.tag) else { return }
        let profile = defaultBrowserDisplayedProfiles[sender.tag]
        let mode = BrowserProfileRouteSelectionMode.mode(forDefaultBrowserBundleID: model.defaultBrowserBundleID)
        let route: DefaultBrowserRoute
        switch mode {
        case .defaultChromiumProfile:
            route = profile.profileKey.isEmpty ? .plain : .chromiumProfile(profileDirectory: profile.profileKey)
        case .defaultFirefoxProfile:
            route = profile.profileKey.isEmpty ? .plain : .firefoxProfile(profileKey: profile.profileKey)
        case .defaultZenContainer:
            route = profile.profileKey.isEmpty ? .plain : .zenContainer(containerName: profile.profileKey)
        case .none, .browserChromiumProfile, .browserFirefoxProfile, .browserZenContainer:
            return
        }
        model.updateDefaultBrowserRoute(route)
        applyDefaultProfileCardSelection()
        refreshRawConfigPreview()
        scheduleAutoSave()
        AppLogger.info(
            "Default browser: selected card \(profile.displayName) key '\(profile.profileKey)' route \(route.description)",
            category: .app
        )
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
        }

        for draft in model.ruleDrafts {
            let row = PreferencesRuleRowView(
                draft: draft,
                discoveredApplications: model.discoveredApplications,
                discoveredBrowsers: model.discoveredBrowsers,
                iconProvider: iconProvider,
                defaultBrowserBundleID: model.defaultBrowserBundleID,
                defaultBrowserAppURL: model.defaultBrowserAppURL,
                onSourceBundleIDChange: { [weak self] value in
                    self?.model.updateRuleSourceBundleID(id: draft.id, value: value)
                    self?.refreshRawConfigPreview()
                    self?.scheduleAutoSave()
                },
                onSourcePickerNeedsUIRefresh: { [weak self] in
                    self?.refreshUI()
                },
                onTargetSelectionChange: { [weak self] selection in
                    self?.model.updateRuleTargetSelection(id: draft.id, targetSelection: selection)
                    self?.refreshRawConfigPreview()
                    self?.scheduleAutoSave()
                },
                onBrowserRouteChange: { [weak self] route in
                    self?.model.updateRuleBrowserRoute(id: draft.id, route: route)
                    self?.refreshRawConfigPreview()
                    self?.scheduleAutoSave()
                },
                onRemove: { [weak self] in
                    self?.model.removeRule(id: draft.id)
                    self?.refreshUI()
                    self?.scheduleAutoSave()
                    self?.setStatus("Removed rule.")
                },
                onTest: { [weak self] in
                    self?.testRule(id: draft.id)
                }
            )
            rulesStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rulesStackView.widthAnchor).isActive = true
        }

        let addButton = makeButton(
            title: "+ Add Rule",
            action: #selector(addRule(_:)),
            accessibilityIdentifier: "preferences.addRuleButton"
        )
        addButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let addButtonRow = NSStackView(views: [addButton, NSView()])
        addButtonRow.orientation = .horizontal
        addButtonRow.spacing = 0
        rulesStackView.addArrangedSubview(addButtonRow)
        addButtonRow.widthAnchor.constraint(equalTo: rulesStackView.widthAnchor).isActive = true
    }

    // MARK: Actions

    @objc private func defaultBrowserPopupChanged(_ sender: Any?) {
        guard let tag = defaultBrowserPopup.selectedItem?.tag else { return }

        if tag == PopupItemTag.otherBrowser.rawValue {
            // Reset the popup to the previously selected item before opening the panel,
            // so the display doesn't jump to "Other…" while the panel is open.
            refreshDefaultBrowserPopup()
            chooseDefaultBrowserFromPanel()
        } else if tag == PopupItemTag.customCurrentBrowser.rawValue {
            // Already current; nothing to do.
        } else if tag >= 0 && tag < model.discoveredBrowsers.count {
            let browser = model.discoveredBrowsers[tag]
            AppLogger.info("Default browser changed to \(browser.bundleID) via popup", category: .app)
            model.setDefaultBrowser(discoveredBrowser: browser)
            refreshUI()
            scheduleAutoSave()
        }
    }

    private func chooseDefaultBrowserFromPanel() {
        guard let hostWindow = view.window else {
            AppLogger.error("Preferences browser picker requested without a host window", category: .app)
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the default browser app."

        panel.beginSheetModal(for: hostWindow) { [weak self] response in
            guard response == .OK, let applicationURL = panel.url else { return }
            do {
                try self?.model.setDefaultBrowser(applicationURL: applicationURL)
                self?.refreshUI()
                self?.scheduleAutoSave()
            } catch {
                self?.presentPreferencesError(error, message: "Could not use the selected browser app.")
            }
        }
    }

    @objc private func addRule(_ sender: Any?) {
        _ = model.addRule()
        refreshUI()
        scheduleAutoSave()
        setStatus("Added new rule.")
    }

    @objc private func reloadPreferences(_ sender: Any?) {
        autoSaveTimer?.invalidate()
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
        autoSaveTimer?.invalidate()
        syncSampleURLField()
        do {
            try model.save()
            lastSaveTimestamp = Date()
            refreshRawConfigPreview()
            setStatus("Saved router config to disk.")
            scheduleSaveBadgeCooldown()
        } catch {
            refreshRawConfigPreview()
            presentPreferencesError(error, message: "Could not save the router config.")
        }
    }

    @objc private func testDefaultBrowser(_ sender: Any?) {
        syncSampleURLField()
        Task { @MainActor [weak self] in
            do {
                try await self?.model.testDefaultBrowser()
                self?.setStatus("Opened the sample URL in the default browser.")
            } catch {
                self?.presentPreferencesError(error, message: "Could not test the default browser launch.")
            }
        }
    }

    @objc private func sampleURLChanged(_ sender: Any?) {
        syncSampleURLField()
    }

    @objc private func toggleRawConfigVisibility(_ sender: Any?) {
        isRawConfigExpanded.toggle()
        refreshRawConfigVisibility()
        guard isRawConfigExpanded else { return }
        view.layoutSubtreeIfNeeded()
        rawConfigCard.scrollToVisible(rawConfigCard.bounds)
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

    @objc private func setDefaultBrowserAsDefaultHandler(_ sender: Any?) {
        AppLogger.info("User requested setting the default browser as the macOS http/https handler", category: .app)
        Task { @MainActor [weak self] in
            do {
                let result = try await self?.model.registerDefaultBrowserAsDefaultHandler()
                self?.refreshUI()
                switch result {
                case .registered:
                    self?.setStatus("Set the default browser as the HTTP/HTTPS handler.")
                case .alreadyRegistered:
                    self?.setStatus(
                        "The default browser is already the HTTP/HTTPS handler.",
                        style: .warning
                    )
                case nil:
                    break
                }
            } catch {
                self?.presentPreferencesError(
                    error,
                    message: "Could not set the default browser as the HTTP/HTTPS handler."
                )
            }
        }
    }

    @objc private func toggleOpenAtLogin(_ sender: NSButton) {
        let shouldEnable = sender.state == .on
        AppLogger.info("User toggled Open at Login to \(shouldEnable)", category: .app)

        do {
            _ = try model.setLaunchAtLoginEnabled(shouldEnable)
            refreshOpenAtLoginDisplay()
            clearStatus()
        } catch {
            refreshOpenAtLoginDisplay()
            presentPreferencesError(
                error,
                message: shouldEnable
                    ? "Could not enable Open at Login."
                    : "Could not disable Open at Login."
            )
        }
    }

    @objc private func openLoginItemsSettings(_ sender: Any?) {
        model.openSystemSettingsLoginItems()
        clearStatus()
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
        case .success:
            statusLabel.textColor = .systemGreen
        case .warning:
            statusLabel.textColor = .systemYellow
        case .error:
            statusLabel.textColor = .systemRed
        }
    }

    private func clearStatus() {
        statusLabel.stringValue = ""
        statusLabel.textColor = .secondaryLabelColor
    }

    private func presentPreferencesError(_ error: Error, message: String) {
        AppLogger.error("\(message) \(error.localizedDescription)", category: .app)
        setStatus(message, style: .error)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
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

    private enum TargetPopupTag {
        static let defaultBrowser = -995
        static let customBrowser = -994
        static let discoveredBrowserBase = 1_000

        static func discoveredBrowserTag(for index: Int) -> Int {
            discoveredBrowserBase + index
        }
    }

    private let sourceAppPopUpButton: NSPopUpButton
    private let manualBundleIDField: NSTextField
    private let manualBundleIDLabel: NSTextField
    private let manualBundleIDStack: NSStackView
    private let sourceIconView: NSImageView
    private let targetBrowserPopupButton: NSPopUpButton
    private let targetIconView: NSImageView
    private let profileCardsStack: NSStackView
    private let profileSectionLabel: NSTextField
    private let profileDiscoveryErrorLabel: NSTextField
    private let profileContainerView: NSStackView

    private var discoveredProfiles: [BrowserProfile] = []
    private var currentSelectionKey: String
    private var currentTargetSelection: PreferencesRuleTargetSelection

    private let draft: PreferencesRuleDraft
    private let discoveredApplications: [DiscoveredApplication]
    private let discoveredBrowsers: [DiscoveredBrowser]
    private let iconProvider: AppIconProvider
    private let defaultBrowserBundleID: String
    private var defaultBrowserAppURL: URL?

    private let onSourceBundleIDChange: (String) -> Void
    private let onSourcePickerNeedsUIRefresh: () -> Void
    private let onTargetSelectionChange: (PreferencesRuleTargetSelection) -> Void
    private let onBrowserRouteChange: (DefaultBrowserRoute) -> Void
    private let onRemove: () -> Void
    private let onTest: () -> Void

    private var iconUpdateTimer: Timer?
    /// Tracks the latest source bundle ID (model may update without row reload).
    private var lastAppliedSourceBundleID: String

    init(
        draft: PreferencesRuleDraft,
        discoveredApplications: [DiscoveredApplication],
        discoveredBrowsers: [DiscoveredBrowser],
        iconProvider: AppIconProvider,
        defaultBrowserBundleID: String,
        defaultBrowserAppURL: URL?,
        onSourceBundleIDChange: @escaping (String) -> Void,
        onSourcePickerNeedsUIRefresh: @escaping () -> Void,
        onTargetSelectionChange: @escaping (PreferencesRuleTargetSelection) -> Void,
        onBrowserRouteChange: @escaping (DefaultBrowserRoute) -> Void,
        onRemove: @escaping () -> Void,
        onTest: @escaping () -> Void
    ) {
        self.draft = draft
        self.discoveredApplications = discoveredApplications
        self.discoveredBrowsers = discoveredBrowsers
        self.iconProvider = iconProvider
        self.defaultBrowserBundleID = defaultBrowserBundleID
        self.defaultBrowserAppURL = defaultBrowserAppURL
        self.onSourceBundleIDChange = onSourceBundleIDChange
        self.onSourcePickerNeedsUIRefresh = onSourcePickerNeedsUIRefresh
        self.onTargetSelectionChange = onTargetSelectionChange
        self.onBrowserRouteChange = onBrowserRouteChange
        self.onRemove = onRemove
        self.onTest = onTest

        lastAppliedSourceBundleID = draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTargetSelection = draft.targetSelection
        switch draft.browserRoute {
        case .plain:
            currentSelectionKey = ""
        case let .chromiumProfile(profileDirectory):
            currentSelectionKey = profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .firefoxProfile(profileKey):
            currentSelectionKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .zenContainer(containerName):
            currentSelectionKey = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        sourceAppPopUpButton = NSPopUpButton()
        manualBundleIDField = NSTextField(string: draft.sourceBundleID)
        manualBundleIDLabel = NSTextField(labelWithString: "Bundle ID:")
        manualBundleIDLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        manualBundleIDLabel.textColor = .secondaryLabelColor

        targetBrowserPopupButton = NSPopUpButton()
        profileCardsStack = NSStackView()
        profileSectionLabel = NSTextField(labelWithString: "Profile")
        profileSectionLabel.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        profileSectionLabel.textColor = .secondaryLabelColor

        profileDiscoveryErrorLabel = NSTextField(labelWithString: "")
        profileDiscoveryErrorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        profileDiscoveryErrorLabel.textColor = .systemOrange
        profileDiscoveryErrorLabel.isHidden = true

        sourceIconView = Self.makeIconView(size: 24)
        targetIconView = Self.makeIconView(size: 24)

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
        populateTargetMenu()
        applyManualFieldVisibilityForInitialState()
        updateSourceIcon(bundleID: draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines))
        updateTargetIcon(targetSelection: draft.targetSelection)
        refreshProfilePresentation()
        if profileRouteSelectionMode() != .none {
            refreshProfileCards()
        }
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

    private func populateTargetMenu() {
        targetBrowserPopupButton.removeAllItems()
        guard let menu = targetBrowserPopupButton.menu else { return }

        let defaultIcon = defaultBrowserAppURL.map(iconProvider.icon(forAppURL:)) ?? (NSImage(named: NSImage.applicationIconName) ?? NSImage())
        let defaultItem = Self.makeMenuItem(title: "Default Browser", icon: defaultIcon, tag: TargetPopupTag.defaultBrowser)
        menu.addItem(defaultItem)

        let selectedBundleID = currentTargetSelection.bundleID
        let matchIndex = selectedBundleID.flatMap { bundleID in
            discoveredBrowsers.firstIndex(where: { $0.bundleID == bundleID })
        }

        if let selectedBundleID, matchIndex == nil {
            let customIcon: NSImage
            if let applicationURL = currentTargetSelection.applicationURL {
                customIcon = iconProvider.icon(forAppURL: applicationURL)
            } else {
                customIcon = iconProvider.icon(forBundleID: selectedBundleID)
            }
            let customItem = Self.makeMenuItem(
                title: "Current: \(targetDisplayName(forBundleID: selectedBundleID, applicationURL: currentTargetSelection.applicationURL))",
                icon: customIcon,
                tag: TargetPopupTag.customBrowser
            )
            menu.addItem(customItem)
        }

        if !discoveredBrowsers.isEmpty {
            menu.addItem(.separator())
        }

        for (index, browser) in discoveredBrowsers.enumerated() {
            let item = Self.makeMenuItem(
                title: browser.name,
                icon: iconProvider.icon(forAppURL: browser.appURL),
                tag: TargetPopupTag.discoveredBrowserTag(for: index)
            )
            menu.addItem(item)
        }

        switch currentTargetSelection {
        case .defaultBrowser:
            targetBrowserPopupButton.selectItem(withTag: TargetPopupTag.defaultBrowser)
        case .browser:
            if let matchIndex {
                targetBrowserPopupButton.selectItem(withTag: TargetPopupTag.discoveredBrowserTag(for: matchIndex))
            } else {
                targetBrowserPopupButton.selectItem(withTag: TargetPopupTag.customBrowser)
            }
        }
    }

    private func targetDisplayName(forBundleID bundleID: String, applicationURL: URL?) -> String {
        if let browser = discoveredBrowsers.first(where: { $0.bundleID == bundleID }) {
            return browser.name
        }
        if let applicationURL {
            return applicationURL.deletingPathExtension().lastPathComponent
        }
        return bundleID
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

        let arrowLabel = NSTextField(labelWithString: "→")
        arrowLabel.font = .systemFont(ofSize: 18, weight: .light)
        arrowLabel.textColor = .tertiaryLabelColor
        arrowLabel.setContentHuggingPriority(.required, for: .horizontal)
        arrowLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        targetBrowserPopupButton.target = self
        targetBrowserPopupButton.action = #selector(targetBrowserChanged(_:))
        targetBrowserPopupButton.setAccessibilityIdentifier("preferences.rule.targetBrowserPopup")

        let targetPickerRow = NSStackView(views: [targetIconView, targetBrowserPopupButton])
        targetPickerRow.orientation = .horizontal
        targetPickerRow.alignment = .centerY
        targetPickerRow.spacing = 8

        profileCardsStack.orientation = .horizontal
        profileCardsStack.alignment = .centerY
        profileCardsStack.spacing = 8
        profileCardsStack.setAccessibilityIdentifier("preferences.rule.profileCardsStack")

        profileContainerView.orientation = .vertical
        profileContainerView.alignment = .leading
        profileContainerView.spacing = 6
        profileContainerView.addArrangedSubview(profileSectionLabel)
        profileContainerView.addArrangedSubview(profileCardsStack)
        profileContainerView.addArrangedSubview(profileDiscoveryErrorLabel)
        profileContainerView.isHidden = true

        let testButton = NSButton(title: "Test Rule", target: self, action: #selector(testRule(_:)))
        testButton.bezelStyle = .rounded
        testButton.setAccessibilityIdentifier("preferences.rule.testButton")

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeRule(_:)))
        removeButton.bezelStyle = .rounded
        removeButton.setAccessibilityIdentifier("preferences.rule.removeButton")

        let mainPickerStack = NSStackView(views: [sourcePickerRow, arrowLabel, targetPickerRow])
        mainPickerStack.orientation = .horizontal
        mainPickerStack.alignment = .centerY
        mainPickerStack.spacing = 12
        mainPickerStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowSpacer = NSView()
        rowSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [mainPickerStack, rowSpacer, testButton, removeButton])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        let rootStack = NSStackView(views: [topRow, manualBundleIDStack, profileContainerView])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8

        addSubview(rootStack)

        NSLayoutConstraint.activate([
            topRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 24),
            sourceIconView.heightAnchor.constraint(equalToConstant: 24),
            targetIconView.widthAnchor.constraint(equalToConstant: 24),
            targetIconView.heightAnchor.constraint(equalToConstant: 24),
            sourceAppPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            targetBrowserPopupButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            manualBundleIDField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            profileCardsStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            profileCardsStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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

    private func updateTargetIcon(targetSelection: PreferencesRuleTargetSelection) {
        switch targetSelection {
        case .defaultBrowser:
            if let appURL = defaultBrowserAppURL {
                targetIconView.image = iconProvider.icon(forAppURL: appURL)
            } else {
                targetIconView.image = NSImage(named: NSImage.applicationIconName)
            }
        case let .browser(bundleID, applicationURL):
            if let applicationURL {
                targetIconView.image = iconProvider.icon(forAppURL: applicationURL)
            } else {
                targetIconView.image = iconProvider.icon(forBundleID: bundleID)
            }
        }
    }

    private func selectedTargetSelection() -> PreferencesRuleTargetSelection {
        guard let tag = targetBrowserPopupButton.selectedItem?.tag else {
            return currentTargetSelection
        }
        if tag == TargetPopupTag.defaultBrowser {
            return .defaultBrowser
        }
        if tag == TargetPopupTag.customBrowser {
            return currentTargetSelection
        }
        if tag >= TargetPopupTag.discoveredBrowserBase {
            let browserIndex = tag - TargetPopupTag.discoveredBrowserBase
            guard browserIndex >= 0, browserIndex < discoveredBrowsers.count else {
                return currentTargetSelection
            }
            let browser = discoveredBrowsers[browserIndex]
            return .browser(bundleID: browser.bundleID, applicationURL: browser.appURL)
        }
        return currentTargetSelection
    }

    private func profileRouteSelectionMode() -> BrowserProfileRouteSelectionMode {
        BrowserProfileRouteSelectionMode.mode(
            targetSelection: currentTargetSelection,
            defaultBrowserBundleID: defaultBrowserBundleID
        )
    }

    private func profileRouteTargetBundleID() -> String {
        switch currentTargetSelection {
        case .defaultBrowser:
            return defaultBrowserBundleID
        case let .browser(bundleID, _):
            return bundleID
        }
    }

    private func refreshProfilePresentation() {
        let mode = profileRouteSelectionMode()
        profileSectionLabel.stringValue = mode.sectionTitle
        profileContainerView.isHidden = mode == .none
        if mode == .none {
            discoveredProfiles = []
            profileDiscoveryErrorLabel.isHidden = true
            clearProfileCards()
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
        }
    }

    @objc private func targetBrowserChanged(_ sender: Any?) {
        currentTargetSelection = selectedTargetSelection()
        currentSelectionKey = ""
        refreshProfilePresentation()
        if profileRouteSelectionMode() != .none {
            refreshProfileCards()
        }
        updateTargetIcon(targetSelection: currentTargetSelection)
        onTargetSelectionChange(currentTargetSelection)
        AppLogger.info("Source rule row: selected target \(String(describing: currentTargetSelection.bundleID ?? "default browser"))", category: .app)
    }

    @objc private func profileCardSelected(_ sender: NSButton) {
        guard discoveredProfiles.indices.contains(sender.tag) else { return }
        let profile = discoveredProfiles[sender.tag]
        currentSelectionKey = profile.profileKey
        switch profileRouteSelectionMode() {
        case .browserChromiumProfile, .defaultChromiumProfile:
            let route: DefaultBrowserRoute = profile.profileKey.isEmpty
                ? .plain
                : .chromiumProfile(profileDirectory: profile.profileKey)
            onBrowserRouteChange(route)
        case .browserFirefoxProfile, .defaultFirefoxProfile:
            let route: DefaultBrowserRoute = profile.profileKey.isEmpty
                ? .plain
                : .firefoxProfile(profileKey: profile.profileKey)
            onBrowserRouteChange(route)
        case .browserZenContainer, .defaultZenContainer:
            let route: DefaultBrowserRoute = profile.profileKey.isEmpty
                ? .plain
                : .zenContainer(containerName: profile.profileKey)
            onBrowserRouteChange(route)
        case .none:
            return
        }
        applyProfileCardSelection()
        AppLogger.info("Profile rule row: selected option \(profile.profileKey) (\(profile.displayName))", category: .app)
    }

    private func refreshProfileCards() {
        let mode = profileRouteSelectionMode()
        refreshProfilePresentation()
        guard mode != .none else {
            return
        }

        let result = BrowserProfileRoutePicker.loadProfileCards(
            mode: mode,
            browserBundleID: profileRouteTargetBundleID()
        )
        discoveredProfiles = result.displayedProfiles
        if let errorMessage = result.errorMessage {
            profileDiscoveryErrorLabel.stringValue = errorMessage
            profileDiscoveryErrorLabel.isHidden = false
        } else {
            profileDiscoveryErrorLabel.isHidden = true
        }

        rebuildProfileCards()
        AppLogger.info(
            "Profile rule row (\(result.logContext)): refreshed \(discoveredProfiles.count) card(s), selected key: '\(currentSelectionKey)'",
            category: .app
        )
    }

    private func rebuildProfileCards() {
        clearProfileCards()
        for (index, profile) in discoveredProfiles.enumerated() {
            let button = ProfileCardButton(title: profile.displayName)
            button.tag = index
            button.target = self
            button.action = #selector(profileCardSelected(_:))
            button.setAccessibilityIdentifier("preferences.rule.profileCard.\(index)")
            profileCardsStack.addArrangedSubview(button)
        }
        applyProfileCardSelection()
    }

    private func clearProfileCards() {
        profileCardsStack.arrangedSubviews.forEach { view in
            profileCardsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func applyProfileCardSelection() {
        for (index, view) in profileCardsStack.arrangedSubviews.enumerated() {
            guard let button = view as? ProfileCardButton, discoveredProfiles.indices.contains(index) else { continue }
            button.isSelectedCard = discoveredProfiles[index].profileKey == currentSelectionKey
        }
    }

    @objc private func removeRule(_ sender: Any?) {
        onRemove()
    }

    @objc private func testRule(_ sender: Any?) {
        onTest()
    }
}

private final class DefaultBrowserAccessibilityPopUpButton: NSPopUpButton {
    convenience init() {
        self.init(frame: .zero, pullsDown: false)
    }

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        setAccessibilityIdentifier("preferences.defaultBrowserPopup")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityIdentifier("preferences.defaultBrowserPopup")
    }
}

