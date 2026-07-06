# Launch runbook

The research says: get ~50–100 stars in the first 24–48h by firing the channels in one window.

## Status

**Done & live:**
- Repo public: <https://github.com/qadanm/elmulator>, description + 18 topics, `v0.1.0` released, CI green (macOS Swift + Ubuntu Python).
- Published to PyPI: <https://pypi.org/project/elmulator/> (`pip install elmulator`), via trusted publishing.
- Demo asset rendering in the README; badges added.
- awesome-canbus PR open: <https://github.com/iDoka/awesome-canbus/pull/56>
- Swift Package Index PR open: <https://github.com/SwiftPackageIndex/PackageList/pull/14297> (ingests once merged).

**Remaining, needs your accounts:**
1. Show HN, submit the drafted post (§3). Your voice, your timing.

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

## 3. Show HN [you write and submit]

Important: HN guidelines say don't post generated or AI-edited text. Write the comment yourself, in your own words. The outline below is notes to write from, not text to paste.

How: go to <https://news.ycombinator.com/submit>, enter the title and the URL, submit, then write your first comment as a reply. Roughly 8 to 10am ET, Tuesday to Thursday, is a good window. Don't ask anyone to upvote or comment on the thread; that's against the rules.

**Title:** (this format is fine as-is; no caps, no numbers, no hype)
> Show HN: Elmulator, a scriptable fake ELM327 for testing OBD2 apps without a car

**URL:** `https://github.com/qadanm/elmulator`

**Points to cover in your own words:**
- The itch: you build an OBD2 app, and the Bluetooth link to the dongle was the one part you couldn't test. The Simulator has no Bluetooth and you can't fake a CBPeripheral, so testing meant a phone, an adapter, and a car.
- What it is: a fake ELM327 you script in a JSON file (its replies, how it chunks them, timing, stalls, disconnects, garbage).
- The three ways to run it: a real BLE peripheral on macOS, a TCP server, or an in-process fake in your tests. Say which one you actually care about and why (real CoreBluetooth code under `swift test`, in CI, no hardware).
- Honest comparison: Ircama's ELM327-emulator is good but TCP/serial only and its license blocks commercial use; yours does BLE and is MIT.
- Two honest caveats: the real BLE peripheral is macOS only for now; scenarios are hand-written (no record button yet).
- Close by inviting real feedback, not stars.

**Also worth posting in the same window:** r/embedded, r/iOSProgramming, r/CarHacking, and a reply in the Apple Developer Forums thread about mocking `CBPeripheral` with a link back.

---

## Sequence

1. Repo public + topics (done).
2. Tag `v0.1.0`, cut the release (PyPI publishes).
3. Open the SPI PackageList PR and the awesome-canbus PR.
4. Once those are merged/visible, post Show HN + Reddit in one morning.
5. First stars from your own network — a short, direct "I made this, a star helps" to people who'd care.
