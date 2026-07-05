# Testing an iOS OBD2 / ELM327 app in CI (no car, no adapter, no radio)

If you build an OBD2 app, you already know the problem: **the iOS Simulator has no Bluetooth**, Apple says [don't subclass CoreBluetooth](https://developer.apple.com/documentation/corebluetooth), and there is [no supported way to instantiate a `CBPeripheral`](https://developer.apple.com/forums/thread/764024). So the Bluetooth path — the one part of the app that actually talks to the car — is usually the one part with no automated tests. People fall back to a phone plus a dongle plus a car in a parking lot.

This guide shows how to run your **real** Bluetooth code against a **scripted ELM327 adapter** in `swift test` / CI, with no hardware, using two libraries:

- [**CoreBluetooth-Mock**](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) (Nordic) — lets your production code run against a mock `CBCentralManager` on the Simulator or in CI.
- **elmulator** (this project) — provides the *behavior* of the mock peripheral: a scriptable ELM327 driven by a JSON scenario, so you don't hand-write fake responses.

CoreBluetooth-Mock gives you the socket; elmulator gives you something realistic on the other end of it.

## The idea in one picture

```
Your app's BLE code  ──▶  CoreBluetooth-Mock  ──▶  ElmulatorMockPeripheral  ──▶  scenario.json
(unchanged, real            (mock CBCentral            (scripted ELM327,            (P0420, chunking,
 CoreBluetooth code)         on Simulator/CI)           runs the engine)             stalls, garbage…)
```

Your production code is untouched and imports nothing from elmulator. Only the **test** target scripts the adapter.

## Step 1 — write your BLE code against CoreBluetooth-Mock

In a shipping app the usual pattern is to alias the mock types to the real ones outside of tests, so release builds use the system framework verbatim:

```swift
import CoreBluetoothMock
#if !DEBUG
typealias CBCentralManager = CBMCentralManager
typealias CBPeripheral    = CBMPeripheral
// …etc; see CoreBluetooth-Mock's migration guide.
#endif
```

Your connect/discover/subscribe/write code stays exactly as it is. (A complete, minimal client is in [`Sources/ObdSampleClient/ELM327Client.swift`](../Sources/ObdSampleClient/ELM327Client.swift).)

## Step 2 — script the adapter in your test

```swift
import Elmulator
import ElmulatorCoreBluetoothMock
import CoreBluetoothMock

let scenario = try FakeELMScenario.load(from: scenarioURL("p0420_basic"))
let adapter = ElmulatorMockPeripheral(scenario: scenario)   // a scripted ELM327
adapter.simulate()                                          // register + power on the mock
defer { CBMCentralManagerMock.tearDownSimulation() }

let client = ELM327Client(forceMock: true)                  // your real client, mock transport
try await client.connect()
#expect(try await client.send("03").contains("43 01 04 20"))  // reads P0420, no radio
```

That test connects over (mock) Bluetooth, subscribes to notifications, writes `03`, reassembles the reply across MTU-sized notifications, and asserts the stored trouble code — in milliseconds, on any CI runner.

## Step 3 — run it in CI

```yaml
# .github/workflows/ci.yml
jobs:
  ios-obd-tests:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift test          # no simulator, no device, no Bluetooth
```

Because CoreBluetooth-Mock runs with `forceMock: true`, this works on a plain macOS runner — you don't even need to boot a simulator.

## What you can actually test this way

Each elmulator [scenario](../scenarios/) is a scripted conversation, so you can cover the failure modes that only ever happen on a real adapter:

- **Happy paths** — read DTCs, VIN, live PIDs, clear codes.
- **BLE chunking** — replies split across many notifications (`stream_split_bytes`), so your response assembler is exercised.
- **Clone quirks** — echo left on despite `ATE0`, missing headers, ELM multi-line formats (`headers_off_echo_on`).
- **Chaos** — stalls (timeouts), mid-session disconnects, malformed/truncated frames (`malformed`, `adapter_disconnect`). Assert your app degrades gracefully instead of crashing or inventing data.

## Two other ways to drive the same scenarios

You don't have to use CoreBluetooth-Mock:

- **If your app already abstracts its BLE stack behind a protocol**, use elmulator's [`FakeBLEStack`](../docs/swift-package.md) (from `ElmulatorBLETestSupport`) — an in-process fake central behind the `BLEStack` protocol, no extra dependency.
- **If you connect over Wi-Fi/TCP** (or you're on Android/React Native/any language), run `elmulator serve scenario.json --port 35000` and point your transport at the socket. See [getting-started](getting-started.md).

## FAQ

**Does this touch a real Bluetooth radio?** No. That's the point — it runs on CI with no hardware.

**Do I need to change my app to use this?** Only to adopt CoreBluetooth-Mock's types (a one-time, release-safe alias). Your logic is unchanged.

**Is the scripted adapter realistic?** It runs the same engine as elmulator's TCP server and real BLE peripheral, and the Python and Swift implementations are held [byte-for-byte identical](../conformance/). It emulates standard OBD2 (SAE J1979 / ISO 15765-4).

**Can I record a real adapter into a scenario?** Not yet — scenarios are hand-authored today. See the [roadmap](roadmap.md).
```
