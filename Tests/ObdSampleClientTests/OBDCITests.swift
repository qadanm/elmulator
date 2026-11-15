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
