"""Smoke tests for the elmulator Python package.

Pure stdlib + pytest; no network fixtures beyond localhost loopback.
"""

import socket
import threading
from pathlib import Path

from elmulator import Scenario, self_test
from elmulator import server as srv
from elmulator import validate as vld

REPO_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = REPO_ROOT / "scenarios"


def test_self_test_passes():
    assert self_test() == 0


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
