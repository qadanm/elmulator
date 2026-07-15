# Security policy

## Supported versions

elmulator follows semantic versioning and is pre-1.0. Only the latest
released version (Swift package tag and PyPI release) receives fixes.
There is no backport policy for older minor versions right now.

| Version | Supported |
|---|---|
| Latest (see [releases](https://github.com/qadanm/elmulator/releases)) | Yes |
| Older | No |

## Reporting a vulnerability

Please do not open a public issue for a suspected security
vulnerability.

Use GitHub's private reporting instead: go to the
[Security tab](https://github.com/qadanm/elmulator/security/advisories/new)
and open a new draft security advisory. That reaches the maintainer
directly and keeps the report private until a fix ships.

Include what you'd include in any good bug report: the affected
version, the scenario or code path involved, and, if possible, a
minimal reproduction.

## Scope

elmulator is a test-only tool: a scripted ELM327 emulator and CI
harness for automotive OBD2 software. It has no runtime network
exposure beyond the localhost TCP server and local Bluetooth
advertising it's designed to run, both meant for use on a developer
machine or CI runner, not a production host. Reports about that
threat model (for example, a scenario file that can crash the parser,
or a malformed adapter reply that isn't handled safely) are in scope.
General hardening requests for a tool with no production deployment
surface are likely out of scope, but open a private report and it
will get a real look either way.

## Response

This is an independently maintained, pre-1.0 open-source project.
There's no SLA, but private reports get triaged and, once a fix is
ready, credited in the release notes unless you'd rather stay
anonymous.
