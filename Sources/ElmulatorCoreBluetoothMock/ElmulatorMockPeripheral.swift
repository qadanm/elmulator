import CoreBluetoothMock
import Elmulator
import ElmulatorBLE
import Foundation

/// Turns an elmulator scenario into a Nordic-CoreBluetooth-Mock peripheral, so
/// an app's **real** CoreBluetooth code can be tested against a scripted
/// ELM327 adapter, on the iOS Simulator or in CI, with no Bluetooth radio.
///
/// This is the bridge for the large majority of OBD2 apps that talk to
/// `CBCentralManager`/`CBPeripheral` directly (via the drop-in `CBM*` types
/// from [CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock)),
/// rather than adopting elmulator's own `CentralStack` protocol.
///
/// This bridge requires main-queue mock operations (including the client manager)
/// because the pinned mock has shared global state and a main-runloop advertising
/// timer. Serialize simulations and cancel pending replies, await client disconnect,
/// then tear down on main, including on throwing test paths.
///
/// Usage in a test:
/// ```swift
/// let scenario = try Scenario.load(from: url)
/// let adapter = ElmulatorMockPeripheral(scenario: scenario)
/// CBMCentralManagerMock.simulatePeripherals([adapter.spec])
/// CBMCentralManagerMock.simulateInitialState(.poweredOn)
/// // ...create your manager with CBMCentralManagerFactory.instance(forceMock: true)
/// // and run your real connect/discover/subscribe/write flow.
/// adapter.cancelPendingResponses()
/// // await client disconnect completion, then:
/// CBMCentralManagerMock.tearDownSimulation()
/// ```
@MainActor
public final class ElmulatorMockPeripheral: @preconcurrency CBMPeripheralSpecDelegate {
    private let profile: AdapterProfile
    private let notifyChunkSize: Int
    private let advertisedName: String
    private let applyDelays: Bool
    private var deliveryGeneration: UInt64 = 0
    private var engine: ScenarioEngine
    private var inbound = ""
    private var notifyEnabled = false

    /// The transcript of the conversation served so far, when the engine
    /// configuration has `recordTranscript` on. Empty otherwise.
    public var transcript: [TranscriptEntry] {
        dispatchPrecondition(condition: .onQueue(.main))
        return engine.transcript
    }

    private let serviceUUID: CBMUUID
    private let writeUUID: CBMUUID
    private let notifyUUID: CBMUUID

    // The notify characteristic instance must be the *same* object that lives
    // in the service: `simulateValueUpdate` verifies membership by identity.
    private let notifyCharacteristic: CBMCharacteristicMock
    private let writeCharacteristic: CBMCharacteristicMock
    private let service: CBMServiceMock

    public init(
        scenario: Scenario,
        profile: AdapterProfile = .fakeELM,
        configuration: EngineConfiguration = .init(),
        notifyChunkSize: Int = 20,
        advertisedName: String? = nil,
        applyDelays: Bool = false
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.profile = profile
        self.notifyChunkSize = notifyChunkSize
        self.advertisedName = advertisedName ?? profile.advertisedName
        self.applyDelays = applyDelays
        self.engine = ScenarioEngine(scenario: scenario, configuration: configuration)

        let serviceUUID = CBMUUID(string: profile.serviceUUID)
        let writeUUID = CBMUUID(string: profile.writeCharacteristicUUID)
        let notifyUUID = CBMUUID(string: profile.notifyCharacteristicUUID)
        self.serviceUUID = serviceUUID
        self.writeUUID = writeUUID
        self.notifyUUID = notifyUUID

        self.notifyCharacteristic = CBMCharacteristicMock(
            type: notifyUUID,
            properties: .notify,
            descriptors: CBMDescriptorMock(type: CBMUUID(string: "2902"))  // CCCD
        )
        self.writeCharacteristic = CBMCharacteristicMock(
            type: writeUUID,
            properties: [.write, .writeWithoutResponse]
        )
        self.service = CBMServiceMock(
            type: serviceUUID,
            primary: true,
            characteristics: writeCharacteristic, notifyCharacteristic
        )
    }

    /// The mock peripheral spec to hand to `CBMCentralManagerMock.simulatePeripherals`.
    public private(set) lazy var spec: CBMPeripheralSpec = CBMPeripheralSpec
        .simulatePeripheral(proximity: .immediate)
        .advertising(
            advertisementData: [
                CBMAdvertisementDataIsConnectable: true as NSNumber,
                CBMAdvertisementDataLocalNameKey: advertisedName,
                CBMAdvertisementDataServiceUUIDsKey: [serviceUUID],
            ],
            withInterval: 0.1
        )
        .connectable(
            name: advertisedName,
            services: [service],
            delegate: self,
            connectionInterval: 0.01
        )
        .build()

    /// Convenience: register this peripheral with the global mock and power on.
    /// Pair with `CBMCentralManagerMock.tearDownSimulation()` in your teardown.
    public func simulate(initialState: CBMManagerState = .poweredOn) {
        dispatchPrecondition(condition: .onQueue(.main))
        CBMCentralManagerMock.simulatePeripherals([spec])
        CBMCentralManagerMock.simulateInitialState(initialState)
    }

    /// Invalidate pending delayed emissions before disconnect/teardown. Call on
    /// main, like all bridge and mock-manager operations. It does not tear down
    /// global state or pretend a connection has finished disconnecting.
    public func cancelPendingResponses() {
        dispatchPrecondition(condition: .onQueue(.main))
        deliveryGeneration &+= 1
        inbound = ""
        notifyEnabled = false
    }

    // MARK: - CBMPeripheralSpecDelegate

    public func peripheral(
        _ peripheral: CBMPeripheralSpec,
        didReceiveSetNotifyRequest enabled: Bool,
        for characteristic: CBMCharacteristicMock
    ) -> Result<Void, Error> {
        dispatchPrecondition(condition: .onQueue(.main))
        guard characteristic.uuid == notifyUUID else {
            return .failure(CBMATTError(.requestNotSupported))
        }
        notifyEnabled = enabled
        return .success(())
    }

    // Write with response.
    public func peripheral(
        _ peripheral: CBMPeripheralSpec,
        didReceiveWriteRequestFor characteristic: CBMCharacteristicMock,
        data: Data
    ) -> Result<Void, Error> {
        dispatchPrecondition(condition: .onQueue(.main))
        guard characteristic.uuid == writeUUID else {
            return .failure(CBMATTError(.writeNotPermitted))
        }
        handle(data, on: peripheral)
        return .success(())
    }

    // Write without response: the common ELM327 clone path.
    public func peripheral(
        _ peripheral: CBMPeripheralSpec,
        didReceiveWriteCommandFor characteristic: CBMCharacteristicMock,
        data: Data
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard characteristic.uuid == writeUUID else { return }
        handle(data, on: peripheral)
    }

    public func peripheral(
        _ peripheral: CBMPeripheralSpec,
        didReceiveReadRequestFor characteristic: CBMCharacteristicMock
    ) -> Result<Data, Error> {
        .failure(CBMATTError(.readNotPermitted))
    }

    // MARK: - Command handling

    private func handle(_ data: Data, on peripheral: CBMPeripheralSpec) {
        inbound += String(decoding: data, as: UTF8.self)
        while let line = takeLine() {
            guard !line.isEmpty else { continue }
            emit(engine.plan(for: line), on: peripheral)
        }
    }

    private func emit(_ plan: ResponsePlan, on peripheral: CBMPeripheralSpec) {
        // Real BLE delivers each reply across MTU-sized notifications; mimic
        // that so the app's response assembler is exercised.
        func send(_ piece: ResponsePlan.Piece) {
            for chunk in Self.chunk(piece.bytes, size: notifyChunkSize) {
                peripheral.simulateValueUpdate(Data(chunk), for: notifyCharacteristic)
            }
        }

        guard applyDelays else {
            for piece in plan.pieces { send(piece) }
            if plan.postAction == .disconnect { peripheral.simulateDisconnection() }
            return
        }

        // The mock reads global manager/peripheral collections before scheduling
        // callbacks. Stay on main with setup/discovery/teardown; callback routing
        // alone does not make background access safe. Generation invalidation
        // prevents a timed-out reply entering a later simulation.
        let target = peripheral
        let characteristic = notifyCharacteristic
        let generation = deliveryGeneration
        var cumulativeMS = 0
        for piece in plan.pieces {
            cumulativeMS += piece.delayMS
            let chunks = Self.chunk(piece.bytes, size: notifyChunkSize).map { Data($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(cumulativeMS)) { [weak self] in
                guard let self, self.deliveryGeneration == generation else { return }
                for chunk in chunks { target.simulateValueUpdate(chunk, for: characteristic) }
            }
        }
        if plan.postAction == .disconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(cumulativeMS)) { [weak self] in
                guard let self, self.deliveryGeneration == generation else { return }
                target.simulateDisconnection()
            }
        }
    }

    private func takeLine() -> String? {
        guard let index = inbound.firstIndex(where: { $0 == "\r" || $0 == "\n" }) else {
            return nil
        }
        let line = String(inbound[inbound.startIndex..<index])
        inbound = String(inbound[inbound.index(after: index)...])
        return line.trimmingCharacters(in: .whitespaces)
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
