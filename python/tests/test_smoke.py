"""Smoke tests for the elmulator Python package.

Pure stdlib + pytest; no network fixtures beyond localhost loopback.
"""

import socket
import threading
from pathlib import Path

import elmulator
from elmulator import (
    Client, Conversation, Scenario, bundled_names, build_scenario,
    load_bundled, self_test, serve_in_background, summary_mismatches,
)
from elmulator import server as srv
from elmulator import validate as vld

REPO_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = REPO_ROOT / "scenarios"


def test_self_test_passes():
    assert self_test() == 0


def test_bundled_names_and_load():
    assert "p0420_basic" in bundled_names()
    assert len(bundled_names()) == 7
    scenario = load_bundled("p0420_basic")
    assert scenario.scenario_id == "p0420_basic"


def test_conversation_in_process():
    conv = Conversation(load_bundled("p0420_basic"))
    assert "ELM327 v1.5" in conv.send("ATZ")
    assert "43 01 04 20" in conv.send("03")
    assert conv.send("0142") == "NO DATA\r\r>"       # default path
    assert len(conv.transcript) == 3


def test_client_over_serve_in_background():
    stop, port = serve_in_background(load_bundled("p0420_basic"))
    try:
        with Client(port=port) as client:
            assert "ELM327 v1.5" in client.send("ATZ")
            assert "43 01 04 20" in client.send("03")
    finally:
        stop()


def test_build_scenario_drives_engine():
    scenario = Scenario(build_scenario("inline", [
        {"request": "ATZ", "response_chunks": ["ELM327 v1.5\r\r>"], "echo": True},
        {"request": "03", "response_chunks": ["7E8 04 43 01 04 20\r\r>"]},
    ]))
    assert "43 01 04 20" in Conversation(scenario).send("03")


def test_summary_mismatches():
    expected = {"stored_codes": ["P0420"], "mil_reported_on": True, "min_session_warnings": 1}
    assert summary_mismatches(expected, {
        "stored_codes": ["P0420"], "mil_reported_on": True, "session_warnings": 2,
    }) == []
    diffs = summary_mismatches(expected, {
        "stored_codes": ["P0301"], "mil_reported_on": True, "session_warnings": 0,
    })
    fields = {d["field"] for d in diffs}
    assert "stored_codes" in fields
    assert "min_session_warnings" in fields
    assert "vin_reported" not in fields


def test_validate_falls_back_to_bundled(monkeypatch):
    monkeypatch.setattr(vld, "BUNDLED_SCENARIOS", Path("/nonexistent-scenarios"))
    assert vld.run() == 0


def test_serve_accepts_bundled_name(monkeypatch):
    import argparse
    args = argparse.Namespace(scenario="p0420_basic", host="127.0.0.1", port=0,
                              echo="scenario", split=None, latency_ms=0, jitter_ms=0, seed=0)
    stop = threading.Event()
    ready = threading.Event()
    # run_serve resolves the bundled name, then serve() binds and sets ready.
    import elmulator.server as server

    def fake_serve(a, scenario, ready_event=None, stop_event=None):
        assert scenario.scenario_id == "p0420_basic"
        if ready_event:
            ready_event.set()
        return 0

    monkeypatch.setattr(server, "serve", fake_serve)
    monkeypatch.setattr(server.signal, "signal", lambda *a, **k: None)
    assert server.run_serve(args) == 0


def test_bundled_scenarios_validate():
    assert vld.run([str(SCENARIOS)]) == 0


def test_normalize_is_case_and_space_insensitive():
    assert srv.normalize(" at z \r") == "ATZ"
    assert srv.normalize("0 1 0 0") == "0100"


def _args(**overrides):
    import argparse
    base = dict(host="127.0.0.1", port=0, echo="scenario",
                split=None, latency_ms=0, jitter_ms=0, seed=0)
    base.update(overrides)
    return argparse.Namespace(**base)


def test_p0420_scan_over_tcp():
    scenario = Scenario.from_path(SCENARIOS / "p0420_basic.scenario.json")
    args = _args()
    ready, stop = threading.Event(), threading.Event()
    thread = threading.Thread(target=srv.serve, args=(args, scenario, ready, stop), daemon=True)
    thread.start()
    assert ready.wait(timeout=5)

    def exchange(sock, command):
        sock.sendall((command + "\r").encode("ascii"))
        reply = ""
        while ">" not in reply:
            chunk = sock.recv(4096).decode("ascii")
            if not chunk:
                break
            reply += chunk
        return reply

    try:
        with socket.create_connection(("127.0.0.1", args.port), timeout=5) as sock:
            assert "ELM327 v1.5" in exchange(sock, "ATZ")
            assert "43 01 04 20" in exchange(sock, "03")  # P0420 stored code bytes
            assert "NO DATA" in exchange(sock, "0142")     # falls through to default
    finally:
        stop.set()
        thread.join(timeout=5)
