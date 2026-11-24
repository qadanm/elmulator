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

To try a real TCP reader locally after installing a candidate wheel, run `python examples/tcp_report.py`. The example opens a temporary loopback listener, exercises positive and link-loss paths, and shuts it down.

## Release verification

For the next additive release, target v0.4.0 and retain `obd2.sim_scenario.v1`. Before requesting publication, set the Python package version and changelog, build both distributions, run the standalone consumer smoke checks, and verify the same commit in the Swift package. Match the published tag to the Python version. Verify the published wheel and exact-tag Action before advancing the floating `v0` alias.
