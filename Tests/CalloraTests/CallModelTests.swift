import Testing
import Foundation
@testable import Callora

@Test func lifecycleRejectsImpossibleTransitions() {
    var call = CallSession(id: "test", bundleID: "test", processID: 1, title: "Test", provider: "Test", manual: true, confidence: 1)
    let outcome6 = (!call.transition(to: .active))
    #expect(outcome6)
    let outcome7 = (call.transition(to: .incoming))
    #expect(outcome7)
    let outcome8 = (!call.transition(to: .ended))
    #expect(outcome8)
    let outcome9 = (call.transition(to: .connecting))
    #expect(outcome9)
    let start = Date(timeIntervalSince1970: 100)
    let outcome11 = (call.transition(to: .active, now: start))
    #expect(outcome11)
    let outcome12 = (call.transition(to: .reconnecting))
    #expect(outcome12)
    let outcome13 = (call.transition(to: .active, now: Date(timeIntervalSince1970: 200)))
    #expect(outcome13)
    #expect(call.startedAt == start)
    let outcome15 = (call.transition(to: .ending))
    #expect(outcome15)
    let outcome16 = (call.transition(to: .ended))
    #expect(outcome16)
    let outcome17 = (!call.transition(to: .active))
    #expect(outcome17)
}

@Test func microphoneOrWindowTitleDoesNotConfirmCall() {
    for labels: Set<String> in [["microphone"], ["Zoom Meeting"], ["Recording", "Mute", "Stop video"], ["Leave call"]] {
        let evidence = DetectionEvidence(bundleID: "test", processID: 1, provider: "Test", windowID: "one", labels: labels)
        #expect(evidence.confidence < 0.9)
    }
}

@Test func detectionRequiresConsecutiveEvidenceAndDebouncesDisappearance() {
    let evidence = DetectionEvidence(bundleID: "test", processID: 1, provider: "Test", windowID: "one", labels: ["Leave call", "Microphone", "Camera"])
    var reducer = DetectionReducer()
    let outcome30 = (reducer.update([evidence]).confirmed.isEmpty)
    #expect(outcome30)
    let outcome31 = (reducer.update([]).confirmed.isEmpty)
    #expect(outcome31)
    let outcome32 = (reducer.update([evidence]).confirmed.isEmpty)
    #expect(outcome32)
    let outcome33 = (reducer.update([evidence]).confirmed.count == 1)
    #expect(outcome33)
    let outcome34 = (reducer.update([]).ended.isEmpty)
    #expect(outcome34)
    let outcome35 = (reducer.update([]).ended.isEmpty)
    #expect(outcome35)
    let outcome36 = (reducer.update([]).ended == ["1:one"])
    #expect(outcome36)
    let outcome37 = (reducer.update([evidence]).confirmed.isEmpty)
    #expect(outcome37)
}

@Test func providersNeverClaimUnverifiedControls() {
    let call = CallSession(id: "test", bundleID: "test", processID: 1, title: "Test", provider: "Test", manual: true, confidence: 1)
    #expect(call.capabilities == [.openApplication, .selectWindow])
    #expect(call.microphoneMuted == nil)
    #expect(call.cameraDisabled == nil)
    #expect(call.screenSharing == nil)
}

@Test func normalizedCropCannotEscapeWindow() {
    for x in stride(from: -2.0, through: 2.0, by: 0.1) {
        let crop = NormalizedCrop(x: x, y: x, width: 2 - x, height: -x)
        #expect(crop.isValid)
    }
}

@Test func settingsRoundTripAndConservativeDefaults() throws {
    let settings = CalloraSettings()
    #expect(settings.detectionEnabled)
    #expect(settings.persistentActivity)
    #expect(settings.frameRate == 15)
    #expect(try JSONDecoder().decode(CalloraSettings.self, from: JSONEncoder().encode(settings)) == settings)
}
