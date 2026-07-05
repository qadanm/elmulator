# Contributing

Thanks for helping build a better OBD2 test harness. This is an MIT-licensed, clean-room project — standard OBD2 only (SAE J1979 / ISO 15765-4). **Do not copy code or scenario data from GPL/AGPL or non-commercial sources** (including other ELM327 emulators). Every scenario must be synthetic and hand-authored.

## Local setup

```bash
# Python
cd python && pip install -e . pytest && pytest -q && cd ..

# Swift
cd swift && swift build && swift test && cd ..

# Cross-implementation parity
cd swift && swift build --product elmulator-tcp && cd ..
python conformance/run_conformance.py --swift-bin swift/.build/debug/elmulator-tcp
```

## The bar for a change

- **New scenarios** must pass `elmulator validate scenarios/` and are automatically covered by the conformance suite. Fill in `expected_scan_summary` and add a row to [`scenarios/README.md`](scenarios/README.md).
- **Engine changes** must keep Python and Swift byte-for-byte identical — if you change one, change the other and confirm the conformance suite still passes.
- **Format changes** update [`SPEC.md`](SPEC.md) and [`spec/obd2.sim_scenario.v1.schema.json`](spec/obd2.sim_scenario.v1.schema.json) together. Backward-compatible additions stay under `v1`; breaking changes bump the `schema_version`.
- Keep the Python package dependency-free (standard library only).

## Scope

This project is the emulator and test harness only. Decoding/parsing of PIDs and DTCs, UI, and app-specific domain logic are intentionally out of scope — `expected_scan_summary` is a consumer-defined oracle the emulator never interprets.
