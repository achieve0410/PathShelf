import AppKit

enum VisualMetrics {
    static let settingsSectionCornerRadius: CGFloat = 10
    static let settingsSectionInset: CGFloat = 16
    static let settingsSectionSpacing: CGFloat = 12
    static let pathBarHeight: CGFloat = 32
    static let panelHorizontalInset: CGFloat = 12
    static let groupSymbolPointSize: CGFloat = 11
    static let favoriteIconSize: CGFloat = 16
    static let fileIconSize: CGFloat = 18
    static let statusBadgePointSize: CGFloat = 10
    static let settingsSymbolPointSize: CGFloat = 14
}

@MainActor
final class SemanticSurfaceView: NSView {
    enum Kind {
        case content
        case fileList
        case settingsSection
        case footer
    }

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch kind {
            case .content:
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                layer?.borderWidth = 0
                layer?.cornerRadius = 0
            case .fileList:
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                layer?.borderWidth = 0
                layer?.cornerRadius = 0
            case .settingsSection:
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                layer?.borderColor = NSColor.separatorColor.cgColor
                layer?.borderWidth = 0.5
                layer?.cornerRadius = VisualMetrics.settingsSectionCornerRadius
            case .footer:
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                layer?.borderWidth = 0
                layer?.cornerRadius = 0
            }
        }
    }
}
