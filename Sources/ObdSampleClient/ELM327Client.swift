import CoreBluetoothMock
import Foundation

/// A small, realistic ELM327 BLE client: the kind of code a real OBD2 app
/// has in its Bluetooth layer.
///
/// It is written entirely against CoreBluetooth-Mock's `CBM*` types. On a real
/// device those forward to the system CoreBluetooth; on the Simulator or in CI
/// (with `forceMock: true`) they run against a mock peripheral. **This file has
/// no dependency on elmulator.** That only appears in the test target, which
/// scripts the adapter's behavior. That separation is the whole point: your
/// production Bluetooth code stays pure, and the test injects the fake.
///
/// > In a shipping app you would typically `import CoreBluetoothMock` and add
/// > `typealias CBCentralManager = CBMCentralManager` (etc.) behind `#if DEBUG`
/// > so release builds use the system framework verbatim. Here we use the
/// > `CBM*` names directly to keep the example explicit.
///
/// Create this sample on the main queue. CoreBluetooth interaction and continuation
/// state stay there: the pinned mock also delivers discovery from its main-runloop
/// timer. Await disconnect before tearing down the shared simulation.
public final class ELM327Client: NSObject, @unchecked Sendable {
    public enum ClientError: Error, Equatable {
        case bluetoothUnavailable
        case timeout(String)
        case disconnected
        case notReady
    }

    // Nordic UART: the common ELM327 BLE clone profile.
    private let serviceUUID = CBMUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let writeUUID = CBMUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let notifyUUID = CBMUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private let queue = DispatchQueue.main
    private var central: CBMCentralManager!
    private var peripheral: CBMPeripheral?
    private var writeCharacteristic: CBMCharacteristic?

    // One in-flight operation at a time (an ELM327 speaks one command at a time).
    private var connect: Pending<Void>?
    private var response: Pending<String>?
    private var disconnection: Pending<Void>?
    private var closing = false
    private var invalidated = false
    private var responseBuffer = ""

    public init(forceMock: Bool = false) {
        super.init()
        dispatchPrecondition(condition: .onQueue(.main))
        central = CBMCentralManagerFactory.instance(delegate: self, queue: queue, forceMock: forceMock)
    }

    /// Powers on, scans for the adapter, connects, discovers the service and
    /// characteristics, and subscribes to notifications.
    public func connect(timeout: TimeInterval = 5) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                guard !self.invalidated else {
                    cont.resume(throwing: ClientError.notReady); return
                }
                self.closing = false
                self.connect = Pending(cont, queue: self.queue, timeout: timeout,
                                       error: ClientError.timeout("connect")) { self.connect = nil }
                if self.central.state == .poweredOn {
                    self.central.scanForPeripherals(withServices: [self.serviceUUID])
                }
                // Otherwise centralManagerDidUpdateState starts the scan.
            }
        }
    }

    /// Sends one command (a `\r` is appended) and returns the reply text up to
    /// and including the ELM prompt `>`.
    public func send(_ command: String, timeout: TimeInterval = 5) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                guard !self.closing, let peripheral = self.peripheral, let write = self.writeCharacteristic else {
                    cont.resume(throwing: ClientError.notReady); return
                }
                self.responseBuffer = ""
                self.response = Pending(cont, queue: self.queue, timeout: timeout,
                                        error: ClientError.timeout("command \(command)")) { self.response = nil }
                peripheral.writeValue(Data((command + "\r").utf8), for: write, type: .withoutResponse)
            }
        }
    }

    /// Completes after the delegate confirms disconnection, not merely after
    /// enqueueing cancellation. The timeout is a failure, never teardown success.
    public func disconnect(timeout: TimeInterval = 5) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.disconnection == nil else {
                    cont.resume(throwing: ClientError.notReady); return
                }
                self.closing = true
                if self.central.state == .poweredOn { self.central.stopScan() }
                self.connect?.resume(.failure(ClientError.disconnected))
                self.response?.resume(.failure(ClientError.disconnected))
                guard let peripheral = self.peripheral, peripheral.state != .disconnected else {
                    self.peripheral = nil
                    self.writeCharacteristic = nil
                    cont.resume(); return
                }
                self.disconnection = Pending(cont, queue: self.queue, timeout: timeout,
                    error: ClientError.timeout("disconnect")) { self.disconnection = nil }
                self.central.cancelPeripheralConnection(peripheral)
            }
        }
    }

    /// Terminally detach a test client before resetting shared mock state.
    /// This also supports forced cleanup after a reported disconnect timeout;
    /// it does not turn that timeout into a confirmed disconnection.
    public func invalidate() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.invalidated = true
                self.closing = true
                if self.central.state == .poweredOn { self.central.stopScan() }
                self.central.delegate = nil
                self.peripheral?.delegate = nil
                self.connect?.resume(.failure(ClientError.disconnected))
                self.response?.resume(.failure(ClientError.disconnected))
                self.disconnection?.resume(.failure(ClientError.disconnected))
                self.peripheral = nil
                self.writeCharacteristic = nil
                continuation.resume()
            }
        }
    }
}

/// A checked continuation paired with a timeout, guaranteed to resume exactly
/// once. All methods run on the owning serial queue.
private final class Pending<T: Sendable> {
    private var cont: CheckedContinuation<T, Error>?
    private var timeout: DispatchWorkItem?
    private let clear: () -> Void

    init(_ cont: CheckedContinuation<T, Error>, queue: DispatchQueue,
         timeout seconds: TimeInterval, error: Error, clear: @escaping () -> Void) {
        self.cont = cont
        self.clear = clear
        let item = DispatchWorkItem { [weak self] in self?.resume(.failure(error)) }
        self.timeout = item
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func resume(_ result: Result<T, Error>) {
        guard let cont else { return }
        self.cont = nil
        timeout?.cancel(); timeout = nil
        clear()
        switch result {
        case .success(let value): cont.resume(returning: value)
        case .failure(let error): cont.resume(throwing: error)
        }
    }
}

extension ELM327Client: CBMCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBMCentralManager) {
        switch central.state {
        case .poweredOn:
            if connect != nil { central.scanForPeripherals(withServices: [serviceUUID]) }
        case .poweredOff, .unauthorized, .unsupported:
            connect?.resume(.failure(ClientError.bluetoothUnavailable))
        default:
            break
        }
    }

    public func centralManager(_ central: CBMCentralManager, didDiscover peripheral: CBMPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !closing, connect != nil, self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    public func centralManager(_ central: CBMCentralManager, didConnect peripheral: CBMPeripheral) {
        guard !closing else { return }
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBMCentralManager, didFailToConnect peripheral: CBMPeripheral, error: Error?) {
        connect?.resume(.failure(error ?? ClientError.disconnected))
    }

    public func centralManager(_ central: CBMCentralManager, didDisconnectPeripheral peripheral: CBMPeripheral, error: Error?) {
        connect?.resume(.failure(ClientError.disconnected))
        response?.resume(.failure(ClientError.disconnected))
        self.peripheral?.delegate = nil
        self.peripheral = nil
        writeCharacteristic = nil
        disconnection?.resume(.success(()))
    }
}

extension ELM327Client: CBMPeripheralDelegate {
    public func peripheral(_ peripheral: CBMPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            connect?.resume(.failure(ClientError.notReady)); return
        }
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }

    public func peripheral(_ peripheral: CBMPeripheral, didDiscoverCharacteristicsFor service: CBMService, error: Error?) {
        let chars = service.characteristics ?? []
        writeCharacteristic = chars.first { $0.uuid == writeUUID }
        guard let notify = chars.first(where: { $0.uuid == notifyUUID }), writeCharacteristic != nil else {
            connect?.resume(.failure(ClientError.notReady)); return
        }
        peripheral.setNotifyValue(true, for: notify)
    }

    public func peripheral(_ peripheral: CBMPeripheral, didUpdateNotificationStateFor characteristic: CBMCharacteristic, error: Error?) {
        if characteristic.uuid == notifyUUID { connect?.resume(.success(())) }
    }

    public func peripheral(_ peripheral: CBMPeripheral, didUpdateValueFor characteristic: CBMCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyUUID, let data = characteristic.value else { return }
        responseBuffer += String(decoding: data, as: UTF8.self)
        if responseBuffer.contains(">") { response?.resume(.success(responseBuffer)) }
    }
}
