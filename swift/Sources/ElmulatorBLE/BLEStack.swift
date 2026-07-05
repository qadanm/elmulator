import Foundation

/// Events a BLE central stack reports. These map onto the connection state
/// machine's events, plus incoming notifications. Defining them as plain
/// data is what lets BLETransportClient be tested without a radio: a fake
/// stack emits the same events a real CoreBluetooth central would.
public enum BLEStackEvent: Sendable {
    case poweredOn
    case poweredOff
    case unauthorized
    case unsupported
    case discovered(BLEDiscoveredPeripheral)
    case connected(peripheralID: String)
    case connectFailed(peripheralID: String, message: String)
    case servicesDiscovered(peripheralID: String, serviceUUIDs: [String], error: String?)
    case characteristicsDiscovered(peripheralID: String, serviceUUID: String, characteristicUUIDs: [String], error: String?)
    case notifyStateChanged(peripheralID: String, characteristicUUID: String, isNotifying: Bool, error: String?)
    case notification(peripheralID: String, characteristicUUID: String, data: Data)
    case disconnected(peripheralID: String, error: String?)
}

/// A central-role BLE stack: scan, connect, discover, subscribe, write.
/// The real implementation wraps CoreBluetooth (CoreBluetoothStack); the
/// test implementation drives a FakeELM peripheral in-process. Events are
/// delivered in order through a single AsyncStream so the transport
/// processes them exactly as CoreBluetooth reported them.
public protocol BLEStack: Sendable {
    func events() -> AsyncStream<BLEStackEvent>
    func scan(serviceUUIDs: [String]) async
    func stopScan() async
    func connect(peripheralID: String) async
    func discoverServices(_ serviceUUIDs: [String], peripheralID: String) async
    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, peripheralID: String) async
    func setNotify(_ enabled: Bool, characteristicUUID: String, serviceUUID: String, peripheralID: String) async
    func write(_ data: Data, characteristicUUID: String, serviceUUID: String, peripheralID: String, withResponse: Bool) async
    func cancel(peripheralID: String) async
    /// Tear the stack down: stop scanning, drop the peripheral, end events.
    func stop() async
}
