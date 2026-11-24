# Generic OBD report fixtures

The scenarios use synthetic CAN frames, two normal diagnostic response addresses, and a scripted ELM prompt. Capture radio and vehicle evidence separately. The same fixtures work across the Swift and Python engines and the macOS BLE peripheral.

| Request | Independent expectation |
|---|---|
| 01 00, 01 20, 01 40 | ECU 7E8 advertises the starter live readings. ECU 7EA advertises RPM and speed as well as both readiness scopes. |
| 01 06–09 | Bank 1 short and long trims are +12.5% and −12.5%. Bank 2 values are 0% and +25%. |
| 01 0B, 10, 1F, 2F, 33, 42 | 100 kPa manifold pressure, 10 g/s MAF, 300 s runtime, 20% fuel, 101 kPa barometer, and 14 V. |
| 03, 07, 0A | ECU 7E8 stored P0420. ECU 7EA reports an empty stored list. Both pending and permanent lists are empty. In the missing-ECU scenario ECU 7EA did not answer pending. |
| 02 02 00 and values | ECU 7E8 frame zero is linked to P0420, with 1726 rpm, 83 °C and 0 km/h. ECU 7EA explicitly reports no stored frame. The wrong-frame variant must fail correlation. |
| 06 01 | Test 80 has a signed −0.01 V result within −1.00 V to +1.00 V. Test 81 has all-zero fields and has no completed result. A different MID in the second record invalidates the exchange. |
| 09 04 and 09 06 | Independent calibration IDs FAKE-CAL-A and FAKE-CAL-C, and verification numbers 01234567 and 0000002A. |

Wire shapes derive from [SAE J1979 MAY2007](https://www.autonerdz.com/yabbfiles/Attachments/1979v3.pdf), sections 7.1, 7.2, 7.6 and 7.9. Interpret monitor scaling using the J1979 Digital Annex. Results are hand-calculated and independent of either Elmulator engine.

## Downstream examples

Two standalone consumers exercise these fixtures outside the engine tests. The Python TCP sample opens a temporary loopback listener, checks the report and link-loss paths, and shuts it down. Run it after installing the wheel.

```bash
python -m pip install python/dist/elmulator-0.4.0-py3-none-any.whl
python examples/tcp_report.py
```

The Swift sample client (`Sources/ObdSampleClient`) runs through CoreBluetooth-Mock in the serialized `OBDCITests` suite. It demonstrates a positive `can_full_report` read (two ECU addresses, stored P0420, 1726 rpm, readiness scopes, calibration IDs, CVNs) and observes the `can_delayed_link_loss` failure after the live reply. The shared `withMockAdapter` helper performs the disconnect, pending-reply cancellation, invalidation and global mock teardown. This needs no simulator, device, or Bluetooth radio. Reproduce it with Xcode 27.1 pinned explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  swift test --filter OBDCITests
```

## Release status and verification

The next additive release is staged as **0.4.0** at the single source of truth, `python/src/elmulator/__init__.py`. The latest **published** Python distribution and GitHub Action remain **0.3.3**; keep published pins and the CI Action smoke on 0.3.3 until maintainers publish tag `v0.4.0`, verify the published wheel and exact-tag Action, and only then advance the floating `v0` alias.

Compatibility: additive only. `obd2.sim_scenario.v1` is unchanged; Python requires 3.9+, the Swift package requires Swift 6 with macOS 14+/iOS 17+, and neither runtime gains a dependency. The distribution tag must match the package version (`v0.4.0`).

Before requesting publication, verify the candidate wheel and source distribution locally.

```bash
cd python && python -m build && twine check dist/* && cd ..
python -c "import sys; sys.path.insert(0, 'python/src'); import elmulator; print(elmulator.__version__)"
python -m pip install python/dist/elmulator-0.4.0-py3-none-any.whl && python examples/tcp_report.py
```

A manual dispatch of `release-pypi.yml` builds and checks the source distribution and wheel with read-only permissions. PyPI publication runs for a published GitHub release whose tag matches the package version.
