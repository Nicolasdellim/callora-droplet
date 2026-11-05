import AppKit
import DroppyKit
import SwiftUI

struct CalloraWidget: View {
    @ObservedObject var droplet: CalloraDroplet
    let context: ShelfWidgetContext
    @State private var visibilityID = UUID()
    @State private var detaching = false
    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            // Keep the header below the host's camera clearance on API 1.21.
            HStack { title; Spacer(minLength: 0); settingsButton }
            if let session = droplet.selected {
                HStack {
                    Text(session.provider).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let start = session.startedAt, droplet.settings.showDuration { Text(start, style: .timer).monospacedDigit().font(.system(size: 11)) }
                }
                if !context.isCompact {
                    PreviewContent(droplet: droplet)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ScreenRectReader { droplet.previewRect = $0 })
                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                        .gesture(DragGesture(minimumDistance: 24).onChanged { value in
                            if value.translation.height > 35, !detaching {
                                detaching = true
                                droplet.detach(at: NSEvent.mouseLocation)
                            }
                            if detaching { droplet.moveDetachedPreview(to: NSEvent.mouseLocation) }
                        }.onEnded { _ in
                            if detaching { droplet.floating.finishDrag() }
                            detaching = false
                        })
                        .accessibilityHint("Drag downward to detach, or use the detach button")
                } else {
                    Spacer(minLength: 0)
                    Text(droplet.capture.isCapturing ? "Window capture" : "Call preview ready").font(.system(size: 14, weight: .medium))
                    Text(session.manual ? "Manually associated" : "Experimental detection").font(.system(size: 11)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
                controls
            } else {
                Spacer(minLength: 0)
                Label("Every call. One beautiful island.", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: context.isCompact ? 13 : 15, weight: .medium)).lineLimit(2)
                Text(droplet.settings.enabled ? "Choose a call window in settings to begin." : "Enable Callora in settings.")
                    .font(.system(size: 12)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!context.isShelfTransitioning)
        .onAppear { droplet.setWidgetVisible(true, id: visibilityID) }
        .onDisappear { droplet.setWidgetVisible(false, id: visibilityID) }
    }
    // SDK 1.21 wash sizes; the context helper was introduced in 1.22.
    private var controlDiameter: CGFloat { context.isCompact ? 28 : 34 }
    private var title: some View {
        Label("Callora", systemImage: "rectangle.on.rectangle").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }
    private var settingsButton: some View {
        Button(action: droplet.openSettings) { Image(systemName: "gearshape") }
            .buttonStyle(DroppyWashCircleButtonStyle(diameter: controlDiameter, tone: .neutral, usesAdaptiveForegrounds: context.usesAdaptiveForegrounds))
            .help("Choose source and settings").accessibilityLabel("Choose source and settings")
    }
    private func control(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(DroppyWashCircleButtonStyle(diameter: controlDiameter, tone: .neutral, usesAdaptiveForegrounds: context.usesAdaptiveForegrounds))
            .help(title).accessibilityLabel(title)
    }
    private var controls: some View {
        HStack(spacing: DroppySpacing.sm) {
            control("Open calling application", symbol: "arrow.up.forward.app", action: droplet.openSource)
            control(droplet.previewHidden ? "Show preview" : "Hide preview", symbol: droplet.previewHidden ? "eye" : "eye.slash") {
                droplet.previewHidden ? droplet.showPreview() : droplet.hidePreview()
            }
            Spacer(minLength: 0)
            if droplet.sessions.count > 1 { control("Switch call", symbol: "arrow.triangle.swap", action: droplet.nextCall) }
            control(droplet.isDetached ? "Dock preview" : "Detach preview", symbol: droplet.isDetached ? "rectangle.topthird.inset.filled" : "pip.enter") {
                droplet.isDetached ? droplet.dock() : droplet.detach()
            }
        }
    }
}

struct PreviewContent: View {
    @ObservedObject var droplet: CalloraDroplet
    @ObservedObject private var capture: VideoCaptureService
    init(droplet: CalloraDroplet) { self.droplet = droplet; capture = droplet.capture }
    var body: some View {
        ZStack {
            Color.black
            if capture.frame != nil, !droplet.previewHidden, droplet.settings.layout != .audioOnly {
                VideoSurface(capture: capture)
            } else {
                VStack(spacing: DroppySpacing.sm) {
                    Image(systemName: droplet.settings.layout == .audioOnly ? "waveform" : "rectangle.on.rectangle")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.7))
                    Text(status).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center)
                    if droplet.settings.layout == .audioOnly { Text("Call status only").font(.caption).foregroundStyle(.secondary) }
                }.padding(DroppySpacing.md)
            }
            VStack {
                Spacer()
                HStack {
                    Label(capture.isCapturing ? "Window capture" : "Preview", systemImage: capture.isCapturing ? "record.circle" : "rectangle")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, DroppySpacing.sm).padding(.vertical, DroppySpacing.xs)
                        .background(.black.opacity(0.65), in: Capsule())
                    Spacer()
                }
            }.padding(DroppySpacing.sm)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(capture.sourceName ?? "No video source"). \(status)")
    }
    private var status: String {
        if droplet.previewHidden { return "Preview hidden" }
        if let error = capture.error { return error }
        if droplet.settings.layout == .audioOnly { return droplet.selected?.provider ?? "Audio call" }
        if capture.isCapturing { return "Waiting for source frames" }
        return "Choose a window in settings"
    }
}

struct FloatingCallView: View {
    @ObservedObject var droplet: CalloraDroplet
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 0) {
            PreviewContent(droplet: droplet)
            if droplet.settings.layout == .controls || droplet.settings.layout == .glass || droplet.settings.layout == .audioOnly || hovering {
                HStack(spacing: DroppySpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(droplet.selected?.provider ?? "Callora").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if let start = droplet.selected?.startedAt, droplet.settings.showDuration {
                            Text(start, style: .timer).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    panelButton("Open calling application", symbol: "arrow.up.forward.app", action: droplet.openSource)
                    panelButton("Dock to notch", symbol: "pip.exit", action: droplet.dock)
                    panelButton("Hide preview", symbol: "xmark", action: droplet.hidePreview)
                }.padding(DroppySpacing.md)
            }
        }
        .background(reduceTransparency ? Color.black : Color.black.opacity(0.86))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        .onHover { hovering = $0 }
        .preferredColorScheme(.dark)
        .frame(minWidth: 220, minHeight: 140)
    }
    private func panelButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

struct CompactCallMark: View {
    @ObservedObject var droplet: CalloraDroplet
    var body: some View {
        Image(systemName: "video.fill").font(.system(size: 13, weight: .medium))
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .accessibilityLabel(droplet.selected?.provider ?? "Callora")
    }
}
struct CompactCallDuration: View {
    @ObservedObject var droplet: CalloraDroplet
    var body: some View {
        Group {
            if let start = droplet.selected?.startedAt, droplet.settings.showDuration { Text(start, style: .timer).monospacedDigit() }
            else { Image(systemName: "rectangle.on.rectangle") }
        }.font(.system(size: 11, weight: .medium)).foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }
}
