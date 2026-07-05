# Launch runbook

The research says: get ~50–100 stars in the first 24–48h by firing the channels in one window.

## Status

**Done & live:**
- Repo public: <https://github.com/qadanm/elmulator> — description + 18 topics, `v0.1.0` tagged, **CI green** (macOS Swift + Ubuntu Python).
- Demo asset (`assets/demo.svg`) rendering in the README; badges added.
- **awesome-canbus PR open:** <https://github.com/iDoka/awesome-canbus/pull/56>
- **Swift Package Index PR open:** <https://github.com/SwiftPackageIndex/PackageList/pull/14297>

**Remaining — needs your accounts (the two genuine human-only steps):**
1. **PyPI** — set up the trusted publisher, then cut a GitHub release (§1 below). I can't touch your PyPI account.
2. **Show HN** — submit the drafted post (§3). Your voice, your timing.

Pre-flight verified: Swift 31/31, Python + byte-for-byte conformance green.

---

## 0. Repo is live

`github.com/qadanm/elmulator` (public), with description and topics set. If you'd rather host under an `elmulator` org, create the org and `Settings → Transfer` the repo — stars, forks, and redirects are preserved. (Update the URLs in `python/pyproject.toml`, `docs/swift-package.md`, and the docs if you do.)

**Topics set:** `obd2 obdii elm327 ble bluetooth-low-energy corebluetooth ios swift emulator simulator testing ci mock automotive canbus swiftpm python test-automation`

---

## 1. Cut a release → PyPI + Swift Package Index

**[you] One-time PyPI trusted-publisher setup** (no token needed): on <https://pypi.org> → your project (or "pending publisher") → add a GitHub publisher:
`owner: qadanm · repo: elmulator · workflow: release-pypi.yml · environment: pypi`.
Also create a repo Environment named `pypi` (Settings → Environments).

Then cut the release (this also gives Swift Package Index its required semver tag):

```bash
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 --title "v0.1.0" --notes-file CHANGELOG.md
```

The `release-pypi.yml` workflow builds and publishes to PyPI on release.

**[you] Swift Package Index:** open a one-line PR adding the repo URL to
<https://github.com/SwiftPackageIndex/PackageList> (`packages.json`, alphabetical). SPI ingests it automatically after that. Nothing else required — SPI reads `Package.swift` from the repo root.

---

## 2. awesome-canbus PR (3.3k★ — the highest-leverage distribution)

Add to the **`## Test equipment and simulators`** section (right after the `ELM327-emulator` line, to invite the comparison):

```markdown
* [elmulator](https://github.com/qadanm/elmulator) - Scriptable Bluetooth LE and TCP ELM327 adapter emulator with a CI test harness for OBD2 app developers. MIT-licensed, with an in-process BLE test double so apps can test their Bluetooth stack with no radio.
```

**[you or automated] Steps:**

```bash
gh repo fork iDoka/awesome-canbus --clone --remote
cd awesome-canbus
git checkout -b add-elmulator
# insert the line after the ELM327-emulator entry in "Test equipment and simulators"
git commit -am "Add elmulator (scriptable BLE + TCP ELM327 emulator / CI harness)"
git push -u origin add-elmulator
gh pr create --repo iDoka/awesome-canbus \
  --title "Add elmulator (scriptable BLE + TCP ELM327 emulator / CI harness)" \
  --body "Adds elmulator to Test equipment and simulators. It's an MIT-licensed, scriptable ELM327 adapter emulator that (unlike existing tools) emulates Bluetooth LE and ships an in-process test double + CI harness so OBD2 apps can test their Bluetooth stack with no radio. Standard OBD2 (SAE J1979 / ISO 15765-4), no GPL/AGPL/NC code copied."
```

Follow the repo's CONTRIBUTING (entries alphabetical within a section if required; keep one line, end with a period).

---

## 3. Show HN [you]

Post at ~8–10am ET on a Tue–Thu. Submit as a **Show HN** with the repo URL, then add the first comment yourself.

**Title:**
> Show HN: Test your car app's Bluetooth in CI – no car, no adapter, no phone

**URL:** `https://github.com/qadanm/elmulator`

**First comment:**
> I build an OBD2 (car diagnostics) app. The most fragile part — the Bluetooth connection to the ELM327 adapter — was also the only part I couldn't test: the iOS Simulator has no Bluetooth, and Apple gives you no supported way to mock `CBPeripheral`. So testing meant a phone + a dongle + sitting in a parking lot.
>
> elmulator is the fake adapter I built to fix that. You write a scenario in JSON (the exact ELM327 conversation: responses, BLE-MTU chunking, latency, stalls, disconnects, malformed frames), and it stands up as a scripted adapter over real Bluetooth LE, over TCP, or as an in-process test double. Your real CoreBluetooth code runs against it in `swift test` with no radio — there's a copy-paste example + green CI in the repo.
>
> The nearest existing tool (Ircama's ELM327-emulator) is great but TCP/serial-only (its "Bluetooth" is RFCOMM serial, not BLE/GATT) and CC-BY-NC-SA. elmulator adds native BLE and is MIT. The Python and Swift servers are held byte-for-byte identical by a conformance suite, so the scenario format is a real spec.
>
> Standard OBD2 only (SAE J1979 / ISO 15765-4), clean-room. Happy to answer questions.

**Also worth a post (same 48h window):** r/embedded, r/iOSProgramming, r/CarHacking; and reply in the Apple Developer Forums thread about mocking `CBPeripheral` with a link.

---

## Sequence

1. Repo public + topics (done).
2. Tag `v0.1.0`, cut the release (PyPI publishes).
3. Open the SPI PackageList PR and the awesome-canbus PR.
4. Once those are merged/visible, post Show HN + Reddit in one morning.
5. First stars from your own network — a short, direct "I made this, a star helps" to people who'd care.
