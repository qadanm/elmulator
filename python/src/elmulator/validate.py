#!/usr/bin/env python3
"""Validates obd2.sim_scenario.v1 scenario files.

Checks:
  - JSON parses and schema_version is obd2.sim_scenario.v1
  - required fields present, synthetic is true
  - scenario_id matches the file name
  - command entries are well formed (request, chunks, delays, actions)
  - prompt-terminated entries actually contain the prompt character
  - stall entries have no chunks and no prompt
  - expected_scan_summary uses only known keys
  - stream_split_bytes is null or a positive integer

Exit 0 clean, 1 violations.
"""

import json
import sys
from pathlib import Path

# The bundled example library, relative to this source file in the repo.
# (python/src/elmulator/validate.py -> repo root -> scenarios/)
BUNDLED_SCENARIOS = Path(__file__).resolve().parents[3] / "scenarios"

REQUIRED_FIELDS = {
    "schema_version", "scenario_id", "synthetic", "description",
    "adapter_profile", "defaults", "commands", "expected_scan_summary",
    "warnings",
}
POST_ACTIONS = {"none", "stall", "disconnect"}
SUMMARY_KEYS = {
    "stored_codes", "pending_codes", "permanent_codes", "mil_reported_on",
    "vin_reported", "live_value_count", "min_session_warnings",
    "no_stored_codes_observation", "scan_error",
}


def validate(path: Path) -> list:
    problems = []
    try:
        scenario = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"{path.name}: invalid JSON: {error}"]

    missing = REQUIRED_FIELDS - scenario.keys()
    if missing:
        problems.append(f"{path.name}: missing fields {sorted(missing)}")
        return problems

    if scenario["schema_version"] != "obd2.sim_scenario.v1":
        problems.append(f"{path.name}: unknown schema_version")
    if scenario["synthetic"] is not True:
        problems.append(f"{path.name}: synthetic must be true")
    expected_id = path.name.removesuffix(".scenario.json")
    if scenario["scenario_id"] != expected_id:
        problems.append(f"{path.name}: scenario_id {scenario['scenario_id']!r} does not match file name")
    if not scenario["description"].strip():
        problems.append(f"{path.name}: empty description")

    defaults = scenario["defaults"]
    for key in ("at_response", "obd_response"):
        if not defaults.get(key):
            problems.append(f"{path.name}: defaults missing {key}")

    split = scenario.get("stream_split_bytes")
    if split is not None and (not isinstance(split, int) or split < 1):
        problems.append(f"{path.name}: stream_split_bytes must be null or a positive integer")

    if not scenario["commands"]:
        problems.append(f"{path.name}: no commands")
    for index, command in enumerate(scenario["commands"]):
        label = f"{path.name} command {index}"
        request = command.get("request", "")
        if not request.strip():
            problems.append(f"{label}: empty request")
        chunks = command.get("response_chunks")
        if not isinstance(chunks, list) or not all(isinstance(chunk, str) for chunk in chunks):
            problems.append(f"{label}: response_chunks must be a list of strings")
            continue
        delay = command.get("delay_ms", 0)
        if not isinstance(delay, int) or delay < 0:
            problems.append(f"{label}: delay_ms must be a non-negative integer")
        action = command.get("post_action", "none")
        if action not in POST_ACTIONS:
            problems.append(f"{label}: unknown post_action {action!r}")
        prompt = command.get("prompt", True)
        joined = "".join(chunks)
        if action == "stall":
            if chunks:
                problems.append(f"{label}: stall entries must have no response_chunks")
            if prompt:
                problems.append(f"{label}: stall entries must set prompt false")
        elif action == "disconnect":
            if prompt and ">" not in joined:
                problems.append(f"{label}: prompt true but no '>' before disconnect")
        else:
            if prompt and ">" not in joined:
                problems.append(f"{label}: prompt true but chunks contain no '>'")
            if not prompt and ">" in joined:
                problems.append(f"{label}: prompt false but chunks contain '>'")

    unknown = set(scenario["expected_scan_summary"].keys()) - SUMMARY_KEYS
    if unknown:
        problems.append(f"{path.name}: unknown expected_scan_summary keys {sorted(unknown)}")

    return problems


def _collect(paths) -> list:
    """Expand file and directory arguments into a sorted list of scenarios."""
    files = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            files.extend(sorted(path.glob("*.scenario.json")))
        else:
            files.append(path)
    return files


def run(paths=None) -> int:
    """Entry point used by the `elmulator validate` CLI subcommand.

    With no paths, validates the bundled example library (repo checkout).
    """
    if paths:
        files = _collect(paths)
    else:
        files = sorted(BUNDLED_SCENARIOS.glob("*.scenario.json"))
        if not files:
            print("FAIL: no scenario paths given and no bundled examples found")
            return 1

    if not files:
        print("FAIL: no scenario files found")
        return 1

    problems = []
    for path in files:
        problems.extend(validate(path))
    if problems:
        for problem in problems:
            print(f"SCENARIO VALIDATION: {problem}")
        print(f"FAIL: {len(problems)} problem(s)")
        return 1
    print(f"OK: {len(files)} scenario(s) validated")
    return 0


def main() -> int:
    return run(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
