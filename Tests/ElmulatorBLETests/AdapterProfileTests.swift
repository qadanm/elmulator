import ElmulatorBLE
import Testing

@Suite("Adapter profile presets")
struct AdapterProfileTests {
    @Test("Nordic UART stays the default")
    func nordicDefault() {
        #expect(AdapterProfile.fakeELM == AdapterProfile.nordicUART)
        #expect(AdapterProfile.nordicUART.serviceUUID == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(AdapterProfile.nordicUART.writeCharacteristicUUID == "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(AdapterProfile.nordicUART.notifyCharacteristicUUID == "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(AdapterProfile.nordicUART.writeWithResponse == false)
        #expect(AdapterProfile.nordicUART.hasSharedCharacteristic == false)
        #expect(AdapterProfile.nordicUART.characteristics.map(\.uuid) == [
            AdapterProfile.nordicUART.writeCharacteristicUUID,
            AdapterProfile.nordicUART.notifyCharacteristicUUID,
        ])
    }

    @Test("conventional FFF0 uses FFF1 for replies and FFF2 for commands")
    func conventionalFFF0() {
        let profile = AdapterProfile.conventionalFFF0
        #expect(profile.serviceUUID == "FFF0")
        #expect(profile.notifyCharacteristicUUID == "FFF1")
        #expect(profile.writeCharacteristicUUID == "FFF2")
        #expect(profile.hasSharedCharacteristic == false)
        #expect(profile.characteristics == [
            AdapterCharacteristic(uuid: "FFF2", notifies: false, write: true, writeWithoutResponse: true),
            AdapterCharacteristic(uuid: "FFF1", notifies: true, write: false, writeWithoutResponse: false),
        ])
    }

    @Test("shared FFE0 exposes exactly one notify/write characteristic")
    func sharedFFE0() {
        let profile = AdapterProfile.sharedFFE0
        #expect(profile.serviceUUID == "FFE0")
        #expect(profile.writeCharacteristicUUID == "FFE1")
        #expect(profile.notifyCharacteristicUUID == "FFE1")
        #expect(profile.hasSharedCharacteristic)
        #expect(profile.characteristics == [
            AdapterCharacteristic(uuid: "FFE1", notifies: true, write: true, writeWithoutResponse: true),
        ])
        #expect(profile.characteristics.filter(\.isShared).count == 1)
    }

    @Test("18F0 uses 2AF0 for replies and 2AF1 for commands")
    func eighteenF0() {
        let profile = AdapterProfile.eighteenF0
        #expect(profile.serviceUUID == "18F0")
        #expect(profile.notifyCharacteristicUUID == "2AF0")
        #expect(profile.writeCharacteristicUUID == "2AF1")
        #expect(profile.hasSharedCharacteristic == false)
        #expect(profile.characteristics.map(\.uuid) == ["2AF1", "2AF0"])
    }

    @Test("preset lookup is case-insensitive and rejects unknown names")
    func presetLookup() {
        #expect(AdapterProfile.preset(named: "nordic") == .nordicUART)
        #expect(AdapterProfile.preset(named: "NORDIC") == .nordicUART)
        #expect(AdapterProfile.preset(named: "fff0") == .conventionalFFF0)
        #expect(AdapterProfile.preset(named: "FFE0") == .sharedFFE0)
        #expect(AdapterProfile.preset(named: "18F0") == .eighteenF0)
        #expect(AdapterProfile.preset(named: "uart") == nil)
        #expect(AdapterProfile.presetNames == ["nordic", "fff0", "ffe0", "18f0"])
    }

    @Test("overriding one UUID keeps the layout coherent")
    func partialOverride() {
        let base = AdapterProfile.sharedFFE0
        let overridden = AdapterProfile(
            serviceUUID: "FFF0",
            writeCharacteristicUUID: base.writeCharacteristicUUID,
            notifyCharacteristicUUID: base.notifyCharacteristicUUID,
            writeWithResponse: true,
            advertisedName: "SyntheticELM"
        )
        #expect(overridden.characteristics == base.characteristics)
        #expect(overridden.writeWithResponse)

        // UUID comparison ignores case, matching CoreBluetooth's normalization.
        let mixedCase = AdapterProfile(
            serviceUUID: "FFE0",
            writeCharacteristicUUID: "ffe1",
            notifyCharacteristicUUID: "FFE1",
            writeWithResponse: false,
            advertisedName: "SyntheticELM"
        )
        #expect(mixedCase.hasSharedCharacteristic)
        #expect(mixedCase.characteristics.count == 1)
    }
}
