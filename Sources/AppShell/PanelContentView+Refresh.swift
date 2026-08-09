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
        statusLabel.stringValue = statusText()
        sidebarTable.reloadData()
        fileTable.reloadData()
        updateBrowserState()
        updateWindowTitle()
        if let selectedIndex = model.selectedIndex {
            fileTable.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }
    }

    private func updateBrowserState() {
        guard model.isLoading == false else {
            browserStateView.isHidden = true
            return
        }
        switch model.availability {
        case .available where model.items.isEmpty:
            browserStateView.show(
                symbolName: "folder",
                title: "This folder is empty",
                detail: nil,
                tintColor: .secondaryLabelColor
            )
        case .unavailable:
            browserStateView.show(
                symbolName: "exclamationmark.triangle",
                title: "This location isn’t available",
                detail: model.lastErrorMessage,
                tintColor: .systemOrange
            )
        case .available:
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
        switch model.availability {
        case .available:
            return model.items.isEmpty ? "Empty folder" : "\(model.items.count) items"
        case .unavailable(let availability, let path):
            return "\(availability.rawValue): \(path)"
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
        statusLabel.stringValue = message
    }
}
