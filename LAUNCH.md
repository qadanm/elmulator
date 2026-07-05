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

## 3. Show HN [you submit]

How: go to <https://news.ycombinator.com/submit>, paste the title and the URL, click submit, then paste the first comment as your own reply. Good timing is roughly 8 to 10am ET on a Tuesday to Thursday.

**Title:**
> Show HN: Elmulator, a scriptable fake ELM327 for testing OBD2 apps without a car

**URL:** `https://github.com/qadanm/elmulator`

**First comment:**
> I make an OBD2 app, the kind that reads your car's diagnostics over one of those cheap Bluetooth dongles. The connection to the dongle was always the part I couldn't really test. The iOS Simulator can't do Bluetooth, and Apple won't let you fake a CBPeripheral, so my choices were to run it on a real phone with a real adapter plugged into a real car, or just not test it. I did a lot of not testing it.
>
> Elmulator is the fake adapter I ended up building. You describe the adapter in a small JSON file: what it replies to each command, how it splits the reply into Bluetooth-sized chunks, how long it waits, and when it stalls or drops the connection or sends back garbage. Then you can run that scripted adapter three ways: as a real Bluetooth LE peripheral (a little macOS program), as a plain TCP server, or as an in-process fake inside your tests. The last one is the whole reason I built it. My real CoreBluetooth code now runs against a scripted adapter under `swift test`, on a normal CI runner, with no hardware.
>
> There's an older tool, Ircama's ELM327-emulator, that's good and has been around a while, but it's TCP and serial only (its "Bluetooth" is the old serial profile, not BLE) and its license blocks commercial use. Elmulator does BLE and is MIT, which is honestly why I wrote my own instead of using it. The Python and Swift servers are tested against each other so they reply the same way, which keeps the JSON format from drifting.
>
> Two honest caveats: the real-radio BLE peripheral is macOS only for now, and scenarios are written by hand, so there's no "record a real adapter" button yet. Both are on my list. It's Swift and Python, there's a copy-paste example in the repo, and the tests it runs in CI are right there too. Would love to hear what breaks or what's missing.

**Also worth posting in the same window:** r/embedded, r/iOSProgramming, r/CarHacking, and a reply in the Apple Developer Forums thread about mocking `CBPeripheral` with a link back.

---

## Sequence

1. Repo public + topics (done).
2. Tag `v0.1.0`, cut the release (PyPI publishes).
3. Open the SPI PackageList PR and the awesome-canbus PR.
4. Once those are merged/visible, post Show HN + Reddit in one morning.
5. First stars from your own network — a short, direct "I made this, a star helps" to people who'd care.
