import CoreBluetooth
import Foundation

/// Builds the real central-role BLE stack backed by CoreBluetooth.
///
/// Use this to drive your production Bluetooth path against a real adapter,
/// then swap in `FakeBLEStack` (from ElmulatorBLETestSupport) to drive the
/// exact same code against a scripted scenario with no radio.
public func makeCoreBluetoothStack() -> any BLEStack {
    CoreBluetoothStack()
}

/// The real central-role BLE stack, wrapping CoreBluetooth. It confines all
/// CoreBluetooth access to a single serial queue and translates delegate
/// callbacks into BLEStackEvent values. It holds no orchestration logic:
/// the transport's state machine decides what to do next.
///
/// This type cannot be exercised without a Bluetooth radio, so it is kept
/// deliberately thin. Its orchestration is proven through the state machine
/// tests and the fake-stack integration test; a real handshake is verified
/// on a physical iPhone (Docs/testing/MACBOOK_ONLY_TESTING.md).
final class CoreBluetoothStack: NSObject, BLEStack, @unchecked Sendable {
    private let queue = DispatchQueue(label: "obd2.ble.central")
    private var central: CBCentralManager?
    private let continuation: AsyncStream<BLEStackEvent>.Continuation
    private let stream: AsyncStream<BLEStackEvent>

    private var discovered: [String: CBPeripheral] = [:]
    private var characteristics: [String: CBCharacteristic] = [:]

    override init() {
        var storedContinuation: AsyncStream<BLEStackEvent>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .unbounded) { storedContinuation = $0 }
        self.continuation = storedContinuation
        super.init()
        queue.async { [weak self] in
            guard let self else { return }
            self.central = CBCentralManager(delegate: self, queue: self.queue)
        }
    }

    func events() -> AsyncStream<BLEStackEvent> { stream }

    func scan(serviceUUIDs: [String]) async {
        queue.async { [weak self] in
            let uuids = serviceUUIDs.map { CBUUID(string: $0) }
            self?.central?.scanForPeripherals(withServices: uuids, options: nil)
        }
    }

    func stopScan() async {
        queue.async { [weak self] in self?.central?.stopScan() }
    }

    func connect(peripheralID: String) async {
        queue.async { [weak self] in
            guard let self, let peripheral = self.discovered[peripheralID] else { return }
            self.central?.connect(peripheral, options: nil)
        }
    }

    func discoverServices(_ serviceUUIDs: [String], peripheralID: String) async {
        queue.async { [weak self] in
            guard let peripheral = self?.discovered[peripheralID] else { return }
            peripheral.delegate = self
            peripheral.discoverServices(serviceUUIDs.map { CBUUID(string: $0) })
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, peripheralID: String) async {
        queue.async { [weak self] in
            guard let peripheral = self?.discovered[peripheralID],
                  let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUUID) }) else { return }
            peripheral.discoverCharacteristics(characteristicUUIDs.map { CBUUID(string: $0) }, for: service)
        }
    }

    func setNotify(_ enabled: Bool, characteristicUUID: String, serviceUUID: String, peripheralID: String) async {
        queue.async { [weak self] in
            guard let self,
                  let peripheral = self.discovered[peripheralID],
                  let characteristic = self.characteristics[Self.key(peripheralID, serviceUUID, characteristicUUID)] else { return }
            peripheral.setNotifyValue(enabled, for: characteristic)
        }
    }

    func write(_ data: Data, characteristicUUID: String, serviceUUID: String, peripheralID: String, withResponse: Bool) async {
        queue.async { [weak self] in
            guard let self,
                  let peripheral = self.discovered[peripheralID],
                  let characteristic = self.characteristics[Self.key(peripheralID, serviceUUID, characteristicUUID)] else { return }
            peripheral.writeValue(data, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)
        }
    }

    func cancel(peripheralID: String) async {
        queue.async { [weak self] in
            guard let self, let peripheral = self.discovered[peripheralID] else { return }
            self.central?.cancelPeripheralConnection(peripheral)
        }
    }

    func stop() async {
        queue.async { [weak self] in
            guard let self else { return }
            self.central?.stopScan()
            for peripheral in self.discovered.values {
                self.central?.cancelPeripheralConnection(peripheral)
            }
            self.continuation.finish()
        }
    }

    private static func key(_ peripheralID: String, _ serviceUUID: String, _ characteristicUUID: String) -> String {
        "\(peripheralID)|\(serviceUUID.uppercased())|\(characteristicUUID.uppercased())"
    }
}

extension CoreBluetoothStack: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: continuation.yield(.poweredOn)
        case .poweredOff: continuation.yield(.poweredOff)
        case .unauthorized: continuation.yield(.unauthorized)
        case .unsupported: continuation.yield(.unsupported)
        case .resetting, .unknown: break
        @unknown default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        discovered[id] = peripheral
        continuation.yield(.discovered(BLEDiscoveredPeripheral(id: id, name: peripheral.name)))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        continuation.yield(.connected(peripheralID: peripheral.identifier.uuidString))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        continuation.yield(.connectFailed(
            peripheralID: peripheral.identifier.uuidString,
            message: error?.localizedDescription ?? "unknown"
        ))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        continuation.yield(.disconnected(
            peripheralID: peripheral.identifier.uuidString,
            error: error?.localizedDescription
        ))
    }
}

extension CoreBluetoothStack: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        continuation.yield(.servicesDiscovered(
            peripheralID: peripheral.identifier.uuidString,
            serviceUUIDs: (peripheral.services ?? []).map { $0.uuid.uuidString },
            error: error?.localizedDescription
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        let peripheralID = peripheral.identifier.uuidString
        let serviceUUID = service.uuid.uuidString
        for characteristic in service.characteristics ?? [] {
            characteristics[Self.key(peripheralID, serviceUUID, characteristic.uuid.uuidString)] = characteristic
        }
        continuation.yield(.characteristicsDiscovered(
            peripheralID: peripheralID,
            serviceUUID: serviceUUID,
            characteristicUUIDs: (service.characteristics ?? []).map { $0.uuid.uuidString },
            error: error?.localizedDescription
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        continuation.yield(.notifyStateChanged(
            peripheralID: peripheral.identifier.uuidString,
            characteristicUUID: characteristic.uuid.uuidString,
            isNotifying: characteristic.isNotifying,
            error: error?.localizedDescription
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        continuation.yield(.notification(
            peripheralID: peripheral.identifier.uuidString,
            characteristicUUID: characteristic.uuid.uuidString,
            data: data
        ))
    }
}
