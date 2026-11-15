import CoreBluetoothMock
import Elmulator
import ElmulatorBLE
import ElmulatorCoreBluetoothMock
import Foundation
import ObdSampleClient
import Testing

// These extend the OBDCITests suite (rather than starting a new suite) so they
// stay serialized with the other CoreBluetooth-Mock tests. CoreBluetooth-Mock
// uses global simulation state, so two CBM suites running in parallel corrupt
// it. Keeping everything in one .serialized suite avoids that.
//
// The CoreBluetooth-Mock bridge can honor per-piece reply delays (opt in with
// `applyDelays: true`), so timeout paths are reachable through BLE. Off by
// default so the common CI path stays fast.
extension OBDCITests {
    private func slowScenario() -> Scenario {
        Scenario(id: "slow", commands: [
            Scenario.Command(request: "ATZ", responseChunks: ["ELM327 v1.5\r\r>"], echo: true),
            Scenario.Command(request: "03", responseChunks: ["7E8 04 43 01 04 20\r\r>"], delayMS: 400),
        ])
    }

    @Test("a delayed reply makes the client time out through the mock")
    func delayedReplyTimesOut() async throws {
        let adapter = ElmulatorMockPeripheral(scenario: slowScenario(), applyDelays: true)
        try await withMockAdapter(adapter) { client in
            _ = try await client.send("ATZ")
            await #expect(throws: ELM327Client.ClientError.self) {
                _ = try await client.send("03", timeout: 0.15)
            }
            // No settling sleep: cleanup invalidates the pending delayed reply
            // and awaits actual disconnect before global teardown.
        }
    }

    @Test("with delays off (default) the same scenario returns promptly")
    func defaultNoDelay() async throws {
        let adapter = ElmulatorMockPeripheral(scenario: slowScenario())   // applyDelays: false
        try await withMockAdapter(adapter) { client in
            _ = try await client.send("ATZ")
            #expect(try await client.send("03", timeout: 1.0).contains("43 01 04 20"))
        }
    }

    @Test("cancelling an enqueued bridge reply prevents it satisfying the next command")
    func cancelledReplyCannotCrossCommand() async throws {
        let scenario = Scenario(id: "cancelled-delivery", commands: [
            Scenario.Command(request: "03", responseChunks: ["OLD\r>"], delayMS: 120),
            Scenario.Command(request: "010C", responseChunks: ["NEW\r>"], delayMS: 240),
        ])
        let adapter = ElmulatorMockPeripheral(scenario: scenario,
            configuration: .init(recordTranscript: true), applyDelays: true)
        try await withMockAdapter(adapter) { client in
            // Queue the old emission and cancel it in one main-actor turn.
            // A client timeout resumes asynchronously: under load OLD may have
            // already reached Nordic's notification queue before this task resumes.
            // cancelPendingResponses fences pending bridge emissions, not bytes
            // already delivered to the underlying Bluetooth mock.
            let write = CBMCharacteristicMock(
                type: CBMUUID(string: AdapterProfile.fakeELM.writeCharacteristicUUID),
                properties: .writeWithoutResponse)
            adapter.peripheral(adapter.spec, didReceiveWriteCommandFor: write,
                               data: Data("03\r".utf8))
            #expect(adapter.transcript.map(\.normalized) == ["03"])
            adapter.cancelPendingResponses()
            let reply = try await client.send("010C", timeout: 2)
            #expect(reply.contains("NEW"))
            #expect(!reply.contains("OLD"))
            #expect(adapter.transcript.map(\.normalized) == ["03", "010C"])
        }
    }

    @Test("throwing test body disconnects before the next simulation")
    func throwingBodyCleansUp() async throws {
        enum DeliberateFailure: Error { case expected }
        await #expect(throws: DeliberateFailure.self) {
            try await withMockAdapter(ElmulatorMockPeripheral(scenario: slowScenario())) { _ in
                throw DeliberateFailure.expected
            }
        }
        try await withMockAdapter(ElmulatorMockPeripheral(scenario: slowScenario())) { client in
            let reply = try await client.send("ATZ")
            #expect(reply.contains("ELM327"))
        }
    }

    @Test("rapid mock sessions close before replacement simulation")
    func repeatedSimulationReplacement() async throws {
        for _ in 0..<12 {
            try await withMockAdapter(ElmulatorMockPeripheral(scenario: slowScenario())) { client in
                let reply = try await client.send("ATZ")
                #expect(reply.contains("ELM327"))
            }
        }
    }

    @Test("disconnect timeout fails but cannot contaminate a replacement simulation")
    func disconnectTimeoutStillResets() async throws {
        var observedTimeout = false
        do {
            try await withMockAdapter(ElmulatorMockPeripheral(scenario: slowScenario()),
                                      disconnectTimeout: 0) { _ in }
        } catch {
            #expect(error as? ELM327Client.ClientError == .timeout("disconnect"))
            observedTimeout = true
        }
        #expect(observedTimeout)
        try await withMockAdapter(ElmulatorMockPeripheral(scenario: slowScenario())) { client in
            let reply = try await client.send("ATZ")
            #expect(reply.contains("ELM327"))
        }
    }
}
