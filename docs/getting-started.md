# Getting started

Three ways to point your app at a fake adapter, from easiest to most realistic.

## 1. TCP (any language)

```bash
cd python
pip install -e .                       # or: pip install elmulator (once published)
elmulator serve ../scenarios/p0420_basic.scenario.json --port 35000
```

Point your app's Wi-Fi/TCP OBD2 transport at `127.0.0.1:35000` and run a scan. Useful chaos flags:

```bash
elmulator serve SCEN --port 35000 \
  --echo scenario \        # on | off | scenario
  --split 1,2,5 \          # fragment replies into cycled byte sizes
  --latency-ms 40 \        # add latency to each reply
  --jitter-ms 100 --seed 42   # deterministic jitter
```

From Swift you can host the same scenario in-process (no subprocess):

```swift
import Elmulator
import ElmulatorTCP

let scenario = try FakeELMScenario.load(from: url)
let server = FakeELMTCPServer(scenario: scenario)
let port = try await server.start(port: 0)   // ephemeral
defer { Task { await server.stop() } }
// connect your TCP transport to 127.0.0.1:port
```

## 2. Bluetooth stack in a unit test — no radio (Swift)

The whole point: run your real Bluetooth connection + parsing flow in CI with no Bluetooth hardware.

```swift
import Elmulator
import ElmulatorBLE
import ElmulatorBLETestSupport

let scenario = try FakeELMScenario.load(from: url)
let stack: any BLEStack = FakeBLEStack(scenario: scenario)   // in-process fake central
// In production you'd instead write:  let stack = makeCoreBluetoothStack()

// Your production code targets the `BLEStack` protocol and (optionally) the
// pure `BLEConnectionStateMachine`, so the exact same code runs against the
// fake here and the real radio in the app. Assert on the bytes you receive
// and on the scenario's expected_scan_summary.
```

`FakeBLEStack` emits the same event order a real CoreBluetooth central reports (power-on → discover → connect → services → characteristics → notify), chunks replies to a notify-sized limit (default 20 bytes) like real BLE, and honors scenario stall/disconnect. Options: `profile:`, `configuration:`, `notifyChunkSize:`, `powerMode:`.

## 3. A real Bluetooth peripheral (macOS)

For device-level testing against a physical iPhone or another machine:

```bash
swift run elmulator-ble --scenario scenarios/p0420_basic.scenario.json
```

This advertises a real ELM327-style GATT service (Nordic UART UUIDs by default). Flags: `--name`, `--service/--write-uuid/--notify-uuid`, `--chunk-size`, `--latency-ms`, `--jitter-ms`, `--seed`, `--split`, `--disconnect-after`. macOS will prompt for Bluetooth permission the first time.

> Adapter clones vary; the default GATT profile is a common Nordic-UART layout, not a guarantee. Verify against the real adapters you target before freezing UUIDs.
