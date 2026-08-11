import AppKit
import FileAccess
import PanelFeature
import FileOperations

extension PanelContentView {
    func makeFavoriteContextMenu(for item: FavoriteSidebarItem?) -> NSMenu {
        let menu = NSMenu(title: "Favorites")
        switch item {
        case .location:
            menu.addItem(withTitle: "Open", action: #selector(openSavedLocation(_:)), keyEquivalent: "").target = self
            menu.addItem(
                withTitle: "Reveal in Finder",
                action: #selector(revealSavedLocation(_:)),
                keyEquivalent: ""
            ).target = self
            let openWithItem = NSMenuItem(
                title: "Open With…",
                action: #selector(openWithMenuPlaceholder(_:)),
                keyEquivalent: ""
            )
            openWithItem.target = self
            openWithItem.submenu = makeFavoriteOpenWithMenu()
            menu.addItem(openWithItem)
            menu.addItem(withTitle: "Retry Access", action: #selector(retrySavedLocation(_:)), keyEquivalent: "").target = self
            let reauthorizeItem = menu.addItem(
                withTitle: "Choose New Folder…",
                action: #selector(reauthorizeSavedLocation(_:)),
                keyEquivalent: ""
            )
            reauthorizeItem.target = self
            reauthorizeItem.identifier = .init("PathShelf.Favorites.ChooseNewFolder")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Rename…", action: #selector(renameSavedLocation(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Move Up", action: #selector(moveSavedLocationUp(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Move Down", action: #selector(moveSavedLocationDown(_:)), keyEquivalent: "").target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Remove from Favorites", action: #selector(removeSavedLocation(_:)), keyEquivalent: "").target = self
        case .group(let group?):
            menu.addItem(withTitle: "New Group…", action: #selector(addFavoriteGroup(_:)), keyEquivalent: "").target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Rename Group…", action: #selector(renameFavoriteGroup(_:)), keyEquivalent: "").target = self
            let iconItem = NSMenuItem(title: "Change Icon", action: nil, keyEquivalent: "")
            let iconMenu = NSMenu(title: "Change Icon")
            for choice in Self.favoriteGroupIconChoices {
                let choiceItem = iconMenu.addItem(
                    withTitle: choice.title,
                    action: #selector(changeFavoriteGroupIcon(_:)),
                    keyEquivalent: ""
                )
                choiceItem.target = self
                choiceItem.representedObject = choice.symbol
                choiceItem.image = NSImage(
                    systemSymbolName: choice.symbol,
                    accessibilityDescription: choice.title
                )
                choiceItem.state = (group.iconName ?? "folder.fill") == choice.symbol ? .on : .off
            }
            iconItem.submenu = iconMenu
            menu.addItem(iconItem)
            menu.addItem(withTitle: "Move Group Up", action: #selector(moveFavoriteGroupUp(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Move Group Down", action: #selector(moveFavoriteGroupDown(_:)), keyEquivalent: "").target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Delete Group", action: #selector(removeFavoriteGroup(_:)), keyEquivalent: "").target = self
        case .group(nil), nil:
            menu.addItem(withTitle: "Add Favorite…", action: #selector(addSavedLocation(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "New Group…", action: #selector(addFavoriteGroup(_:)), keyEquivalent: "").target = self
        }
        return menu
    }

    @objc func openSavedLocation(_ sender: Any?) {
        guard let id = favoriteIDForAction(sender) else {
            return
        }
        favoriteActivationTask?.cancel()
        favoriteActivationTask = Task { [weak self] in
            do {
                try await self?.model.navigateToSavedLocation(id: id)
            } catch {
                self?.showError(String(describing: error))
            }
            self?.refreshTablesAndThumbnails()
        }
    }

    @objc func addSavedLocation(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add to Favorites"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                return
            }
            do {
                try model.addSavedLocation(url: url)
                refreshTables()
            } catch {
                showError(String(describing: error))
            }
        }
    }

    @objc func addFavoriteGroup(_ sender: Any?) {
        guard let name = prompt(message: "New favorite group name:", defaultValue: "New Group") else {
            return
        }
        do {
            _ = try model.addFavoriteGroup(named: name)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func renameFavoriteGroup(_ sender: Any?) {
        guard let id = favoriteGroupIDForAction(sender),
              let group = model.favoriteGroups.first(where: { $0.id == id }),
              let name = prompt(message: "Favorite group name:", defaultValue: group.name) else {
            return
        }
        do {
            try model.renameFavoriteGroup(id: id, to: name)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func changeFavoriteGroupIcon(_ sender: NSMenuItem) {
        guard let id = favoriteGroupIDForAction(sender),
              let iconName = sender.representedObject as? String else {
            return
        }
        do {
            try model.updateFavoriteGroupIcon(id: id, iconName: iconName)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func moveFavoriteGroupUp(_ sender: Any?) {
        moveFavoriteGroup(for: sender, direction: -1)
    }

    @objc func moveFavoriteGroupDown(_ sender: Any?) {
        moveFavoriteGroup(for: sender, direction: 1)
    }

    @objc func removeFavoriteGroup(_ sender: Any?) {
        guard let id = favoriteGroupIDForAction(sender) else {
            return
        }
        do {
            try model.removeFavoriteGroup(id: id)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    private func moveFavoriteGroup(for sender: Any?, direction: Int) {
        guard let id = favoriteGroupIDForAction(sender),
              let index = model.favoriteGroups.firstIndex(where: { $0.id == id }) else {
            return
        }
        let target = index + direction
        guard model.favoriteGroups.indices.contains(target) else {
            return
        }
        let beforeID = direction > 0
            ? (model.favoriteGroups.indices.contains(target + 1) ? model.favoriteGroups[target + 1].id : nil)
            : model.favoriteGroups[target].id
        do {
            try model.moveFavoriteGroup(id: id, before: beforeID)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func renameSavedLocation(_ sender: Any?) {
        guard let id = favoriteIDForAction(sender),
              let location = model.savedLocations.first(where: { $0.id == id }),
              let name = prompt(message: "Favorite name:", defaultValue: location.displayName) else {
            return
        }
        do {
            try model.renameSavedLocation(id: id, to: name)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func revealSavedLocation(_ sender: Any?) {
        guard let id = favoriteIDForAction(sender),
              let location = model.savedLocations.first(where: { $0.id == id }) else {
            return
        }
        let url = URL(fileURLWithPath: location.bookmark.originalPath, isDirectory: true)
        do {
            try workspaceService.revealInFinder(url)
            onEscape()
        } catch {
            showError(String(describing: error))
        }
    }

    @objc func retrySavedLocation(_ sender: Any?) {
        guard let id = favoriteIDForAction(sender) else {
            return
        }
        Task { [weak self] in
            do {
                try await self?.model.retrySavedLocation(id: id)
            } catch {
                self?.showError(String(describing: error))
            }
            self?.refreshTables()
        }
    }

    func reauthorizeSelectedOrFirstUnavailableFavorite() async -> Bool {
        await awaitInitialLoad()
        guard let id = Self.reauthorizationTargetID(
            selectedRow: sidebarTable.selectedRow,
            visibleItems: sidebarDataSource.visibleItems,
            savedLocations: model.savedLocations
        ) else {
            showStatus("No Favorite needs folder access.")
            return false
        }
        presentReauthorizationPanel(for: id)
        return true
    }

    static func reauthorizationTargetID(
        selectedRow: Int,
        visibleItems: [FavoriteSidebarItem],
        savedLocations: [SavedLocation]
    ) -> UUID? {
        if visibleItems.indices.contains(selectedRow),
           case .location(let location) = visibleItems[selectedRow] {
            return location.id
        }
        return savedLocations.first(where: {
            ExternalLocationStateResolver.isUsable($0.availability) == false
        })?.id
    }

    @objc func reauthorizeSavedLocation(_ sender: Any?) {
        guard let id = favoriteIDForAction(sender) else {
            return
        }
        presentReauthorizationPanel(for: id)
    }

    private func presentReauthorizationPanel(for id: UUID) {
        let panel = NSOpenPanel()
        panel.identifier = .init("PathShelf.Favorites.ReauthorizePanel")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose New Folder"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                return
            }
            do {
                try model.reauthorizeSavedLocation(id: id, url: url)
                refreshTables()
                let name = model.savedLocations.first(where: { $0.id == id })?.displayName
                    ?? "Favorite"
                showStatus("Folder access updated for \(name).")
            } catch {
                showError(reauthorizationErrorMessage(error))
            }
        }
    }

    private func reauthorizationErrorMessage(_ error: Error) -> String {
        if let browserError = error as? FileBrowserError {
            return browserError.description
        }
        return "Could not update folder access. The selected folder could not be saved."
    }

    @objc func moveSavedLocationUp(_ sender: Any?) {
        moveSavedLocation(for: sender, direction: -1)
    }

    @objc func moveSavedLocationDown(_ sender: Any?) {
        moveSavedLocation(for: sender, direction: 1)
    }

    @objc func removeSavedLocation(_ sender: Any?) {
        guard let id = favoriteIDForAction(sender) else {
            return
        }
        do {
            try model.removeSavedLocation(id: id)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    private func moveSavedLocation(for sender: Any?, direction: Int) {
        guard let id = favoriteIDForAction(sender) else {
            return
        }
        do {
            try model.moveSavedLocation(id: id, direction: direction)
            refreshTables()
        } catch {
            showError(String(describing: error))
        }
    }

    func favoriteIDForAction(_ sender: Any?) -> UUID? {
        if sender is NSMenuItem {
            guard case .location(let location)? = contextSidebarItem else {
                return nil
            }
            return location.id
        }
        let row = sidebarTable.clickedRow >= 0 ? sidebarTable.clickedRow : sidebarTable.selectedRow
        let items = sidebarDataSource.visibleItems
        guard items.indices.contains(row), case .location(let location) = items[row] else {
            return nil
        }
        return location.id
    }

    func favoriteGroupIDForAction(_ sender: Any?) -> UUID? {
        if sender is NSMenuItem {
            guard case .group(let group?)? = contextSidebarItem else {
                return nil
            }
            return group.id
        }
        let row = sidebarTable.clickedRow >= 0 ? sidebarTable.clickedRow : sidebarTable.selectedRow
        let items = sidebarDataSource.visibleItems
        guard items.indices.contains(row), case .group(let group?) = items[row] else {
            return nil
        }
        return group.id
    }

    func handleFavoriteDrop(
        payload: FavoriteSidebarDragPayload,
        row: Int,
        operation: NSTableView.DropOperation
    ) -> Bool {
        let items = sidebarDataSource.visibleItems
        do {
            switch payload {
            case .group(let sourceID):
                let targetID = items.dropFirst(max(0, row)).compactMap { item -> UUID? in
                    guard case .group(let group?) = item, group.id != sourceID else {
                        return nil
                    }
                    return group.id
                }.first
                try model.moveFavoriteGroup(id: sourceID, before: targetID)
            case .location(let sourceID):
                let destination: (groupID: UUID?, beforeID: UUID?)
                if items.indices.contains(row) {
                    switch items[row] {
                    case .group(let group):
                        destination = (group?.id, nil)
                    case .location(let location):
                        destination = (location.groupID, location.id)
                    }
                } else {
                    destination = (nil, nil)
                }
                try model.moveSavedLocation(
                    id: sourceID,
                    toGroup: destination.groupID,
                    before: operation == .on ? nil : destination.beforeID
                )
            }
            refreshTables()
            return true
        } catch {
            showError(String(describing: error))
            return false
        }
    }

    private func makeFavoriteOpenWithMenu() -> NSMenu {
        let menu = NSMenu(title: "Open With")
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Finder", action: #selector(revealSavedLocation(_:)), keyEquivalent: "").target = self

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
                self?.openFavoriteWithApplication(application.url)
            })
        }
        return menu
    }

    private func openFavoriteWithApplication(_ applicationURL: URL) {
        guard case .location(let location)? = contextSidebarItem else {
            return
        }
        let url = URL(fileURLWithPath: location.bookmark.originalPath, isDirectory: true)
        Task { [weak self] in
            do {
                try await self?.workspaceService.open(url, with: applicationURL)
                self?.onEscape()
            } catch {
                self?.showError(String(describing: error))
            }
        }
    }
}
