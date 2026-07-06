#!/usr/bin/env python3
"""Scriptable ELM327 TCP server.

Serves an obd2.sim_scenario.v1 scenario over localhost TCP so an app in a
simulator, or any TCP client in any language, can run a full OBD2 session
without a car. The matching, echo, splitting, and jitter semantics are the
same as the Swift `FakeELMScenarioEngine` — the two implementations are held
byte-for-byte equivalent by the conformance suite.

Pure Python standard library; no third-party dependencies.

Behavior:
  - prints "LISTENING <port>" on stdout once bound (port 0 picks a free port)
  - accepts one or more clients, each with its own scenario cursor state
  - reads commands until CR or LF; partial reads stay buffered
  - logs every command and reply timing to stderr
  - exits cleanly on SIGINT / Ctrl-C
"""

import argparse
import json
import selectors
import signal
import socket
import sys
import threading
import time
from pathlib import Path

POST_ACTIONS = ("none", "stall", "disconnect")


class SplitMix64:
    """Deterministic jitter source; clean-room SplitMix64."""

    MASK = (1 << 64) - 1

    def __init__(self, seed: int):
        self.state = seed & self.MASK

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & self.MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & self.MASK
        return z ^ (z >> 31)


class Scenario:
    def __init__(self, data: dict):
        if data.get("schema_version") != "obd2.sim_scenario.v1":
            raise ValueError(f"unsupported schema_version {data.get('schema_version')!r}")
        if data.get("synthetic") is not True:
            raise ValueError("scenario must declare synthetic true")
        self.scenario_id = data["scenario_id"]
        self.defaults = data["defaults"]
        self.stream_split_bytes = data.get("stream_split_bytes")
        self.commands = data["commands"]
        for command in self.commands:
            action = command.get("post_action", "none")
            if action not in POST_ACTIONS:
                raise ValueError(f"unknown post_action {action!r}")

    @classmethod
    def from_path(cls, path: Path) -> "Scenario":
        return cls(json.loads(Path(path).read_text(encoding="utf-8")))


def normalize(command: str) -> str:
    return "".join(command.upper().split())


class EngineState:
    """Per-connection cursor state, mirroring the Swift engine semantics:
    entries per request consume in order, the last entry repeats, and an
    entry with repeat true pins the cursor."""

    def __init__(self, scenario: Scenario, args):
        self.scenario = scenario
        self.args = args
        self.cursors = {}
        self.random = SplitMix64(args.seed)
        self.transcript = []

    def plan(self, raw_command: str):
        result = self._make_plan(raw_command)
        if getattr(self.args, "record", False):
            pieces, _delay, action, matched = result
            self.transcript.append({
                "raw_command": raw_command,
                "normalized": normalize(raw_command),
                "matched_request": matched,
                "reply": "".join(pieces),
                "post_action": action,
            })
        return result

    def _make_plan(self, raw_command: str):
        normalized = normalize(raw_command)
        entries = [
            command for command in self.scenario.commands
            if normalize(command["request"]) == normalized
        ]
        if not entries:
            return self._default_plan(normalized)

        cursor = self.cursors.get(normalized, 0)
        position = min(cursor, len(entries) - 1)
        command = entries[position]
        if not command.get("repeat", False):
            self.cursors[normalized] = min(position + 1, len(entries) - 1)

        echo = command.get("echo", False)
        if self.args.echo == "on":
            echo = True
        elif self.args.echo == "off":
            echo = False

        text = (normalized + "\r" if echo else "") + "".join(command["response_chunks"])
        pieces = self._split(text)
        first_delay = command.get("delay_ms", 0) + self.args.latency_ms + self._jitter()
        return pieces, first_delay, command.get("post_action", "none"), command["request"]

    def _default_plan(self, normalized: str):
        body = (
            self.scenario.defaults["at_response"]
            if normalized.startswith("AT")
            else self.scenario.defaults["obd_response"]
        )
        text = (normalized + "\r" if self.args.echo == "on" else "") + body
        return self._split(text), self.args.latency_ms + self._jitter(), "none", None

    def _jitter(self) -> int:
        if self.args.jitter_ms <= 0:
            return 0
        return self.random.next() % (self.args.jitter_ms + 1)

    def _split(self, text: str):
        pieces = [text] if text else []
        if self.scenario.stream_split_bytes:
            pieces = self._slice(pieces, [self.scenario.stream_split_bytes])
        if self.args.split:
            pieces = self._slice(pieces, self.args.split)
        return [piece for piece in pieces if piece]

    @staticmethod
    def _slice(pieces, sizes):
        result = []
        for piece in pieces:
            index = 0
            size_index = 0
            while index < len(piece):
                size = max(1, sizes[size_index % len(sizes)])
                result.append(piece[index:index + size])
                index += size
                size_index += 1
        return result


def log(message: str):
    print(f"[elmulator] {message}", file=sys.stderr, flush=True)


def handle_client(client: socket.socket, address, scenario: Scenario, args):
    engine = EngineState(scenario, args)
    buffer = ""
    log(f"client connected: {address}")
    try:
        while True:
            data = client.recv(4096)
            if not data:
                break
            buffer += data.decode("ascii", errors="replace")
            while True:
                cr = buffer.find("\r")
                lf = buffer.find("\n")
                cut = min(x for x in (cr, lf) if x >= 0) if (cr >= 0 or lf >= 0) else -1
                if cut < 0:
                    break
                line, buffer = buffer[:cut].strip(), buffer[cut + 1:]
                if not line:
                    continue
                started = time.monotonic()
                pieces, first_delay, action, matched = engine.plan(line)
                if action == "stall":
                    log(f"{line!r} -> stall (no reply)")
                    continue
                for index, piece in enumerate(pieces):
                    delay = first_delay if index == 0 else 0
                    if delay > 0:
                        time.sleep(delay / 1000.0)
                    client.sendall(piece.encode("ascii"))
                elapsed_ms = int((time.monotonic() - started) * 1000)
                source = "scenario" if matched else "default"
                log(f"{line!r} -> {sum(len(p) for p in pieces)} bytes in {len(pieces)} piece(s), {elapsed_ms}ms ({source})")
                if action == "disconnect":
                    log(f"{line!r} -> disconnect (scenario action)")
                    return
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        client.close()
        log(f"client closed: {address}")


def serve(args, scenario: Scenario, ready_event=None, stop_event=None):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.host, args.port))
    server.listen(4)
    bound_port = server.getsockname()[1]
    print(f"LISTENING {bound_port}", flush=True)
    log(f"scenario {scenario.scenario_id!r} on {args.host}:{bound_port}")
    if ready_event is not None:
        args.port = bound_port
        ready_event.set()

    selector = selectors.DefaultSelector()
    selector.register(server, selectors.EVENT_READ)
    threads = []
    try:
        while stop_event is None or not stop_event.is_set():
            if not selector.select(timeout=0.2):
                continue
            client, address = server.accept()
            thread = threading.Thread(
                target=handle_client,
                args=(client, address, scenario, args),
                daemon=True,
            )
            thread.start()
            threads.append(thread)
    except KeyboardInterrupt:
        log("interrupted, shutting down")
    finally:
        selector.close()
        server.close()
    return 0


def run_serve(args) -> int:
    """Entry point used by the `elmulator serve` CLI subcommand. `args.scenario`
    can be a file path or the name of a bundled example scenario."""
    path = Path(args.scenario)
    try:
        if path.exists():
            scenario = Scenario.from_path(path)
        else:
            from ._bundled import BUNDLED
            if args.scenario not in BUNDLED:
                log(f"scenario not found: {args.scenario!r} (not a file, not a bundled name)")
                return 2
            scenario = Scenario(json.loads(BUNDLED[args.scenario]))
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        log(f"scenario load failed: {error}")
        return 2
    signal.signal(signal.SIGINT, signal.default_int_handler)
    return serve(args, scenario)


# A tiny, fully self-contained scenario so `self-test` works even when the
# package is pip-installed and no example files are on disk.
SELF_TEST_SCENARIO = {
    "schema_version": "obd2.sim_scenario.v1",
    "scenario_id": "self_test",
    "synthetic": True,
    "description": "inline loopback self-test scenario",
    "adapter_profile": "elm327_like_tcp",
    "defaults": {"at_response": "OK\r\r>", "obd_response": "NO DATA\r\r>"},
    "stream_split_bytes": None,
    "warnings": [],
    "commands": [
        {"request": "ATZ", "response_chunks": ["ELM327 v1.5\r\r>"], "echo": True, "prompt": True},
        {"request": "03", "response_chunks": ["43 01 04 20\r\r>"], "prompt": True},
    ],
    "expected_scan_summary": {},
}


def _self_test_args():
    return argparse.Namespace(
        host="127.0.0.1", port=0, echo="scenario",
        split=None, latency_ms=0, jitter_ms=0, seed=0,
    )


def self_test() -> int:
    """Loopback check: serve the inline scenario on an ephemeral port, speak a
    short ELM conversation, and verify echo, prompt, defaults, and code bytes."""
    scenario = Scenario(SELF_TEST_SCENARIO)
    args = _self_test_args()
    ready = threading.Event()
    stop = threading.Event()
    server_thread = threading.Thread(
        target=serve, args=(args, scenario, ready, stop), daemon=True
    )
    server_thread.start()
    if not ready.wait(timeout=5):
        print("SELF-TEST FAIL: server did not start")
        return 1

    failures = []

    def exchange(sock, command: str) -> str:
        sock.sendall((command + "\r").encode("ascii"))
        reply = ""
        while ">" not in reply:
            chunk = sock.recv(4096).decode("ascii")
            if not chunk:
                failures.append(f"{command}: connection closed before prompt")
                return reply
            reply += chunk
        return reply

    try:
        with socket.create_connection(("127.0.0.1", args.port), timeout=5) as sock:
            reset = exchange(sock, "ATZ")
            if not reset.startswith("ATZ\r"):
                failures.append(f"ATZ echo missing: {reset!r}")
            if "ELM327 v1.5" not in reset:
                failures.append(f"ATZ banner missing: {reset!r}")
            for setup in ("ATE0", "ATL0", "ATH1", "ATSP0"):
                reply = exchange(sock, setup)
                if "OK" not in reply:
                    failures.append(f"{setup} expected OK: {reply!r}")
            stored = exchange(sock, "03")
            if "43 01 04 20" not in stored:
                failures.append(f"03 expected P0420 bytes: {stored!r}")
            unknown = exchange(sock, "0142")
            if "NO DATA" not in unknown:
                failures.append(f"0142 expected default NO DATA: {unknown!r}")
    except OSError as error:
        failures.append(f"socket error: {error}")
    finally:
        stop.set()
        server_thread.join(timeout=5)

    if failures:
        for failure in failures:
            print(f"SELF-TEST FAIL: {failure}")
        return 1
    print("SELF-TEST OK")
    return 0
