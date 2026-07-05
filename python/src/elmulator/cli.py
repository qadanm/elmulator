#!/usr/bin/env python3
"""`elmulator` command line entry point.

Subcommands:
  elmulator serve SCENARIO [options]   host a scenario over TCP
  elmulator validate [PATHS...]        validate scenario files (or the bundled examples)
  elmulator self-test                  run an in-process loopback smoke test
"""

import argparse
import sys

from . import server, validate


def _split_list(text: str):
    return [int(piece) for piece in text.split(",") if piece]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="elmulator",
        description="Scriptable Bluetooth + TCP OBD2 (ELM327) adapter emulator.",
    )
    sub = parser.add_subparsers(dest="command")

    serve = sub.add_parser("serve", help="host a scenario over localhost TCP")
    serve.add_argument("scenario", help="path to a .scenario.json file")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=35000, help="0 picks a free port")
    serve.add_argument(
        "--echo", choices=["on", "off", "scenario"], default="scenario",
        help="force echo on or off, or follow the scenario (default)",
    )
    serve.add_argument(
        "--split", type=_split_list, default=None,
        help="cycled piece sizes, for example 1,2,5",
    )
    serve.add_argument("--latency-ms", type=int, default=0)
    serve.add_argument("--jitter-ms", type=int, default=0)
    serve.add_argument("--seed", type=int, default=0, help="deterministic jitter seed")

    check = sub.add_parser("validate", help="validate scenario files")
    check.add_argument(
        "paths", nargs="*",
        help="scenario files or directories (default: the bundled examples)",
    )

    sub.add_parser("self-test", help="run an in-process loopback smoke test")
    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "serve":
        return server.run_serve(args)
    if args.command == "validate":
        return validate.run(args.paths)
    if args.command == "self-test":
        return server.self_test()
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
