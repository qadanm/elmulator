# Synthetic CAN clear-outcome fixtures

These fixtures give client tests six different Mode `04` reply and transport outcomes. Use the fixtures from a source checkout of Elmulator. The six scenarios and both bundled catalogs use the existing `obd2.sim_scenario.v1` format.

## Replay a transcript

Run this from the repository root. `Conversation` replays the fixture in memory.

```sh
PYTHONPATH=python/src python3 - <<'PYTHON'
from elmulator import Conversation, load_bundled

adapter = Conversation(load_bundled("can_clear_acknowledged"))
reads = ("03", "07", "0A", "0101")
for request in (*reads, "04", *reads):
    print(request, repr(adapter.send(request)))
PYTHON
```

The expected order is one pre-scan using `03`, `07`, `0A` and `0101`, one clear request, and, for the acknowledged and negative fixtures, the same readback sequence. A new connection or `Conversation` starts the script from the first reply for each request. Repeated reads advance the scripted reply cursor. Follow the stated order when comparing pre- and post-clear evidence. Client tests should count submissions and decide whether a readback is appropriate for each outcome.

For stream tests, start either command from the repository root. Both servers bind to `127.0.0.1` and print `LISTENING <port>` when ready. Python accepts a bundled fixture name. The Swift CLI takes a scenario file path.

```sh
PYTHONPATH=python/src python3 -m elmulator serve can_clear_acknowledged --host 127.0.0.1 --port 0
swift run elmulator-tcp --scenario scenarios/can_clear_acknowledged.scenario.json --port 0
```

The public `Conversation` transcript includes a planned post-action. A TCP test can distinguish peer EOF from a read deadline while the socket stays open.

## Wire expectations

All six fixtures use synthetic 11-bit Classical CAN response IDs `7E8` and `7EA` in an ELM-style ASCII stream. After the response ID, the single-frame PCI in these fixtures gives the payload length. For example, `01 44` contains one payload byte and `03 7F 04 78` contains three. Lines end in a carriage return. Complete replies end with a blank line and `>`. [ELM327 datasheet, pp. 35, 44–45](https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DS.pdf) · [Linux ISO-TP transport reference](https://docs.kernel.org/networking/iso15765-2.html)

| Fixture | Reply to `04` | Stream outcome |
| --- | --- | --- |
| `can_clear_acknowledged` | `7E8 01 44` and `7EA 01 44` | Prompt after both positive responses |
| `can_clear_negative` | `7E8 03 7F 04 22` and `7EA 03 7F 04 22` | Prompt after both final negative responses |
| `can_clear_lost_ack` | Zero bytes | Peer EOF |
| `can_clear_timeout` | Zero bytes | Open link with no prompt |
| `can_clear_partial_ack` | `7E8 01 44` | Prompt with one expected reply absent |
| `can_clear_pending` | `7E8 01 44` and `7EA 03 7F 04 78` | Open link with no final response from `7EA` and no prompt |

The pre-scan shows stored P0420, pending P0301 and permanent P0420 from `7E8`. The other ECU supplies explicit empty responses for those categories. After the two acknowledgments, both ECUs report empty stored and pending lists, readiness reports incomplete monitors, and the permanent P0420 response is byte-for-byte unchanged. The final negative transcript replays the original readings after the negative response. An acknowledged request and the later readback each provide separate evidence.

The selected NRC `22` represents a final rejection in the synthetic transcript. NRC `78` represents a pending response. The fixture’s open-link conditions are suitable for testing a caller’s configured deadline. They establish no universal adapter timing or cause of rejection. [AUTOSAR Diagnostic Communication Manager R24-11, §7.4.3.6](https://www.autosar.org/fileadmin/standards/R24-11/CP/AUTOSAR_CP_SWS_DiagnosticCommunicationManager.pdf#page=233)

The expected scan summary is empty in these fixtures. Use the ordered transcript and independent assertions above for pre- and post-clear meaning. A consumer must assess responder coverage and uncertainty and handle any vehicle-operation policy separately.

## Verify changes

Run the existing checks from the repository root. The language tests pin literal reply bytes separately from the scenario JSON. TCP conformance checks exact bytes and termination for all source scenarios.

```sh
python3 scripts/build_bundled.py --check
PYTHONPATH=python/src python3 -m elmulator validate scenarios/
swift test
PYTHONPATH=python/src python3 -m pytest python/tests
swift build --product elmulator-tcp
PYTHONPATH=python/src python3 conformance/run_conformance.py --swift-bin .build/debug/elmulator-tcp
```

The fixtures are authored synthetic data under Elmulator’s MIT license. The references document protocol facts. Testing here establishes the simulator’s replay and transport behavior. Vehicle support requires separate validation.
