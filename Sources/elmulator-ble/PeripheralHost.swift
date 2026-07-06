import CoreBluetooth
import Elmulator
import ElmulatorBLE
import Foundation

/// Hosts a FakeELM scenario as a BLE peripheral using CBPeripheralManager.
///
/// It reuses ScenarioEngine verbatim, so its matching, echo, default,
/// stall, and disconnect behavior is identical to the TCP servers. This tool
/// adds a BLE transport and nothing else. All scenario data comes from
/// Fixtures/sim_scenarios; no external emulator dictionaries are used.
final class PeripheralHost: NSObject, @unchecked Sendable {
    struct Options {
        var profile: AdapterProfile
        var chunkSize: Int
        var configuration: EngineConfiguration
        var disconnectAfter: Int?
    }

    private let scenario: Scenario
    private let options: Options
    private let queue = DispatchQueue(label: "obd2.fakeelm.peripheral")

    private var manager: CBPeripheralManager?
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var engine: ScenarioEngine
    private var inboundBuffer = ""
    private var outbound: [Data] = []
    private var commandCount = 0
    private var disconnected = false

    init(scenario: Scenario, options: Options) {
        self.scenario = scenario
        self.options = options
        self.engine = ScenarioEngine(scenario: scenario, configuration: options.configuration)
        super.init()
    }

    func start() {
        manager = CBPeripheralManager(delegate: self, queue: queue)
        log("scenario \(scenario.scenarioID), advertising \(options.profile.advertisedName)")
    }

    // MARK: - Command handling

    /// Accumulates written bytes and processes each CR or LF terminated
    /// command. One write is never assumed to be one command.
    private func ingest(_ data: Data) {
        inboundBuffer += String(decoding: data, as: UTF8.self)
        while let line = takeLine() {
            guard !line.isEmpty else { continue }
            handleCommand(line)
        }
    }

    private func takeLine() -> String? {
        guard let index = inboundBuffer.firstIndex(where: { $0 == "\r" || $0 == "\n" }) else {
            return nil
        }
        let line = String(inboundBuffer[inboundBuffer.startIndex..<index])
        inboundBuffer = String(inboundBuffer[inboundBuffer.index(after: index)...])
        return line.trimmingCharacters(in: .whitespaces)
    }

    private func handleCommand(_ command: String) {
        guard !disconnected else { return }
        commandCount += 1
        let plan = engine.plan(for: command)
        let source = plan.matchedRequest == nil ? "default" : "scenario"

        if plan.pieces.isEmpty, plan.postAction == .stall {
            log("\(command) -> stall (no reply)")
            return
        }

        var pending: [(bytes: [UInt8], delayMS: Int)] = []
        for piece in plan.pieces {
            let chunks = Self.chunk(piece.bytes, size: options.chunkSize)
            for (index, chunk) in chunks.enumerated() {
                pending.append((chunk, index == 0 ? piece.delayMS : 0))
            }
        }
        log("\(command) -> \(plan.pieces.reduce(0) { $0 + $1.bytes.count }) bytes in \(pending.count) notification(s) (\(source))")

        let shouldDisconnect = plan.postAction == .disconnect
            || (options.disconnectAfter.map { commandCount >= $0 } ?? false)
        schedule(pending, index: 0, thenDisconnect: shouldDisconnect)
    }

    /// Sends pieces in order, honoring per-piece delay, then optionally
    /// tears the service down so the central sees a disconnect.
    private func schedule(_ pieces: [(bytes: [UInt8], delayMS: Int)], index: Int, thenDisconnect: Bool) {
        guard index < pieces.count else {
            if thenDisconnect { performDisconnect() }
            return
        }
        let piece = pieces[index]
        let send = { [weak self] in
            guard let self else { return }
            self.enqueueNotification(Data(piece.bytes))
            self.schedule(pieces, index: index + 1, thenDisconnect: thenDisconnect)
        }
        if piece.delayMS > 0 {
            queue.asyncAfter(deadline: .now() + .milliseconds(piece.delayMS), execute: send)
        } else {
            queue.async(execute: send)
        }
    }

    // MARK: - Notification backpressure

    private func enqueueNotification(_ data: Data) {
        outbound.append(data)
        flushOutbound()
    }

    private func flushOutbound() {
        guard let manager, let characteristic = notifyCharacteristic else { return }
        while let next = outbound.first {
            // updateValue returns false when the transmit queue is full;
            // peripheralManagerIsReady will call back when there is room.
            if manager.updateValue(next, for: characteristic, onSubscribedCentrals: nil) {
                outbound.removeFirst()
            } else {
                break
            }
        }
    }

    private func performDisconnect() {
        guard !disconnected else { return }
        disconnected = true
        log("disconnect (scenario or --disconnect-after): removing service and stopping advertising")
        manager?.stopAdvertising()
        manager?.removeAllServices()
    }

    // MARK: - Helpers

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

    func log(_ message: String) {
        FileHandle.standardError.write(Data("[fake_elm_ble] \(message)\n".utf8))
    }
}

extension PeripheralHost: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            publishService(peripheral)
        case .poweredOff:
            log("Bluetooth is powered off. Turn it on to advertise.")
        case .unauthorized:
            log("Bluetooth access is not authorized for this process. Grant it in System Settings, Privacy and Security, Bluetooth.")
        case .unsupported:
            log("Bluetooth Low Energy is not available on this machine.")
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    private func publishService(_ peripheral: CBPeripheralManager) {
        let writeCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: options.profile.writeCharacteristicUUID),
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let notify = CBMutableCharacteristic(
            type: CBUUID(string: options.profile.notifyCharacteristicUUID),
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        self.notifyCharacteristic = notify

        let service = CBMutableService(type: CBUUID(string: options.profile.serviceUUID), primary: true)
        service.characteristics = [writeCharacteristic, notify]
        peripheral.add(service)

        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: options.profile.advertisedName,
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: options.profile.serviceUUID)],
        ])
        log("ready: advertising service \(options.profile.serviceUUID)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                ingest(value)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        log("central subscribed (max notify \(central.maximumUpdateValueLength) bytes)")
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushOutbound()
    }
}
