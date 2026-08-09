import AppKit
import FileAccess
import PanelFeature

private struct FileVisualPresentation {
    var image: NSImage
    var showsDocumentBadge: Bool
}

private enum FileVisualResolver {
    static func resolve(
        thumbnail: NSImage?,
        nativeIcon: NSImage
    ) -> FileVisualPresentation {
        guard let thumbnail else {
            return FileVisualPresentation(
                image: nativeIcon,
                showsDocumentBadge: false
            )
        }
        return FileVisualPresentation(
            image: thumbnail,
            showsDocumentBadge: true
        )
    }
}

@MainActor
final class FileTableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let model: FileBrowserModel
    private var thumbnails: [URL: NSImage] = [:]
    var onDrop: (([URL], Bool) -> Void)?
    var onSortColumn: ((String) -> Void)?
    var explicitMoveSignal: () -> Bool = { false }
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()

    init(model: FileBrowserModel) {
        self.model = model
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard model.items.indices.contains(row) else {
            return nil
        }
        let item = model.items[row]
        switch tableColumn?.identifier.rawValue {
        case "metadata":
            let value: String
            switch item.localAvailability {
            case .downloadRequired:
                value = "Download required"
            case .local, .unknown:
                value = item.contentModificationDate.map { dateFormatter.string(from: $0) } ?? ""
            }
            return detailLabel(
                value,
                color: item.localAvailability == .downloadRequired ? .systemOrange : nil
            )
        case "kind":
            return detailLabel(kindDescription(item.kind))
        case "size":
            let value = item.byteSize.map { byteCountFormatter.string(fromByteCount: $0) } ?? "—"
            return detailLabel(value)
        case "created":
            return detailLabel(item.creationDate.map { dateFormatter.string(from: $0) } ?? "—")
        case "availability":
            return detailLabel(
                availabilityDescription(item.localAvailability),
                color: item.localAvailability == .downloadRequired ? .systemOrange : nil
            )
        default:
            break
        }

        let cell = NSTableCellView()
        let imageView = NSImageView()
        let thumbnail = thumbnails[item.url]
        let visual = FileVisualResolver.resolve(
            thumbnail: thumbnail,
            nativeIcon: NSWorkspace.shared.icon(forFile: item.url.path)
        )
        imageView.image = visual.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: VisualMetrics.fileIconSize).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: VisualMetrics.fileIconSize).isActive = true
        if item.kind == .file {
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.quaternaryLabelColor
                .withAlphaComponent(0.12)
                .cgColor
            imageView.layer?.borderColor = NSColor.separatorColor
                .withAlphaComponent(0.5)
                .cgColor
            imageView.layer?.borderWidth = 0.5
            imageView.layer?.cornerRadius = 3
        }
        let thumbnailBadge: NSImageView? = visual.showsDocumentBadge ? {
            let badge = NSImageView(
                image: NSImage(
                    systemSymbolName: "doc.fill",
                    accessibilityDescription: kindDescription(item.kind)
                ) ?? NSImage()
            )
            badge.contentTintColor = .secondaryLabelColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            return badge
        }() : nil

        let label = NSTextField(labelWithString: item.name)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.toolTip = item.url.path

        cell.addSubview(imageView)
        if let thumbnailBadge {
            cell.addSubview(thumbnailBadge)
        }
        cell.addSubview(label)
        var constraints = [
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ]
        if let thumbnailBadge {
            constraints.append(contentsOf: [
                thumbnailBadge.widthAnchor.constraint(equalToConstant: 8),
                thumbnailBadge.heightAnchor.constraint(equalToConstant: 8),
                thumbnailBadge.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 1),
                thumbnailBadge.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 1)
            ])
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    private func detailLabel(_ value: String, color: NSColor? = nil) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = color ?? (value.isEmpty || value == "—" ? .secondaryLabelColor : .labelColor)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        onSortColumn?(tableColumn.identifier.rawValue)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else {
            return
        }
        model.select(index: tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard model.items.indices.contains(row) else {
            return nil
        }
        return model.items[row].url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        shouldMoveDrop(info) ? .move : .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let items = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], items.isEmpty == false else {
            return false
        }
        onDrop?(items, shouldMoveDrop(info))
        return true
    }

    private func shouldMoveDrop(_ info: NSDraggingInfo) -> Bool {
        DropOperationResolver.shouldMove(
            DropOperationIntent(
                allowsMove: info.draggingSourceOperationMask.contains(.move),
                explicitMove: explicitMoveSignal()
            )
        )
    }

    func setThumbnail(_ image: NSImage, for url: URL) {
        thumbnails[url] = image
    }

    func removeThumbnails() {
        thumbnails.removeAll()
    }

    var renderingPolicyReady: Bool {
        let nativeIcon = NSImage(size: CGSize(width: 16, height: 16))
        let thumbnail = NSImage(size: CGSize(width: 32, height: 32))
        let fallback = FileVisualResolver.resolve(
            thumbnail: nil,
            nativeIcon: nativeIcon
        )
        let preview = FileVisualResolver.resolve(
            thumbnail: thumbnail,
            nativeIcon: nativeIcon
        )
        return fallback.image === nativeIcon
            && fallback.showsDocumentBadge == false
            && preview.image === thumbnail
            && preview.showsDocumentBadge
    }

    private func kindDescription(_ kind: FileItem.Kind) -> String {
        switch kind {
        case .directory:
            return "Folder"
        case .file:
            return "File"
        case .symbolicLink:
            return "Alias / Link"
        case .other:
            return "Other"
        }
    }

    private func availabilityDescription(_ availability: FileItem.LocalAvailability) -> String {
        switch availability {
        case .local:
            return "Local"
        case .downloadRequired:
            return "Download required"
        case .unknown:
            return "Unknown"
        }
    }
}
