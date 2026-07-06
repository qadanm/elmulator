import Foundation

/// The GATT profile the app expects an ELM-style BLE adapter to expose.
///
/// The defaults are a UART-style service used by many ELM327 clones. Clone
/// adapters vary, so every value is configurable, and the defaults are to
/// be verified against the real adapters on hand before they are frozen
/// (Docs/testing/FAKE_BLE_PERIPHERAL.md). The FakeELMBLEPeripheral tool and
/// BLETransportClient share this type so both sides of a test agree.
public struct AdapterProfile: Sendable, Equatable {
    /// Advertised service that carries the command and response
    /// characteristics.
    public let serviceUUID: String
    /// Characteristic the app writes commands to.
    public let writeCharacteristicUUID: String
    /// Characteristic the adapter notifies replies on.
    public let notifyCharacteristicUUID: String
    /// Whether writes use write-with-response. Many clones want
    /// write-without-response on the command characteristic.
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

    /// The profile the FakeELMBLEPeripheral tool advertises by default. Same
    /// UUIDs as `nordicUART`; named so tests and the tool reference one
    /// source of truth.
    public static let fakeELM = AdapterProfile.nordicUART
}
