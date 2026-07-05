#!/usr/bin/env python3
"""Cross-implementation conformance suite for obd2.sim_scenario.v1.

For every example scenario, this drives an identical command sequence against
two servers and asserts the reply byte streams are identical:

  - the Python server  (`elmulator serve`)
  - the Swift server    (`elmulator-tcp`, if a binary is provided)

This is what makes the scenario format a real specification rather than one
implementation's behavior: any new implementation (Kotlin, Rust, ...) can be
dropped in here and held to byte-for-byte parity.

Usage:
  python3 conformance/run_conformance.py [--swift-bin PATH] [--scenarios DIR]

With no --swift-bin, it runs the Python server against itself (a determinism
check) so the suite is still meaningful on Linux CI without a Swift toolchain.
"""

import argparse
import json
import socket
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCENARIOS = REPO_ROOT / "scenarios"
IDLE_TIMEOUT = 0.5  # seconds of silence that marks the end of a reply


def start_server(cmd) -> tuple:
    """Launch a server subprocess and parse its 'LISTENING <port>' line."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        line = proc.stdout.readline()
        if not line:
            break
        if line.startswith("LISTENING "):
            return proc, int(line.split()[1])
    proc.kill()
    raise RuntimeError(f"server did not announce a port: {' '.join(str(c) for c in cmd)}")


def read_reply(sock) -> bytes:
    """Read one reply: bytes up to the ELM prompt, or until the peer goes
    silent (a stall) or closes (a disconnect)."""
    sock.settimeout(IDLE_TIMEOUT)
    data = b""
    while True:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
        if b">" in chunk:
            break
    return data


def drive(port: int, commands) -> list:
    """Send each command and collect the raw reply bytes, in order."""
    replies = []
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        dead = False
        for command in commands:
            if dead:
                replies.append(b"")
                continue
            try:
                sock.sendall((command + "\r").encode("ascii"))
                reply = read_reply(sock)
            except OSError:
                # Peer closed the connection (a scenario disconnect). Every
                # later command sees the same dead socket on both servers.
                reply = b""
                dead = True
            replies.append(reply)
    return replies


def command_sequence(scenario: dict) -> list:
    """The scenario's own commands in order, plus a couple of unmatched ones
    to exercise the AT and OBD default paths."""
    commands = [entry["request"] for entry in scenario["commands"]]
    return commands + ["ATDPN", "0142"]


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

    failures = 0
    for path in scenario_files:
        scenario = json.loads(path.read_text(encoding="utf-8"))
        commands = command_sequence(scenario)

        a_proc, a_port = start_server(python_cmd(path))
        try:
            if swift_bin:
                b_proc, b_port = start_server(swift_cmd(swift_bin, path))
            else:
                b_proc, b_port = start_server(python_cmd(path))
            try:
                a = drive(a_port, commands)
                b = drive(b_port, commands)
            finally:
                b_proc.kill()
        finally:
            a_proc.kill()

        mismatches = [
            (commands[i], a[i], b[i])
            for i in range(len(commands))
            if a[i] != b[i]
        ]
        if mismatches:
            failures += 1
            print(f"  FAIL {path.name}")
            for command, left, right in mismatches:
                print(f"    {command!r}\n      python: {left!r}\n      other : {right!r}")
        else:
            print(f"  ok   {path.name}  ({len(commands)} commands identical)")

    print()
    if failures:
        print(f"FAIL: {failures} scenario(s) diverged")
        return 1
    print("OK: all implementations agree byte-for-byte")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-bin", default=None, help="path to the elmulator-tcp binary")
    parser.add_argument("--scenarios", default=str(DEFAULT_SCENARIOS), help="scenarios directory")
    args = parser.parse_args()
    return run(Path(args.scenarios), args.swift_bin)


if __name__ == "__main__":
    sys.exit(main())
