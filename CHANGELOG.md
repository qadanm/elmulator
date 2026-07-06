# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow semantic versioning.

## [0.2.0] - 2026-07-06

### Changed
- Renamed the Swift public types for a cleaner API (breaking): `FakeELMScenario` is now `Scenario`, `FakeELMScenarioEngine` is `ScenarioEngine`, `FakeELMEngineConfiguration` is `EngineConfiguration`, `FakeELMResponsePlan` is `ResponsePlan` (all in the `Elmulator` module), and `FakeELMTCPServer` is `TCPServer` (in `ElmulatorTCP`). The old names collided with a consumer that has its own `FakeELM` module and read oddly for a package called `Elmulator`. The Python API is unchanged (it already used `Scenario`). Surfaced by [#1](https://github.com/qadanm/elmulator/issues/1).

### Added
- The Python README notes `python -m elmulator` for when the console script is not on PATH. Surfaced by [#3](https://github.com/qadanm/elmulator/issues/3).

## [0.1.0] - 2026-07-05

### Added
- **iOS/Swift CI story.** `ElmulatorCoreBluetoothMock` (`ElmulatorMockPeripheral`) bridges any scenario to Nordic's CoreBluetooth-Mock, so an app's real `CBCentralManager` code can be tested against a scripted ELM327 with no radio.
- **Copy-this example** (the sample `ObdSampleClient` target + `ObdSampleClientTests`): a realistic ELM327 BLE client in pure CoreBluetooth-Mock plus a passing `swift test` suite (P0420 read, chunked-notification reassembly, malformed-input robustness).
- Guides: [testing-obd2-apps-in-ci.md](docs/testing-obd2-apps-in-ci.md) and [testing-swiftobd2.md](docs/testing-swiftobd2.md).
- CI now builds and tests the iOS example on macOS.
- Initial extraction of the OBD2 adapter emulator and CI test harness.
- `obd2.sim_scenario.v1` scenario format: prose spec (`SPEC.md`) and JSON Schema (`spec/`).
- Seven example scenarios, each a regression oracle (`scenarios/`).
- Swift package: `Elmulator` (engine), `ElmulatorTCP`, `ElmulatorBLE` (GATT profile, pure connection state machine, `BLEStack`, real CoreBluetooth central), `ElmulatorBLETestSupport` (`FakeBLEStack` in-process fake central); `elmulator-tcp` and `elmulator-ble` executables. 28 tests.
- Python package (pure stdlib): `elmulator` CLI (`serve`, `validate`, `self-test`) and library API.
- Cross-implementation conformance suite proving byte-for-byte parity between the Python and Swift servers.
- CI for Python (Ubuntu) and Swift + parity (macOS).
