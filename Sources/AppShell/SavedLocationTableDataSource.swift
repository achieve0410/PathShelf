import AppKit
import FileAccess
import PanelFeature

private enum FavoriteGroupIdentity: Hashable {
    case defaultGroup
    case group(UUID)
}

@MainActor
final class SavedLocationTableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let model: FileBrowserModel
    private weak var tableView: NSTableView?
    private var collapsedGroups: Set<FavoriteGroupIdentity> = []
    var onDrop: ((FavoriteSidebarDragPayload, Int, NSTableView.DropOperation) -> Bool)?

    init(model: FileBrowserModel) {
        self.model = model
    }

    var visibleItems: [FavoriteSidebarItem] {
        var result: [FavoriteSidebarItem] = []
        var hidesLocations = false
        for item in model.favoriteSidebarItems {
            switch item {
            case .group:
                result.append(item)
                hidesLocations = collapsedGroups.contains(identity(for: item))
            case .location where hidesLocations == false:
                result.append(item)
            case .location:
                continue
            }
        }
        return result
    }

    func attach(to tableView: NSTableView) {
        self.tableView = tableView
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = visibleItems
        guard items.indices.contains(row) else {
            return nil
        }
        switch items[row] {
        case .group(let group):
            return groupCell(
                title: group?.name ?? "Default Group",
                iconName: group?.iconName ?? "tray.full.fill",
                row: row,
                isExpanded: collapsedGroups.contains(identity(for: items[row])) == false
            )
        case .location(let location):
            return locationCell(location)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let items = visibleItems
        guard items.indices.contains(row) else {
            return false
        }
        if case .group = items[row] {
            return false
        }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let items = visibleItems
        guard items.indices.contains(row) else {
            return tableView.rowHeight
        }
        if case .group = items[row] {
            return 32
        }
        return 28
    }

    private func groupCell(title: String, iconName: String, row: Int, isExpanded: Bool) -> NSView {
        let cell = NSTableCellView()
        let disclosure = NSButton(title: "", target: self, action: #selector(toggleGroup(_:)))
        disclosure.setButtonType(.onOff)
        disclosure.bezelStyle = .disclosure
        disclosure.state = isExpanded ? .on : .off
        disclosure.tag = row
        disclosure.toolTip = isExpanded ? "Collapse \(title)" : "Expand \(title)"
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: title)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(
            pointSize: VisualMetrics.groupSymbolPointSize,
            weight: .medium
        )
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(disclosure)
        cell.addSubview(icon)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            disclosure.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
            disclosure.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            disclosure.widthAnchor.constraint(equalToConstant: 12),
            disclosure.heightAnchor.constraint(equalToConstant: 16),
            icon.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 5),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func toggleGroup(_ sender: NSButton) {
        let items = visibleItems
        guard items.indices.contains(sender.tag), case .group = items[sender.tag] else {
            return
        }
        let groupIdentity = identity(for: items[sender.tag])
        if collapsedGroups.contains(groupIdentity) {
            collapsedGroups.remove(groupIdentity)
        } else {
            collapsedGroups.insert(groupIdentity)
        }
        tableView?.reloadData()
    }

    private func identity(for item: FavoriteSidebarItem) -> FavoriteGroupIdentity {
        guard case .group(let group) = item else {
            preconditionFailure("Favorite group identity requested for a location")
        }
        return group.map { .group($0.id) } ?? .defaultGroup
    }

    private func locationCell(_ location: SavedLocation) -> NSView {
        let showsWarning = Self.showsWarning(for: location.availability)
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: location.bookmark.originalPath)
        let label = NSTextField(labelWithString: location.displayName)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = showsWarning ? .secondaryLabelColor : .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 35),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: VisualMetrics.favoriteIconSize),
            icon.heightAnchor.constraint(equalToConstant: VisualMetrics.favoriteIconSize),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        if showsWarning == false {
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8).isActive = true
            cell.toolTip = location.bookmark.originalPath
        } else {
            let accessibilityDescription = location.availability.accessibilityDescription
            let badge = NSImageView()
            badge.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: accessibilityDescription
            )
            badge.contentTintColor = .systemOrange
            badge.symbolConfiguration = .init(
                pointSize: VisualMetrics.statusBadgePointSize,
                weight: .medium
            )
            badge.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(badge)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6),
                badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                badge.widthAnchor.constraint(equalToConstant: 13),
                badge.heightAnchor.constraint(equalToConstant: 13)
            ])
            cell.toolTip = "\(location.bookmark.originalPath)\n\(accessibilityDescription)"
            cell.setAccessibilityLabel("\(location.displayName), \(accessibilityDescription)")
        }
        return cell
    }

    static func showsWarning(for availability: SavedLocation.Availability) -> Bool {
        ExternalLocationStateResolver.isUsable(availability) == false
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> (any NSPasteboardWriting)? {
        let items = visibleItems
        guard items.indices.contains(row) else {
            return nil
        }
        let payload: FavoriteSidebarDragPayload
        switch items[row] {
        case .group(let group?):
            payload = .group(group.id)
        case .group(nil):
            return nil
        case .location(let location):
            payload = .location(location.id)
        }
        let item = NSPasteboardItem()
        item.setString(payload.encoded, forType: .favoriteSidebarItem)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard let payload = FavoriteSidebarDragPayload(info.draggingPasteboard) else {
            return []
        }
        let items = visibleItems
        switch payload {
        case .group:
            tableView.setDropRow(max(1, row), dropOperation: .above)
        case .location:
            if items.indices.contains(row), case .group = items[row] {
                tableView.setDropRow(row, dropOperation: .on)
            } else {
                tableView.setDropRow(row, dropOperation: .above)
            }
        }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let payload = FavoriteSidebarDragPayload(info.draggingPasteboard) else {
            return false
        }
        return onDrop?(payload, row, dropOperation) ?? false
    }
}

extension NSPasteboard.PasteboardType {
    static let favoriteSidebarItem = NSPasteboard.PasteboardType(
        "app.pathshelf.favorite-sidebar-item"
    )
}

enum FavoriteSidebarDragPayload {
    case group(UUID)
    case location(UUID)

    var encoded: String {
        switch self {
        case .group(let id):
            return "group:\(id.uuidString)"
        case .location(let id):
            return "location:\(id.uuidString)"
        }
    }

    init?(_ pasteboard: NSPasteboard) {
        guard let encoded = pasteboard.string(forType: .favoriteSidebarItem) else {
            return nil
        }
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        switch parts[0] {
        case "group":
            self = .group(id)
        case "location":
            self = .location(id)
        default:
            return nil
        }
    }
}

