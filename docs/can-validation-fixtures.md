# CAN validation fixtures

These are deliberately specified synthetic facts, authored before integration with a consumer decoder. They are not captures, and contain no real VIN, device identifier, or user data. Elmulator only serves the authored bytes; it does not approve a consumer's interpretation.

| Fixture | Request | Required consumer outcome |
| --- | --- | --- |
| can_wrong_service | 03 | Reject response service 47; do not treat pending codes as stored. |
| can_invalid_hex | 03 | Reject non-hex GG; never turn it into empty success. |
| can_truncated_payload | 03 | Reject/incomplete: declared length 06 exceeds the four bytes supplied. |
| can_padded_rpm | 010C | RPM 1726, computed as (0x1A × 256 + 0xF8) / 4. Payload length 04 includes 41/0C/1A/F8; ignore the remaining padding. |

Framing reference: [ELM327 data sheet](https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DS.pdf), CAN formatting and OBD examples. The RPM formula is also independently represented in [Shiny.Obd command tests](https://github.com/shinyorg/obd/blob/0352328690724e220702f43be0b036e33e2aa38c/tests/Shiny.Obd.Tests/CommandTests.cs#L24-L40). These references are not a claim of comprehensive SAE/ISO conformance. The pinned `EngineRpmCommand.cs` implementation in the same revision also states and implements this formula. The fixture facts and bytes above are the oracle; changing a decoder must not change them.

The existing summary schema cannot express exact numeric telemetry or typed parse errors. Consequently, the padding fixture only asserts one live value in `expected_scan_summary`; consumers must separately assert 1726. Invalid cases omit `stored_codes` rather than encoding an empty list, and require a warning plus no no-code observation. `no_stored_codes_observation: false` means an all-clear claim is prohibited, not that a valid DTC was found.

Run `python3 scripts/build_bundled.py --check`, `swift test`, Python tests, and `conformance/run_conformance.py --swift-bin .build/debug/elmulator-tcp`. The Swift/Python byte tests intentionally contain literal expectations independent of the scenario JSON. Parity verifies byte delivery, not vehicle diagnostic correctness. Existing fixtures are unchanged. New fixtures need independent consumer/reviewer coverage before release.

Independent review (2026-11-13) reproduced 47 Swift tests, 15 Python tests and 11 TCP parity scenarios / 139 responses. All seven original scenarios and bundled entries were unchanged. The requested provenance-link correction is applied above. The reviewer also demonstrated that warning-only summary matching can accept a fabricated code alongside a warning; these fixtures therefore require consumer-level rejection assertions, not merely `summary_mismatches == []`. No consumer correctness or release approval is inferred.
