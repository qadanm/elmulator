# Conformance suite

Proves that every implementation of `obd2.sim_scenario.v1` produces **byte-for-byte identical reply content**. This is what makes the scenario format a specification rather than one program's behavior.

For each example scenario, the harness drives the scenario's own command sequence (plus a couple of unmatched commands to hit the default paths) against two servers and compares the raw reply bytes for every command.

The harness compares reply bytes, not TCP segmentation (the OS may coalesce writes). Authored chunk boundaries are part of the engine contract and are covered by the Swift and Python unit tests.

## Run

```bash
# Python vs Swift (requires a built Swift binary):
swift build --product elmulator-tcp
python conformance/run_conformance.py --swift-bin .build/debug/elmulator-tcp

# Python-only determinism check (no Swift toolchain, e.g. Linux CI):
python conformance/run_conformance.py
```

Exit code 0 means all implementations agreed; non-zero prints the diverging command and both byte streams.

## Adding an implementation

Any server that (a) accepts a scenario path and a `--port`, and (b) prints `LISTENING <port>` on stdout once bound, can be dropped in. Add a `*_cmd()` builder and wire it into `run()`. New scenarios in [`scenarios/`](../scenarios/) are picked up automatically.
