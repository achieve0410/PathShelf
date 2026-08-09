import AppKit
import PreviewFeature
import QuickLookUI

@MainActor
final class QuickLookPanelCoordinator: NSObject {
    private let contractController: QuickLookPreviewController
    private var itemURL: URL?
    private var previewPanel: NSPanel?
    private var previewView: QLPreviewView?

    init(contractController: QuickLookPreviewController) {
        self.contractController = contractController
    }

    var isVisible: Bool {
        previewPanel?.isVisible == true
    }

    var hasPreviewItem: Bool {
        previewView?.previewItem != nil
    }

    var previewedURL: URL? {
        itemURL
    }

    var diagnostics: String {
        "visible=\(isVisible),previewItem=\(hasPreviewItem),"
            + "url=\(itemURL?.lastPathComponent ?? "nil")"
    }

    func present(_ url: URL?) {
        guard let url else {
            return
        }
        itemURL = url
        contractController.present(PreviewItem(url: url))
        let panel = previewPanel ?? makePreviewPanel()
        previewPanel = panel
        previewView?.previewItem = url as NSURL
        previewView?.refreshPreviewItem()
        panel.title = "Quick Look — \(url.lastPathComponent)"
        panel.makeKeyAndOrderFront(nil)
    }

    func toggle(_ url: URL) {
        if previewPanel?.isVisible == true {
            close()
        } else {
            present(url)
        }
    }

    func close() {
        previewPanel?.orderOut(nil)
        previewView?.previewItem = nil
        itemURL = nil
        contractController.close()
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = CGSize(width: 420, height: 320)

        if let previewView = QLPreviewView(
            frame: panel.contentView?.bounds ?? .zero,
            style: .normal
        ) {
            previewView.autoresizingMask = [.width, .height]
            previewView.shouldCloseWithWindow = false
            panel.contentView = previewView
            self.previewView = previewView
        }
        return panel
    }
}