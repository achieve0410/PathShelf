import AppKit
import FileOperations
import FileAccess
import PanelFeature

extension PanelContentView {
    func makeActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "File actions")
        menu.addItem(withTitle: "Open", action: #selector(openSelection(_:)), keyEquivalent: "").target = self
        let openWithItem = NSMenuItem(
            title: "Open With…",
            action: #selector(openWithMenuPlaceholder(_:)),
            keyEquivalent: ""
        )
        openWithItem.target = self
        openWithItem.submenu = makeOpenWithMenu()
        menu.addItem(openWithItem)
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealSelection(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Add to Favorites", action: #selector(addSelectionToFavorites(_:)), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "New Folder…", action: #selector(createFolder(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Rename…", action: #selector(renameSelection(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy To…", action: #selector(copySelection(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Move To…", action: #selector(moveSelection(_:)), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Move to Trash", action: #selector(trashSelection), keyEquivalent: "").target = self
        return menu
    }

    private func makeOpenWithMenu() -> NSMenu {
        let menu = NSMenu(title: "Open With")
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Finder", action: #selector(revealSelection(_:)), keyEquivalent: "").target = self

        let preferredApplications: [(String, [String])] = [
            ("Visual Studio Code", ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]),
            ("iTerm2", ["com.googlecode.iterm2"]),
            ("Terminal", ["com.apple.Terminal"]),
            ("Google Chrome", ["com.google.Chrome"])
        ]
        for (name, bundleIdentifiers) in preferredApplications {
            guard let applicationURL = bundleIdentifiers.lazy.compactMap({
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }).first else {
                continue
            }
            let application = WorkspaceApplication(
                name: name,
                bundleIdentifier: bundleIdentifiers.first,
                url: applicationURL
            )
            menu.addItem(OpenWithMenuItem(application: application) { [weak self] application in
                self?.openSelectionWithApplication(application.url)
            })
        }
        return menu
    }

    func makePathComponentMenu(for url: URL) -> NSMenu {
        let menu = NSMenu(title: url.lastPathComponent)
        let revealItem = NSMenuItem(title: "Reveal in Finder", action: nil, keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)
        revealItem.representedObject = url
        revealItem.action = #selector(revealPathComponent(_:))

        let openWithItem = NSMenuItem(
            title: "Open With…",
            action: #selector(openWithMenuPlaceholder(_:)),
            keyEquivalent: ""
        )
        openWithItem.target = self
        openWithItem.submenu = makeOpenWithMenuForURL(url)
        menu.addItem(openWithItem)
        return menu
    }

    private func makeOpenWithMenuForURL(_ url: URL) -> NSMenu {
        let menu = NSMenu(title: "Open With")
        menu.autoenablesItems = false
        let finderItem = NSMenuItem(
            title: "Finder",
            action: #selector(revealPathComponent(_:)),
            keyEquivalent: ""
        )
        finderItem.target = self
        finderItem.representedObject = url
        menu.addItem(finderItem)
        let preferredApplications: [(String, [String])] = [
            ("Visual Studio Code", ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]),
            ("iTerm2", ["com.googlecode.iterm2"]),
            ("Terminal", ["com.apple.Terminal"]),
            ("Google Chrome", ["com.google.Chrome"])
        ]
        for (name, bundleIdentifiers) in preferredApplications {
            guard let applicationURL = bundleIdentifiers.lazy.compactMap({
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }).first else {
                continue
            }
            let application = WorkspaceApplication(
                name: name,
                bundleIdentifier: bundleIdentifiers.first,
                url: applicationURL
            )
            let targetURL = url
            menu.addItem(OpenWithMenuItem(application: application) { [weak self] application in
                Task { [weak self] in
                    do {
                        try await self?.workspaceService.open(targetURL, with: application.url)
                    } catch {
                        self?.showError(String(describing: error))
                    }
                }
            })
        }
        return menu
    }

    @objc func revealPathComponent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        do {
            try workspaceService.revealInFinder(url)
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func addSelectionToFavorites(_ sender: Any?) {
        guard let item = itemForAction(sender), item.kind == .directory else {
            showError("Select a folder to add it to Favorites.")
            return
        }
        if model.savedLocations.contains(where: { $0.bookmark.originalPath == item.url.path }) {
            showError("\(item.name) is already in Favorites.")
            return
        }
        do {
            try model.addSavedLocation(url: item.url)
            refreshTables()
            statusLabel.stringValue = "Added \(item.name) to Favorites."
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func createFolder(_ sender: Any? = nil) {
        guard let name = prompt(message: "New folder name:", defaultValue: "Untitled Folder") else {
            return
        }
        Task { [weak self] in
            let policy = await self?.conflictPolicyForUser(
                replaceWarning: "Replace can move an existing folder to the macOS Trash before creating the new folder."
            ) ?? .skip
            _ = await self?.model.createFolder(named: name, conflictPolicy: policy)
            self?.refreshTablesAndThumbnails()
        }
    }

    @objc func renameSelection(_ sender: Any? = nil) {
        guard let item = selectItemForModelAction(sender),
              let name = prompt(message: "Rename:", defaultValue: item.name) else {
            return
        }
        Task { [weak self] in
            let policy = await self?.conflictPolicyForUser(
                replaceWarning: "Replace can move an existing item to the macOS Trash before renaming."
            ) ?? .skip
            _ = await self?.model.renameSelection(to: name, conflictPolicy: policy)
            self?.refreshTablesAndThumbnails()
        }
    }

    @objc func copySelection(_ sender: Any? = nil) {
        _ = selectItemForModelAction(sender)
        copyOrMoveSelection(move: false)
    }

    @objc func moveSelection(_ sender: Any? = nil) {
        _ = selectItemForModelAction(sender)
        copyOrMoveSelection(move: true)
    }

    private func copyOrMoveSelection(move: Bool) {
        guard model.selectedItem != nil else {
            showError("No item is selected.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = move ? "Move" : "Copy"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let destinationURL = panel.url else {
                return
            }
            Task { [weak self] in
                guard let self else {
                    return
                }
                let policy = await conflictPolicyForUser(
                    replaceWarning: "Replace can move an existing destination item to the macOS Trash before copying or moving."
                )
                if move {
                    _ = await model.moveSelection(to: destinationURL, conflictPolicy: policy)
                } else {
                    _ = await model.copySelection(to: destinationURL, conflictPolicy: policy)
                }
                refreshTablesAndThumbnails()
            }
        }
    }

    @objc func openSelection(_ sender: Any? = nil) {
        _ = selectItemForModelAction(sender)
        Task { [weak self] in
            guard let self else {
                return
            }
            if let url = await model.openSelectionOrEnterDirectory() {
                do {
                    try workspaceService.openDefault(url)
                    onEscape()
                } catch {
                    showError(String(describing: error))
                }
            }
            refreshTablesAndThumbnails()
        }
    }

    @objc func openClickedFile(_ sender: Any?) {
        let row = fileTable.clickedRow >= 0 ? fileTable.clickedRow : fileTable.selectedRow
        guard model.items.indices.contains(row) else {
            return
        }
        model.select(index: row)
        openSelection(nil)
    }

    private func openSelectionWithApplication(_ applicationURL: URL) {
        guard let item = itemForActionContext() else {
            showError("No item is selected.")
            return
        }
        Task { [weak self] in
            do {
                try await self?.workspaceService.open(item.url, with: applicationURL)
                self?.onEscape()
            } catch {
                self?.showError(String(describing: error))
            }
        }
    }

    @objc func openWithMenuPlaceholder(_ sender: Any?) {}

    @objc func revealSelection(_ sender: Any? = nil) {
        guard let item = itemForAction(sender) else {
            showError("No item is selected.")
            return
        }
        do {
            try workspaceService.revealInFinder(item.url)
            onEscape()
        } catch {
            showError(String(describing: error))
        }
    }

    func toggleQuickLookFromKeyboard() {
        guard let item = model.selectedItem else {
            showError("Select an item, then press Space to preview it.")
            return
        }
        model.presentQuickLookForSelection()
        quickLookCoordinator.toggle(item.url)
    }

    private func itemForAction(_ sender: Any?) -> FileItem? {
        if sender is NSMenuItem {
            return itemForActionContext()
        }
        return model.selectedItem
    }

    private func itemForActionContext() -> FileItem? {
        if let contextItemURL,
           let item = model.items.first(where: { $0.url == contextItemURL }) {
            return item
        }
        return model.selectedItem
    }

    @discardableResult
    private func selectItemForModelAction(_ sender: Any?) -> FileItem? {
        guard let item = itemForAction(sender),
              let index = model.items.firstIndex(where: { $0.url == item.url }) else {
            return nil
        }
        model.select(index: index)
        return item
    }

    @objc func trashSelection() {
        guard model.selectedItem != nil else {
            showError("No item is selected.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = "The selected item will be moved to the macOS Trash."
        alert.addButton(withTitle: "Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { [weak self] in
            _ = await self?.model.trashSelection(confirm: true)
            self?.refreshTablesAndThumbnails()
        }
    }

    private func conflictPolicyForUser(replaceWarning: String) async -> ConflictPolicy {
        let alert = NSAlert()
        alert.messageText = "Name conflict policy"
        alert.informativeText = "Skip is the safe default. Replace only runs when explicitly selected."
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        switch alert.runModal() {
        case .alertThirdButtonReturn:
            let replaceAlert = NSAlert()
            replaceAlert.messageText = "Replace existing item?"
            replaceAlert.informativeText = replaceWarning
            replaceAlert.addButton(withTitle: "Replace")
            replaceAlert.addButton(withTitle: "Skip")
            guard replaceAlert.runModal() == .alertFirstButtonReturn else {
                return .skip
            }
            return .replace
        case .alertSecondButtonReturn:
            return .keepBoth
        default:
            return .skip
        }
    }

    func copyOrMoveDroppedURLs(_ urls: [URL], move: Bool) {
        Task { [weak self] in
            guard let self else {
                return
            }
            let policy = await conflictPolicyForUser(
                replaceWarning: "Replace can move an existing destination item to the macOS Trash before copying or moving dropped files."
            )
            for url in urls {
                let request = FileOperationRequest(
                    action: move ? .move : .copy,
                    sourceURL: url,
                    destinationDirectoryURL: model.currentDirectoryURL,
                    conflictPolicy: policy
                )
                _ = await model.performFileOperation(request)
            }
            refreshTablesAndThumbnails()
        }
    }

    func prompt(message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        let field = NSTextField(string: defaultValue)
        field.frame = CGRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return field.stringValue
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openSavedLocation(_:)),
             #selector(revealSavedLocation(_:)),
             #selector(retrySavedLocation(_:)),
             #selector(renameSavedLocation(_:)),
             #selector(moveSavedLocationUp(_:)),
             #selector(moveSavedLocationDown(_:)),
             #selector(removeSavedLocation(_:)):
            return favoriteIDForAction(menuItem) != nil
        case #selector(renameFavoriteGroup(_:)),
             #selector(changeFavoriteGroupIcon(_:)),
             #selector(moveFavoriteGroupUp(_:)),
             #selector(moveFavoriteGroupDown(_:)),
             #selector(removeFavoriteGroup(_:)):
            return favoriteGroupIDForAction(menuItem) != nil
        case #selector(openWithMenuPlaceholder(_:)):
            if itemForAction(menuItem) != nil {
                return true
            }
            if favoriteIDForAction(menuItem) != nil {
                return true
            }
            return menuItem.submenu?.items.isEmpty == false
        case #selector(revealPathComponent(_:)):
            return menuItem.representedObject as? URL != nil
        case #selector(openSelection(_:)),
             #selector(revealSelection(_:)),
             #selector(renameSelection(_:)),
             #selector(copySelection(_:)),
             #selector(moveSelection(_:)),
             #selector(trashSelection):
            return itemForAction(menuItem) != nil
        case #selector(addSelectionToFavorites(_:)):
            guard let item = itemForAction(menuItem), item.kind == .directory else {
                return false
            }
            return model.savedLocations.contains { $0.bookmark.originalPath == item.url.path } == false
        default:
            return true
        }
    }

}
