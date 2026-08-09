import Foundation
import CoreGraphics

public enum PanelPlacementMode: String, Codable, CaseIterable, Sendable {
    case cursorAdjacent
    case activeDisplayTopCenter
}

public struct PanelPlacementPreference: Codable, Equatable, Sendable {
    public var mode: PanelPlacementMode

    public init(mode: PanelPlacementMode = .cursorAdjacent) {
        self.mode = mode
    }
}

public struct PanelPlacementCalculator: Sendable {
    public var panelSize: CGSize
    public var screenMargin: CGFloat

    public init(
        panelSize: CGSize = CGSize(width: 640, height: 420),
        screenMargin: CGFloat = 12
    ) {
        self.panelSize = panelSize
        self.screenMargin = screenMargin
    }

    public func frame(
        mode: PanelPlacementMode,
        cursor: CGPoint,
        visibleFrame: CGRect
    ) -> CGRect {
        let origin: CGPoint
        switch mode {
        case .cursorAdjacent:
            origin = cursorAdjacentOrigin(cursor: cursor, visibleFrame: visibleFrame)
        case .activeDisplayTopCenter:
            origin = topCenterOrigin(visibleFrame: visibleFrame)
        }

        return CGRect(origin: origin, size: panelSize)
    }

    private func cursorAdjacentOrigin(cursor: CGPoint, visibleFrame: CGRect) -> CGPoint {
        let preferred = CGPoint(
            x: cursor.x + screenMargin,
            y: cursor.y - panelSize.height - screenMargin
        )
        return clampedOrigin(preferred, visibleFrame: visibleFrame)
    }

    private func topCenterOrigin(visibleFrame: CGRect) -> CGPoint {
        let preferred = CGPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - panelSize.height - screenMargin
        )
        return clampedOrigin(preferred, visibleFrame: visibleFrame)
    }

    private func clampedOrigin(_ origin: CGPoint, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, visibleFrame.minX + screenMargin),
                visibleFrame.maxX - panelSize.width - screenMargin
            ),
            y: min(
                max(origin.y, visibleFrame.minY + screenMargin),
                visibleFrame.maxY - panelSize.height - screenMargin
            )
        )
    }
}
