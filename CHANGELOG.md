# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow semantic versioning.

## [0.3.1] - 2026-07-06

### Changed
- The GitHub Action's display name is now `elmulator` (was `elmulator serve`), so the Marketplace listing and the step label in Actions logs read as the project name. No inputs or outputs changed. Pin `qadanm/elmulator@v0.3.1`, or `@v0` to track the latest 0.x.

### Docs
- Refreshed the README front page: the quickstart now leads with the in-process `Conversation` and load-by-name, and there is a dedicated GitHub Actions section.

## [0.3.0] - 2026-07-06

Developer-experience release. Everything is additive except the BLE type rename, which ships with deprecated aliases so existing code keeps compiling.

### Added
- Test client. `ElmulatorTestSupport` ships an in-process `Conversation` and a socket `Client` (Swift); the Python package adds `Conversation`, `Client`, and `serve_in_background`. Driving the emulator is a few lines instead of a hand-rolled socket loop.
- Bundled scenarios by name: `Scenario.bundled("p0420_basic")` and `Scenario.bundledNames` (Swift), `elmulator.load_bundled(...)` and `bundled_names()` (Python). Embedded in the package, so no files on disk are needed. `elmulator serve` and the new GitHub Action accept a bundled name.
- Served-conversation transcript: opt in with `EngineConfiguration.recordTranscript` and read `transcript` from the engine, `TCPServer`, `FakeCentral`, or `ElmulatorMockPeripheral`; `TranscriptEntry.debugDump()` prints a byte-level line.
- In-code scenario builders: public memberwise initializers on `Scenario`, `Command`, `Defaults`, and `ExpectedScanSummary`, plus `Scenario(id:commands:)` (Swift) and `build_scenario(...)` (Python).
- `expected_scan_summary` helper: `ExpectedScanSummary.mismatches(observed:)` (Swift) and `summary_mismatches(expected, observed)` (Python) diff a consumer-decoded scan against the scenario's expectations.
- A reusable GitHub Action (`action.yml`) that installs elmulator and serves a scenario over TCP, exposing the bound port.

### Changed
- BLE types dropped the `BLE` prefix (the `ElmulatorBLE` module already namespaces them), so they no longer collide with a consuming app's own BLE layer: `BLEStack` -> `CentralStack`, `BLEConnectionStateMachine` -> `ConnectionStateMachine`, `BLEAdapterProfile` -> `AdapterProfile`, `BLEDiscoveredPeripheral` -> `DiscoveredPeripheral`, `BLEStackEvent` -> `CentralEvent`, `BLEConnectionEvent` -> `ConnectionEvent`, `BLEConnectionAction` -> `ConnectionAction`, `BLETransportError` -> `ConnectionError`, `FakeBLEStack` -> `FakeCentral`. Deprecated typealiases keep the old names working for now.

### Fixed
- The CoreBluetooth-Mock bridge can honor per-piece reply delays (opt in with `applyDelays: true`), so timeout paths are reachable through BLE.
- `elmulator validate` with no arguments now works from a pip-installed wheel (it validates the embedded scenarios rather than a repo-root path that is not shipped).

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
