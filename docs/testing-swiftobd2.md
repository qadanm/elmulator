# Using elmulator with SwiftOBD2

[SwiftOBD2](https://github.com/kkonteh97/SwiftOBD2) is a popular Swift OBD2 library. If you build on it, here's how elmulator helps you test — what works today, and two contributions that would make it seamless.

## Works today: Wi-Fi (TCP) mode, zero library changes

SwiftOBD2 supports a Wi-Fi transport. Its `WifiManager` connects to a fixed `192.168.0.10:35000` (the classic Wi-Fi OBD2 adapter address). Point that at an elmulator TCP server:

```bash
# On the machine running the app/simulator, alias the adapter IP to loopback:
sudo ifconfig lo0 alias 192.168.0.10
elmulator serve scenarios/p0420_basic.scenario.json --host 192.168.0.10 --port 35000
```

Then run SwiftOBD2 in `.wifi` mode and it will talk to the scripted adapter — real transport, scripted responses, no car. (The hardcoded IP is a SwiftOBD2 limitation; making host/port configurable is contribution #1 below.)

## The BLE path needs an upstream change

SwiftOBD2's `BLEManager` uses the system `CoreBluetooth` types directly, so it can't be transparently driven by CoreBluetooth-Mock (and therefore by [`ElmulatorCoreBluetoothMock`](../swift/README.md)) without a small change to SwiftOBD2 itself. Two options, smallest first:

### Contribution #1 — inject the transport (small, high value)

SwiftOBD2 already has a `CommProtocol` seam (`BLEComm`, `WifiComm`, `MOCKComm`), and `ELM327` is built with `init(comm: CommProtocol)`. Making that protocol `public` and adding `OBDService(comm:)` (or a `.custom(CommProtocol)` connection type) would let anyone inject a comm — including an elmulator-backed one that replaces the hand-written `MOCKComm` with scriptable scenarios:

```swift
// Sketch of what becomes possible once CommProtocol is public + injectable:
final class ElmulatorComm: CommProtocol {
    private var engine: FakeELMScenarioEngine
    func sendCommand(_ command: String, retries: Int) async throws -> [String] {
        // feed command to the scenario engine, return the decoded lines
    }
    // connectAsync/scanForPeripherals/connectionState … no-ops for a scripted comm
}
let service = OBDService(comm: ElmulatorComm(scenario: .p0420Basic))
```

This tests SwiftOBD2's whole ELM327 + decoder stack against every elmulator scenario, deterministically, in CI.

### Contribution #2 — adopt CoreBluetooth-Mock typealiases (bigger, best)

If `BLEManager` aliased the `CBM*` types (behind `#if DEBUG`, exactly as [CoreBluetooth-Mock recommends](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock)), then `ElmulatorMockPeripheral` would drive SwiftOBD2's **real BLE code path** end-to-end — scan, connect, discover, subscribe, notify — against a scripted ELM327. This is the strongest form of the integration.

## A ready-to-file issue

> **Title:** Make the transport testable (inject `CommProtocol`, or adopt CoreBluetooth-Mock)
>
> **Body:** SwiftOBD2's BLE path can't currently be exercised in CI/unit tests because it uses `CoreBluetooth` directly and `CommProtocol` is internal. Two options would fix this: (1) make `CommProtocol` public and allow `OBDService(comm:)` injection, so a scripted comm can drive the ELM327/decoder stack; or (2) alias the `CBM*` types from CoreBluetooth-Mock behind `#if DEBUG` so the real BLE path can run against a mock peripheral. I maintain [elmulator](https://github.com/elmulator/elmulator), a scriptable ELM327 emulator, and would be happy to contribute a PR + a test suite of realistic scenarios (stored codes, chunked replies, clone quirks, disconnects). Interested?

If you maintain a SwiftOBD2-based app, contribution #1 is a small PR with a large testing payoff — happy to help.
