# Using elmulator with SwiftOBD2

[SwiftOBD2](https://github.com/kkonteh97/SwiftOBD2) is a popular Swift OBD2 library. If you build on it, here is how elmulator can help you test: what works today, and two changes to SwiftOBD2 that would make the two fit together more cleanly.

## Works today: Wi-Fi (TCP) mode, no library changes

SwiftOBD2 has a Wi-Fi transport. Its `WifiManager` connects to a fixed `192.168.0.10:35000`, the usual Wi-Fi OBD2 adapter address. Point that at an elmulator TCP server:

```bash
# On the machine running the app or simulator, alias the adapter IP to loopback:
sudo ifconfig lo0 alias 192.168.0.10
elmulator serve scenarios/p0420_basic.scenario.json --host 192.168.0.10 --port 35000
```

Run SwiftOBD2 in `.wifi` mode and it will talk to the scripted adapter: real transport, scripted responses, no car. The hardcoded IP is a SwiftOBD2 limitation, and making the host and port configurable is one of the changes described below.

## The BLE path needs an upstream change

SwiftOBD2's `BLEManager` uses the system `CoreBluetooth` types directly, so it can't be driven by CoreBluetooth-Mock (and therefore by [`ElmulatorCoreBluetoothMock`](swift-package.md)) without a small change to SwiftOBD2 itself. Two options, smallest first.

### Option 1: inject the transport (small, high value)

SwiftOBD2 already has a `CommProtocol` seam (`BLEComm`, `WifiComm`, `MOCKComm`), and `ELM327` is built with `init(comm: CommProtocol)`. Making that protocol public and adding `OBDService(comm:)` (or a `.custom(CommProtocol)` connection type) would let anyone inject a comm, including an elmulator-backed one that replaces the hand-written `MOCKComm` with scripted scenarios:

```swift
// What becomes possible once CommProtocol is public and injectable:
final class ElmulatorComm: CommProtocol {
    private var engine: FakeELMScenarioEngine
    func sendCommand(_ command: String, retries: Int) async throws -> [String] {
        // feed the command to the scenario engine, return the decoded lines
    }
    // connectAsync/scanForPeripherals/connectionState are no-ops for a scripted comm
}
let service = OBDService(comm: ElmulatorComm(scenario: .p0420Basic))
```

That would test SwiftOBD2's whole ELM327 and decoder stack against every elmulator scenario, deterministically, in CI.

### Option 2: adopt CoreBluetooth-Mock typealiases (bigger, best)

If `BLEManager` aliased the `CBM*` types (behind `#if DEBUG`, the way [CoreBluetooth-Mock recommends](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock)), then `ElmulatorMockPeripheral` would drive SwiftOBD2's real BLE code path from end to end (scan, connect, discover, subscribe, notify) against a scripted ELM327. This is the strongest form of the integration.

Both are small, well-scoped changes to SwiftOBD2 rather than to elmulator.
