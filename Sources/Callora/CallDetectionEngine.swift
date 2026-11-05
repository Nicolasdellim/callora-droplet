import AppKit
import ApplicationServices

public protocol CallProvider: Identifiable, Sendable {
    var id: String { get }
    var name: String { get }
    var automatic: Bool { get }
    var capabilities: Set<CallCapability> { get }
}

public struct ProviderDescriptor: CallProvider {
    public var capabilities: Set<CallCapability> { [.openApplication, .selectWindow] }
    public let id: String
    public let name: String
    public let automatic: Bool
}

public enum ProviderRegistry {
    public static let providers: [ProviderDescriptor] = [
        .init(id: "us.zoom.xos", name: "Zoom", automatic: true),
        .init(id: "com.apple.FaceTime", name: "FaceTime", automatic: true),
        .init(id: "com.microsoft.teams2", name: "Teams", automatic: true),
        .init(id: "com.microsoft.teams", name: "Teams classic", automatic: true),
        .init(id: "com.google.Chrome", name: "Browser calls in Chrome", automatic: true),
        .init(id: "com.apple.Safari", name: "Browser calls in Safari", automatic: true),
        .init(id: "com.microsoft.edgemac", name: "Browser calls in Edge", automatic: true),
        .init(id: "com.brave.Browser", name: "Browser calls in Brave", automatic: true),
        .init(id: "com.hnc.Discord", name: "Discord", automatic: true),
        .init(id: "net.whatsapp.WhatsApp", name: "WhatsApp", automatic: true),
        .init(id: "ru.keepcoder.Telegram", name: "Telegram", automatic: true),
        .init(id: "com.tinyspeck.slackmacgap", name: "Slack Huddles", automatic: true),
        .init(id: "Cisco-Systems.Spark", name: "Webex", automatic: true),
        .init(id: "org.whispersystems.signal-desktop", name: "Signal", automatic: true)
    ]
}

/// All potentially blocking AX messages run on one dedicated queue, with bounded depth and timeout.
@MainActor final class CallDetectionEngine {
    private let queue = DispatchQueue(label: "app.callora.accessibility", qos: .utility)
    private var task: Task<Void, Never>?
    private var reducer = DetectionReducer()
    var onUpdate: (([DetectionEvidence], Set<String>) -> Void)?

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let apps = NSWorkspace.shared.runningApplications.compactMap { app -> ScanTarget? in
                    guard let id = app.bundleIdentifier,
                          let provider = ProviderRegistry.providers.first(where: { $0.id == id && $0.automatic }) else { return nil }
                    return ScanTarget(id: id, pid: app.processIdentifier, name: provider.name)
                }
                let evidence = await self.scan(apps)
                guard !Task.isCancelled else { return }
                let result = self.reducer.update(evidence)
                self.onUpdate?(result.confirmed, result.ended)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func stop() { task?.cancel(); task = nil; reducer = DetectionReducer() }

    private func scan(_ targets: [ScanTarget]) async -> [DetectionEvidence] {
        await withCheckedContinuation { continuation in
            queue.async {
                guard AXIsProcessTrusted() else { continuation.resume(returning: []); return }
                var result: [DetectionEvidence] = []
                for target in targets {
                    let app = AXUIElementCreateApplication(target.pid)
                    AXUIElementSetMessagingTimeout(app, 0.12)
                    let windows = Self.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
                    for (index, window) in windows.prefix(8).enumerated() {
                        var budget = 250
                        let deadline = Date().addingTimeInterval(0.6)
                        var labels = Set<String>()
                        Self.collect(window, depth: 0, budget: &budget, labels: &labels, deadline: deadline)
                        // AXIdentifier is stable where supplied; ordinal fallback is explicitly best effort.
                        let key = Self.attribute(window, kAXIdentifierAttribute) as? String ?? "window-\(index)"
                        let title = Self.attribute(window, kAXTitleAttribute) as? String
                        var bounds: CGRect?
                        if let position = Self.attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                           let size = Self.attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() {
                            var point = CGPoint.zero; var dimensions = CGSize.zero
                            if AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
                               AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) {
                                bounds = CGRect(origin: point, size: dimensions)
                            }
                        }
                        result.append(.init(bundleID: target.id, processID: target.pid, provider: target.name, windowID: key, labels: labels, windowTitle: title, windowBounds: bounds))
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    nonisolated private static func collect(_ element: AXUIElement, depth: Int, budget: inout Int, labels: inout Set<String>, deadline: Date) {
        guard depth < 14, budget > 0, Date() < deadline else { return }
        budget -= 1
        let role = attribute(element, kAXRoleAttribute) as? String
        if role == kAXButtonRole || role == kAXCheckBoxRole {
            for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                if let label = attribute(element, name) as? String, !label.isEmpty { labels.insert(label) }
            }
        }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(80) {
            collect(child, depth: depth + 1, budget: &budget, labels: &labels, deadline: deadline)
        }
    }
}
private struct ScanTarget: Sendable { let id: String; let pid: Int32; let name: String }
