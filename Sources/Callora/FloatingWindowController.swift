import AppKit
import SwiftUI

@MainActor final class FloatingWindowController: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    var onHide: (() -> Void)?
    var onDock: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    var snapToEdges = true
    private var movingProgrammatically = false

    func show<Content: View>(content: Content, from origin: NSRect?, settings: CalloraSettings) {
        if let panel { panel.orderFrontRegardless(); return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = settings.layout == .compact ? 280 : 440
        var target = NSRect(x: visible.maxX - width - 24, y: visible.maxY - 320, width: width, height: width * 9 / 16 + 62)
        if settings.rememberPosition, let saved = settings.panelFrame, saved.count == 4, saved.allSatisfy(\.isFinite) {
            let proposed = NSRect(x: saved[0], y: saved[1], width: saved[2], height: saved[3])
            if proposed.width >= 240, proposed.height >= 160,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersection(proposed).width >= 120 && $0.visibleFrame.intersection(proposed).height >= 80 }) { target = proposed }
        }
        let panel = NSPanel(contentRect: target, styleMask: [.titled, .resizable, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Callora preview"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 240, height: 160)
        panel.contentAspectRatio = target.size
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.alphaValue = settings.opacity
        panel.contentView = NSHostingView(rootView: content)
        panel.delegate = self
        self.panel = panel
        snapToEdges = settings.snapToEdges
        if let origin, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(origin, display: false)
            panel.orderFrontRegardless()
            movingProgrammatically = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.movingProgrammatically = false }
            }
        } else { panel.orderFrontRegardless() }
    }

    func update(settings: CalloraSettings) {
        panel?.level = settings.alwaysOnTop ? .floating : .normal
        panel?.alphaValue = min(1, max(0.4, settings.opacity))
        snapToEdges = settings.snapToEdges
    }
    func hide() { panel?.orderOut(nil); panel?.delegate = nil; panel = nil }
    func dock(to target: NSRect?) {
        guard let panel else { return }
        if let target, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            movingProgrammatically = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.hide(); self?.movingProgrammatically = false }
            }
        } else { hide() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onHide?(); return false }
    func windowDidMove(_ notification: Notification) {
        guard !movingProgrammatically, let panel else { return }
        onFrameChange?(panel.frame)
    }
    func windowDidResize(_ notification: Notification) {
        guard !movingProgrammatically, let panel else { return }
        onFrameChange?(panel.frame)
    }
    func windowDidEndLiveResize(_ notification: Notification) { snap() }
    func windowDidChangeScreen(_ notification: Notification) { snap() }
    func finishDrag() {
        guard let panel else { return }
        if let screen = panel.screen,
           abs(panel.frame.midX - screen.frame.midX) < 110,
           panel.frame.maxY > screen.frame.maxY - 100 { onDock?(); return }
        snap()
    }
    private func snap() {
        guard snapToEdges, !movingProgrammatically, let panel, let screen = panel.screen else { return }
        var frame = panel.frame
        let edge = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        if abs(frame.minX - edge.minX) < 28 { frame.origin.x = edge.minX }
        if abs(frame.maxX - edge.maxX) < 28 { frame.origin.x = edge.maxX - frame.width }
        if abs(frame.minY - edge.minY) < 28 { frame.origin.y = edge.minY }
        if abs(frame.maxY - edge.maxY) < 28 { frame.origin.y = edge.maxY - frame.height }
        movingProgrammatically = true
        panel.setFrame(frame, display: true)
        movingProgrammatically = false
        onFrameChange?(frame)
    }
}

/// Reads an actual view rectangle in global AppKit coordinates; no guessed notch origin.
struct ScreenRectReader: NSViewRepresentable {
    let onChange: (NSRect) -> Void
    func makeNSView(context: Context) -> RectReaderView { RectReaderView(onChange: onChange) }
    func updateNSView(_ view: RectReaderView, context: Context) { view.report() }
}
final class RectReaderView: NSView {
    let onChange: (NSRect) -> Void
    init(onChange: @escaping (NSRect) -> Void) { self.onChange = onChange; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); report() }
    override func viewDidMoveToWindow() { report() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func report() {
        guard let window, bounds.width > 1 else { return }
        let rect = window.convertToScreen(convert(bounds, to: nil))
        DispatchQueue.main.async { [weak self] in self?.onChange(rect) }
    }
}
