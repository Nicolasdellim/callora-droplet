import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit
import SwiftUI

/// CMSampleBuffer is immutable once handed to SCStreamOutput. It is retained only until the next frame.
final class VideoFrame: @unchecked Sendable {
    let sample: CMSampleBuffer
    init(_ sample: CMSampleBuffer) { self.sample = sample }
}

@MainActor final class VideoCaptureService: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var frame: VideoFrame?
    @Published private(set) var isCapturing = false
    @Published private(set) var sourceName: String?
    @Published private(set) var error: String?
    @Published private(set) var lastFrameAt: Date?
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "app.callora.frames", qos: .userInteractive)
    private var generation = 0
    private var trackingTask: Task<Void, Never>?
    private var acceptedStream: ObjectIdentifier?
    private var configuredSize = CGSize.zero
    var onSourceLost: (() -> Void)?

    func windows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        return content.windows.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
            $0.windowLayer == 0 && $0.frame.width >= 100 && $0.frame.height >= 80 &&
            !($0.title ?? "").isEmpty
        }.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
    }

    func start(window: SCWindow, settings: CalloraSettings) async {
        await stop()
        generation += 1
        let token = generation
        error = nil
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = makeConfiguration(filter: filter, settings: settings)
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            stream = newStream
            acceptedStream = ObjectIdentifier(newStream)
            try await newStream.startCapture()
            guard token == generation else { try? await newStream.stopCapture(); return }
            sourceName = "\(window.owningApplication?.applicationName ?? "Application") — window capture"
            isCapturing = true
            track(windowID: window.windowID, stream: newStream, settings: settings, token: token)
        } catch {
            guard token == generation else { return }
            self.error = "Capture unavailable. Check Screen Recording permission and select an available window."
            stream = nil; acceptedStream = nil; frame = nil; isCapturing = false
        }
    }

    private func makeConfiguration(filter: SCContentFilter, settings: CalloraSettings) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let bounds = filter.contentRect
        let c = settings.crop.isValid ? settings.crop : NormalizedCrop()
        configuration.sourceRect = CGRect(x: bounds.width * c.x, y: bounds.height * c.y,
                                          width: bounds.width * c.width, height: bounds.height * c.height)
        let ratio = max(0.1, configuration.sourceRect.width / max(1, configuration.sourceRect.height))
        configuration.width = 960
        configuration.height = min(1920, max(160, Int(960 / ratio)))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32([10, 15, 30].contains(settings.frameRate) ? settings.frameRate : 15))
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuredSize = bounds.size
        return configuration
    }

    private func track(windowID: CGWindowID, stream: SCStream, settings: CalloraSettings, token: Int) {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            var misses = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard let self, self.generation == token else { return }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                    guard !Task.isCancelled, self.generation == token else { return }
                    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                        misses += 1
                        if misses >= 2 {
                            await self.stop()
                            self.error = "The selected window is no longer available. Select another source."
                            self.onSourceLost?()
                            return
                        }
                        continue
                    }
                    misses = 0
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    if filter.contentRect.size != self.configuredSize {
                        try await stream.updateContentFilter(filter)
                        try await stream.updateConfiguration(self.makeConfiguration(filter: filter, settings: settings))
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == token else { return }
                    await self.stop()
                    self.error = "Source access was lost. Check Screen Recording permission."
                    self.onSourceLost?()
                    return
                }
            }
        }
    }

    func stop() async {
        trackingTask?.cancel(); trackingTask = nil
        generation += 1
        acceptedStream = nil
        let previous = stream; stream = nil
        isCapturing = false; frame = nil; sourceName = nil; lastFrameAt = nil
        if let previous { try? await previous.stopCapture() }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue else { return }
        let frame = VideoFrame(sampleBuffer)
        let identity = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, self.acceptedStream == identity else { return }
            self.frame = frame
            self.lastFrameAt = .now
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let identity = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, self.acceptedStream == identity else { return }
            await self.stop()
            self.error = "The source stopped sharing. Select its window again."
            self.onSourceLost?()
        }
    }
}

struct VideoSurface: NSViewRepresentable {
    @ObservedObject var capture: VideoCaptureService
    func makeNSView(context: Context) -> SampleBufferView { SampleBufferView() }
    func updateNSView(_ view: SampleBufferView, context: Context) {
        if let sample = capture.frame?.sample { view.show(sample) }
        else { view.clear() }
    }
}

final class SampleBufferView: NSView {
    private let videoLayer = AVSampleBufferDisplayLayer()
    private var previous: CMSampleBuffer?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); videoLayer.frame = bounds }
    func show(_ sample: CMSampleBuffer) {
        guard previous !== sample else { return }
        previous = sample
        if videoLayer.status == .failed { videoLayer.flush() }
        // The capture timestamp shares the host clock. Display immediately to avoid accumulating latency.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        if videoLayer.isReadyForMoreMediaData { videoLayer.enqueue(sample) }
    }
    func clear() { previous = nil; videoLayer.flushAndRemoveImage() }
}
