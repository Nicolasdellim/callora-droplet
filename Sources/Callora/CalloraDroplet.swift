import AppKit
import Combine
import DroppyKit
import ScreenCaptureKit
import SwiftUI

@objc(CalloraPrincipal)
public final class CalloraPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { CalloraDroplet() }
}

@MainActor
public final class CalloraDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "callora"
    @Published private(set) var sessions: [CallSession] = []
    @Published var selectedID: String?
    @Published var settings = CalloraSettings()
    @Published private(set) var availableWindows: [SCWindow] = []
    @Published private(set) var isLoadingWindows = false
    @Published private(set) var message: String?
    @Published private(set) var isDetached = false
    @Published private(set) var previewHidden = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenCaptureGranted = false
    let capture = VideoCaptureService()
    let floating = FloatingWindowController()
    private let detection = CallDetectionEngine()
    private var host: DropletHost?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var captureTask: Task<Void, Never>?
    private var automaticSourceTask: Task<Void, Never>?
    private var callPresentation: ExpandedSurfacePresentation?
    private var sourceTask: Task<Void, Never>?
    private var sourceWindow: SCWindow?
    private var sourceSessionID: String?
    private var visibleWidgets = Set<UUID>()
    private var widgetVisible: Bool { !visibleWidgets.isEmpty }
    private var sleeping = false
    private var active = false
    private var mouseMonitor: Any?
    var previewRect: NSRect?
    private let activity = CurrentValueSubject<LiveActivityState?, Never>(nil)
    var selected: CallSession? { sessions.first { $0.id == selectedID } ?? sessions.first }
    var canCapture: Bool { host?.isGranted(.screenCapture) == true && screenCaptureGranted }

    public func activate(host: DropletHost) throws {
        self.host = host; active = true
        settings = host.preferences.value(forKey: "settings", default: CalloraSettings())
        // This migration follows the user's explicit request for automatic notch-first calls.
        if !host.preferences.value(forKey: "notchFirst.v2", default: false) {
            settings.detectionEnabled = true
            settings.persistentActivity = true
            settings.automaticallyPresentCalls = true
            persistSettings()
            host.preferences.setValue(true, forKey: "notchFirst.v2")
        }
        refreshPermissions()
        detection.onUpdate = { [weak self] evidence, ended in self?.receive(evidence, ended: ended) }
        capture.onSourceLost = { [weak self] in self?.message = "Source unavailable. Open its app and select the window again." }
        floating.onHide = { [weak self] in self?.hidePreview() }
        floating.onDock = { [weak self] in self?.dock() }
        floating.onFrameChange = { [weak self] frame in
            guard let self else { return }
            self.settings.panelFrame = [frame.minX, frame.minY, frame.width, frame.height]
            self.persistSettings()
        }
        host.notchSurface.didChange.sink { [weak self] in self?.reconcileCapture() }.store(in: &subscriptions)
        host.shelf.didChange.sink { [weak self] in
            guard let self else { return }
            if self.active, self.host?.shelf.isExpanded == true, self.selected != nil,
               !self.isDetached, !self.previewHidden,
               self.host?.notchSurface.expandedState.current == nil {
                self.presentCallInNotch()
            }
            self.reconcileCapture()
        }.store(in: &subscriptions)
        // Forward only status changes; publishing frames on the droplet would invalidate the whole host shelf.
        capture.$isCapturing.removeDuplicates().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        host.shortcuts.register(id: "open-notch", title: "Afficher Callora dans la notch", defaultShortcut: nil) { [weak self] in self?.showPreview() }
        host.shortcuts.register(id: "detach-dock", title: "Detach or dock call preview", defaultShortcut: nil) { [weak self] in
            guard let self else { return }; self.isDetached ? self.dock() : self.detach()
        }
        host.shortcuts.register(id: "toggle-preview", title: "Show or hide call preview", defaultShortcut: nil) { [weak self] in
            guard let self else { return }; self.previewHidden ? self.showPreview() : self.hidePreview()
        }
        host.shortcuts.register(id: "open-source", title: "Open calling application", defaultShortcut: nil) { [weak self] in self?.openSource() }
        host.shortcuts.register(id: "switch-call", title: "Switch selected call", defaultShortcut: nil) { [weak self] in self?.nextCall() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let eventName = notification.name
                Task { @MainActor in self?.workspaceEvent(eventName, pid: pid) }
            })
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated { self?.floating.finishDrag() }
            return event
        }
        updateDetection()
        host.log.info("Callora activated; no capture starts until a source is chosen and its preview is visible")
    }

    public func deactivate() {
        active = false; detection.stop(); captureTask?.cancel(); sourceTask?.cancel(); automaticSourceTask?.cancel()
        sourceTask = nil; sourceWindow = nil; sourceSessionID = nil
        dismissCallSurface()
        floating.hide(); isDetached = false; visibleWidgets.removeAll()
        Task { await capture.stop() }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }; mouseMonitor = nil
        for id in ["open-notch", "detach-dock", "toggle-preview", "open-source", "switch-call"] { host?.shortcuts.unregister(id: id) }
        subscriptions.removeAll(); sessions.removeAll(); activity.send(nil)
        host?.shelf.setHoldsOpen(false)
        host = nil
    }

    func changeSettings(_ mutate: (inout CalloraSettings) -> Void) {
        mutate(&settings)
        settings.opacity = min(1, max(0.4, settings.opacity))
        persistSettings(); updateDetection(); floating.update(settings: settings)
        if !settings.enabled { dismissCallSurface(); floating.hide(); isDetached = false; previewHidden = true }
        reconcileCapture(restart: true); publishActivity()
    }
    private func persistSettings() { host?.preferences.setValue(settings, forKey: "settings") }
    private func updateDetection() {
        detection.stop()
        guard host?.environment.isHarness != true else { return }
        if active && settings.enabled && settings.detectionEnabled && accessibilityGranted && !sleeping {
            detection.start()
        } else if !sleeping {
            for id in sessions.filter({ !$0.manual }).map(\.id) { endSession(id) }
        }
    }
    func refreshPermissions() {
        accessibilityGranted = host?.isGranted(.accessibility) == true && host?.permissions.status(for: .accessibility) == .granted
        screenCaptureGranted = host?.isGranted(.screenCapture) == true && host?.permissions.status(for: .screenCapture) == .granted
    }
    func requestPermission(_ permission: DropletPermission) async {
        guard let host, host.isGranted(permission) else { message = "Enable this capability in Droppy's local droplet settings first."; return }
        _ = await host.permissions.request(permission)
        refreshPermissions(); updateDetection()
        if permission == .screenCapture, !screenCaptureGranted { host.permissions.openSystemSettings(for: permission) }
    }
    func openSettings() { _ = host?.workspace.openSettings() }
    func openShortcuts() { _ = host?.workspace.openShortcuts() }
    func refreshSources() {
        guard canCapture else { message = "Allow Screen Recording in Privacy settings, then refresh sources."; return }
        guard !isLoadingWindows else { return }
        isLoadingWindows = true; message = nil
        sourceTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingWindows = false }
            do {
                let windows = try await self.capture.windows()
                guard self.active, !Task.isCancelled else { return }
                self.availableWindows = windows
            } catch { self.message = "Unable to list windows. Check Screen Recording permission, then try again." }
        }
    }
    func selectSource(_ window: SCWindow) {
        guard settings.enabled, canCapture, let app = window.owningApplication else { return }
        // A new source never inherits another call's identity or controls.
        let existing = sessions.first { $0.processID == app.processID && !$0.manual }
        let id = existing?.id ?? "manual:\(app.processID):\(window.windowID)"
        if existing == nil, !sessions.contains(where: { $0.id == id }) {
            var session = CallSession(id: id, bundleID: app.bundleIdentifier, processID: app.processID,
                                      title: app.applicationName, provider: app.applicationName, manual: true, confidence: 1)
            session.transition(to: .connecting); session.transition(to: .active)
            sessions.append(session)
        }
        sourceWindow = window; sourceSessionID = id; selectedID = id; previewHidden = false
        message = "Window capture selected. Only this window is shown; audio stays in its calling app."
        publishActivity()
        presentCallInNotch()
        reconcileCapture(restart: true)
    }
    func selectCall(_ id: String) {
        selectedID = id
        if sourceSessionID != id { sourceWindow = nil; sourceSessionID = nil; previewHidden = false }
        publishActivity(); reconcileCapture(restart: true)
    }
    func nextCall() {
        guard !sessions.isEmpty else { return }
        let index = sessions.firstIndex { $0.id == selectedID } ?? 0
        selectCall(sessions[(index + 1) % sessions.count].id)
    }
    func openSource() {
        guard let selected, let app = NSRunningApplication(processIdentifier: selected.processID) else { return }
        app.activate(options: [])
    }
    func forgetSession() {
        guard let session = selected, session.manual else { return }
        endSession(session.id)
    }
    func detach(at position: NSPoint? = nil) {
        guard selected != nil, settings.enabled else { return }
        previewHidden = false; isDetached = true
        dismissCallSurface()
        let origin = previewRect
        floating.show(content: FloatingCallView(droplet: self), from: origin, settings: settings)
        if let position, let panel = floating.panel {
            panel.setFrameOrigin(NSPoint(x: position.x - panel.frame.width / 2, y: position.y - panel.frame.height / 2))
        }
        host?.shelf.setHoldsOpen(false)
        reconcileCapture()
    }
    func moveDetachedPreview(to position: NSPoint) {
        guard let panel = floating.panel else { return }
        panel.setFrameOrigin(NSPoint(x: position.x - panel.frame.width / 2, y: position.y - panel.frame.height / 2))
    }
    func dock() {
        guard isDetached else { return }
        isDetached = false; previewHidden = false
        presentCallInNotch()
        floating.dock(to: previewRect)
        reconcileCapture()
    }
    func hidePreview() {
        previewHidden = true
        dismissCallSurface()
        floating.hide(); isDetached = false
        reconcileCapture()
    }
    func showPreview() {
        previewHidden = false
        presentCallInNotch()
        reconcileCapture()
    }
    func setWidgetVisible(_ visible: Bool, id: UUID) {
        if visible { visibleWidgets.insert(id) } else { visibleWidgets.remove(id) }
        reconcileCapture()
    }

    private func reconcileCapture(restart: Bool = false) {
        let shouldRun = active && settings.enabled && !sleeping && !previewHidden && settings.layout != .audioOnly &&
            (isDetached || host?.notchSurface.expandedState.current?.surfaceID == "callora.call" || (widgetVisible && host?.shelf.isExpanded == true)) && sourceWindow != nil && sourceSessionID == selected?.id
        if shouldRun, capture.isCapturing, !restart { return }
        captureTask?.cancel()
        let previous = captureTask
        captureTask = Task { [weak self] in
            // Serialize teardown/start so a late start cannot survive a hide or source switch.
            await previous?.value
            guard let self else { return }
            await self.capture.stop()
            guard !Task.isCancelled, shouldRun, let window = self.sourceWindow else { return }
            await self.capture.start(window: window, settings: self.settings)
        }
    }
    func receive(_ evidence: [DetectionEvidence], ended: Set<String>) {
        var newSelectedEvidence: DetectionEvidence?
        for item in evidence {
            let id = "\(item.processID):\(item.windowID)"
            guard let phase = item.detectedPhase else { continue }
            if let index = sessions.firstIndex(where: { $0.id == id }) {
                if sessions[index].phase == .incoming, phase == .active {
                    sessions[index].transition(to: .connecting)
                    sessions[index].transition(to: .active)
                    if selectedID == id { resolveAutomaticSource(item) }
                }
                continue
            }
            var session = CallSession(id: id, bundleID: item.bundleID, processID: item.processID,
                                      title: item.provider, provider: item.provider, manual: false, confidence: item.confidence)
            if phase == .incoming { session.transition(to: .incoming) }
            else { session.transition(to: .connecting); session.transition(to: .active) }
            sessions.append(session)
            if selectedID == nil || phase == .incoming && !isDetached {
                selectedID = id
                newSelectedEvidence = item
            }
        }
        for id in ended { endSession(id) }
        publishActivity()
        if let item = newSelectedEvidence {
            if settings.automaticallyPresentCalls { presentCallInNotch() }
            resolveAutomaticSource(item)
        }
    }

    func presentCallInNotch() {
        guard active, settings.enabled, let host else { return }
        // Only an explicit detach action may create an NSPanel.
        floating.hide(); isDetached = false; previewHidden = false
        if host.notchSurface.expandedState.current?.surfaceID != "callora.call" {
            callPresentation = host.notchSurface.presentExpandedSurface(.init(surfaceID: "callora.call", opensShelf: true, triggersHaptic: false))
        }
        if host.notchSurface.expandedState.current?.surfaceID != "callora.call" {
            _ = host.shelf.open(revealing: "callora")
            message = "Open Callora's notch surface from the shelf; allow expanded-surface in its local capabilities if needed."
        }
        reconcileCapture()
    }

    private func dismissCallSurface() {
        host?.notchSurface.dismissExpandedSurface("callora.call")
        callPresentation = nil
    }

    private func resolveAutomaticSource(_ item: DetectionEvidence) {
        guard canCapture, host?.environment.isHarness != true else { return }
        let id = "\(item.processID):\(item.windowID)"
        automaticSourceTask?.cancel()
        automaticSourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let candidates = try await self.capture.windows().filter { $0.owningApplication?.processID == item.processID }
                guard !Task.isCancelled, self.active, self.selected?.id == id else { return }
                // Never substitute a random window from the same app. Match the detected AX window.
                let matches = candidates.filter { window in
                    guard let bounds = item.windowBounds else { return false }
                    return abs(window.frame.minX - bounds.minX) < 8 && abs(window.frame.minY - bounds.minY) < 8 &&
                           abs(window.frame.width - bounds.width) < 12 && abs(window.frame.height - bounds.height) < 40
                }
                guard matches.count == 1, let window = matches.first else {
                    self.message = "Call detected in the notch. Select its video window in settings if no preview appears."
                    return
                }
                self.sourceWindow = window; self.sourceSessionID = id
                self.reconcileCapture(restart: true)
            } catch { self.message = "Call detected; allow Screen Recording for a video preview in the notch." }
        }
    }
    private func endSession(_ id: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].transition(to: .ending); sessions[index].transition(to: .ended)
        }
        sessions.removeAll { $0.id == id }
        if sourceSessionID == id { sourceWindow = nil; sourceSessionID = nil; floating.hide(); isDetached = false }
        if selectedID == id { selectedID = sessions.first?.id }
        if sessions.isEmpty { dismissCallSurface() }
        reconcileCapture(); publishActivity()
    }
    private func workspaceEvent(_ name: Notification.Name, pid: Int32?) {
        if name == NSWorkspace.willSleepNotification { sleeping = true; detection.stop(); reconcileCapture() }
        else if name == NSWorkspace.didWakeNotification { sleeping = false; refreshPermissions(); updateDetection(); reconcileCapture() }
        else if let pid { for id in sessions.filter({ $0.processID == pid }).map(\.id) { endSession(id) } }
    }
    private func publishActivity() {
        guard settings.enabled, let selected else { activity.send(nil); return }
        activity.send(.init(priority: selected.phase == .incoming ? 80 : 40, accessibilityTitle: "\(selected.provider) call preview", joinsPersistentActivitySet: settings.persistentActivity,
                            compactPresentation: nil, expandedWidgetID: "callora"))
    }
}

extension CalloraDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [ShelfWidgetDescriptor(id: "callora", title: "Callora", systemImage: "rectangle.on.rectangle",
            layoutTraits: ShelfWidgetLayoutTraits(preferredSoloWidth: 420, preferredPairedWidth: 240,
                contentHeight: .fixed(selected == nil ? 156 : 310)))]
    }
    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(CalloraWidget(droplet: self, context: context))
    }
    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}
extension CalloraDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> { activity.eraseToAnyPublisher() }
    public func makeCompactLeading() -> AnyView { AnyView(CompactCallMark(droplet: self)) }
    public func makeCompactTrailing() -> AnyView { AnyView(CompactCallDuration(droplet: self)) }
    public func makeExpanded(context: LiveActivityContext) -> AnyView { AnyView(EmptyView()) }
}
extension CalloraDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView { AnyView(CalloraSettingsView(droplet: self)) }
    public var settingsSearchEntries: [SettingsSearchEntry] {
        ["Video source", "Floating window", "Screen Recording", "Call detection", "Keyboard shortcuts"].map {
            SettingsSearchEntry(title: $0, keywords: ["call", "video", "Callora"])
        }
    }
}


extension CalloraDroplet: ExpandedSurfaceHosting, ExpandedSurfaceProviding {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [.init(id: "callora.call", title: "Callora call", systemImage: "video.fill",
               suppresses: [.shelfWidgets, .favoritesBar, .floatingNavLane, .autoCollapse])]
    }
    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        guard id == "callora.call" else { return AnyView(EmptyView()) }
        return AnyView(CallNotchView(droplet: self).allowsHitTesting(!context.isHostShelfTransitioning))
    }
    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        CGSize(width: min(460, proposal.maximumSize.width), height: min(selected?.phase == .incoming ? 200 : 320, proposal.maximumSize.height))
    }
    public func expandedSurfaceDidDismiss(_ id: ExpandedSurfaceID, presentation: ExpandedSurfacePresentation, reason: ExpandedSurfaceDismissalReason) {
        guard callPresentation?.id == presentation.id else { return }
        callPresentation = nil
        reconcileCapture()
    }
}
