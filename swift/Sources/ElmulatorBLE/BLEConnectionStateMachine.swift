import Foundation

/// A peripheral the central found while scanning.
public struct BLEDiscoveredPeripheral: Sendable, Equatable {
    public let id: String
    public let name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }
}

/// Inputs to the connection state machine. These mirror the CoreBluetooth
/// callbacks the BLEStack reports, plus a `start` kick and a `timedOut`
/// signal the transport raises on its own deadline.
public enum BLEConnectionEvent: Sendable, Equatable {
    case start
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
    case disconnected(peripheralID: String, error: String?)
    case timedOut
}

/// Side effects the machine asks the transport to perform. Pure data, so
/// the whole sequencing is testable without CoreBluetooth.
public enum BLEConnectionAction: Sendable, Equatable {
    case scan(serviceUUIDs: [String])
    case stopScan
    case connect(peripheralID: String)
    case discoverServices([String], peripheralID: String)
    case discoverCharacteristics([String], serviceUUID: String, peripheralID: String)
    case setNotify(Bool, characteristicUUID: String, serviceUUID: String, peripheralID: String)
    case becameReady(peripheralID: String)
    case fail(BLETransportError)
}

/// Drives one adapter connection from power-on through ready, in the fixed
/// CoreBluetooth order: power on, scan, connect, discover services,
/// discover characteristics, subscribe, ready. Case insensitive on UUIDs
/// because CoreBluetooth normalizes 16-bit UUIDs to uppercase 128-bit form.
///
/// The machine is pure: `handle` returns the actions to run and mutates
/// only its own state. The transport owns all I/O and timers.
public struct BLEConnectionStateMachine: Sendable {
    public enum State: Sendable, Equatable {
        case idle
        case waitingForPowerOn
        case scanning
        case connecting(peripheralID: String)
        case discoveringServices(peripheralID: String)
        case discoveringCharacteristics(peripheralID: String)
        case subscribing(peripheralID: String)
        case ready(peripheralID: String)
        case failed
    }

    public private(set) var state: State = .idle
    private let profile: BLEAdapterProfile
    /// When set, only connect to a peripheral whose id or name matches.
    private let peripheralMatch: String?

    public init(profile: BLEAdapterProfile, peripheralMatch: String? = nil) {
        self.profile = profile
        self.peripheralMatch = peripheralMatch
    }

    private func matches(_ peripheral: BLEDiscoveredPeripheral) -> Bool {
        guard let peripheralMatch, !peripheralMatch.isEmpty else { return true }
        if peripheral.id.caseInsensitiveCompare(peripheralMatch) == .orderedSame { return true }
        if let name = peripheral.name, name.localizedCaseInsensitiveContains(peripheralMatch) { return true }
        return false
    }

    private static func sameUUID(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    public mutating func handle(_ event: BLEConnectionEvent) -> [BLEConnectionAction] {
        switch (state, event) {
        case (.idle, .start):
            state = .waitingForPowerOn
            return []

        case (_, .poweredOff):
            // A drop after ready is a lost connection; before ready it is a
            // failed connect. Either way the scan cannot continue.
            state = .failed
            return [.fail(.connectionLost("Bluetooth powered off"))]

        case (_, .unauthorized):
            state = .failed
            return [.fail(.connectFailed("Bluetooth access not authorized"))]

        case (_, .unsupported):
            state = .failed
            return [.fail(.connectFailed("Bluetooth Low Energy not available"))]

        case (.waitingForPowerOn, .poweredOn):
            state = .scanning
            return [.scan(serviceUUIDs: [profile.serviceUUID])]

        case let (.scanning, .discovered(peripheral)) where matches(peripheral):
            state = .connecting(peripheralID: peripheral.id)
            return [.stopScan, .connect(peripheralID: peripheral.id)]

        case (.scanning, .discovered):
            return []

        case let (.connecting(expected), .connected(peripheralID)) where expected == peripheralID:
            state = .discoveringServices(peripheralID: peripheralID)
            return [.discoverServices([profile.serviceUUID], peripheralID: peripheralID)]

        case let (.connecting(expected), .connectFailed(peripheralID, message)) where expected == peripheralID:
            state = .failed
            return [.fail(.connectFailed("connect failed: \(message)"))]

        case let (.discoveringServices(expected), .servicesDiscovered(peripheralID, serviceUUIDs, error)) where expected == peripheralID:
            if let error {
                state = .failed
                return [.fail(.connectFailed("service discovery failed: \(error)"))]
            }
            guard serviceUUIDs.contains(where: { Self.sameUUID($0, profile.serviceUUID) }) else {
                state = .failed
                return [.fail(.connectFailed("adapter did not expose the expected service"))]
            }
            state = .discoveringCharacteristics(peripheralID: peripheralID)
            return [.discoverCharacteristics(
                [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
                serviceUUID: profile.serviceUUID,
                peripheralID: peripheralID
            )]

        case let (.discoveringCharacteristics(expected), .characteristicsDiscovered(peripheralID, serviceUUID, characteristicUUIDs, error)) where expected == peripheralID && Self.sameUUID(serviceUUID, profile.serviceUUID):
            if let error {
                state = .failed
                return [.fail(.connectFailed("characteristic discovery failed: \(error)"))]
            }
            let hasWrite = characteristicUUIDs.contains { Self.sameUUID($0, profile.writeCharacteristicUUID) }
            let hasNotify = characteristicUUIDs.contains { Self.sameUUID($0, profile.notifyCharacteristicUUID) }
            guard hasWrite, hasNotify else {
                state = .failed
                return [.fail(.connectFailed("adapter is missing the write or notify characteristic"))]
            }
            state = .subscribing(peripheralID: peripheralID)
            return [.setNotify(
                true,
                characteristicUUID: profile.notifyCharacteristicUUID,
                serviceUUID: profile.serviceUUID,
                peripheralID: peripheralID
            )]

        case let (.subscribing(expected), .notifyStateChanged(peripheralID, characteristicUUID, isNotifying, error)) where expected == peripheralID && Self.sameUUID(characteristicUUID, profile.notifyCharacteristicUUID):
            if let error {
                state = .failed
                return [.fail(.connectFailed("subscribe failed: \(error)"))]
            }
            guard isNotifying else {
                state = .failed
                return [.fail(.connectFailed("adapter did not enable notifications"))]
            }
            state = .ready(peripheralID: peripheralID)
            return [.becameReady(peripheralID: peripheralID)]

        case let (.ready(expected), .disconnected(peripheralID, error)) where expected == peripheralID:
            state = .failed
            return [.fail(.connectionLost(error ?? "adapter disconnected"))]

        case let (_, .disconnected(peripheralID, error)):
            // A disconnect during setup for the peripheral we were pursuing.
            if isPursuing(peripheralID) {
                state = .failed
                return [.fail(.connectionLost(error ?? "adapter disconnected during setup"))]
            }
            return []

        case (.ready, .timedOut):
            return []

        case (.failed, _):
            return []

        case (_, .timedOut):
            state = .failed
            return [.fail(.connectFailed("connect timed out"))]

        default:
            return []
        }
    }

    private func isPursuing(_ peripheralID: String) -> Bool {
        switch state {
        case let .connecting(id), let .discoveringServices(id),
             let .discoveringCharacteristics(id), let .subscribing(id),
             let .ready(id):
            return id == peripheralID
        case .idle, .waitingForPowerOn, .scanning, .failed:
            return false
        }
    }

    public var readyPeripheralID: String? {
        if case let .ready(id) = state { return id }
        return nil
    }
}
