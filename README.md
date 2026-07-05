# elmulator

**A scriptable Bluetooth + TCP OBD2 adapter emulator and CI test harness.**

Test your OBD2 app against a fake ELM327 — over real Bluetooth LE or TCP — with no car, no adapter, and no phone. MIT-licensed.

<!-- badges: add CI / SPM / PyPI once published -->
`SwiftPM` · `PyPI` · `SAE J1979 / ISO 15765-4` · `MIT`

---

Every consumer OBD2 app talks to a Bluetooth adapter. Almost none can test that path: the iOS Simulator has no radio, and the alternative is a phone plus a dongle plus a car in a parking lot. **elmulator makes the adapter fake and scriptable** so your Bluetooth stack runs in CI.

- 🔵 **Real BLE peripheral.** A macOS process advertises a genuine ELM327-style GATT profile (Nordic UART by default). Your app connects over actual Bluetooth — no mock objects.
- 🧪 **In-process test double.** The same scenario engine behind a `BLEStack` protocol: swap the real CoreBluetooth central for the fake one and run your whole Bluetooth connection flow in unit tests, no radio.
- 🍏 **Works with your existing CoreBluetooth code.** A bridge to Nordic's [CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) turns any scenario into a mock BLE peripheral, so your real `CBCentralManager` code runs against a scripted ELM327 in `swift test` — see the [iOS CI guide](docs/testing-obd2-apps-in-ci.md).
- 🔌 **TCP server too.** One command exposes any scenario over a socket — for the Simulator, Android, or any language.
- 📜 **Scenarios are just JSON.** Script the exact ELM327 conversation: responses, chunking, latency, deterministic jitter, stalls, disconnects, malformed frames. Each scenario is also a regression oracle.
- ♻️ **Chaos built in.** BLE-MTU chunking, timeouts, dropped connections, garbage bytes — the failures that only ever happen on a real adapter.
- ✅ **Proven equivalent.** The Python and Swift servers are held **byte-for-byte identical** by a [conformance suite](conformance/), so the scenario format is a real spec, not one implementation's quirks.

> The closest existing tool, [ELM327-emulator](https://github.com/Ircama/ELM327-emulator), is excellent, but its "Bluetooth" is RFCOMM serial (Bluetooth *Classic* SPP) — not the BLE/GATT that every iOS adapter uses — and it's licensed CC-BY-NC-SA (non-commercial). elmulator adds native BLE, an iOS/CI test story, and is MIT. (Claims verified against its repo, July 2026.)

## Quickstart

### TCP in five seconds (any language)

```bash
cd python && pip install -e .          # or: pip install elmulator (once published)
elmulator serve ../scenarios/p0420_basic.scenario.json --port 35000
# point your app's Wi-Fi/TCP transport at 127.0.0.1:35000
```

Prove it end to end without writing any app code:

```bash
elmulator self-test        # loopback smoke test: prints SELF-TEST OK
```

### Bluetooth stack in a unit test — no radio (Swift)

```swift
import Elmulator
import ElmulatorBLE
import ElmulatorBLETestSupport

// A scripted adapter, stood up as an in-process BLE central.
let scenario = try FakeELMScenario.load(from: scenarioURL)
let stack: any BLEStack = FakeBLEStack(scenario: scenario)   // no Bluetooth radio

// Drive YOUR production Bluetooth code — it targets the same `BLEStack`
// protocol the real CoreBluetooth central implements — then assert against
// the scenario's expected_scan_summary. Swap in the real central with:
//   let stack = makeCoreBluetoothStack()
```

The connection state machine (power-on → scan → connect → discover → subscribe → ready) lives in `ElmulatorBLE` as a pure, fully testable value type.

### A real Bluetooth peripheral (macOS)

```bash
cd swift
swift run elmulator-ble --scenario ../scenarios/p0420_basic.scenario.json
# a real ELM327-style BLE peripheral is now advertising; connect a physical
# iPhone/app to it over CoreBluetooth
```

## Test your iOS OBD2 app in CI

The iOS Simulator has no Bluetooth and Apple provides [no supported way to mock `CBPeripheral`](https://developer.apple.com/forums/thread/764024), so the Bluetooth path is usually the untested part of an OBD2 app. elmulator + [CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) fixes that — your **real** CoreBluetooth code runs against a scripted ELM327 on a plain macOS runner:

```swift
let adapter = ElmulatorMockPeripheral(scenario: try .load(from: url))
adapter.simulate()                                  // scripted ELM327 as a mock BLE peripheral
let client = MyOBDClient(forceMock: true)           // your real CBCentralManager code
try await client.connect()
#expect(try await client.send("03").contains("43 01 04 20"))   // reads P0420, no radio
```

- **Full walkthrough:** [docs/testing-obd2-apps-in-ci.md](docs/testing-obd2-apps-in-ci.md)
- **Copy-this sample + passing CI suite:** [examples/ios-ci/](examples/ios-ci/)
- **Building on [SwiftOBD2](https://github.com/kkonteh97/SwiftOBD2)?** [docs/testing-swiftobd2.md](docs/testing-swiftobd2.md)

## What's in the box

| Piece | Where | What it is |
|---|---|---|
| Scenario engine | `swift` → `Elmulator`, `python` | Pure request→reply engine: matching, echo, defaults, chunking, seeded jitter, stall/disconnect |
| TCP server | `Elmulator​TCP` (in-process) · `elmulator-tcp` / `elmulator serve` (CLI) | Serve a scenario over localhost TCP |
| **BLE test double** | `Elmulator​BLETestSupport` → `FakeBLEStack` | In-process fake central for CI, behind the `BLEStack` protocol |
| **CoreBluetooth-Mock bridge** | `Elmulator​CoreBluetoothMock` → `ElmulatorMockPeripheral` | Turn a scenario into a mock BLE peripheral so your **real** CoreBluetooth code runs in CI |
| **BLE peripheral** | `elmulator-ble` (macOS) | Real CoreBluetooth peripheral advertising an ELM327 GATT profile |
| BLE transport kit | `ElmulatorBLE` | GATT profile, connection state machine, `BLEStack` protocol, real central |
| Scenario format | [`SPEC.md`](SPEC.md) + [`spec/`](spec/) | The public contract (`obd2.sim_scenario.v1`) + JSON Schema |
| Example library | [`scenarios/`](scenarios/) | Seven documented scenarios, each a regression oracle |
| Conformance suite | [`conformance/`](conformance/) | Byte-for-byte parity across implementations |

## The scenario format

A scenario is a JSON file describing a synthetic ELM327 conversation — per command: the request, the response chunks, delays, echo, prompt behavior, and post-actions (stall, disconnect) — plus an `expected_scan_summary` so each scenario doubles as a regression oracle. See **[SPEC.md](SPEC.md)** for the full contract and **[scenarios/](scenarios/)** for the example library.

```jsonc
{
  "schema_version": "obd2.sim_scenario.v1",
  "scenario_id": "p0420_basic",
  "synthetic": true,
  "adapter_profile": "elm327_like_tcp",
  "defaults": { "at_response": "OK\r\r>", "obd_response": "NO DATA\r\r>" },
  "commands": [
    { "request": "ATZ", "response_chunks": ["ELM327 v1.5\r\r>"], "echo": true },
    { "request": "03",  "response_chunks": ["43 01 04 20\r\r>"] }
  ],
  "expected_scan_summary": { "stored_codes": ["P0420"], "mil_reported_on": true }
}
```

## Cross-platform

The TCP server and the JSON scenario format are language-neutral **today** — any app in any language can point at the socket. Swift additionally gets the in-process test double and the real BLE peripheral. The roadmap for going wider (a cross-platform BLE peripheral via `bless`, engine ports) is in [docs/roadmap.md](docs/roadmap.md).

## Layout

```
scenarios/      example scenario library (the regression oracles)
spec/           obd2.sim_scenario.v1 JSON Schema
swift/          SwiftPM package: engine, TCP, BLE kit, fake central, CLIs
python/         pip package: TCP server + validator (pure stdlib)
conformance/    cross-implementation byte-for-byte parity suite
docs/           getting-started guides + roadmap
SPEC.md         the scenario format specification
```

## Standards & provenance

Clean-room, standard OBD2 only (SAE J1979 / ISO 15765-4). No GPL/AGPL/non-commercial code was copied; every scenario is synthetic and hand-authored, which is why the whole project is MIT.

## License

[MIT](LICENSE).
