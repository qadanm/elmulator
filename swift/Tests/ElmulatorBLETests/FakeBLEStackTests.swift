import Elmulator
import ElmulatorBLE
import ElmulatorBLETestSupport
import Foundation
import Testing

/// Locate the repo's `scenarios/` directory relative to this source file.
private func scenarioURL(_ name: String) -> URL {
    URL(filePath: #filePath)            // .../swift/Tests/ElmulatorBLETests/FakeBLEStackTests.swift
        .deletingLastPathComponent()    // .../ElmulatorBLETests
        .deletingLastPathComponent()    // .../Tests
        .deletingLastPathComponent()    // .../swift
        .deletingLastPathComponent()    // repo root
        .appending(path: "scenarios")
        .appending(path: "\(name).scenario.json")
}

/// Collects notification payloads from the stack until it sees the ELM prompt
/// (`>`) or the stream ends, reassembling MTU-sized chunks the way a real
/// client's response assembler would.
private func drainReply(_ stack: FakeBLEStack, profile: BLEAdapterProfile) async -> String {
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

@Suite("FakeBLEStack in-process central")
struct FakeBLEStackTests {
    let profile = BLEAdapterProfile.fakeELM

    @Test("emits the CoreBluetooth event sequence up to notify-ready")
    func handshakeSequence() async throws {
        let scenario = try FakeELMScenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeBLEStack(scenario: scenario)
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
        let scenario = try FakeELMScenario.load(from: scenarioURL("p0420_basic"))
        let stack = FakeBLEStack(scenario: scenario)
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
}
