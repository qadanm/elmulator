# Roadmap and cross-platform story

## Where things stand

- Language-neutral today. The TCP server (`elmulator serve` / `elmulator-tcp`) and the JSON scenario format work for any app in any language, since anything can open a socket.
- Swift gets the most. On top of TCP, Swift has the in-process BLE test double (`FakeBLEStack`), the pure connection state machine, the real CoreBluetooth central, and a real BLE peripheral executable.
- Provable parity. The [conformance suite](../conformance/) holds every implementation to byte-for-byte agreement on the scenario format.

## Going wider (in priority order)

1. A cross-platform BLE peripheral. The real-radio peripheral (`elmulator-ble`) uses `CBPeripheralManager`, so it is macOS only. Reimplementing it on [`bless`](https://github.com/kevincar/bless) (a cross-platform BLE-server library for Linux/BlueZ, macOS, and Windows) with the same scenario engine would make a real BLE peripheral available on Linux CI, not just on a Mac. This is the highest-leverage cross-platform step.
2. A non-Swift in-process double. Port the scenario engine to Kotlin or Rust so those ecosystems get the in-process fake, not just the socket. The conformance suite keeps ports honest.
3. More scenarios. Grow the quirk coverage: clone adapters, protocol variants, more chaos.

### Known limitation

The Android emulator, like the iOS Simulator, has no BLE radio. Even with a cross-platform `bless` peripheral, Android BLE CI needs a Linux peripheral plus an on-device instrumented test. The TCP path has no such limit.

## Not in scope right now

The format, the engine, and the servers are MIT and stay that way. A few things are intentionally out of scope for now, though they could sit on top later:

- Scenario studio: record real adapter traffic and turn it into a scenario.
- Adapter-quirk library: a curated catalog of clone and knockoff behaviors (`headers_off_echo_on` is the first one).
- Cloud CI runner: hosted BLE peripherals for teams without a Mac runner.
