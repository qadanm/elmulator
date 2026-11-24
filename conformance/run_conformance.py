#!/usr/bin/env python3
"""Cross-implementation conformance suite for obd2.sim_scenario.v1.

For every example scenario, this drives an identical command sequence against
two servers and asserts the reply byte streams are identical:

  - the Python server  (`elmulator serve`)
  - the Swift server    (`elmulator-tcp`, if a binary is provided)

This is what makes the scenario format a real specification rather than one
implementation's behavior: expected reply bytes and termination are derived
directly from each scenario (never from a server), and any new implementation
(Kotlin, Rust, ...) can be dropped in here and held to that oracle plus
byte-for-byte parity with the others.

Usage:
  python3 conformance/run_conformance.py [--swift-bin PATH] [--scenarios DIR]

With no --swift-bin, it runs the Python server against itself (a determinism
check) so the suite is still meaningful on Linux CI without a Swift toolchain.
"""

from __future__ import annotations

import argparse
import json
import queue
import socket
import subprocess
import sys
import threading
import time
from typing import NamedTuple
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCENARIOS = REPO_ROOT / "scenarios"
IDLE_TIMEOUT = 0.5  # seconds of silence that marks the end of a reply
STARTUP_TIMEOUT = 10.0  # seconds to wait for the child's LISTENING announcement


class StartupError(RuntimeError):
    """The child never produced a usable 'LISTENING <port>' announcement."""


def terminate(proc) -> None:
    """Stop and reap a child on every exit path, then close its stdout pipe."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    if proc.stdout is not None:
        proc.stdout.close()


def start_server(cmd, timeout: float = STARTUP_TIMEOUT) -> tuple:
    """Launch a server subprocess and parse its 'LISTENING <port>' line.

    Reading happens on a daemon thread so a child that never writes anything
    cannot block the deadline. Any non-zero exit, malformed announcement,
    timeout, or port out of range fails promptly and reaps the child.
    """
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    lines: queue.Queue = queue.Queue()

    def pump() -> None:
        try:
            for line in proc.stdout:
                lines.put(line)
        except (OSError, ValueError):
            pass
        finally:
            lines.put(None)

    threading.Thread(target=pump, daemon=True, name="conformance-stdout").start()
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise StartupError(
                    f"server did not announce a port within {timeout:g}s: "
                    f"{' '.join(str(c) for c in cmd)}"
                )
            try:
                line = lines.get(timeout=remaining)
            except queue.Empty:
                raise StartupError(
                    f"server produced no output within {timeout:g}s: "
                    f"{' '.join(str(c) for c in cmd)}"
                ) from None
            if line is None:
                code = proc.poll()
                raise StartupError(
                    f"server exited before announcing a port (exit {code}): "
                    f"{' '.join(str(c) for c in cmd)}"
                )
            stripped = line.strip()
            if not stripped.startswith("LISTENING"):
                continue
            parts = stripped.split()
            if len(parts) != 2:
                raise StartupError(f"malformed port announcement {stripped!r}")
            try:
                port = int(parts[1])
            except ValueError:
                raise StartupError(f"malformed port announcement {stripped!r}") from None
            if not 1 <= port <= 65535:
                raise StartupError(f"announced port out of range: {port}")
            return proc, port
    except BaseException:
        terminate(proc)
        raise


def read_reply(sock, *, wait_for_close: bool = False) -> tuple:
    """Read one reply as ``(bytes, closed)``: up to the ELM prompt, or until
    the peer goes silent (a stall) or closes (a disconnect)."""
    sock.settimeout(IDLE_TIMEOUT)
    data = b""
    while True:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            return data, False
        except ConnectionResetError:
            return data, True
        if not chunk:
            return data, True
        data += chunk
        if b">" in chunk and not wait_for_close:
            return data, False


class Reply(NamedTuple):
    data: bytes
    closed: bool
    skipped: bool  # an earlier command ended the connection


def drive(port: int, commands, expectations) -> list:
    """Send each command and collect ``Reply`` records, in order."""
    replies = []
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        dead = False
        for command, expected in zip(commands, expectations):
            if dead:
                replies.append(Reply(b"", True, True))
                continue
            try:
                sock.sendall((command + "\r").encode("ascii"))
                data, closed = read_reply(sock, wait_for_close=expected.termination == "disconnect")
            except OSError:
                data, closed = b"", True
            # Peer closed the connection (a scenario disconnect). Every later
            # command sees the same dead socket on both servers.
            dead = closed
            replies.append(Reply(data, closed, False))
    return replies


def command_sequence(scenario: dict) -> list:
    """The scenario's own commands in order, plus a couple of unmatched ones
    to exercise the AT and OBD default paths."""
    commands = [entry["request"] for entry in scenario["commands"]]
    return commands + ["ATDPN", "0142"]


def normalize(command: str) -> str:
    return "".join(command.upper().split())


class Expected(NamedTuple):
    data: bytes
    termination: str  # "prompt", "stall", "disconnect", or "skipped"


def command_expectations(scenario: dict) -> list:
    """Derive the expected reply bytes and termination independently of either
    server, straight from the scenario's declared bytes and cursor semantics.

    Entries for one request are consumed first-to-last and the last repeats,
    exactly as ``obd2.sim_scenario.v1`` specifies. An entry with
    ``repeat: true`` pins that request's cursor. Unmatched requests use the
    scenario's default reply for their AT/OBD class (never echoing, because
    the harness does not pass a host echo override).
    """
    entries_by_request: dict = {}
    for entry in scenario["commands"]:
        entries_by_request.setdefault(normalize(entry["request"]), []).append(entry)
    cursors: dict = {}
    closed = False  # a disconnect ends the connection; later commands never send

    expected = []
    for request in command_sequence(scenario):
        if closed:
            expected.append(Expected(b"", "skipped"))
            continue
        key = normalize(request)
        entries = entries_by_request.get(key)
        if not entries:
            body = scenario["defaults"]["at_response" if key.startswith("AT") else "obd_response"]
            expected.append(Expected(body.encode("ascii"), "prompt"))
            continue

        position = min(cursors.get(key, 0), len(entries) - 1)
        entry = entries[position]
        if not entry.get("repeat", False):
            cursors[key] = min(position + 1, len(entries) - 1)

        action = entry.get("post_action", "none")
        echo = bool(entry.get("echo", False))
        data = ((key + "\r") if echo else "") + "".join(entry.get("response_chunks", []))
        if action == "stall":
            expected.append(Expected(b"", "stall"))
        elif action == "disconnect":
            expected.append(Expected(data.encode("ascii"), "disconnect"))
            closed = True
        elif not entry.get("prompt", True):
            expected.append(Expected(data.encode("ascii"), "stall"))
        else:
            expected.append(Expected(data.encode("ascii"), "prompt"))
    return expected


def reply_problem(expected: Expected, actual: Reply) -> str | None:
    """Return a human-readable problem, or None when bytes and termination
    match the scenario-derived expectation."""
    if expected.termination == "skipped":
        if not actual.skipped or actual.data != b"":
            return "command was sent after an expected disconnect"
        return None
    if actual.skipped:
        if expected.termination == "prompt":
            return "command was skipped after an earlier disconnect"
        return None
    if actual.data != expected.data:
        return f"bytes differ: got {actual.data!r}, expected {expected.data!r}"
    if expected.termination == "prompt":
        if actual.closed:
            return "connection closed before the prompt"
        if not actual.data.endswith(b">"):
            return "reply is not terminated by the ELM prompt '>'"
    elif expected.termination == "stall":
        if actual.closed:
            return "stalled command closed the connection"
    elif expected.termination == "disconnect" and not actual.closed:
        return "disconnect command did not close the connection"
    return None


def python_cmd(scenario_path: Path) -> list:
    return [sys.executable, "-m", "elmulator", "serve", str(scenario_path), "--port", "0"]


def swift_cmd(swift_bin: str, scenario_path: Path) -> list:
    return [swift_bin, "--scenario", str(scenario_path), "--port", "0"]


def run(scenarios_dir: Path, swift_bin: str | None) -> int:
    scenario_files = sorted(scenarios_dir.glob("*.scenario.json"))
    if not scenario_files:
        print(f"FAIL: no scenarios in {scenarios_dir}")
        return 1

    label = "python-vs-swift" if swift_bin else "python-vs-python (determinism)"
    print(f"conformance: {label}, {len(scenario_files)} scenario(s)\n")

    other = "swift" if swift_bin else "python"
    failures = 0
    for path in scenario_files:
        scenario = json.loads(path.read_text(encoding="utf-8"))
        commands = command_sequence(scenario)
        expected = command_expectations(scenario)

        a_proc = None
        b_proc = None
        try:
            try:
                a_proc, a_port = start_server(python_cmd(path))
                if swift_bin:
                    b_proc, b_port = start_server(swift_cmd(swift_bin, path))
                else:
                    b_proc, b_port = start_server(python_cmd(path))
                a = drive(a_port, commands, expected)
                b = drive(b_port, commands, expected)
            except (StartupError, OSError) as exc:
                failures += 1
                print(f"  FAIL {path.name}\n    transport/setup error: {exc}")
                continue

            problems = []
            for command, want, left, right in zip(commands, expected, a, b):
                for impl, reply in (("python", left), (other, right)):
                    issue = reply_problem(want, reply)
                    if issue is not None:
                        problems.append((command, impl, want, reply, issue))

            parity = [
                (commands[i], a[i], b[i])
                for i in range(len(commands))
                if a[i] != b[i]
            ]

            if problems or parity:
                failures += 1
                print(f"  FAIL {path.name}")
                for command, impl, want, got, issue in problems:
                    print(
                        f"    {command!r} {impl}: {issue}\n"
                        f"      expected: {want.data!r} ({want.termination})\n"
                        f"      actual  : {got.data!r} (closed={got.closed})"
                    )
                for command, left, right in parity:
                    print(
                        f"    {command!r} parity\n"
                        f"      python: {left!r}\n"
                        f"      {other}: {right!r}"
                    )
            else:
                print(
                    f"  ok   {path.name}  "
                    f"({len(commands)} commands match expected bytes/termination and agree)"
                )
        finally:
            for proc in (b_proc, a_proc):
                if proc is not None:
                    terminate(proc)

    print()
    if failures:
        print(f"FAIL: {failures} scenario(s) diverged")
        return 1
    print("OK: all replies match scenario-derived expectations and agree byte-for-byte")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-bin", default=None, help="path to the elmulator-tcp binary")
    parser.add_argument("--scenarios", default=str(DEFAULT_SCENARIOS), help="scenarios directory")
    args = parser.parse_args()
    return run(Path(args.scenarios), args.swift_bin)


if __name__ == "__main__":
    sys.exit(main())
