import AppKit
import Foundation
import SottoAPI
import SottoCore
import XCTest
@testable import Sotto

@MainActor
final class RemoteCaptureTests: XCTestCase {
    func testLongRemoteTakeSealsBeforeServerDeadline() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_CAPTURE_LONG_TEST"] == "1" else {
            throw XCTSkip("Set SOTTO_CAPTURE_LONG_TEST=1 to exercise the real three-minute deadline.")
        }
        try await withController(sources: ["ready"]) { controller, client in
            controller.toggleTestRecording()
            try await until { controller.isRecording }
            try await until(timeout: 182) { controller.activity == .success || controller.activity == .failed }
            XCTAssertEqual(controller.activity, .success, controller.errorMessage ?? "")
            XCTAssertEqual(controller.lastDeliveryStatus, .tested)
            XCTAssertEqual(controller.recordingFeedback.limitNotice, .stopped)
            let record = try await client.history().items.first { $0.device.id == controller.preferences.deviceID }
            XCTAssertEqual(record?.capture?.state, .sealed)
        }
    }

    func testRemoteOnlyMacNeedsNoMicrophonePermissionAndRenewsLeaseThroughDrain() async throws {
        try await withController(sources: ["ready"]) { controller, client in
            XCTAssertFalse(controller.permissions.microphone)
            XCTAssertTrue(controller.canTest)
            let clipboardCount = NSPasteboard.general.changeCount
            controller.toggleTestRecording()
            try await until { controller.isRecording }
            XCTAssertTrue(controller.recordingInputName?.contains("capture-fixture") == true)
            try await until { controller.liveTranscript == "Remote preview." }
            try await until { controller.recordingFeedback.levels.contains { $0 > 0 } }
            try await Task.sleep(for: .seconds(6.2))
            XCTAssertTrue(controller.isRecording, "The six-second lease must be renewed")
            controller.toggleTestRecording()
            try await until { controller.activity == .success }
            XCTAssertEqual(controller.lastDeliveryStatus, .tested)
            XCTAssertEqual(controller.lastTranscript, "Remote transcript.")
            XCTAssertEqual(NSPasteboard.general.changeCount, clipboardCount, "Mic tests must never paste or copy")
            let record = try await client.history().items.first { $0.device.id == controller.preferences.deviceID }
            XCTAssertEqual(record?.capture?.state, .sealed)
            XCTAssertEqual(record?.delivery?.status, "tested")
            XCTAssertEqual(record?.mode, .test)
        }
    }

    func testPreReadyRejectionFallsBackOnceWithFreshAdmissionAndNoPreferenceChanges() async throws {
        try await withController(sources: ["reject", "ready"]) { controller, client in
            let order = controller.microphones.preferences
            controller.toggleTestRecording()
            try await until { controller.isRecording }
            XCTAssertTrue(controller.recordingInputName?.contains("ready") == true)
            try await Task.sleep(for: .milliseconds(300))
            controller.toggleTestRecording()
            try await until { controller.activity == .success }
            XCTAssertEqual(controller.microphones.preferences, order)
            let records = try await client.history().items.filter { $0.device.id == controller.preferences.deviceID }
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(Set(records.map(\.requestID)).count, 2)
            XCTAssertEqual(records.filter { $0.status == .cancelled }.count, 1)
        }
    }

    func testRemoteStartupAllowsServerReadinessBudget() async throws {
        try await withController(sources: ["slow"]) { controller, _ in
            controller.toggleTestRecording()
            try await until { controller.isRecording || controller.activity == .failed }
            XCTAssertTrue(controller.isRecording, controller.errorMessage ?? "Remote startup failed")
            controller.cancelDictation()
            XCTAssertEqual(controller.activity, .idle)
        }
    }

    func testUnavailableRemoteSelectsLocalFallbackAndExplainsMissingLocalPermission() async throws {
        try await withController(sources: ["unknown"]) { controller, _ in
            let local = AudioInputDevice(uid: "local-test-input", name: "Mac fallback", transport: .builtIn)
            controller.microphones.update(devices: [local], systemDefaultUID: local.uid)
            controller.toggleTestRecording()
            try await until { controller.activity == .failed }
            XCTAssertTrue(controller.errorMessage?.contains("Allow microphone access") == true)
            XCTAssertFalse(controller.isRecording)
        }
    }

    func testFailedDiscoveryStillAttemptsLocalFallback() async throws {
        try await withController(sources: ["ready"]) { controller, client in
            let local = AudioInputDevice(uid: "local-test-input", name: "Mac fallback", transport: .builtIn)
            controller.microphones.update(devices: [local], systemDefaultUID: local.uid)
            try await client.send(path: "fixture/discovery", method: "POST", body: Data(#"{"unavailable":true}"#.utf8))
            do {
                controller.toggleTestRecording()
                try await until { controller.activity == .failed }
                XCTAssertTrue(controller.errorMessage?.contains("Allow microphone access") == true)
                XCTAssertEqual(controller.microphones.resolution.device, local)
            } catch {
                try? await client.send(path: "fixture/discovery", method: "POST", body: Data(#"{"unavailable":false}"#.utf8))
                throw error
            }
            try await client.send(path: "fixture/discovery", method: "POST", body: Data(#"{"unavailable":false}"#.utf8))
        }
    }

    func testOneLostHeartbeatResponseDoesNotInterruptAnOwnedTake() async throws {
        try await withController(sources: ["heartbeat-once"]) { controller, _ in
            controller.toggleTestRecording()
            try await until { controller.isRecording }
            try await Task.sleep(for: .seconds(1.2))
            XCTAssertTrue(controller.isRecording)
            controller.toggleTestRecording()
            try await until { controller.activity == .success }
            XCTAssertEqual(controller.lastDeliveryStatus, .tested)
        }
    }

    func testKnownSourceLossAndEventDisconnectCancelWithoutResultOrAutomaticSwitch() async throws {
        for source in ["lost", "event-loss", "heartbeat-loss"] {
            try await withController(sources: [source, "ready"]) { controller, client in
                controller.toggleTestRecording()
                try await until { controller.activity == .failed }
                XCTAssertTrue(controller.lastTranscript.isEmpty)
                XCTAssertEqual(controller.lastDeliveryStatus, .none)
                try await until {
                    let records = try await client.history().items.filter { $0.device.id == controller.preferences.deviceID }
                    return records.count == 1 && records[0].status == .cancelled
                }
            }
        }
    }

    func testReleaseWhileStartingAndCancelWhileRecordingNeverDeliver() async throws {
        for source in ["slow", "ready"] {
            try await withController(sources: [source]) { controller, client in
                controller.toggleTestRecording()
                if source == "ready" { try await until { controller.isRecording } }
                else { try await Task.sleep(for: .milliseconds(300)) }
                if source == "slow" { controller.toggleTestRecording() }
                else { controller.cancelDictation() }
                XCTAssertEqual(controller.activity, .idle)
                // An interrupted create response has no generation ID; the server lease releases it.
                try await until(timeout: 7) {
                    let records = try await client.history().items.filter { $0.device.id == controller.preferences.deviceID }
                    return records.count == 1 && records[0].status == .cancelled
                }
                XCTAssertTrue(controller.lastTranscript.isEmpty)
                XCTAssertEqual(controller.lastDeliveryStatus, .none)
            }
        }
    }

    private func withController(sources: [String], operation: (SottoController, ServerClient) async throws -> Void) async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["SOTTO_CAPTURE_TEST_URL"] else {
            throw XCTSkip("Run Server/tests/fixtures/capture-client-server.ts for the native capture contract test.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SottoCaptureTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ConfigurationStore(file: ConfigurationFile(url: root.appendingPathComponent("config.json")))
        await configuration.start(); configuration.stopWatching()
        let token = "sotto-native-capture-test-token-2026"
        let preferences = ClientPreferencesStore(root: root, environment: ["SOTTO_SERVER_URL": endpoint], readCredential: { _ in token })
        let controller = SottoController(configuration: configuration, startServices: false, clientPreferences: preferences)
        defer { controller.shutdown() }
        let client = try ServerClient(endpoint: endpoint, token: token)
        let inventory = try await client.audioSources()
        controller.microphones.updateRemote(inventory, server: client.endpoint.absoluteString)
        for source in sources {
            let device = try XCTUnwrap(controller.microphones.availableDevices.first { $0.uid == source })
            controller.microphones.addToPriority(device)
        }
        controller.refreshServer()
        try await until { controller.isServerReady }
        do { try await operation(controller, client) }
        catch { controller.cancelDictation(); await configuration.flush(); throw error }
        await configuration.flush()
    }

    private func until(timeout: TimeInterval = 8, _ condition: () async throws -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while try await !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail("Timed out waiting for capture state")
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
