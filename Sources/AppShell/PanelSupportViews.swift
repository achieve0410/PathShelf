import AppKit
import Carbon.HIToolbox
import FileOperations

@MainActor
final class BrowserStateView: NSView {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var currentTitle = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true

        symbolView.symbolConfiguration = .init(pointSize: 34, weight: .regular)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.alignment = .center
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 3
        detailLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [symbolView, titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: symbolView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])
    }

    func show(
        symbolName: String,
        title: String,
        detail: String?,
        tintColor: NSColor
    ) {
        symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        symbolView.contentTintColor = tintColor
        currentTitle = title
        titleLabel.stringValue = title
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail?.isEmpty != false
        toolTip = [title, detail].compactMap { $0 }.joined(separator: ". ")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(toolTip)
        isHidden = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class FilterSearchField: NSSearchField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
final class PanelFocusView: NSView {
    private let onEscape: () -> Void
    weak var contentView: PanelContentView?

    init(onEscape: @escaping () -> Void) {
        self.onEscape = onEscape
        super.init(frame: .zero)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            contentView?.focusSearchField()
            return
        }
        switch event.keyCode {
        case UInt16(kVK_Escape):
            onEscape()
        case UInt16(kVK_Space):
            contentView?.toggleQuickLookFromKeyboard()
        case UInt16(kVK_Return):
            contentView?.openSelection(nil)
        case UInt16(kVK_Delete):
            contentView?.trashSelection()
        default:
            super.keyDown(with: event)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

final class OpenWithMenuItem: NSMenuItem {
    private let application: WorkspaceApplication
    private let handler: (WorkspaceApplication) -> Void

    init(application: WorkspaceApplication, handler: @escaping (WorkspaceApplication) -> Void) {
        self.application = application
        self.handler = handler
        super.init(title: application.name, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler(application)
    }
}

@MainActor
final class PathBarControl: NSPathControl {
    var pathContextMenuProvider: ((URL) -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedURL = pathItem(at: point)?.url ?? url
        guard let clickedURL else {
            return super.menu(for: event)
        }
        return pathContextMenuProvider?(clickedURL) ?? super.menu(for: event)
    }

    private func pathItem(at point: NSPoint) -> NSPathControlItem? {
        let items = pathItems
        guard !items.isEmpty else {
            return nil
        }

        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var x: CGFloat = 0
        for item in items {
            let title = item.title as NSString
            let width = title.size(withAttributes: [.font: font]).width + 28
            let rect = NSRect(x: x, y: 0, width: width, height: bounds.height)
            if rect.contains(point) {
                return item
            }
            x += width
        }
        return items.last
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class KeyHandlingTableView: NSTableView {
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?
    var onFind: (() -> Void)?
    var onContextRow: ((Int?) -> Void)?
    var contextMenuProvider: ((Int?) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        if clickedRow >= 0 {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            onContextRow?(clickedRow)
            return contextMenuProvider?(clickedRow) ?? super.menu(for: event)
        } else {
            deselectAll(nil)
            onContextRow?(nil)
            return contextMenuProvider?(nil) ?? super.menu(for: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFind?()
            return
        }
        switch event.keyCode {
        case UInt16(kVK_Escape):
            onEscape?()
        case UInt16(kVK_Return):
            onReturn?()
        case UInt16(kVK_Space):
            onSpace?()
        case UInt16(kVK_Delete):
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }
}
