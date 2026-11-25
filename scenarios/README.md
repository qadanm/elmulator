# Example scenario library

These hand-authored, synthetic `obd2.sim_scenario.v1` scenarios are runnable emulator inputs. Read-only scan fixtures can provide an `expected_scan_summary`. Clear-outcome fixtures have separate ordered [wire expectations](../docs/clear-outcome-fixtures.md). [Format reference](../SPEC.md)

| Scenario | What it exercises |
|---|---|
| [`no_codes_basic`](no_codes_basic.scenario.json) | A clean full scan: no stored/pending/permanent codes, MIL off, VIN retrieved, live values. The healthy-vehicle baseline. |
| [`p0420_basic`](p0420_basic.scenario.json) | One stored code (**P0420**, catalytic converter), MIL on, VIN, live values. The canonical "found a fault" path. |
| [`p0301_basic`](p0301_basic.scenario.json) | One stored code (**P0301**, cylinder-1 misfire) with a freeze frame that carries a trailing pad byte. Exercises robust frame parsing. |
| [`chunked_stream`](chunked_stream.scenario.json) | The clean scan delivered in **7-byte chunks** (`stream_split_bytes: 7`) to mimic BLE notification sizes and harsh TCP segmentation. Tests reassembly. |
| [`headers_off_echo_on`](headers_off_echo_on.scenario.json) | A clone-adapter quirk: commands are echoed despite `ATE0`, headers are absent despite `ATH1`, and the VIN arrives in ELM multi-line form. Tests adapter-compatibility handling. |
| [`adapter_disconnect`](adapter_disconnect.scenario.json) | Chaos: the first `0100` **stalls** (timeout, then retry), the retry succeeds, then `03` **disconnects**. Validates typed transport-error handling. |
| [`malformed`](malformed.scenario.json) | Garbage and truncated replies on every service (short bitmaps, unparseable hex, unknown-command markers). The scan must complete without crashing and attach warnings instead of inventing data. |
| [`can_wrong_service`](can_wrong_service.scenario.json) | CAN validation fixture: requests Mode `03` and receives Mode `07` (`47`). Must reject instead of reporting stored codes. See [can-validation-fixtures.md](../docs/can-validation-fixtures.md). |
| [`can_invalid_hex`](can_invalid_hex.scenario.json) | CAN validation fixture: returns non-hex bytes (`GG`). Must reject rather than becoming an empty success. |
| [`can_truncated_payload`](can_truncated_payload.scenario.json) | CAN validation fixture: declared ISO-TP length `06` exceeds the four supplied bytes. Must fail as incomplete/invalid. |
| [`can_padded_rpm`](can_padded_rpm.scenario.json) | CAN validation fixture: ISO-TP length `04` bounds `41 0C 1A F8` (`1726 rpm`) followed by padding bytes `AA BB CC`. |
| [`can_full_report`](can_full_report.scenario.json) | Two ECU addresses with independent Mode 01 scopes, P0420 freeze frame, CAN monitor records, calibration IDs and CVNs. |
| [`can_missing_ecu`](can_missing_ecu.scenario.json) | A known ECU omits pending codes and drive-cycle readiness. |
| [`can_wrong_freeze_frame`](can_wrong_freeze_frame.scenario.json) | Mode 02 returns the wrong frame number despite otherwise valid framing. |
| [`can_wrong_monitor`](can_wrong_monitor.scenario.json) | The second Mode 06 result names a different monitor. |
| [`can_delayed_link_loss`](can_delayed_link_loss.scenario.json) | Seven-byte chunks, delayed RPM, a deliberate disconnection, and a request that stalls. |
| [`can_clear_acknowledged`](can_clear_acknowledged.scenario.json) | Both ECUs acknowledge, successive stored and pending scans are empty, readiness is incomplete, and the permanent code remains. |
| [`can_clear_negative`](can_clear_negative.scenario.json) | Both ECUs return final negative responses, followed by unchanged scripted readback. |
| [`can_clear_lost_ack`](can_clear_lost_ack.scenario.json) | The connection closes with no acknowledgment bytes. |
| [`can_clear_timeout`](can_clear_timeout.scenario.json) | The link stays open and sends no reply bytes. |
| [`can_clear_partial_ack`](can_clear_partial_ack.scenario.json) | Only one of two pre-scan responders acknowledges before the prompt. |
| [`can_clear_pending`](can_clear_pending.scenario.json) | One acknowledgment and a pending response from the other ECU, with no final reply or prompt. |

The separate [wire expectations](../docs/report-fixtures.md) give independent meanings for these synthetic bytes. Inspect adapter outputs and the decoded application separately.

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
