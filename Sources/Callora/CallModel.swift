import Foundation

public enum CallPhase: String, Codable, Sendable {
    case idle, incoming, connecting, active, reconnecting, ending, ended

    public func permits(_ next: Self) -> Bool {
        if self == next { return true }
        switch (self, next) {
        case (.idle, .incoming), (.idle, .connecting), (.incoming, .connecting),
             (.incoming, .ending), (.connecting, .active), (.connecting, .ending),
             (.active, .reconnecting), (.active, .ending), (.reconnecting, .active),
             (.reconnecting, .ending), (.ending, .ended), (.ended, .idle): return true
        default: return false
        }
    }
}

public enum CallCapability: String, Codable, Hashable, Sendable {
    case openApplication, selectWindow, answer, decline, hangUp, microphone, camera, remoteStream
}

public struct CallSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let bundleID: String
    public let processID: Int32
    public var title: String
    public var provider: String
    public var phase: CallPhase = .idle
    public var startedAt: Date?
    public var manual: Bool
    public var confidence: Double
    public var microphoneMuted: Bool?
    public var cameraDisabled: Bool?
    public var screenSharing: Bool?
    public var minimized: Bool?
    public var capabilities: Set<CallCapability> = [.openApplication, .selectWindow]

    @discardableResult public mutating func transition(to next: CallPhase, now: Date = .now) -> Bool {
        guard phase.permits(next) else { return false }
        phase = next
        if next == .active, startedAt == nil { startedAt = now }
        return true
    }
}

public struct DetectionEvidence: Sendable, Equatable {
    public let bundleID: String
    public let processID: Int32
    public let provider: String
    public let windowID: String
    public let labels: Set<String>
    public let windowTitle: String?
    public let windowBounds: CGRect?
    public init(bundleID: String, processID: Int32, provider: String, windowID: String, labels: Set<String>, windowTitle: String? = nil, windowBounds: CGRect? = nil) {
        self.bundleID = bundleID; self.processID = processID; self.provider = provider
        self.windowID = windowID; self.labels = labels; self.windowTitle = windowTitle; self.windowBounds = windowBounds
    }
    private var normalized: Set<String> {
        Set(labels.map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    public var detectedPhase: CallPhase? {
        let labels = normalized
        let answers: Set<String> = ["answer", "answer call", "accept call", "repondre", "accepter l'appel", "accepter l'appel video"]
        let declines: Set<String> = ["decline", "decline call", "refuser", "refuser l'appel", "rejeter l'appel"]
        if !labels.isDisjoint(with: answers), !labels.isDisjoint(with: declines) { return .incoming }
        let leave = !labels.isDisjoint(with: ["leave", "leave meeting", "end meeting", "end call", "leave call", "hang up", "disconnect", "quitter", "quitter l'appel", "quitter la reunion", "terminer l'appel", "mettre fin a l'appel", "raccrocher", "deconnecter", "se deconnecter"])
        let audio = labels.contains { $0.contains("microphone") || $0.contains("micro") || ["mute", "unmute", "mute audio", "unmute audio", "couper le son", "reactiver le son", "activer le son"].contains($0) }
        let video = labels.contains { $0.contains("camera") || $0.contains("video") }
        return leave && audio && video ? .active : nil
    }
    public var confidence: Double { detectedPhase == nil ? 0 : 0.95 }

}

/// Requires two positive samples; three missing samples end an automatically detected call.
public struct DetectionReducer: Sendable {
    private var positives: [String: Int] = [:]
    private var missing: [String: Int] = [:]
    public init() {}
    public mutating func update(_ evidence: [DetectionEvidence]) -> (confirmed: [DetectionEvidence], ended: Set<String>) {
        let good = evidence.filter { $0.confidence >= 0.9 }
        let present = Set(good.map { "\($0.processID):\($0.windowID)" })
        var ended = Set<String>()
        for id in Array(positives.keys) where !present.contains(id) {
            positives[id] = 0
            missing[id, default: 0] += 1
            if missing[id, default: 0] >= 3 { ended.insert(id); positives[id] = nil; missing[id] = nil }
        }
        var confirmed: [DetectionEvidence] = []
        for item in good {
            let id = "\(item.processID):\(item.windowID)"
            positives[id, default: 0] += 1; missing[id] = 0
            if positives[id, default: 0] >= 2 { confirmed.append(item) }
        }
        return (confirmed, ended)
    }
}

public struct NormalizedCrop: Codable, Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 1
    public var height: Double = 1
    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        self.x = min(0.95, max(0, x)); self.y = min(0.95, max(0, y))
        self.width = min(1 - self.x, max(0.05, width))
        self.height = min(1 - self.y, max(0.05, height))
    }
    public var isValid: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1 && y + height <= 1 }
}

public struct CalloraSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var detectionEnabled = true
    public var persistentActivity = true
    public var automaticallyPresentCalls = true
    public var showDuration = true
    public var alwaysOnTop = true
    public var rememberPosition = true
    public var snapToEdges = true
    public var opacity = 1.0
    public var frameRate = 15
    public var layout: PanelLayout = .controls
    public var crop = NormalizedCrop()
    public var panelFrame: [Double]?
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, detectionEnabled, persistentActivity, automaticallyPresentCalls, showDuration, alwaysOnTop, rememberPosition, snapToEdges, opacity, frameRate, layout, crop, panelFrame }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        detectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .detectionEnabled) ?? detectionEnabled
        persistentActivity = try c.decodeIfPresent(Bool.self, forKey: .persistentActivity) ?? persistentActivity
        automaticallyPresentCalls = try c.decodeIfPresent(Bool.self, forKey: .automaticallyPresentCalls) ?? automaticallyPresentCalls
        showDuration = try c.decodeIfPresent(Bool.self, forKey: .showDuration) ?? showDuration
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? alwaysOnTop
        rememberPosition = try c.decodeIfPresent(Bool.self, forKey: .rememberPosition) ?? rememberPosition
        snapToEdges = try c.decodeIfPresent(Bool.self, forKey: .snapToEdges) ?? snapToEdges
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? frameRate
        layout = try c.decodeIfPresent(PanelLayout.self, forKey: .layout) ?? layout
        crop = try c.decodeIfPresent(NormalizedCrop.self, forKey: .crop) ?? crop
        panelFrame = try c.decodeIfPresent([Double].self, forKey: .panelFrame)
    }
}

public enum PanelLayout: String, Codable, CaseIterable, Sendable {
    case minimal, glass, controls, compact, audioOnly
    public var title: String {
        switch self {
        case .audioOnly: return "Audio only"
        default: return rawValue.capitalized
        }
    }
}
