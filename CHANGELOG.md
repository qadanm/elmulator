# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow semantic versioning.

## [Unreleased]

### Added
- Initial extraction of the OBD2 adapter emulator and CI test harness.
- `obd2.sim_scenario.v1` scenario format: prose spec (`SPEC.md`) and JSON Schema (`spec/`).
- Seven example scenarios, each a regression oracle (`scenarios/`).
- Swift package: `Elmulator` (engine), `ElmulatorTCP`, `ElmulatorBLE` (GATT profile, pure connection state machine, `BLEStack`, real CoreBluetooth central), `ElmulatorBLETestSupport` (`FakeBLEStack` in-process fake central); `elmulator-tcp` and `elmulator-ble` executables. 28 tests.
- Python package (pure stdlib): `elmulator` CLI (`serve`, `validate`, `self-test`) and library API.
- Cross-implementation conformance suite proving byte-for-byte parity between the Python and Swift servers.
- CI for Python (Ubuntu) and Swift + parity (macOS).
