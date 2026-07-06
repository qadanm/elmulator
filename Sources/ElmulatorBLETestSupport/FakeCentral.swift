import Elmulator
import ElmulatorBLE
import Foundation

/// A `CentralStack` that hosts a scenario in-process, so a full scan can run
/// through your production Bluetooth code with no Bluetooth radio. It emits
/// the same event sequence a real CoreBluetooth central reports, chunks
/// replies to a notify-sized limit like real BLE notifications, and honors
/// the scenario's stall and disconnect actions.
///
/// Swap this in wherever you would use `makeCoreBluetoothStack()` to test the
/// whole connect → discover → subscribe → write → notify flow deterministically.
public actor FakeCentral: CentralStack {
    public enum PowerMode: Sendable {
        case poweredOn
        case neverPowersOn
        case unauthorized
    }

    private let scenario: Scenario
    private let profile: AdapterProfile
    private let notifyChunkSize: Int
    private let powerMode: PowerMode
    private let peripheralID: String
    private let peripheralName: String
    private var engine: ScenarioEngine

    private let stream: AsyncStream<CentralEvent>
    private let continuation: AsyncStream<CentralEvent>.Continuation

    public init(
        scenario: Scenario,
        profile: AdapterProfile = .fakeELM,
        configuration: EngineConfiguration = .init(),
        notifyChunkSize: Int = 20,
        powerMode: PowerMode = .poweredOn,
        peripheralID: String = "FAKE-BLE-PERIPHERAL",
        peripheralName: String = "FakeELM"
    ) {
        self.scenario = scenario
        self.profile = profile
        self.notifyChunkSize = notifyChunkSize
        self.powerMode = powerMode
        self.peripheralID = peripheralID
        self.peripheralName = peripheralName
        self.engine = ScenarioEngine(scenario: scenario, configuration: configuration)
        var storedContinuation: AsyncStream<CentralEvent>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .unbounded) { storedContinuation = $0 }
        self.continuation = storedContinuation
        // Power state is reported first, exactly like CoreBluetooth.
        switch powerMode {
        case .poweredOn: continuation.yield(.poweredOn)
        case .unauthorized: continuation.yield(.unauthorized)
        case .neverPowersOn: break
        }
    }

    /// The transcript of the conversation served so far, when the engine
    /// configuration has `recordTranscript` on. Empty otherwise.
    public var transcript: [TranscriptEntry] { engine.transcript }

    public nonisolated func events() -> AsyncStream<CentralEvent> { stream }

    public func scan(serviceUUIDs: [String]) async {
        guard powerMode == .poweredOn else { return }
        continuation.yield(.discovered(DiscoveredPeripheral(id: peripheralID, name: peripheralName)))
    }

    public func stopScan() async {}

    public func connect(peripheralID: String) async {
        continuation.yield(.connected(peripheralID: peripheralID))
    }

    public func discoverServices(_ serviceUUIDs: [String], peripheralID: String) async {
        continuation.yield(.servicesDiscovered(
            peripheralID: peripheralID,
            serviceUUIDs: [profile.serviceUUID],
            error: nil
        ))
    }

    public func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, peripheralID: String) async {
        continuation.yield(.characteristicsDiscovered(
            peripheralID: peripheralID,
            serviceUUID: serviceUUID,
            characteristicUUIDs: [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
            error: nil
        ))
    }

    public func setNotify(_ enabled: Bool, characteristicUUID: String, serviceUUID: String, peripheralID: String) async {
        continuation.yield(.notifyStateChanged(
            peripheralID: peripheralID,
            characteristicUUID: characteristicUUID,
            isNotifying: enabled,
            error: nil
        ))
    }

    public func write(_ data: Data, characteristicUUID: String, serviceUUID: String, peripheralID: String, withResponse: Bool) async {
        let command = String(decoding: data, as: UTF8.self)
        let plan = engine.plan(for: command)
        for piece in plan.pieces {
            if piece.delayMS > 0 {
                try? await Task.sleep(for: .milliseconds(piece.delayMS))
            }
            // Real BLE splits each write reply across MTU-sized
            // notifications; mimic that so the assembler is exercised.
            for chunk in Self.chunk(piece.bytes, size: notifyChunkSize) {
                continuation.yield(.notification(
                    peripheralID: peripheralID,
                    characteristicUUID: profile.notifyCharacteristicUUID,
                    data: Data(chunk)
                ))
            }
        }
        if plan.postAction == .disconnect {
            continuation.yield(.disconnected(peripheralID: peripheralID, error: "scenario disconnect"))
        }
    }

    public func cancel(peripheralID: String) async {
        continuation.yield(.disconnected(peripheralID: peripheralID, error: nil))
    }

    public func stop() async {
        continuation.finish()
    }

    private static func chunk(_ bytes: [UInt8], size: Int) -> [[UInt8]] {
        guard size > 0, bytes.count > size else { return bytes.isEmpty ? [] : [bytes] }
        var pieces: [[UInt8]] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + size, bytes.count)
            pieces.append(Array(bytes[index..<end]))
            index = end
        }
        return pieces
    }
}
