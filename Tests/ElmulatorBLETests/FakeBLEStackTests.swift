import Elmulator
import ElmulatorBLE
import ElmulatorBLETestSupport
import Foundation
import Testing

/// Locate the repo's `scenarios/` directory relative to this source file.
private func scenarioURL(_ name: String) -> URL {
    URL(filePath: #filePath)            // .../Tests/ElmulatorBLETests/FakeCentralTests.swift
        .deletingLastPathComponent()    // ElmulatorBLETests
        .deletingLastPathComponent()    // Tests
        .deletingLastPathComponent()    // repo root
        .appending(path: "scenarios")
        .appending(path: "\(name).scenario.json")
}

/// Collects notification payloads from the stack until it sees the ELM prompt
/// (`>`) or the stream ends, reassembling MTU-sized chunks the way a real
/// client's response assembler would.
private func drainReply(_ stack: FakeCentral, profile: AdapterProfile) async -> String {
    var assembled = ""
    for await event in stack.events() {
        if case let .notification(_, _, data) = event {
            assembled += String(decoding: data, as: UTF8.self)
            if assembled.contains(">") { break }
        }
        if case .disconnected = event { break }
    }
    return assembled
}

@Suite("FakeCentral in-process central")
struct FakeCentralTests {
    let profile = AdapterProfile.fakeELM

    @Test("emits the CoreBluetooth event sequence up to notify-ready")
    func handshakeSequence() async throws {
        let scenario = try Scenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeCentral(scenario: scenario)
        defer { Task { await stack.stop() } }

        let collector = Task { () -> [String] in
            var events: [String] = []
            for await event in stack.events() {
                switch event {
                case .poweredOn: events.append("poweredOn")
                case .discovered: events.append("discovered")
                case .connected: events.append("connected")
                case .servicesDiscovered: events.append("servicesDiscovered")
                case .characteristicsDiscovered: events.append("characteristicsDiscovered")
                case .notifyStateChanged: events.append("notify")
                default: break
                }
                if events.last == "notify" { break }
            }
            return events
        }

        await stack.scan(serviceUUIDs: [profile.serviceUUID])
        await stack.connect(peripheralID: "FAKE-BLE-PERIPHERAL")
        await stack.discoverServices([profile.serviceUUID], peripheralID: "FAKE-BLE-PERIPHERAL")
        await stack.discoverCharacteristics(
            [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
            serviceUUID: profile.serviceUUID,
            peripheralID: "FAKE-BLE-PERIPHERAL"
        )
        await stack.setNotify(true, characteristicUUID: profile.notifyCharacteristicUUID, serviceUUID: profile.serviceUUID, peripheralID: "FAKE-BLE-PERIPHERAL")
        let events = await collector.value

        #expect(events == [
            "poweredOn", "discovered", "connected",
            "servicesDiscovered", "characteristicsDiscovered", "notify",
        ])
    }

    @Test("a written command comes back reassembled across notifications")
    func writeRoundTrip() async throws {
        let scenario = try Scenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeCentral(scenario: scenario)
        defer { Task { await stack.stop() } }

        // The reply arrives in 20-byte notifications; the assembler stitches it.
        async let reply = drainReply(stack, profile: profile)
        await stack.write(
            Data("ATZ\r".utf8),
            characteristicUUID: profile.writeCharacteristicUUID,
            serviceUUID: profile.serviceUUID,
            peripheralID: "FAKE-BLE-PERIPHERAL",
            withResponse: false
        )
        let assembled = await reply
        #expect(assembled.contains("ELM327 v1.5"))
        #expect(assembled.hasSuffix(">"))
    }

    @Test("every preset completes the handshake and returns a reply", arguments: [
        AdapterProfile.nordicUART,
        AdapterProfile.conventionalFFF0,
        AdapterProfile.sharedFFE0,
        AdapterProfile.eighteenF0,
    ])
    func presetRoundTrip(profile: AdapterProfile) async throws {
        let scenario = try Scenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeCentral(scenario: scenario, profile: profile)
        defer { Task { await stack.stop() } }

        let collector = Task { () -> (discovered: (uuids: [String], service: String)?, ready: Bool) in
            var discovered: ([String], String)?
            for await event in stack.events() {
                switch event {
                case .discovered:
                    break
                case .characteristicsDiscovered(_, let serviceUUID, let uuids, _):
                    discovered = (uuids, serviceUUID)
                case .notifyStateChanged(_, _, let isNotifying, _) where isNotifying:
                    return (discovered, true)
                default:
                    break
                }
            }
            return (discovered, false)
        }

        await stack.scan(serviceUUIDs: [profile.serviceUUID])
        await stack.connect(peripheralID: "FAKE-BLE-PERIPHERAL")
        await stack.discoverServices([profile.serviceUUID], peripheralID: "FAKE-BLE-PERIPHERAL")
        await stack.discoverCharacteristics(
            [profile.writeCharacteristicUUID, profile.notifyCharacteristicUUID],
            serviceUUID: profile.serviceUUID,
            peripheralID: "FAKE-BLE-PERIPHERAL"
        )
        await stack.setNotify(true, characteristicUUID: profile.notifyCharacteristicUUID, serviceUUID: profile.serviceUUID, peripheralID: "FAKE-BLE-PERIPHERAL")
        let handshake = await collector.value
        #expect(handshake.ready)
        #expect(handshake.discovered?.uuids == profile.characteristics.map(\.uuid))
        #expect(handshake.discovered?.service == profile.serviceUUID)

        async let reply = drainReply(stack, profile: profile)
        await stack.write(
            Data("ATZ\r".utf8),
            characteristicUUID: profile.writeCharacteristicUUID,
            serviceUUID: profile.serviceUUID,
            peripheralID: "FAKE-BLE-PERIPHERAL",
            withResponse: profile.writeWithResponse
        )
        #expect(await reply.contains("ELM327"))
    }

    @Test("shared FFE0 notifies on the same characteristic it accepts writes on")
    func sharedCharacteristicRoundTrip() async throws {
        let profile = AdapterProfile.sharedFFE0
        let scenario = try Scenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeCentral(scenario: scenario, profile: profile)
        defer { Task { await stack.stop() } }

        let collector = Task { () -> (assembled: String, notifyUUID: String?) in
            var assembled = ""
            var notifyUUID: String?
            for await event in stack.events() {
                switch event {
                case let .notification(_, characteristicUUID, data):
                    notifyUUID = characteristicUUID
                    assembled += String(decoding: data, as: UTF8.self)
                    if assembled.contains(">") { return (assembled, notifyUUID) }
                case .disconnected:
                    return (assembled, notifyUUID)
                default:
                    break
                }
            }
            return (assembled, notifyUUID)
        }

        await stack.write(
            Data("ATZ\r".utf8),
            characteristicUUID: profile.writeCharacteristicUUID,
            serviceUUID: profile.serviceUUID,
            peripheralID: "FAKE-BLE-PERIPHERAL",
            withResponse: false
        )
        let reply = await collector.value
        #expect(reply.assembled.contains("ELM327"))
        #expect(reply.notifyUUID == profile.writeCharacteristicUUID)
        #expect(reply.notifyUUID == profile.notifyCharacteristicUUID)
    }

    @Test("mixed UUID spellings negotiate one shared characteristic")
    func mixedUUIDHandshake() async throws {
        let profile = AdapterProfile(serviceUUID: "FFE0", writeCharacteristicUUID: "FFE1",
            notifyCharacteristicUUID: "0000FFE1-0000-1000-8000-00805F9B34FB",
            writeWithResponse: false, advertisedName: "SyntheticELM")
        var state = ConnectionStateMachine(profile: profile)
        let id = "synthetic"
        _ = state.handle(.start)
        _ = state.handle(.poweredOn)
        // Use the same events that a central returns after the user starts scanning.
        _ = state.handle(.discovered(.init(id: id, name: "SyntheticELM")))
        _ = state.handle(.connected(peripheralID: id))
        _ = state.handle(.servicesDiscovered(peripheralID: id, serviceUUIDs: ["FFE0"], error: nil))
        let actions = state.handle(.characteristicsDiscovered(peripheralID: id, serviceUUID: "FFE0",
            characteristicUUIDs: ["FFE1"], error: nil))
        #expect(!actions.isEmpty)
        _ = state.handle(.notifyStateChanged(peripheralID: id, characteristicUUID: "FFE1", isNotifying: true, error: nil))
        #expect(state.state == .ready(peripheralID: id))
    }

    @Test("cancel reports a disconnect before the event stream finishes")
    func cancelTeardown() async throws {
        let scenario = try Scenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeCentral(scenario: scenario, profile: .sharedFFE0)
        var events = stack.events().makeAsyncIterator()

        guard case .poweredOn? = await events.next() else { Issue.record("Expected powered-on state"); return }
        await stack.cancel(peripheralID: "FAKE-BLE-PERIPHERAL")
        guard case .disconnected? = await events.next() else { Issue.record("Expected disconnection"); return }

        await stack.stop()
        #expect(await events.next() == nil)
    }
}
