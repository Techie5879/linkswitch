import AppKit
import UniformTypeIdentifiers

@MainActor
final class PreferencesWindowController: NSWindowController {
    private enum StatusStyle {
        case normal
        case warning
        case error
    }

    private let model: PreferencesModel

    private let configPathLabel = NSTextField(wrappingLabelWithString: "")
    private let fallbackBrowserBundleLabel = NSTextField(labelWithString: "")
    private let fallbackBrowserPathLabel = NSTextField(wrappingLabelWithString: "")
    private let httpHandlerLabel = NSTextField(labelWithString: "")
    private let httpsHandlerLabel = NSTextField(labelWithString: "")
    private let sampleURLField = NSTextField(string: "")
    private let rulesStackView = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(model: PreferencesModel) throws {
        self.model = model
        try model.load()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow()
        refreshUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window else { return }

        window.title = "LinkSwitch Preferences"
        window.center()
        window.setContentSize(NSSize(width: 780, height: 620))

        let contentView = NSView()
        window.contentView = contentView

        let rootStackView = NSStackView()
        rootStackView.translatesAutoresizingMaskIntoConstraints = false
        rootStackView.orientation = .vertical
        rootStackView.alignment = .leading
        rootStackView.spacing = 16

        let introLabel = NSTextField(wrappingLabelWithString: "Configure the explicit fallback browser, source-app rules, and test launches from the same routing config used at runtime.")
        introLabel.maximumNumberOfLines = 0

        configPathLabel.maximumNumberOfLines = 0
        configPathLabel.textColor = .secondaryLabelColor

        fallbackBrowserBundleLabel.lineBreakMode = .byTruncatingMiddle
        fallbackBrowserPathLabel.maximumNumberOfLines = 0
        fallbackBrowserPathLabel.textColor = .secondaryLabelColor

        let chooseFallbackBrowserButton = makeButton(
            title: "Choose Browser…",
            action: #selector(chooseFallbackBrowser(_:)),
            accessibilityIdentifier: "preferences.chooseFallbackBrowserButton"
        )
        let testFallbackBrowserButton = makeButton(
            title: "Test Fallback Browser",
            action: #selector(testFallbackBrowser(_:)),
            accessibilityIdentifier: "preferences.testFallbackBrowserButton"
        )

        sampleURLField.target = self
        sampleURLField.action = #selector(sampleURLChanged(_:))
        sampleURLField.placeholderString = "https://example.com"
        sampleURLField.setAccessibilityIdentifier("preferences.sampleURLField")

        let addRuleButton = makeButton(
            title: "Add Rule",
            action: #selector(addRule(_:)),
            accessibilityIdentifier: "preferences.addRuleButton"
        )
        let registerHandlerButton = makeButton(
            title: "Set LinkSwitch as HTTP/HTTPS Handler",
            action: #selector(registerLinkSwitchAsDefaultHandler(_:)),
            accessibilityIdentifier: "preferences.registerHandlerButton"
        )
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

        rulesStackView.orientation = .vertical
        rulesStackView.alignment = .leading
        rulesStackView.spacing = 12
        rulesStackView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.maximumNumberOfLines = 0
        statusLabel.textColor = .secondaryLabelColor

        let fallbackButtonsStackView = NSStackView(views: [chooseFallbackBrowserButton, testFallbackBrowserButton])
        fallbackButtonsStackView.orientation = .horizontal
        fallbackButtonsStackView.spacing = 12

        let footerButtonsStackView = NSStackView(views: [reloadButton, saveButton])
        footerButtonsStackView.orientation = .horizontal
        footerButtonsStackView.spacing = 12

        rootStackView.addArrangedSubview(makeSectionLabel("Router Config"))
        rootStackView.addArrangedSubview(introLabel)
        rootStackView.addArrangedSubview(configPathLabel)
        rootStackView.addArrangedSubview(makeSectionLabel("Fallback Browser"))
        rootStackView.addArrangedSubview(fallbackBrowserBundleLabel)
        rootStackView.addArrangedSubview(fallbackBrowserPathLabel)
        rootStackView.addArrangedSubview(fallbackButtonsStackView)
        rootStackView.addArrangedSubview(makeSectionLabel("URL Handler Registration"))
        rootStackView.addArrangedSubview(httpHandlerLabel)
        rootStackView.addArrangedSubview(httpsHandlerLabel)
        rootStackView.addArrangedSubview(registerHandlerButton)
        rootStackView.addArrangedSubview(makeSectionLabel("Sample URL"))
        rootStackView.addArrangedSubview(sampleURLField)
        rootStackView.addArrangedSubview(makeSectionLabel("Source-App Rules"))
        rootStackView.addArrangedSubview(addRuleButton)
        rootStackView.addArrangedSubview(rulesStackView)
        rootStackView.addArrangedSubview(footerButtonsStackView)
        rootStackView.addArrangedSubview(statusLabel)

        contentView.addSubview(rootStackView)

        NSLayoutConstraint.activate([
            rootStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            sampleURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            rulesStackView.widthAnchor.constraint(equalTo: rootStackView.widthAnchor),
        ])
    }

    private func refreshUI() {
        configPathLabel.stringValue = "Config file: \(model.configFileURLDescription)"
        sampleURLField.stringValue = model.sampleURLString

        if let fallbackBrowserAppURL = model.fallbackBrowserAppURL {
            fallbackBrowserBundleLabel.stringValue = "Bundle ID: \(model.fallbackBrowserBundleID)"
            fallbackBrowserPathLabel.stringValue = "App URL: \(fallbackBrowserAppURL.path())"
        } else {
            fallbackBrowserBundleLabel.stringValue = "No fallback browser selected yet."
            fallbackBrowserPathLabel.stringValue = "Choose the browser app that should receive non-matching links."
        }

        httpHandlerLabel.stringValue = "Current http handler: \(model.currentHandlerBundleID(forURLScheme: "http") ?? "Unavailable")"
        httpsHandlerLabel.stringValue = "Current https handler: \(model.currentHandlerBundleID(forURLScheme: "https") ?? "Unavailable")"

        rulesStackView.arrangedSubviews.forEach { arrangedSubview in
            rulesStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        if model.ruleDrafts.isEmpty {
            let emptyStateLabel = NSTextField(wrappingLabelWithString: "No source-app rules are configured yet. Add one to route a sender such as Slack to Helium.")
            emptyStateLabel.textColor = .secondaryLabelColor
            rulesStackView.addArrangedSubview(emptyStateLabel)
            return
        }

        for draft in model.ruleDrafts {
            let rowView = PreferencesRuleRowView(
                draft: draft,
                onSourceBundleIDChange: { [weak self] value in
                    self?.model.updateRuleSourceBundleID(id: draft.id, value: value)
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
                    self?.setStatus("Removed rule \(draft.id.uuidString).")
                },
                onTest: { [weak self] in
                    self?.testRule(id: draft.id)
                }
            )
            rulesStackView.addArrangedSubview(rowView)
        }
    }

    @objc private func chooseFallbackBrowser(_ sender: Any?) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the fallback browser app."

        panel.beginSheetModal(for: window) { [weak self] response in
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
        let ruleID = model.addRule()
        refreshUI()
        setStatus("Added rule draft \(ruleID.uuidString).")
    }

    @objc private func reloadPreferences(_ sender: Any?) {
        do {
            try model.load()
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
                self?.setStatus("Opened the sample URL in the configured fallback browser.")
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

    private func testRule(id: UUID) {
        syncSampleURLField()
        Task { @MainActor [weak self] in
            do {
                try await self?.model.testRule(id: id)
                self?.setStatus("Opened the sample URL with rule \(id.uuidString).")
            } catch {
                self?.presentPreferencesError(error, message: "Could not test the selected rule.")
            }
        }
    }

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
        if let window {
            alert.beginSheetModal(for: window)
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
}

@MainActor
private final class PreferencesRuleRowView: NSView, NSTextFieldDelegate {
    private let sourceBundleIDField: NSTextField
    private let targetKindPopupButton: NSPopUpButton
    private let heliumProfileDirectoryField: NSTextField

    private let onSourceBundleIDChange: (String) -> Void
    private let onTargetKindChange: (PreferencesRuleTargetKind) -> Void
    private let onHeliumProfileDirectoryChange: (String) -> Void
    private let onRemove: () -> Void
    private let onTest: () -> Void

    init(
        draft: PreferencesRuleDraft,
        onSourceBundleIDChange: @escaping (String) -> Void,
        onTargetKindChange: @escaping (PreferencesRuleTargetKind) -> Void,
        onHeliumProfileDirectoryChange: @escaping (String) -> Void,
        onRemove: @escaping () -> Void,
        onTest: @escaping () -> Void
    ) {
        self.onSourceBundleIDChange = onSourceBundleIDChange
        self.onTargetKindChange = onTargetKindChange
        self.onHeliumProfileDirectoryChange = onHeliumProfileDirectoryChange
        self.onRemove = onRemove
        self.onTest = onTest

        sourceBundleIDField = NSTextField(string: draft.sourceBundleID)
        targetKindPopupButton = NSPopUpButton()
        heliumProfileDirectoryField = NSTextField(string: draft.heliumProfileDirectory)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        sourceBundleIDField.placeholderString = "Source app bundle ID"
        sourceBundleIDField.delegate = self
        sourceBundleIDField.setAccessibilityIdentifier("preferences.rule.sourceBundleIDField")

        targetKindPopupButton.addItems(withTitles: ["Fallback Browser", "Helium"])
        targetKindPopupButton.selectItem(at: draft.targetKind == .fallbackBrowser ? 0 : 1)
        targetKindPopupButton.target = self
        targetKindPopupButton.action = #selector(targetKindChanged(_:))
        targetKindPopupButton.setAccessibilityIdentifier("preferences.rule.targetKindPopup")

        heliumProfileDirectoryField.placeholderString = "Helium profile directory"
        heliumProfileDirectoryField.delegate = self
        heliumProfileDirectoryField.setAccessibilityIdentifier("preferences.rule.heliumProfileField")
        heliumProfileDirectoryField.isHidden = draft.targetKind != .helium

        let testButton = NSButton(title: "Test Rule", target: self, action: #selector(testRule(_:)))
        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeRule(_:)))

        let rootStackView = NSStackView()
        rootStackView.translatesAutoresizingMaskIntoConstraints = false
        rootStackView.orientation = .vertical
        rootStackView.alignment = .leading
        rootStackView.spacing = 8

        let headerLabel = NSTextField(labelWithString: "Source-App Rule")
        headerLabel.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        let targetRowStackView = NSStackView(views: [
            NSTextField(labelWithString: "Target"),
            targetKindPopupButton,
            NSTextField(labelWithString: "Profile"),
            heliumProfileDirectoryField,
        ])
        targetRowStackView.orientation = .horizontal
        targetRowStackView.alignment = .centerY
        targetRowStackView.spacing = 8

        let buttonsStackView = NSStackView(views: [testButton, removeButton])
        buttonsStackView.orientation = .horizontal
        buttonsStackView.spacing = 8

        rootStackView.addArrangedSubview(headerLabel)
        rootStackView.addArrangedSubview(sourceBundleIDField)
        rootStackView.addArrangedSubview(targetRowStackView)
        rootStackView.addArrangedSubview(buttonsStackView)

        addSubview(rootStackView)

        NSLayoutConstraint.activate([
            rootStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rootStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rootStackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rootStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            sourceBundleIDField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            heliumProfileDirectoryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 700),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        if textField === sourceBundleIDField {
            onSourceBundleIDChange(textField.stringValue)
        } else if textField === heliumProfileDirectoryField {
            onHeliumProfileDirectoryChange(textField.stringValue)
        }
    }

    @objc private func targetKindChanged(_ sender: Any?) {
        let targetKind: PreferencesRuleTargetKind = targetKindPopupButton.indexOfSelectedItem == 0 ? .fallbackBrowser : .helium
        heliumProfileDirectoryField.isHidden = targetKind != .helium
        onTargetKindChange(targetKind)
    }

    @objc private func removeRule(_ sender: Any?) {
        onRemove()
    }

    @objc private func testRule(_ sender: Any?) {
        onTest()
    }
}
