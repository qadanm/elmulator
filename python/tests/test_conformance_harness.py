"""Regression tests for conformance/run_conformance.py.

These pin two independent properties of the cross-language harness:

* startup is genuinely bounded and always reaps the child, and
* the expected reply bytes/termination are derived from scenario facts, not
  from whichever server happens to answer first.
"""

import importlib.util
import json
import socket
import sys
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = REPO_ROOT / "scenarios"


def _load_harness():
    spec = importlib.util.spec_from_file_location(
        "run_conformance", REPO_ROOT / "conformance" / "run_conformance.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


harness = _load_harness()


@pytest.fixture
def tracked_popen(monkeypatch):
    """Record every child so tests can assert it was reaped, not leaked."""
    created = []
    real_popen = harness.subprocess.Popen

    def tracking_popen(*args, **kwargs):
        proc = real_popen(*args, **kwargs)
        created.append(proc)
        return proc

    monkeypatch.setattr(harness.subprocess, "Popen", tracking_popen)
    return created


def _scenario(**overrides):
    base = {
        "schema_version": "obd2.sim_scenario.v1",
        "scenario_id": "inline",
        "synthetic": True,
        "description": "synthetic harness fixture",
        "adapter_profile": "elm327_like_tcp",
        "defaults": {"at_response": "OK\r\r>", "obd_response": "NO DATA\r\r>"},
        "warnings": [],
        "commands": [],
        "expected_scan_summary": {},
    }
    base.update(overrides)
    return base


def _load(name):
    return json.loads((SCENARIOS / f"{name}.scenario.json").read_text(encoding="utf-8"))


def test_silent_child_fails_within_deadline_and_is_reaped(tracked_popen):
    code = "import time; time.sleep(30)"
    started = time.monotonic()
    with pytest.raises(harness.StartupError) as excinfo:
        harness.start_server([sys.executable, "-c", code], timeout=0.4)
    elapsed = time.monotonic() - started

    assert elapsed < 5
    assert "no output" in str(excinfo.value)
    assert len(tracked_popen) == 1
    assert tracked_popen[0].poll() is not None


def test_premature_exit_reports_code_and_reaps(tracked_popen):
    code = "import sys; print('booting'); sys.exit(3)"
    with pytest.raises(harness.StartupError) as excinfo:
        harness.start_server([sys.executable, "-c", code], timeout=5)

    assert "exit 3" in str(excinfo.value)
    assert tracked_popen[0].poll() == 3


@pytest.mark.parametrize(
    "announcement",
    ["LISTENING nope", "LISTENING", "LISTENING 0", "LISTENING 70000", "LISTENING 1 2"],
)
def test_malformed_announcement_is_rejected(announcement, tracked_popen):
    code = f"print({announcement!r}); import sys; sys.stdout.flush(); sys.exit(0)"
    with pytest.raises(harness.StartupError):
        harness.start_server([sys.executable, "-c", code], timeout=5)
    assert tracked_popen[0].poll() is not None


def test_healthy_server_starts_and_is_terminated():
    scenario = SCENARIOS / "p0420_basic.scenario.json"
    cmd = [sys.executable, "-m", "elmulator", "serve", str(scenario), "--port", "0"]
    proc, port = harness.start_server(cmd, timeout=10)
    try:
        assert 1 <= port <= 65535
        with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
            sock.sendall(b"ATZ\r")
            reply, closed = harness.read_reply(sock)
        assert b"ELM327 v1.5" in reply
        assert not closed
    finally:
        harness.terminate(proc)
    assert proc.poll() is not None
    if proc.stdout is not None:
        assert proc.stdout.closed


def test_adapter_disconnect_expectations_cover_stall_disconnect_and_skip():
    scenario = _load("adapter_disconnect")
    commands = harness.command_sequence(scenario)
    expected = harness.command_expectations(scenario)
    assert len(expected) == len(commands)

    seen = {}
    for command, want in zip(commands, expected):
        seen.setdefault(harness.normalize(command), []).append(want)

    assert seen["0100"][0] == harness.Expected(b"", "stall")
    assert seen["0100"][1].termination == "prompt"
    assert seen["03"][0] == harness.Expected(b"", "disconnect")
    assert seen["ATDPN"][0] == harness.Expected(b"", "skipped")
    assert seen["0142"][0] == harness.Expected(b"", "skipped")


def test_default_path_classifies_at_versus_obd():
    scenario = _scenario(
        commands=[{"request": "XYZZY", "response_chunks": ["NOPE\r\r>"]}],
        defaults={"at_response": "AT-DEFAULT\r\r>", "obd_response": "OBD-DEFAULT\r\r>"},
    )
    expected = harness.command_expectations(scenario)
    assert expected[1:] == [
        harness.Expected(b"AT-DEFAULT\r\r>", "prompt"),
        harness.Expected(b"OBD-DEFAULT\r\r>", "prompt"),
    ]


def test_repeat_true_pins_cursor_while_last_entry_still_repeats():
    pinned = _scenario(
        commands=[
            {"request": "0100", "response_chunks": ["A\r\r>"], "repeat": True},
            {"request": "0100", "response_chunks": ["B\r\r>"]},
        ]
    )
    expected = harness.command_expectations(pinned)
    assert expected[0] == harness.Expected(b"A\r\r>", "prompt")
    assert expected[1] == harness.Expected(b"A\r\r>", "prompt")

    capped = _scenario(
        commands=[
            {"request": "0100", "response_chunks": ["A\r\r>"]},
            {"request": "0100", "response_chunks": ["B\r\r>"]},
            {"request": "0100", "response_chunks": ["C\r\r>"]},
        ]
    )
    data = [item.data for item in harness.command_expectations(capped)[:3]]
    assert data == [b"A\r\r>", b"B\r\r>", b"C\r\r>"]


def test_echo_prefix_and_prompt_termination_are_explicit():
    scenario = _scenario(
        commands=[
            {"request": "ATZ", "response_chunks": ["ELM327 v1.5\r\r>"], "echo": True},
            {"request": "0100", "response_chunks": ["SEARCHING...\r7E8 06 41 00 BE 3E B8 11\r\r>"]},
        ]
    )
    expected = harness.command_expectations(scenario)
    assert expected[0].data == b"ATZ\rELM327 v1.5\r\r>"
    assert expected[0].termination == "prompt"
    assert expected[1].data.startswith(b"SEARCHING...\r")
    assert expected[1].termination == "prompt"


def test_reply_problem_flags_bytes_and_termination_mismatches():
    prompt = harness.Expected(b"OK\r\r>", "prompt")
    assert harness.reply_problem(prompt, harness.Reply(b"OK\r\r>", False, False)) is None
    assert "bytes differ" in harness.reply_problem(
        prompt, harness.Reply(b"NO\r\r>", False, False)
    )
    stall = harness.Expected(b"", "stall")
    assert harness.reply_problem(stall, harness.Reply(b"", False, False)) is None
    assert "closed" in harness.reply_problem(stall, harness.Reply(b"", True, False))
    drop = harness.Expected(b"bye\r\r", "disconnect")
    assert "did not close" in harness.reply_problem(
        drop, harness.Reply(b"bye\r\r", False, False)
    )
