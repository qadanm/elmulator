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

    @Test("shared FFE0 exposes one notify/write characteristic and serves both write modes")
    func sharedCharacteristicLayout() async throws {
        let scenario = try Scenario.bundled("p0420_basic")
        let adapter = ElmulatorMockPeripheral(scenario: scenario, profile: .sharedFFE0)
        adapter.simulate()
        let probe = SharedProfileProbe()

        do {
            try await probe.connect()
            let characteristics = probe.discoveredCharacteristics
            #expect(characteristics.count == 1)
            let characteristic = try #require(characteristics.first)
            #expect(characteristic.uuid == CBMUUID(string: "FFE1"))
            #expect(characteristic.properties.contains(.notify))
            #expect(characteristic.properties.contains(.write))
            #expect(characteristic.properties.contains(.writeWithoutResponse))

            let withoutResponse = try await probe.send("ATZ", withResponse: false)
            #expect(withoutResponse.contains("ELM327"))

            // The same characteristic must also accept a write-with-response.
            let withResponse = try await probe.send("03", withResponse: true)
            #expect(withResponse.contains("43 01 04 20"))
        } catch {
            adapter.cancelPendingResponses()
            try? await probe.disconnect()
            CBMCentralManagerMock.tearDownSimulation()
            throw error
        }

        adapter.cancelPendingResponses()
        try await probe.disconnect()
        CBMCentralManagerMock.tearDownSimulation()
    }
}

/// Minimal raw CoreBluetooth central used to inspect GATT layout. The sample
/// client hardcodes Nordic UART, so a shared-profile test needs its own probe.
private final class SharedProfileProbe: NSObject, @unchecked Sendable {
    enum ProbeError: Error { case timeout, notReady }

    private let serviceUUID = CBMUUID(string: "FFE0")
    private let characteristicUUID = CBMUUID(string: "FFE1")
    private var central: CBMCentralManager!
    private var peripheral: CBMPeripheral?
    private var characteristic: CBMCharacteristic?
    private(set) var discoveredCharacteristics: [CBMCharacteristic] = []
    private var replyBuffer = ""

    private var connectPending: ProbePending<Void>?
    private var replyPending: ProbePending<String>?
    private var disconnectPending: ProbePending<Void>?

    override init() {
        super.init()
        central = CBMCentralManagerFactory.instance(delegate: self, queue: .main, forceMock: true)
    }

    @MainActor func connect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            connectPending = ProbePending(continuation, timeout: 5, error: ProbeError.timeout)
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [serviceUUID])
            }
        }
    }

    @MainActor func send(_ command: String, withResponse: Bool) async throws -> String {
        guard let peripheral, let characteristic else { throw ProbeError.notReady }
        replyBuffer = ""
        return try await withCheckedThrowingContinuation { continuation in
            replyPending = ProbePending(continuation, timeout: 5, error: ProbeError.timeout)
            peripheral.writeValue(
                Data((command + "\r").utf8),
                for: characteristic,
                type: withResponse ? .withResponse : .withoutResponse
            )
        }
    }

    @MainActor func disconnect() async throws {
        guard let peripheral, peripheral.state != .disconnected else {
            self.peripheral?.delegate = nil
            self.peripheral = nil
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            disconnectPending = ProbePending(continuation, timeout: 5, error: ProbeError.timeout)
            central.cancelPeripheralConnection(peripheral)
        }
        self.peripheral?.delegate = nil
        self.peripheral = nil
        characteristic = nil
    }
}

extension SharedProfileProbe: CBMCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBMCentralManager) {
        if central.state == .poweredOn, connectPending != nil {
            central.scanForPeripherals(withServices: [serviceUUID])
        }
    }

    func centralManager(_ central: CBMCentralManager, didDiscover peripheral: CBMPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard connectPending != nil, self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBMCentralManager, didConnect peripheral: CBMPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBMCentralManager, didFailToConnect peripheral: CBMPeripheral, error: Error?) {
        connectPending?.finish(.failure(error ?? ProbeError.notReady))
        connectPending = nil
    }

    func centralManager(_ central: CBMCentralManager, didDisconnectPeripheral peripheral: CBMPeripheral, error: Error?) {
        disconnectPending?.finish(.success(()))
        disconnectPending = nil
    }
}

extension SharedProfileProbe: CBMPeripheralDelegate {
    func peripheral(_ peripheral: CBMPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            connectPending?.finish(.failure(ProbeError.notReady))
            connectPending = nil
            return
        }
        peripheral.discoverCharacteristics([characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBMPeripheral, didDiscoverCharacteristicsFor service: CBMService, error: Error?) {
        discoveredCharacteristics = service.characteristics ?? []
        guard let notify = discoveredCharacteristics.first(where: { $0.uuid == characteristicUUID }) else {
            connectPending?.finish(.failure(ProbeError.notReady))
            connectPending = nil
            return
        }
        characteristic = notify
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBMPeripheral, didUpdateNotificationStateFor characteristic: CBMCharacteristic, error: Error?) {
        if let error {
            connectPending?.finish(.failure(error))
        } else {
            connectPending?.finish(.success(()))
        }
        connectPending = nil
    }

    func peripheral(_ peripheral: CBMPeripheral, didUpdateValueFor characteristic: CBMCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        replyBuffer += String(decoding: data, as: UTF8.self)
        if replyBuffer.contains(">") {
            replyPending?.finish(.success(replyBuffer))
            replyPending = nil
        }
    }

    func peripheral(_ peripheral: CBMPeripheral, didWriteValueFor characteristic: CBMCharacteristic, error: Error?) {
        if let error {
            replyPending?.finish(.failure(error))
            replyPending = nil
        }
    }
}

/// Checked continuation plus timeout, resumed at most once (main queue only).
private final class ProbePending<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private var timeout: DispatchWorkItem?

    init(_ continuation: CheckedContinuation<T, Error>, timeout seconds: TimeInterval, error: Error) {
        self.continuation = continuation
        let item = DispatchWorkItem { [weak self] in self?.finish(.failure(error)) }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func finish(_ result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}
