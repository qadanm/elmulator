import CoreBluetoothMock
import Elmulator
import ElmulatorCoreBluetoothMock
import Foundation
import ObdSampleClient
import Testing

/// Locate the repo's `scenarios/` directory relative to this source file.
private func scenarioURL(_ name: String) -> URL {
    URL(filePath: #filePath)            // .../Tests/ObdSampleClientTests/OBDCITests.swift
        .deletingLastPathComponent()    // ObdSampleClientTests
        .deletingLastPathComponent()    // Tests
        .deletingLastPathComponent()    // repo root
        .appending(path: "scenarios")
        .appending(path: "\(name).scenario.json")
}

/// Stand up a scripted ELM327 as a mock BLE peripheral, connect a real
/// CoreBluetooth client to it, and run the body. Serialized because
/// CoreBluetooth-Mock uses global simulation state.
private struct MockCleanupFailure: Error {
    let bodyError: (any Error)?
    let cleanupError: any Error
}

@MainActor
func withMockAdapter(
    _ adapter: ElmulatorMockPeripheral,
    disconnectTimeout: TimeInterval = 5,
    _ body: (ELM327Client) async throws -> Void
) async throws {
    adapter.simulate()
    let client = ELM327Client(forceMock: true)
    var bodyError: (any Error)?
    do {
        try await client.connect()
        try await body(client)
    } catch { bodyError = error }

    adapter.cancelPendingResponses()
    var cleanupError: (any Error)?
    do { try await client.disconnect(timeout: disconnectTimeout) }
    catch { cleanupError = error }
    await client.invalidate()
    CBMCentralManagerMock.tearDownSimulation()
    if let cleanupError {
        if bodyError != nil { throw MockCleanupFailure(bodyError: bodyError, cleanupError: cleanupError) }
        throw cleanupError
    }
    if let bodyError { throw bodyError }
}

@MainActor
private func withScriptedAdapter(
    _ scenario: String,
    notifyChunkSize: Int = 20,
    _ body: (ELM327Client) async throws -> Void
) async throws {
    let loaded = try Scenario.load(from: scenarioURL(scenario))
    let adapter = ElmulatorMockPeripheral(scenario: loaded, notifyChunkSize: notifyChunkSize)
    try await withMockAdapter(adapter, body)
}

@MainActor
@Suite("OBD2 app CI tests against a scripted BLE ELM327", .serialized)
struct OBDCITests {
    @Test("connects over BLE and reads a stored P0420 with no radio")
    func p0420Scan() async throws {
        try await withScriptedAdapter("p0420_basic") { client in
            let reset = try await client.send("ATZ")
            #expect(reset.contains("ELM327 v1.5"))

            for setup in ["ATE0", "ATL0", "ATH1", "ATSP0"] {
                #expect(try await client.send(setup).contains("OK"))
            }

            let stored = try await client.send("03")
            #expect(stored.contains("43 01 04 20"))       // P0420 code bytes

            // An unmatched command falls through to the scenario default.
            #expect(try await client.send("0142").contains("NO DATA"))
        }
    }

    @Test("reassembles a reply split across many BLE notifications")
    func chunkedReassembly() async throws {
        // This scenario ships its replies in small pieces; the client must
        // stitch them back into one response ending at the prompt.
        try await withScriptedAdapter("chunked_stream", notifyChunkSize: 4) { client in
            _ = try await client.send("ATZ")
            let reply = try await client.send("0100")
            #expect(reply.contains("41 00"))
            #expect(reply.hasSuffix(">"))
        }
    }

    @Test("reads the full two-ECU CAN report from the sample client")
    func fullCanReport() async throws {
        try await withScriptedAdapter("can_full_report") { client in
            _ = try await client.send("ATZ")
            for setup in ["ATE0", "ATL0", "ATH1", "ATSP0"] {
                #expect(try await client.send(setup).contains("OK"))
            }

            #expect(try await client.send("ATDPN").contains("A6"))

            let stored = try await client.send("03")
            #expect(stored.contains("7E8 04 43 01 04 20"))   // stored P0420
            #expect(stored.contains("7EA 02 43 00"))         // second ECU, empty list

            let rpm = try await client.send("010C")
            #expect(rpm.contains("7E8 04 41 0C 1A F8"))      // 0x1AF8 / 4 = 1726 rpm
            #expect(rpm.contains("7EA 04 41 0C 00 00"))

            // The two ECUs advertise distinct readiness scopes.
            let readiness = try await client.send("0141")
            #expect(readiness.contains("7E8 06 41 41 00 07 65 04"))
            #expect(readiness.contains("7EA 06 41 41 00 04 00 00"))

            // Calibration IDs are split across ECU-specific CAN frames.
            let calibration = try await client.send("0904")
            #expect(calibration.contains("7E8 21 45 2D 43 41 4C 2D 41")) // FAKE-CAL-A
            #expect(calibration.contains("7EA 21 45 2D 43 41 4C 2D 43")) // FAKE-CAL-C

            let cvn = try await client.send("0906")
            #expect(cvn.contains("7E8 07 49 06 01 01 23 45 67"))
            #expect(cvn.contains("7EA 07 49 06 01 00 00 00 2A"))
        }
    }

    @Test("observes link loss after the scripted live reply")
    func linkLossAfterLiveReply() async throws {
        // can_delayed_link_loss answers 010C and then drops the link. The
        // helper still owns disconnect and global mock cleanup.
        try await withScriptedAdapter("can_delayed_link_loss") { client in
            _ = try await client.send("ATZ")
            for setup in ["ATE0", "ATL0", "ATH1", "ATSP0"] {
                #expect(try await client.send(setup).contains("OK"))
            }

            let live = try await client.send("010C")
            #expect(live.contains("7E8 04 41 0C 1A F8"))

            do {
                _ = try await client.send("03")
                Issue.record("expected the scripted link loss to fail the next request")
            } catch let error as ELM327Client.ClientError {
                switch error {
                case .disconnected, .notReady:
                    break   // link loss surfaced to the caller
                default:
                    Issue.record("unexpected client error after link loss: \(error)")
                }
            }
        }
    }

    @Test("does not crash on malformed adapter output")
    func malformedIsRobust() async throws {
        try await withScriptedAdapter("malformed") { client in
            _ = try await client.send("ATZ")
            let garbage = try await client.send("03")
            // The client returns whatever bytes arrived, up to the prompt. It
            // must not crash. Interpretation/robustness is the app's job.
            #expect(garbage.contains(">"))
        }
    }
}
