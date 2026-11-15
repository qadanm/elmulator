# Contributing

Thanks for helping build a better OBD2 test harness. This is an MIT-licensed, clean-room project, standard OBD2 only (SAE J1979 / ISO 15765-4). **Do not copy code or scenario data from GPL/AGPL or non-commercial sources** (including other ELM327 emulators). Every scenario must be synthetic and hand-authored.

Found a security vulnerability instead of a regular bug? See [SECURITY.md](SECURITY.md) for how to report it privately.

## Local setup

```bash
# Python
cd python && pip install -e . pytest && pytest -q && cd ..

# Python lint (same rules as CI)
pip install ruff && ruff check .

# Swift
swift build && swift test

# Cross-implementation parity
swift build --product elmulator-tcp
python conformance/run_conformance.py --swift-bin .build/debug/elmulator-tcp
```

CI runs the Python suite on 3.9 (the minimum supported version) and 3.12, so keep new code 3.9-compatible.

## Local-only GitHub workflow

Work and review happen in local branches and commits. Pushing a branch, opening a remote pull request, publishing a release, or treating a local result as hosted CI evidence requires explicit maintainer authorization.

1. Create a focused branch from the maintainer-designated base commit:

   ```bash
   git switch -c <topic-branch>
   ```

2. Change only what the task needs. Keep new scenarios synthetic and hand-authored, and keep expected outcomes independent of the implementation under test.
3. Stage only the intended files, then inspect the staged patch and check both staged and unstaged whitespace errors:

   ```bash
   git add <intended-files>
   git diff --cached
   git diff --check
   git diff --cached --check
   ```

4. Run the tests relevant to the change. For engine, scenario, or fixture changes, run the documented Python, Swift, and conformance commands above; a local pass does not prove that a hosted CI job ran.
5. Make one coherent commit with an imperative subject. Include the ticket reference, why the change is needed, and the exact testing and limitations in the body.
6. Have someone independent review the local commit or staged diff. The reviewer checks scope, correctness, fixture provenance, Swift/Python parity, and test evidence; the author must not self-approve. Record the review in the pull request template, which serves as a local review record.
7. Do not push, publish, or include secrets, real VINs or Bluetooth identifiers, private app code, generated build products, caches, or machine-specific absolute paths. The changes remain local until a maintainer explicitly authorizes publication.

## The bar for a change

- **New scenarios** must pass `elmulator validate scenarios/` and are automatically covered by the conformance suite. Fill in `expected_scan_summary` and add a row to [`scenarios/README.md`](scenarios/README.md).
- **Engine changes** must keep Python and Swift byte-for-byte identical, including how authored `response_chunks` boundaries and `stream_split_bytes` frame a reply. If you change one, change the other and confirm the conformance suite still passes.
- **Format changes** update [`SPEC.md`](SPEC.md) and [`spec/obd2.sim_scenario.v1.schema.json`](spec/obd2.sim_scenario.v1.schema.json) together. Backward-compatible additions stay under `v1`; breaking changes bump the `schema_version`.
- Keep the Python package dependency-free (standard library only).

## Scope

This project is the emulator and test harness only. Decoding/parsing of PIDs and DTCs, UI, and app-specific domain logic are intentionally out of scope. `expected_scan_summary` is a consumer-defined oracle the emulator never interprets.
