import AppKit
import PreviewFeature

extension PanelContentView {
    func refreshTablesAndThumbnails() {
        refreshTables()
        startThumbnailRequests()
    }

    func refreshTables() {
        pathControl.url = model.currentDirectoryURL
        pathControl.toolTip = model.currentDirectoryURL.path
        if searchField.stringValue != model.filterQuery {
            searchField.stringValue = model.filterQuery
        }
        statusLabel.stringValue = statusText()
        statusLabel.toolTip = statusLabel.stringValue
        statusLabel.setAccessibilityValue(statusLabel.stringValue)
        sidebarTable.reloadData()
        fileTable.reloadData()
        updateBrowserState()
        updateWindowTitle()
        if let selectedIndex = model.selectedIndex {
            fileTable.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else {
            fileTable.deselectAll(nil)
        }
    }

    private func updateBrowserState() {
        guard model.isLoading == false else {
            fileScrollView?.isHidden = true
            browserStateView.show(
                symbolName: "arrow.triangle.2.circlepath",
                title: "Loading…",
                detail: nil,
                tintColor: .secondaryLabelColor
            )
            return
        }
        switch model.availability {
        case .available where model.unfilteredItemCount == 0:
            fileScrollView?.isHidden = true
            browserStateView.show(
                symbolName: "folder",
                title: "This folder is empty",
                detail: nil,
                tintColor: .secondaryLabelColor
            )
        case .available where model.items.isEmpty && model.filterQuery.isEmpty == false:
            fileScrollView?.isHidden = true
            browserStateView.show(
                symbolName: "magnifyingglass",
                title: "No matching items",
                detail: "No filenames match “\(model.filterQuery)”.",
                tintColor: .secondaryLabelColor
            )
        case .unavailable:
            fileScrollView?.isHidden = true
            browserStateView.show(
                symbolName: "exclamationmark.triangle",
                title: "This location isn’t available",
                detail: model.lastErrorMessage,
                tintColor: .systemOrange
            )
        case .available:
            fileScrollView?.isHidden = false
            browserStateView.isHidden = true
        }
    }

    private func updateWindowTitle() {
        let folderName = model.currentDirectoryURL.lastPathComponent
        window?.title = folderName.isEmpty ? model.currentDirectoryURL.path : folderName
        window?.representedURL = model.currentDirectoryURL
    }

    private func statusText() -> String {
        if let error = model.lastErrorMessage {
            return error
        }
        if model.isLoading {
            return "Loading…"
        }
        switch model.availability {
        case .available:
            if model.unfilteredItemCount == 0 {
                return "Empty folder"
            }
            if model.filterQuery.isEmpty == false {
                return "\(model.items.count) of \(model.unfilteredItemCount) items"
            }
            return "\(model.items.count) items"
        case .unavailable(let availability, let path):
            return "\(availability.accessibilityDescription): \(path)"
        }
    }

    func startThumbnailRequests() {
        cancelThumbnailRequests()
        guard isTornDown == false else {
            return
        }
        let generation = model.generation
        for item in model.items.prefix(60) where item.kind == .file {
            let request = ThumbnailRequest(url: item.url, size: CGSize(width: 32, height: 32))
            thumbnailTasks[item.url] = Task { [weak self] in
                guard let self else {
                    return
                }
                if let result = try? await thumbnailService.thumbnail(for: request) {
                    await MainActor.run {
                        guard self.isTornDown == false, self.model.generation == generation else {
                            return
                        }
                        self.fileDataSource.setThumbnail(result.image, for: item.url)
                        self.fileTable.reloadData()
                    }
                }
            }
        }
        model.setActiveThumbnailCount(thumbnailTasks.count)
    }

    func cancelThumbnailRequests() {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        thumbnailService.cancelAll()
        fileDataSource.removeThumbnails()
        model.setActiveThumbnailCount(0)
    }

    func showError(_ message: String) {
        showStatus(message)
    }

    func showStatus(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.toolTip = message
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
}
