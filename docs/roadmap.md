# Roadmap & cross-platform story

## Where things stand

- **Language-neutral today.** The TCP server (`elmulator serve` / `elmulator-tcp`) plus the JSON scenario format work for any app in any language — point your TCP transport at the socket. This is the universal on-ramp and it costs nothing.
- **Swift gets the most.** In addition to TCP, Swift has the in-process BLE test double (`FakeBLEStack`), the pure connection state machine, the real CoreBluetooth central, and a real BLE peripheral executable.
- **Provable parity.** The [conformance suite](../conformance/) holds every implementation to byte-for-byte agreement on the scenario format.

## Going wider (in priority order)

1. **A cross-platform BLE peripheral.** The real-radio peripheral (`elmulator-ble`) uses `CBPeripheralManager`, so it is macOS-only. Reimplementing the peripheral on [`bless`](https://github.com/kevincar/bless) (a cross-platform BLE-server library: Linux/BlueZ, macOS, Windows) reusing the same scenario engine would make "BLE OBD2 emulator" true on Linux CI, not just on a Mac. This is the single highest-leverage cross-platform investment.
2. **A non-Swift in-process double.** Port the scenario engine to Kotlin/Rust so those ecosystems get the in-process fake, not just the socket. The conformance suite keeps ports honest.
3. **Publish artifacts.** PyPI release for `elmulator`; Swift Package Index listing.
4. **More scenarios.** Grow the quirk coverage (clone adapters, protocol variants, more chaos).

### Known limitation (documented on purpose)

The Android emulator, like the iOS Simulator, has **no BLE radio**. Even with a cross-platform `bless` peripheral, Android BLE CI needs a Linux peripheral plus an on-device instrumented test. The TCP path has no such limit.

## Non-goals (for now) — and where a paid tier could sit later

The core — the format, the engine, the servers — is and stays MIT. Some things are deliberately **not** in scope now but are kept possible without rework, and are the natural place for a future hosted/premium offering:

- **Scenario studio** — record real adapter traffic and turn it into a scenario.
- **Adapter-quirk library** — a curated catalog of clone/knockoff behaviors (`headers_off_echo_on` is quirk #1).
- **CI cloud runner** — hosted BLE peripherals for teams without a Mac runner.

The clean line: the open format and engine stay permissive; any premium is a hosted service or curated data on top, never a fork of the core.
