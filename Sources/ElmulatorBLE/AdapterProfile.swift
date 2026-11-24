import Foundation

/// One GATT characteristic in an adapter profile, described independently of
/// CoreBluetooth so the real peripheral host, the CoreBluetooth-Mock bridge,
/// and tests all agree on the layout.
public struct AdapterCharacteristic: Sendable, Equatable {
    /// Characteristic UUID.
    public let uuid: String
    /// Whether the adapter sends replies on this characteristic.
    public let notifies: Bool
    /// Whether the central may write commands with response.
    public let write: Bool
    /// Whether the central may write commands without response.
    public let writeWithoutResponse: Bool

    public init(uuid: String, notifies: Bool, write: Bool, writeWithoutResponse: Bool) {
        self.uuid = uuid
        self.notifies = notifies
        self.write = write
        self.writeWithoutResponse = writeWithoutResponse
    }

    /// True when this one characteristic carries both commands and replies.
    public var isShared: Bool {
        notifies && (write || writeWithoutResponse)
    }
}

/// The GATT profile the app expects an ELM-style BLE adapter to expose.
///
/// The defaults are a UART-style service used by many ELM327 clones. Clone
/// adapters vary, so every value is configurable; verify the defaults against
/// the real adapters you target before freezing them. The `elmulator-ble`
/// peripheral, the CoreBluetooth-Mock bridge, and the in-process `FakeCentral`
/// share this type so every side of a test agrees.
public struct AdapterProfile: Sendable, Equatable {
    /// Advertised service that carries the command and response
    /// characteristics.
    public let serviceUUID: String
    /// Characteristic the app writes commands to.
    public let writeCharacteristicUUID: String
    /// Characteristic the adapter notifies replies on.
    public let notifyCharacteristicUUID: String
    /// The write mode a client should prefer. The bundled hosts still accept
    /// both write modes, so a central that picks the other one keeps working.
    public let writeWithResponse: Bool
    /// The short local name to advertise. Kept short because advertising
    /// data is small (roughly 28 bytes in the foreground).
    public let advertisedName: String

    public init(
        serviceUUID: String,
        writeCharacteristicUUID: String,
        notifyCharacteristicUUID: String,
        writeWithResponse: Bool,
        advertisedName: String
    ) {
        self.serviceUUID = serviceUUID
        self.writeCharacteristicUUID = writeCharacteristicUUID
        self.notifyCharacteristicUUID = notifyCharacteristicUUID
        self.writeWithResponse = writeWithResponse
        self.advertisedName = advertisedName
    }

    /// True when commands and replies travel on the same characteristic.
    /// Short and full Bluetooth base UUID spellings identify the same characteristic.
    public var hasSharedCharacteristic: Bool {
        Self.canonicalUUID(writeCharacteristicUUID) == Self.canonicalUUID(notifyCharacteristicUUID)
    }

    static func canonicalUUID(_ spelling: String) -> String {
        let uuid = spelling.uppercased()
        if uuid.count == 4, UInt16(uuid, radix: 16) != nil { return "0000" + uuid }
        let baseSuffix = "-0000-1000-8000-00805F9B34FB"
        if uuid.count == 36, uuid.hasSuffix(baseSuffix), UInt32(uuid.prefix(8), radix: 16) != nil {
            return String(uuid.prefix(8))
        }
        return uuid
    }

    /// The characteristics this profile exposes, deduplicated when the write
    /// and notify UUIDs are the same. A shared layout has exactly one
    /// characteristic that both notifies and accepts writes; a split layout
    /// has a write-only characteristic followed by a notify-only one.
    public var characteristics: [AdapterCharacteristic] {
        let writeSide = AdapterCharacteristic(
            uuid: writeCharacteristicUUID,
            notifies: hasSharedCharacteristic,
            write: true,
            writeWithoutResponse: true
        )
        guard !hasSharedCharacteristic else { return [writeSide] }
        return [
            writeSide,
            AdapterCharacteristic(
                uuid: notifyCharacteristicUUID,
                notifies: true,
                write: false,
                writeWithoutResponse: false
            ),
        ]
    }

    /// A Nordic UART style profile. Common on ELM327 BLE clones, but not
    /// universal, so treat this as a starting point, not a guarantee.
    /// Verify against the real adapters at bring-up.
    public static let nordicUART = AdapterProfile(
        serviceUUID: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",
        writeCharacteristicUUID: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E",
        notifyCharacteristicUUID: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E",
        writeWithResponse: false,
        advertisedName: "FakeELM"
    )

    /// The conventional clone layout: service FFF0, replies on FFF1, commands
    /// on FFF2. Widely used by ELM327 BLE clones that follow the FFF0
    /// examples in hobbyist firmware.
    public static let conventionalFFF0 = AdapterProfile(
        serviceUUID: "FFF0",
        writeCharacteristicUUID: "FFF2",
        notifyCharacteristicUUID: "FFF1",
        writeWithResponse: false,
        advertisedName: "FakeELM"
    )

    /// The shared layout: service FFE0 with one FFE1 characteristic that both
    /// notifies replies and accepts commands.
    public static let sharedFFE0 = AdapterProfile(
        serviceUUID: "FFE0",
        writeCharacteristicUUID: "FFE1",
        notifyCharacteristicUUID: "FFE1",
        writeWithResponse: false,
        advertisedName: "FakeELM"
    )

    /// The 18F0 layout used by some ELM327 adapters: replies on 2AF0,
    /// commands on 2AF1.
    public static let eighteenF0 = AdapterProfile(
        serviceUUID: "18F0",
        writeCharacteristicUUID: "2AF1",
        notifyCharacteristicUUID: "2AF0",
        writeWithResponse: false,
        advertisedName: "FakeELM"
    )

    /// The profile the `elmulator-ble` executable advertises by default. Same
    /// UUIDs as `nordicUART`; named so tests and the tool reference one
    /// source of truth.
    public static let fakeELM = AdapterProfile.nordicUART

    /// Named presets accepted by `elmulator-ble --profile`. Keys are the
    /// lowercase names shown in `presetNames`.
    public static let presets: [String: AdapterProfile] = [
        "nordic": .nordicUART,
        "fff0": .conventionalFFF0,
        "ffe0": .sharedFFE0,
        "18f0": .eighteenF0,
    ]

    /// Preset names in documentation order.
    public static let presetNames = ["nordic", "fff0", "ffe0", "18f0"]

    /// Resolve a preset name case-insensitively, or `nil` when unknown.
    public static func preset(named name: String) -> AdapterProfile? {
        presets[name.lowercased()]
    }
}
