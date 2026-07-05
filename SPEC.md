# The `obd2.sim_scenario.v1` scenario format

A **scenario** is a JSON file describing a synthetic ELM327 conversation. It is the public contract of elmulator: every server (Python TCP, Swift TCP, Swift BLE peripheral, in-process fake central) consumes the same format with identical semantics, and the [conformance suite](conformance/) holds implementations to byte-for-byte parity.

- Machine-readable schema: [`spec/obd2.sim_scenario.v1.schema.json`](spec/obd2.sim_scenario.v1.schema.json) (JSON Schema 2020-12)
- Worked examples: [`scenarios/`](scenarios/)

File names end in `.scenario.json`, and the base name must equal `scenario_id`.

## Conventions

- All strings are ASCII. `\r` (carriage return) and `\n` (line feed) appear literally in `response_chunks` and default replies; ELM adapters terminate lines with `\r` and end a reply with the prompt character `>`.
- **Command matching is normalized**: uppercase, with all whitespace (spaces, `\r`, `\n`) removed. So `atz`, `AT Z`, and `ATZ\r` all match a `request` of `"ATZ"`.
- Numbers are integers. Durations are milliseconds.

## Top-level fields

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schema_version` | string | yes | Must be exactly `"obd2.sim_scenario.v1"`. |
| `scenario_id` | string | yes | Must match the file name without `.scenario.json`. |
| `synthetic` | boolean | yes | Must be `true`. A loader must refuse anything else — emulated bytes must never masquerade as real vehicle data. |
| `description` | string | yes | Human-readable summary (non-empty). |
| `adapter_profile` | string | yes | Free-form label for the behavior being emulated, e.g. `"elm327_like_tcp"`. |
| `defaults` | object | yes | Replies for unmatched commands (see below). |
| `stream_split_bytes` | integer \| null | no | If set (positive), split **every** reply into chunks of at most this many bytes. Simulates BLE notification / TCP segment sizes. Default `null`. |
| `warnings` | string[] | yes | Notes about intentional quirks (may be empty). Informational only. |
| `commands` | object[] | yes | The scripted conversation, in order. Non-empty. |
| `expected_scan_summary` | object | yes | Consumer-defined oracle (see below). May be empty. |

### `defaults`

```json
{ "at_response": "OK\r\r>", "obd_response": "NO DATA\r\r>" }
```

When an incoming command matches no entry in `commands`, the engine replies with `at_response` if the normalized command starts with `AT`, otherwise `obd_response`. Both keys are required.

## Commands

Each entry in `commands`:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `request` | string | — | The command this entry answers (matched normalized). Required. |
| `response_chunks` | string[] | — | Reply payload pieces, concatenated in order. Required (may be empty for a stall). |
| `delay_ms` | integer ≥ 0 | `0` | Delay before the **first** chunk of this reply. |
| `echo` | boolean | `false` | Prepend the normalized request + `\r` to the reply (ELM echo). |
| `prompt` | boolean | `true` | Whether the reply ends at the prompt `>`. Used by the validator to sanity-check chunk content; it does not itself append `>`. |
| `post_action` | `"none"`\|`"stall"`\|`"disconnect"` | `"none"` | Transport behavior after the reply (see below). |
| `repeat` | boolean | `false` | Keep answering with this entry on every later match. |

### Ordered consumption and `repeat`

Multiple entries may share the same `request`. They are consumed **in order**: the first match returns the first entry, the next match the second, and so on. The cursor caps at the last entry, so **the last matching entry repeats indefinitely** — re-polling a PID never goes silent. An entry with `repeat: true` pins the cursor at that entry so it answers every subsequent match.

This is how a scenario models, e.g., a command that times out once and then succeeds on retry (`adapter_disconnect`), or live data that can be polled repeatedly.

### Reply assembly order

For a matched entry, the reply bytes are built as:

1. Optionally the echo prefix (`normalized request` + `\r`) if `echo` (or a host echo override) is on.
2. `response_chunks` joined.
3. The result is split, in this order: first by the authored chunk boundaries, then by `stream_split_bytes` (if set), then by any host-provided split pattern (e.g. `--split 1,2,5`).
4. `delay_ms` + any host latency + deterministic jitter is applied before the first piece only.

Splitting only changes **how the bytes are framed on the wire**, never their content — a correct client reassembles the identical stream regardless of chunking.

### Post-actions

- `none` — send the reply; the connection stays open.
- `stall` — send nothing and take no further action, forcing the client's session to time out and (typically) retry. A stall entry must have empty `response_chunks` and `prompt: false`.
- `disconnect` — send any chunks, then close the connection. Forces the client to observe a dropped link.

## `expected_scan_summary`

An optional oracle block. **The emulator never reads it.** It records what a consuming scan/decoder should conclude after running the whole scenario, so each scenario is self-checking in that consumer's tests. All keys are optional:

| Key | Type | Meaning |
|---|---|---|
| `stored_codes` | string[] | Expected stored DTCs, e.g. `["P0420"]`. |
| `pending_codes` | string[] | Expected pending DTCs. |
| `permanent_codes` | string[] | Expected permanent DTCs. |
| `mil_reported_on` | boolean | Whether the malfunction indicator lamp reads on. |
| `vin_reported` | boolean | Whether a VIN was retrieved. |
| `live_value_count` | integer | Number of live PID values decoded. |
| `min_session_warnings` | integer | Minimum robustness/parse warnings expected. |
| `no_stored_codes_observation` | boolean | Whether a "no codes" result was explicitly observed. |
| `scan_error` | string | Typed terminal error name, if the scan is expected to fail. |

Because these are consumer-defined, the format stays a clean wire-level contract while still letting a scenario carry its own regression expectations. Decoder/parsing logic lives in the consuming app, not here.

## Validation

Validate scenarios two ways:

```bash
# Hand-rolled validator, pure stdlib, no dependencies:
elmulator validate path/to/scenarios/

# Or with any JSON Schema 2020-12 validator against spec/obd2.sim_scenario.v1.schema.json
```

Both enforce the same rules; the JSON Schema is the normative reference and the validator additionally checks file-name/`scenario_id` agreement and prompt/stall/disconnect chunk consistency.

## Versioning

The `schema_version` string is the contract version. Backward-compatible additions (new optional fields) may appear under the same `v1` id; a breaking change bumps to `obd2.sim_scenario.v2`. Implementations must reject a `schema_version` they do not recognize.
