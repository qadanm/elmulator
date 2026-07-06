import CoreBluetoothMock
import Elmulator
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
        adapter.simulate()
        defer { CBMCentralManagerMock.tearDownSimulation() }

        let client = ELM327Client(forceMock: true)
        try await client.connect()
        _ = try await client.send("ATZ")   // no delay, returns promptly
        await #expect(throws: ELM327Client.ClientError.self) {
            _ = try await client.send("03", timeout: 0.15)
        }
        // Let the scheduled 400ms emission fire while the simulation is still
        // up, so teardown does not race a late notification.
        try? await Task.sleep(for: .milliseconds(500))
        client.disconnect()
    }

    @Test("with delays off (default) the same scenario returns promptly")
    func defaultNoDelay() async throws {
        let adapter = ElmulatorMockPeripheral(scenario: slowScenario())   // applyDelays: false
        adapter.simulate()
        defer { CBMCentralManagerMock.tearDownSimulation() }

        let client = ELM327Client(forceMock: true)
        try await client.connect()
        _ = try await client.send("ATZ")
        #expect(try await client.send("03", timeout: 1.0).contains("43 01 04 20"))
        client.disconnect()
    }
}
