# How to mock an ELM327 over Bluetooth

If you build an OBD2 app, it connects to an ELM327 adapter over Bluetooth, and sooner or later you want to test that path without a real adapter in front of you. The iOS Simulator has no Bluetooth, and Apple does not let you build a fake `CBPeripheral` by hand, so the usual answer is to mock at the code level and feed it realistic adapter behavior. elmulator supplies that behavior from a JSON scenario, in three forms.

## 1. In-process, no radio (Swift unit tests)

If your app talks to Bluetooth through a protocol boundary, use `FakeBLEStack`. It stands in for the CoreBluetooth central, walks your connection flow, and answers commands from a scenario. Nothing touches a radio.

```swift
import Elmulator
import ElmulatorBLETestSupport

let scenario = try Scenario.load(from: scenarioURL)
let stack: any BLEStack = FakeBLEStack(scenario: scenario)
// drive your production code against `stack`, then check the result
```

## 2. Your real CoreBluetooth code (CoreBluetooth-Mock)

If your app uses `CBCentralManager` directly, the CoreBluetooth-Mock bridge turns a scenario into a mock BLE peripheral. Your real connection code runs against a scripted ELM327 under `swift test`, on a normal macOS runner.

```swift
let adapter = ElmulatorMockPeripheral(scenario: try .load(from: url))
adapter.simulate()
// your real CBCentralManager code connects and reads, with no radio
```

The full walkthrough is in [Test an iOS OBD2 app in CI](testing-obd2-apps-in-ci.md).

## 3. A real Bluetooth peripheral (macOS)

For device-level testing, run the peripheral tool. It advertises a real ELM327-style GATT service (Nordic UART by default), so a physical iPhone or another machine can connect to it over Bluetooth.

```bash
swift run elmulator-ble --scenario scenarios/p0420_basic.scenario.json
```

## Questions

**Can you mock a Bluetooth device on the iOS Simulator?**
The Simulator has no Bluetooth at all, so it cannot connect to anything. You mock at the code level with [CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock), and elmulator supplies the scripted adapter it talks to.

**Do I need a physical ELM327 to test?**
No. The first two approaches need no hardware. The third advertises a real BLE peripheral from a Mac if you want to test on a device.

**Does this run in CI?**
Yes. The in-process fake and the CoreBluetooth-Mock bridge both run under `swift test` on a plain macOS runner.

**What can the adapter do besides answer normally?**
A scenario can split replies into Bluetooth-sized chunks, add delays, stall, drop the connection, or return malformed bytes, so you can test the cases that only show up with a real adapter.
