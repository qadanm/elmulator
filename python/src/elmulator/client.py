"""Test helpers for driving the emulator in a few lines.

- `Conversation` runs a scenario in-process with no sockets.
- `Client` connects to a running TCP server and reassembles replies.
- `serve_in_background` starts a server thread and returns its bound port.
"""

import argparse
import socket
import threading

from .server import EngineState, Scenario, normalize, serve


def _args(**overrides) -> argparse.Namespace:
    base = dict(host="127.0.0.1", port=0, echo="scenario", split=None,
                latency_ms=0, jitter_ms=0, seed=0, record=False)
    base.update(overrides)
    return argparse.Namespace(**base)


class Conversation:
    """Drive a scenario in-process, no sockets. The fastest way to check what
    a scripted adapter would reply.

        conv = Conversation(elmulator.load_bundled("p0420_basic"))
        assert "43 01 04 20" in conv.send("03")
    """

    def __init__(self, scenario: Scenario, **cfg):
        self._engine = EngineState(scenario, _args(record=True, **cfg))

    def send(self, command: str) -> str:
        pieces, _delay, _action, _matched = self._engine.plan(command)
        return "".join(pieces)

    @property
    def transcript(self) -> list:
        return self._engine.transcript


class Client:
    """A tiny TCP client for a running elmulator server (`serve` /
    `elmulator serve` / `elmulator-tcp`). Sends commands and reassembles each
    reply up to the ELM `>` prompt."""

    def __init__(self, host: str = "127.0.0.1", port: int = 0):
        self.host = host
        self.port = port
        self._sock = None

    def connect(self) -> None:
        self._sock = socket.create_connection((self.host, self.port), timeout=5)

    def send(self, command: str, timeout: float = 5.0) -> str:
        if self._sock is None:
            raise RuntimeError("not connected")
        self._sock.settimeout(timeout)
        self._sock.sendall((command + "\r").encode("ascii"))
        reply = ""
        while ">" not in reply:
            try:
                chunk = self._sock.recv(4096).decode("ascii", errors="replace")
            except socket.timeout as error:
                raise TimeoutError(f"no prompt for {command!r} within {timeout}s") from error
            if not chunk:
                raise ConnectionError(f"peer closed before a prompt for {command!r}")
            reply += chunk
        return reply

    def close(self) -> None:
        if self._sock is not None:
            self._sock.close()
            self._sock = None

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *exc):
        self.close()


def serve_in_background(scenario: Scenario, **cfg):
    """Start a server thread for a scenario. Returns (stop, port), where stop()
    shuts it down. Mirrors the in-process pattern used by self_test."""
    args = _args(**cfg)
    ready = threading.Event()
    stop = threading.Event()
    thread = threading.Thread(target=serve, args=(args, scenario, ready, stop), daemon=True)
    thread.start()
    if not ready.wait(timeout=5):
        raise RuntimeError("elmulator server did not start")

    def _stop():
        stop.set()
        thread.join(timeout=5)

    return _stop, args.port
