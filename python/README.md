# elmulator — Python package

A pure-standard-library ELM327 TCP server and scenario validator. No third-party dependencies. Python 3.9+.

## Install

```bash
pip install elmulator
# or from a checkout of this repo:
pip install -e .
```

## CLI

```bash
elmulator serve SCENARIO [--host H] [--port N] [--echo on|off|scenario] \
                         [--split a,b,c] [--latency-ms N] [--jitter-ms N] [--seed N]
elmulator validate [PATHS...]     # files or dirs; defaults to the bundled examples
elmulator self-test               # in-process loopback smoke test
```

`serve` prints `LISTENING <port>` on stdout once bound (`--port 0` picks a free port) and logs activity to stderr. Each client gets its own scenario cursor state.

## Library

```python
from elmulator import Scenario, serve
import argparse

scenario = Scenario.from_path("scenarios/p0420_basic.scenario.json")
args = argparse.Namespace(host="127.0.0.1", port=0, echo="scenario",
                          split=None, latency_ms=0, jitter_ms=0, seed=0)
serve(args, scenario)   # blocking; pass ready_event/stop_event for threaded use
```

The matching, echo, splitting, and jitter semantics are identical to the Swift engine; the [conformance suite](../conformance/) proves byte-for-byte parity.

## Test

```bash
pip install pytest
pytest -q
```
