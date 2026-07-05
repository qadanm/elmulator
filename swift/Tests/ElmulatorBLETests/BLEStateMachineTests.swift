import ElmulatorBLE
import Foundation
import Testing

@Suite("BLE connection state machine")
struct BLEStateMachineTests {
    let profile = BLEAdapterProfile.fakeELM
    var peripheral: BLEDiscoveredPeripheral {
        BLEDiscoveredPeripheral(id: "PERIPH-1", name: "FakeELM")
    }

    /// Drives the machine through the full happy path and returns the
    /// actions emitted at each step for inspection.
    func driveToReady() -> (machine: BLEConnectionStateMachine, actions: [BLEConnectionAction]) {
        var machine = BLEConnectionStateMachine(profile: profile)
        var actions: [BLEConnectionAction] = []
        actions += machine.handle(.start)
        actions += machine.handle(.poweredOn)
        actions += machine.handle(.discovered(peripheral))
        actions += machine.handle(.connected(peripheralID: "PERIPH-1"))
        actions += machine.handle(.servicesDiscovered(peripheralID: "PERIPH-1", serviceUUIDs: [profile.serviceUUID], error: nil))
        actions += machine.handle(.characteristicsDiscovered(
            peripheralID: "PERIPH-1",
            serviceUUID: profile.serviceUUID,
            characteristicUUIDs: [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
            error: nil
        ))
        actions += machine.handle(.notifyStateChanged(
            peripheralID: "PERIPH-1",
            characteristicUUID: profile.notifyCharacteristicUUID,
            isNotifying: true,
            error: nil
        ))
        return (machine, actions)
    }

    @Test("happy path reaches ready with the expected action sequence")
    func happyPath() {
        let (machine, actions) = driveToReady()
        #expect(machine.state == .ready(peripheralID: "PERIPH-1"))
        #expect(machine.readyPeripheralID == "PERIPH-1")
        #expect(actions == [
            .scan(serviceUUIDs: [profile.serviceUUID]),
            .stopScan,
            .connect(peripheralID: "PERIPH-1"),
            .discoverServices([profile.serviceUUID], peripheralID: "PERIPH-1"),
            .discoverCharacteristics(
                [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
                serviceUUID: profile.serviceUUID,
                peripheralID: "PERIPH-1"
            ),
            .setNotify(true, characteristicUUID: profile.notifyCharacteristicUUID, serviceUUID: profile.serviceUUID, peripheralID: "PERIPH-1"),
            .becameReady(peripheralID: "PERIPH-1"),
        ])
    }

    @Test("UUID matching is case insensitive like CoreBluetooth")
    func caseInsensitiveUUIDs() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        _ = machine.handle(.discovered(peripheral))
        _ = machine.handle(.connected(peripheralID: "PERIPH-1"))
        let actions = machine.handle(.servicesDiscovered(
            peripheralID: "PERIPH-1",
            serviceUUIDs: [profile.serviceUUID.lowercased()],
            error: nil
        ))
        #expect(machine.state == .discoveringCharacteristics(peripheralID: "PERIPH-1"))
        #expect(actions.contains(.discoverCharacteristics(
            [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
            serviceUUID: profile.serviceUUID,
            peripheralID: "PERIPH-1"
        )))
    }

    @Test("peripheral match filters by name")
    func peripheralMatch() {
        var machine = BLEConnectionStateMachine(profile: profile, peripheralMatch: "OBDII")
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        let ignored = machine.handle(.discovered(BLEDiscoveredPeripheral(id: "OTHER", name: "SomethingElse")))
        #expect(ignored.isEmpty)
        #expect(machine.state == .scanning)
        let matched = machine.handle(.discovered(BLEDiscoveredPeripheral(id: "TARGET", name: "Vgate OBDII BLE")))
        #expect(machine.state == .connecting(peripheralID: "TARGET"))
        #expect(matched.contains(.connect(peripheralID: "TARGET")))
    }

    @Test("powered off before ready fails typed")
    func poweredOffDuringSetup() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        let actions = machine.handle(.poweredOff)
        #expect(machine.state == .failed)
        #expect(actions == [.fail(.connectionLost("Bluetooth powered off"))])
    }

    @Test("unauthorized fails typed")
    func unauthorized() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        let actions = machine.handle(.unauthorized)
        #expect(machine.state == .failed)
        #expect(actions == [.fail(.connectFailed("Bluetooth access not authorized"))])
    }

    @Test("missing service fails typed")
    func missingService() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        _ = machine.handle(.discovered(peripheral))
        _ = machine.handle(.connected(peripheralID: "PERIPH-1"))
        let actions = machine.handle(.servicesDiscovered(peripheralID: "PERIPH-1", serviceUUIDs: ["180A"], error: nil))
        #expect(machine.state == .failed)
        #expect(actions == [.fail(.connectFailed("adapter did not expose the expected service"))])
    }

    @Test("missing notify characteristic fails typed")
    func missingCharacteristic() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        _ = machine.handle(.discovered(peripheral))
        _ = machine.handle(.connected(peripheralID: "PERIPH-1"))
        _ = machine.handle(.servicesDiscovered(peripheralID: "PERIPH-1", serviceUUIDs: [profile.serviceUUID], error: nil))
        let actions = machine.handle(.characteristicsDiscovered(
            peripheralID: "PERIPH-1",
            serviceUUID: profile.serviceUUID,
            characteristicUUIDs: [profile.writeCharacteristicUUID],
            error: nil
        ))
        #expect(machine.state == .failed)
        #expect(actions == [.fail(.connectFailed("adapter is missing the write or notify characteristic"))])
    }

    @Test("connect failure fails typed")
    func connectFailure() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        _ = machine.handle(.discovered(peripheral))
        let actions = machine.handle(.connectFailed(peripheralID: "PERIPH-1", message: "peer removed"))
        #expect(machine.state == .failed)
        #expect(actions == [.fail(.connectFailed("connect failed: peer removed"))])
    }

    @Test("disconnect after ready reports a lost connection")
    func disconnectAfterReady() {
        var (machine, _) = driveToReady()
        let actions = machine.handle(.disconnected(peripheralID: "PERIPH-1", error: "link supervision timeout"))
        #expect(machine.state == .failed)
        #expect(actions == [.fail(.connectionLost("link supervision timeout"))])
    }

    @Test("timeout before ready fails typed, after ready is ignored")
    func timeout() {
        var connecting = BLEConnectionStateMachine(profile: profile)
        _ = connecting.handle(.start)
        _ = connecting.handle(.poweredOn)
        let actions = connecting.handle(.timedOut)
        #expect(connecting.state == .failed)
        #expect(actions == [.fail(.connectFailed("connect timed out"))])

        var (ready, _) = driveToReady()
        #expect(ready.handle(.timedOut).isEmpty)
        #expect(ready.state == .ready(peripheralID: "PERIPH-1"))
    }

    @Test("events after failure are inert")
    func inertAfterFailure() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.unauthorized)
        #expect(machine.handle(.poweredOn).isEmpty)
        #expect(machine.handle(.discovered(peripheral)).isEmpty)
        #expect(machine.state == .failed)
    }

    @Test("a stray disconnect for another peripheral is ignored during scan")
    func strayDisconnect() {
        var machine = BLEConnectionStateMachine(profile: profile)
        _ = machine.handle(.start)
        _ = machine.handle(.poweredOn)
        #expect(machine.handle(.disconnected(peripheralID: "SOMEONE-ELSE", error: nil)).isEmpty)
        #expect(machine.state == .scanning)
    }
}
