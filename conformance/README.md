# Conformance suite

Proves that every implementation of `obd2.sim_scenario.v1` produces **byte-for-byte identical reply content**. This is what makes the scenario format a specification rather than one program's behavior.

For each example scenario, the harness derives the expected reply bytes and termination (`prompt`, `stall`, `disconnect`, or `skipped` after an earlier disconnect) directly from the scenario, never from either server. It then drives the scenario's own command sequence (plus a couple of unmatched commands to hit the default paths) against two servers and checks both the independent oracle and raw byte-for-byte parity for every command.

The harness compares reply bytes, not TCP segmentation (the OS may coalesce writes). Authored chunk boundaries are part of the engine contract and are covered by the Swift and Python unit tests.

Startup is genuinely bounded: the harness waits at most 10 seconds for a `LISTENING <port>` announcement, reads stdout on a daemon thread so a silent child cannot block the deadline, reports premature exits and malformed or out-of-range announcements explicitly, and terminates and reaps both child processes on every success and failure path.

## Run

```bash
# Python vs Swift (requires a built Swift binary):
swift build --product elmulator-tcp
python conformance/run_conformance.py --swift-bin .build/debug/elmulator-tcp

# Python-only determinism check (no Swift toolchain, e.g. Linux CI):
python conformance/run_conformance.py
```

Exit code 0 means every reply matched the scenario-derived expectation **and** all implementations agreed byte-for-byte; non-zero prints the diverging command, the expected/actual bytes and termination, and any parity mismatch.

## Adding an implementation

Any server that (a) accepts a scenario path and a `--port`, and (b) prints `LISTENING <port>` on stdout once bound, can be dropped in. Add a `*_cmd()` builder and wire it into `run()`. New scenarios in [`scenarios/`](../scenarios/) are picked up automatically.
