# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow semantic versioning.

## [Unreleased]

### Added
- **iOS/Swift CI story.** `ElmulatorCoreBluetoothMock` (`ElmulatorMockPeripheral`) bridges any scenario to Nordic's CoreBluetooth-Mock, so an app's real `CBCentralManager` code can be tested against a scripted ELM327 with no radio.
- **Copy-this example** (`examples/ios-ci/`): a realistic ELM327 BLE client in pure CoreBluetooth-Mock plus a passing `swift test` suite (P0420 read, chunked-notification reassembly, malformed-input robustness).
- Guides: [testing-obd2-apps-in-ci.md](docs/testing-obd2-apps-in-ci.md) and [testing-swiftobd2.md](docs/testing-swiftobd2.md).
- CI now builds and tests the iOS example on macOS.
- Initial extraction of the OBD2 adapter emulator and CI test harness.
- `obd2.sim_scenario.v1` scenario format: prose spec (`SPEC.md`) and JSON Schema (`spec/`).
- Seven example scenarios, each a regression oracle (`scenarios/`).
- Swift package: `Elmulator` (engine), `ElmulatorTCP`, `ElmulatorBLE` (GATT profile, pure connection state machine, `BLEStack`, real CoreBluetooth central), `ElmulatorBLETestSupport` (`FakeBLEStack` in-process fake central); `elmulator-tcp` and `elmulator-ble` executables. 28 tests.
- Python package (pure stdlib): `elmulator` CLI (`serve`, `validate`, `self-test`) and library API.
- Cross-implementation conformance suite proving byte-for-byte parity between the Python and Swift servers.
- CI for Python (Ubuntu) and Swift + parity (macOS).
