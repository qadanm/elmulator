"""elmulator: a scriptable Bluetooth LE and TCP OBD2 (ELM327) adapter emulator.

The Python package provides the language-neutral TCP server, the scenario
validator, a test client, and the bundled example scenarios. See the
`elmulator` console command (`elmulator --help`).
"""

from __future__ import annotations

import json as _json

from . import _bundled
from .client import Client, Conversation, serve_in_background
from .server import EngineState, Scenario, normalize, self_test, serve
from .summary import summary_mismatches

__all__ = [
    "Scenario", "EngineState", "normalize", "serve", "self_test",
    "Conversation", "Client", "serve_in_background",
    "load_bundled", "bundled_names", "build_scenario", "summary_mismatches",
    "__version__",
]

__version__ = "0.3.1"


def bundled_names() -> list:
    """The ids of the built-in example scenarios."""
    return sorted(_bundled.BUNDLED)


def load_bundled(name: str) -> Scenario:
    """Load a built-in example scenario by name, for example
    `elmulator.load_bundled("p0420_basic")`. Works from a pip-installed wheel."""
    if name not in _bundled.BUNDLED:
        raise KeyError(f"unknown bundled scenario: {name!r}")
    return Scenario(_json.loads(_bundled.BUNDLED[name]))


def build_scenario(
    scenario_id: str,
    commands: list,
    *,
    description: str = "",
    adapter_profile: str = "elm327_like_tcp",
    defaults: dict | None = None,
    stream_split_bytes: int | None = None,
    warnings: list | None = None,
    expected_scan_summary: dict | None = None,
) -> dict:
    """Build a scenario dict in code (pass it to `Scenario(...)`), so a test
    needs no JSON file."""
    return {
        "schema_version": "obd2.sim_scenario.v1",
        "scenario_id": scenario_id,
        "synthetic": True,
        "description": description,
        "adapter_profile": adapter_profile,
        "defaults": defaults or {"at_response": "OK\r\r>", "obd_response": "NO DATA\r\r>"},
        "stream_split_bytes": stream_split_bytes,
        "warnings": warnings or [],
        "commands": commands,
        "expected_scan_summary": expected_scan_summary or {},
    }
