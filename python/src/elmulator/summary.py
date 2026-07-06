"""Compare a decoded scan against a scenario's expected_scan_summary.

elmulator emits bytes only and never decodes OBD2, so `expected_scan_summary`
is the consuming app's own interpretation of a scan. This diffs the values you
pass against the scenario's declared expectations.
"""

_KEYS = [
    "stored_codes", "pending_codes", "permanent_codes", "mil_reported_on",
    "vin_reported", "live_value_count", "no_stored_codes_observation", "scan_error",
]


def summary_mismatches(expected: dict, observed: dict) -> list:
    """Return a list of {field, expected, observed} for each expectation the
    observed scan does not satisfy. Only keys present (non-None) in `expected`
    are checked; anything else is "don't care". `min_session_warnings` is a
    lower bound; the observed count is read from `session_warnings`.
    """
    result = []
    for key in _KEYS:
        want = expected.get(key)
        if want is None:
            continue
        got = observed.get(key)
        if got != want:
            result.append({"field": key, "expected": want, "observed": got})

    min_warnings = expected.get("min_session_warnings")
    if min_warnings is not None:
        seen = observed.get("session_warnings", 0) or 0
        if seen < min_warnings:
            result.append({"field": "min_session_warnings", "expected": f">={min_warnings}", "observed": seen})

    return result
