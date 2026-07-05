# Example: testing an iOS OBD2 app in CI

A minimal, **copy-this** example of testing a real CoreBluetooth OBD2 client against a scripted ELM327 — no car, no adapter, no Bluetooth radio.

- [`Sources/ObdSampleClient/ELM327Client.swift`](Sources/ObdSampleClient/ELM327Client.swift) — a realistic ELM327 BLE client written in pure CoreBluetooth-Mock. **It imports nothing from elmulator.** This is your app's production Bluetooth code.
- [`Tests/ObdSampleClientTests/OBDCITests.swift`](Tests/ObdSampleClientTests/OBDCITests.swift) — the test target scripts the adapter with elmulator scenarios and drives the client through a full connect → subscribe → command flow.

## Run it

```bash
cd examples/ios-ci
swift test
```

```
✔ Test "connects over BLE and reads a stored P0420 with no radio" passed
✔ Test "reassembles a reply split across many BLE notifications" passed
✔ Test "does not crash on malformed adapter output" passed
```

No simulator boot, no device — runs on any macOS runner.

## How it fits together

```
ELM327Client (real CoreBluetooth code)
      │  CoreBluetooth-Mock (forceMock: true)
      ▼
ElmulatorMockPeripheral  ──runs──▶  FakeELMScenarioEngine  ──reads──▶  scenarios/*.json
```

The production client and the scripted peripheral only meet through CoreBluetooth-Mock's `CBM*` types — exactly as they would on a real device. Full walkthrough: [docs/testing-obd2-apps-in-ci.md](../../docs/testing-obd2-apps-in-ci.md).

> This example uses a local path dependency on the repo's Swift package. In your own project, add elmulator as a normal package dependency and depend on the `ElmulatorCoreBluetoothMock` product from your test target.
