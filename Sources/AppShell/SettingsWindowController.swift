import AppKit
import Carbon.HIToolbox
import PanelFeature
import SettingsFeature

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let selectedPaneDefaultsKey = "PathShelf.SelectedSettingsPane"
    private static let toolbarDefinitions: [
        (identifier: NSToolbarItem.Identifier, label: String, symbol: String)
    ] = [
        (.init("GeneralSettings"), "General", "gearshape"),
        (.init("ShortcutSettings"), "Shortcut", "command"),
        (.init("BrowserSettings"), "Browser", "folder"),
        (.init("AccessSettings"), "Access", "lock.shield")
    ]

    private let invocationController: InvocationController
    private let configurationTransferController: ConfigurationTransferController
    private let onClose: () -> Void
    private let onApply: () -> Void
    private let onGrantFolderAccess: (URL) throws -> Void
    private let placementPopup = NSPopUpButton()
    private let keyPopup = NSPopUpButton()
    private let commandCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let controlCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let optionCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let shiftCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let showHiddenFilesCheckbox = NSButton(checkboxWithTitle: "Show hidden files", target: nil, action: nil)
    private let modifiedColumnCheckbox = NSButton(checkboxWithTitle: "Modified", target: nil, action: nil)
    private let kindColumnCheckbox = NSButton(checkboxWithTitle: "Kind", target: nil, action: nil)
    private let sizeColumnCheckbox = NSButton(checkboxWithTitle: "Size", target: nil, action: nil)
    private let createdColumnCheckbox = NSButton(checkboxWithTitle: "Created", target: nil, action: nil)
    private let availabilityColumnCheckbox = NSButton(checkboxWithTitle: "Availability", target: nil, action: nil)
    private let defaultLocationLabel = NSTextField(labelWithString: "")
    private let quickLookGuideLabel = NSTextField(
        wrappingLabelWithString: "Quick Look previews the selected file without opening another app. Press Space in the panel."
    )
    private let shortcutHintLabel = NSTextField(wrappingLabelWithString: "")
    private let accessGuideLabel = NSTextField(
        wrappingLabelWithString: "Grant persistent access only to folders used in Favorites."
    )
    private let paneContainer = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var exportConfigurationButton = NSButton(
        title: "Export Configuration…",
        target: configurationTransferController,
        action: #selector(ConfigurationTransferController.exportConfiguration(_:))
    )
    private lazy var importConfigurationButton = NSButton(
        title: "Import Configuration…",
        target: configurationTransferController,
        action: #selector(ConfigurationTransferController.importConfiguration(_:))
    )
    private var panes: [NSView] = []
    private var pendingDefaultLocationPath: String?
    private var selectedPaneIndex = 0

    init(
        invocationController: InvocationController,
        transferCoordinator: SettingsTransferCoordinator,
        producerVersion: String,
        onClose: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onGrantFolderAccess: @escaping (URL) throws -> Void
    ) {
        self.invocationController = invocationController
        self.configurationTransferController = ConfigurationTransferController(
            coordinator: transferCoordinator,
            producerVersion: producerVersion
        )
        self.onClose = onClose
        self.onApply = onApply
        self.onGrantFolderAccess = onGrantFolderAccess
        self.pendingDefaultLocationPath = invocationController.settings.defaultLocationPath
        let savedPaneIndex = UserDefaults.standard.integer(forKey: Self.selectedPaneDefaultsKey)
        self.selectedPaneIndex = Self.toolbarDefinitions.indices.contains(savedPaneIndex)
            ? savedPaneIndex
            : 0
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 660, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PathShelf Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 620, height: 500)
        super.init(window: window)
        configurationTransferController.onStatus = { [weak self] message, tooltip in
            self?.setStatus(message, tooltip: tooltip)
        }
        configurationTransferController.onImport = { [weak self] _ in
            guard let self else {
                return
            }
            syncFromSettings(updateStatus: false)
            onApply()
        }
        window.delegate = self
        window.contentView = makeContentView()
        configureToolbar(for: window)
        syncFromSettings(updateStatus: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        syncFromSettings(updateStatus: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    var browserPreferencesReady: Bool {
        window?.styleMask.contains(.resizable) == true
            && window?.toolbarStyle == .preference
            && window?.toolbar?.items.count == Self.toolbarDefinitions.count
            && showHiddenFilesCheckbox.title == "Show hidden files"
            && defaultLocationLabel.stringValue.isEmpty == false
            && quickLookGuideLabel.stringValue.contains("Press Space")
            && accessGuideLabel.stringValue.contains("persistent access")
    }

    var configurationTransferReady: Bool {
        exportConfigurationButton.identifier?.rawValue
            == "PathShelf.Settings.ExportConfiguration"
            && importConfigurationButton.identifier?.rawValue
                == "PathShelf.Settings.ImportConfiguration"
            && statusLabel.identifier?.rawValue == "PathShelf.Settings.Status"
            && exportConfigurationButton.action
                == #selector(ConfigurationTransferController.exportConfiguration(_:))
            && importConfigurationButton.action
                == #selector(ConfigurationTransferController.importConfiguration(_:))
    }

    func runConfigurationTransferProbe(in directory: URL) -> ConfigurationTransferProbeResult {
        configurationTransferController.runProbe(in: directory)
    }

    func runConfigurationRollbackFailureMessageProbe() -> Bool {
        configurationTransferController.rollbackFailureMessageProbe()
    }

    func runConfigurationTransferAccessibilityProbe() -> Bool {
        let message = "Configuration transfer accessibility check."
        setStatus(message, tooltip: nil)
        return statusLabel.stringValue == message && statusLabel.toolTip == message
    }

    func captureSmokePanes(in directoryURL: URL) -> Bool {
        guard let window,
              let contentView = window.contentView,
              let captureView = contentView.superview else {
            return false
        }
        syncFromSettings(updateStatus: true)
        let previousIndex = selectedPaneIndex
        defer {
            window.toolbar?.selectedItemIdentifier =
                Self.toolbarDefinitions[previousIndex].identifier
            showPane(at: previousIndex)
        }

        for (index, definition) in Self.toolbarDefinitions.enumerated() {
            window.toolbar?.selectedItemIdentifier = definition.identifier
            showPane(at: index)
            captureView.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let representation = captureView.bitmapImageRepForCachingDisplay(
                in: captureView.bounds
            ) else {
                return false
            }
            captureView.cacheDisplay(in: captureView.bounds, to: representation)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                return false
            }
            do {
                try data.write(
                    to: directoryURL.appendingPathComponent(
                        "settings-\(definition.label.lowercased()).png"
                    ),
                    options: .atomic
                )
            } catch {
                return false
            }
        }
        return true
    }

    private func makeContentView() -> NSView {
        let root = SemanticSurfaceView(kind: .content)
        placementPopup.identifier = .init("PathShelf.Settings.PanelPlacement")
        keyPopup.identifier = .init("PathShelf.Settings.ShortcutKey")
        launchAtLoginCheckbox.identifier = .init("PathShelf.Settings.LaunchAtLogin")
        showHiddenFilesCheckbox.identifier = .init("PathShelf.Settings.ShowHiddenFiles")
        defaultLocationLabel.identifier = .init("PathShelf.Settings.DefaultLocation")
        statusLabel.identifier = .init("PathShelf.Settings.Status")
        exportConfigurationButton.identifier = .init("PathShelf.Settings.ExportConfiguration")
        importConfigurationButton.identifier = .init("PathShelf.Settings.ImportConfiguration")
        placementPopup.addItems(withTitles: ["Cursor adjacent", "Top center"])
        keyPopup.addItems(withTitles: ShortcutKeyChoice.supported.map(\.displayName))

        launchAtLoginCheckbox.title = "Open PathShelf when I log in"
        shortcutHintLabel.textColor = .secondaryLabelColor
        shortcutHintLabel.maximumNumberOfLines = 2
        quickLookGuideLabel.textColor = .secondaryLabelColor
        quickLookGuideLabel.maximumNumberOfLines = 2
        accessGuideLabel.textColor = .secondaryLabelColor
        accessGuideLabel.maximumNumberOfLines = 4

        let modifiers = NSGridView(views: [
            [commandCheckbox, controlCheckbox],
            [optionCheckbox, shiftCheckbox]
        ])
        modifiers.columnSpacing = 12
        modifiers.rowSpacing = 6
        modifiers.column(at: 0).width = 115
        modifiers.column(at: 1).width = 90
        modifiers.setContentHuggingPriority(.required, for: .horizontal)
        let detailColumns = NSStackView(
            views: [
                modifiedColumnCheckbox,
                kindColumnCheckbox,
                sizeColumnCheckbox,
                createdColumnCheckbox,
                availabilityColumnCheckbox
            ]
        )
        detailColumns.orientation = .vertical
        detailColumns.alignment = .leading
        detailColumns.spacing = 6

        defaultLocationLabel.lineBreakMode = .byTruncatingMiddle
        defaultLocationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseDefault = NSButton(title: "Choose…", target: self, action: #selector(chooseDefaultLocation))
        let useHome = NSButton(title: "Use Home", target: self, action: #selector(useHomeAsDefault))
        let defaultControls = NSStackView(views: [defaultLocationLabel, chooseDefault, useHome])
        defaultControls.orientation = .horizontal
        defaultControls.alignment = .centerY
        defaultControls.spacing = 8

        let configurationControls = NSStackView(
            views: [exportConfigurationButton, importConfigurationButton]
        )
        configurationControls.orientation = .horizontal
        configurationControls.alignment = .centerY
        configurationControls.spacing = 8

        let chooseAccessibleFolder = NSButton(
            title: "Choose Accessible Folder…",
            target: self,
            action: #selector(chooseAccessibleFolder)
        )
        chooseAccessibleFolder.image = NSImage(
            systemSymbolName: "folder.badge.plus",
            accessibilityDescription: nil
        )
        chooseAccessibleFolder.symbolConfiguration = .init(
            pointSize: VisualMetrics.settingsSymbolPointSize,
            weight: .medium
        )
        chooseAccessibleFolder.imagePosition = .imageLeading
        chooseAccessibleFolder.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 240
        ).isActive = true
        let openFullDiskAccess = NSButton(
            title: "Open Settings…",
            target: self,
            action: #selector(openFullDiskAccessSettings)
        )
        openFullDiskAccess.image = NSImage(
            systemSymbolName: "lock.shield",
            accessibilityDescription: nil
        )
        openFullDiskAccess.symbolConfiguration = .init(
            pointSize: VisualMetrics.settingsSymbolPointSize,
            weight: .medium
        )
        openFullDiskAccess.imagePosition = .imageLeading
        let revealApp = NSButton(
            title: "Show This App in Finder",
            target: self,
            action: #selector(revealCurrentApp)
        )
        revealApp.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: nil
        )
        revealApp.symbolConfiguration = .init(
            pointSize: VisualMetrics.settingsSymbolPointSize,
            weight: .medium
        )
        revealApp.imagePosition = .imageLeading
        let generalPane = makePane(
            title: "General",
            subtitle: "Choose where the panel appears and how it starts.",
            views: [
                settingsSection([
                    row("Panel placement", placementPopup),
                    indentedControl(launchAtLoginCheckbox)
                ]),
                settingsSection([
                    settingsActionRow(
                        title: "Configuration",
                        detail: "Move settings and Favorites between Macs.",
                        control: configurationControls
                    )
                ])
            ]
        )
        let shortcutPane = makePane(
            title: "Shortcut",
            subtitle: "Configure the global shortcut used to show the panel.",
            views: [
                settingsSection([
                    shortcutHintLabel,
                    row("Shortcut key", keyPopup),
                    row("Modifiers", modifiers)
                ])
            ]
        )
        let browserPane = makePane(
            title: "Browser",
            subtitle: "Set the default folder and information shown in the file list.",
            views: [
                settingsSection([
                    showHiddenFilesCheckbox
                ]),
                settingsSection([
                    settingsActionRow(
                        title: "Visible columns",
                        detail: "Choose the metadata shown beside each file.",
                        control: detailColumns
                    )
                ]),
                settingsSection([
                    settingsActionRow(
                        title: "Default location",
                        detail: "The folder shown when the panel first opens.",
                        control: defaultControls
                    ),
                    quickLookGuideLabel
                ])
            ]
        )
        let accessPane = makePane(
            title: "File & Folder Access",
            subtitle: "Grant only the folder access needed for your Favorites.",
            views: [
                settingsSection([
                    settingsActionRow(
                        title: "Folder Access",
                        detail: accessGuideLabel.stringValue,
                        control: chooseAccessibleFolder
                    )
                ]),
                settingsSection([
                    settingsActionRow(
                        title: "Full Disk Access",
                        detail: "Optional. Most Favorites only need folder access.",
                        control: openFullDiskAccess
                    )
                ]),
                settingsSection([
                    settingsActionRow(
                        title: "Application Location",
                        detail: "Locate this app when adding it to System Settings.",
                        control: revealApp
                    )
                ])
            ]
        )
        panes = [generalPane, shortcutPane, browserPane, accessPane]
        for pane in panes {
            pane.translatesAutoresizingMaskIntoConstraints = false
            paneContainer.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor)
            ])
        }

        let footerSeparator = NSBox()
        footerSeparator.boxType = .separator
        let apply = NSButton(title: "Apply Changes", target: self, action: #selector(applySettings))
        apply.bezelStyle = .rounded
        apply.keyEquivalent = "\r"

        statusLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        for view in [paneContainer, footerSeparator, apply, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            paneContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            paneContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            paneContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            paneContainer.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor, constant: -16),
            footerSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerSeparator.bottomAnchor.constraint(equalTo: apply.topAnchor, constant: -14),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            statusLabel.centerYAnchor.constraint(equalTo: apply.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: apply.leadingAnchor, constant: -16),
            apply.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            apply.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        showPane(at: selectedPaneIndex)
        return root
    }

    private func setStatus(_ message: String, tooltip: String?) {
        statusLabel.stringValue = message
        statusLabel.toolTip = tooltip.map { "\(message)\n\($0)" } ?? message
        if let application = NSApp {
            NSAccessibility.post(
                element: application,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
        }
    }

    private func makePane(title: String, subtitle: String, views: [NSView]) -> NSView {
        let pane = NSView()
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.alignment = .left
        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [titleLabel, subtitleLabel] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(22, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        pane.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 460),
            stack.topAnchor.constraint(equalTo: pane.topAnchor)
        ])
        return pane
    }

    private func settingsSection(_ views: [NSView]) -> NSView {
        let section = SemanticSurfaceView(kind: .settingsSection)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = VisualMetrics.settingsSectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: section.leadingAnchor,
                constant: VisualMetrics.settingsSectionInset
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: section.trailingAnchor,
                constant: -VisualMetrics.settingsSectionInset
            ),
            stack.topAnchor.constraint(
                equalTo: section.topAnchor,
                constant: VisualMetrics.settingsSectionInset
            ),
            stack.bottomAnchor.constraint(
                equalTo: section.bottomAnchor,
                constant: -VisualMetrics.settingsSectionInset
            )
        ])
        return section
    }

    private func settingsActionRow(title: String, detail: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3
        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [textStack, control])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fill
        stack.spacing = 20
        return stack
    }

    private func row(_ label: String, _ control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13)
        title.alignment = .right
        title.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let stack = NSStackView(views: [title, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func indentedControl(_ control: NSView) -> NSView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let stack = NSStackView(views: [spacer, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func configureToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "PathShelf.SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        toolbar.selectedItemIdentifier = Self.toolbarDefinitions[selectedPaneIndex].identifier
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarDefinitions.map(\.identifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarDefinitions.map(\.identifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarDefinitions.map(\.identifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let definition = Self.toolbarDefinitions.first(where: {
            $0.identifier == itemIdentifier
        }) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = definition.label
        item.paletteLabel = definition.label
        item.toolTip = "\(definition.label) settings"
        item.image = NSImage(
            systemSymbolName: definition.symbol,
            accessibilityDescription: definition.label
        )?.withSymbolConfiguration(.init(
            pointSize: VisualMetrics.settingsSymbolPointSize,
            weight: .medium
        ))
        item.target = self
        item.action = #selector(selectSettingsPane(_:))
        return item
    }

    @objc private func selectSettingsPane(_ sender: NSToolbarItem) {
        guard let index = Self.toolbarDefinitions.firstIndex(where: {
            $0.identifier == sender.itemIdentifier
        }) else {
            return
        }
        selectedPaneIndex = index
        UserDefaults.standard.set(index, forKey: Self.selectedPaneDefaultsKey)
        showPane(at: index)
    }

    private func showPane(at index: Int) {
        for (paneIndex, pane) in panes.enumerated() {
            pane.isHidden = paneIndex != index
        }
    }

    private func syncFromSettings(updateStatus: Bool) {
        let settings = invocationController.settings
        pendingDefaultLocationPath = settings.defaultLocationPath
        shortcutHintLabel.stringValue = "Press \(describe(settings.shortcut)) from any app to open the file panel. You can also use the folder icon in the menu bar."
        placementPopup.selectItem(at: settings.panelPlacement.mode == .cursorAdjacent ? 0 : 1)
        let keyChoice = ShortcutKeyChoice.choice(for: settings.shortcut.keyCode)
        keyPopup.selectItem(withTitle: keyChoice.displayName)
        commandCheckbox.state = settings.shortcut.modifiers.contains(.command) ? .on : .off
        controlCheckbox.state = settings.shortcut.modifiers.contains(.control) ? .on : .off
        optionCheckbox.state = settings.shortcut.modifiers.contains(.option) ? .on : .off
        shiftCheckbox.state = settings.shortcut.modifiers.contains(.shift) ? .on : .off
        let launchAtLoginStatus = invocationController.launchAtLoginStatus
        let launchAtLoginAvailable = launchAtLoginStatus != .notFound
        launchAtLoginCheckbox.isEnabled = launchAtLoginAvailable
        launchAtLoginCheckbox.state = switch launchAtLoginStatus {
        case .enabled, .requiresApproval:
            .on
        case .notRegistered, .notFound:
            .off
        }
        launchAtLoginCheckbox.toolTip = launchAtLoginAvailable
            ? nil
            : SettingsStatusFormatter.describe(.notFound)
        showHiddenFilesCheckbox.state = settings.showHiddenFiles ? .on : .off
        modifiedColumnCheckbox.state = settings.visibleDetailColumns.contains(.modified) ? .on : .off
        kindColumnCheckbox.state = settings.visibleDetailColumns.contains(.kind) ? .on : .off
        sizeColumnCheckbox.state = settings.visibleDetailColumns.contains(.size) ? .on : .off
        createdColumnCheckbox.state = settings.visibleDetailColumns.contains(.created) ? .on : .off
        availabilityColumnCheckbox.state = settings.visibleDetailColumns.contains(.availability) ? .on : .off
        updateDefaultLocationLabel()
        if updateStatus {
            statusLabel.stringValue = "Launch at login: \(describe(launchAtLoginStatus))"
        }
    }

    @objc private func applySettings() {
        var messages: [String] = []
        let placementMode: PanelPlacementMode = placementPopup.indexOfSelectedItem == 0
            ? .cursorAdjacent
            : .activeDisplayTopCenter
        switch invocationController.updatePanelPlacement(PanelPlacementPreference(mode: placementMode)) {
        case .success:
            messages.append("Placement saved.")
        case .failure(let error):
            messages.append(error.description)
        }

        let keyChoice = ShortcutKeyChoice.supported[max(0, keyPopup.indexOfSelectedItem)]
        let binding = ShortcutBinding(keyCode: keyChoice.keyCode, modifiers: selectedModifiers())
        switch invocationController.validateAndCommitShortcut(binding) {
        case .success:
            messages.append("Shortcut saved.")
        case .failure(let error):
            messages.append(error.description)
        }

        if launchAtLoginCheckbox.isEnabled {
            switch invocationController.updateLaunchAtLogin(enabled: launchAtLoginCheckbox.state == .on) {
            case .success(let status):
                messages.append("Launch at login: \(describe(status))")
            case .failure(let error):
                messages.append(error.description)
            }
        }

        switch invocationController.updateBrowserPreferences(
            showHiddenFiles: showHiddenFilesCheckbox.state == .on,
            visibleDetailColumns: selectedDetailColumns(),
            defaultLocationPath: pendingDefaultLocationPath
        ) {
        case .success:
            messages.append("Browser preferences saved.")
            onApply()
        case .failure(let error):
            messages.append(error.description)
        }
        statusLabel.stringValue = messages.joined(separator: "  •  ")
        syncFromSettings(updateStatus: false)
    }

    @objc private func chooseDefaultLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Default"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            self?.pendingDefaultLocationPath = url.path
            self?.updateDefaultLocationLabel()
        }
    }

    @objc private func useHomeAsDefault() {
        pendingDefaultLocationPath = nil
        updateDefaultLocationLabel()
    }

    @objc private func chooseAccessibleFolder() {
        guard let window else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                return
            }
            do {
                try onGrantFolderAccess(url)
                setStatus(
                    "Access granted and \(url.lastPathComponent) was added to Favorites.",
                    tooltip: nil
                )
            } catch {
                let message = (error as? FileBrowserError)?.description
                    ?? "Could not grant folder access. The selected folder could not be saved."
                setStatus(message, tooltip: nil)
            }
        }
    }

    @objc private func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ), NSWorkspace.shared.open(url) else {
            statusLabel.stringValue = "Could not open Full Disk Access settings."
            return
        }
        statusLabel.stringValue = "Click +, select the PathShelf.app shown in Finder, enable it, then relaunch."
    }

    @objc private func revealCurrentApp() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
        statusLabel.stringValue = "App selected in Finder: \(appURL.path)"
    }

    private func selectedDetailColumns() -> [FileDetailColumn] {
        var columns: [FileDetailColumn] = []
        if modifiedColumnCheckbox.state == .on { columns.append(.modified) }
        if kindColumnCheckbox.state == .on { columns.append(.kind) }
        if sizeColumnCheckbox.state == .on { columns.append(.size) }
        if createdColumnCheckbox.state == .on { columns.append(.created) }
        if availabilityColumnCheckbox.state == .on { columns.append(.availability) }
        return columns
    }

    private func updateDefaultLocationLabel() {
        defaultLocationLabel.stringValue = pendingDefaultLocationPath ?? "Home directory"
        defaultLocationLabel.toolTip = defaultLocationLabel.stringValue
    }

    private func selectedModifiers() -> Set<ShortcutBinding.Modifier> {
        var modifiers: Set<ShortcutBinding.Modifier> = []
        if commandCheckbox.state == .on { modifiers.insert(.command) }
        if controlCheckbox.state == .on { modifiers.insert(.control) }
        if optionCheckbox.state == .on { modifiers.insert(.option) }
        if shiftCheckbox.state == .on { modifiers.insert(.shift) }
        return modifiers
    }

    private func describe(_ status: LaunchAtLoginStatus) -> String {
        SettingsStatusFormatter.describe(status)
    }

    private func describe(_ binding: ShortcutBinding) -> String {
        var parts: [String] = []
        if binding.modifiers.contains(.control) { parts.append("Control") }
        if binding.modifiers.contains(.option) { parts.append("Option") }
        if binding.modifiers.contains(.shift) { parts.append("Shift") }
        if binding.modifiers.contains(.command) { parts.append("Command") }
        parts.append(ShortcutKeyChoice.choice(for: binding.keyCode).displayName)
        return parts.joined(separator: " + ")
    }
}
