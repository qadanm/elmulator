# Example scenario library

Seven hand-authored, fully synthetic `obd2.sim_scenario.v1` scenarios. Each is a runnable emulator input **and** a regression oracle (see each file's `expected_scan_summary`). Format reference: [SPEC.md](../SPEC.md).

| Scenario | What it exercises |
|---|---|
| [`no_codes_basic`](no_codes_basic.scenario.json) | A clean full scan: no stored/pending/permanent codes, MIL off, VIN retrieved, live values. The healthy-vehicle baseline. |
| [`p0420_basic`](p0420_basic.scenario.json) | One stored code (**P0420**, catalytic converter), MIL on, VIN, live values. The canonical "found a fault" path. |
| [`p0301_basic`](p0301_basic.scenario.json) | One stored code (**P0301**, cylinder-1 misfire) with a freeze frame that carries a trailing pad byte — exercises robust frame parsing. |
| [`chunked_stream`](chunked_stream.scenario.json) | The clean scan delivered in **7-byte chunks** (`stream_split_bytes: 7`) to mimic BLE notification sizes and harsh TCP segmentation. Tests reassembly. |
| [`headers_off_echo_on`](headers_off_echo_on.scenario.json) | A clone-adapter quirk: commands are echoed despite `ATE0`, headers are absent despite `ATH1`, and the VIN arrives in ELM multi-line form. Tests adapter-compatibility handling. |
| [`adapter_disconnect`](adapter_disconnect.scenario.json) | Chaos: the first `0100` **stalls** (timeout → retry), the retry succeeds, then `03` **disconnects**. Validates typed transport-error handling. |
| [`malformed`](malformed.scenario.json) | Garbage and truncated replies on every service (short bitmaps, unparseable hex, unknown-command markers). The scan must complete without crashing and attach warnings instead of inventing data. |

## Using one

```bash
# TCP
elmulator serve scenarios/p0420_basic.scenario.json --port 35000

# Real BLE peripheral (macOS)
swift run elmulator-ble --scenario scenarios/p0420_basic.scenario.json
```

## Adding your own

1. Copy the closest example and edit the `commands`.
2. Set `scenario_id` to the file's base name.
3. `elmulator validate scenarios/` (or validate against [`spec/`](../spec/)).
4. If you want cross-implementation coverage, the [conformance suite](../conformance/) will pick it up automatically.
