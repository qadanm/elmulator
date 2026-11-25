"""Independent synthetic expectations for Mode 04 adapter replies."""

import pytest

from elmulator import Client, Conversation, load_bundled, serve_in_background


PRE_SCAN = (
    ("03", "7E8 04 43 01 04 20\r7EA 02 43 00\r\r>"),
    ("07", "7E8 04 47 01 03 01\r7EA 02 47 00\r\r>"),
    ("0A", "7E8 04 4A 01 04 20\r7EA 02 4A 00\r\r>"),
    ("0101", "7E8 06 41 01 81 07 01 00\r7EA 06 41 01 00 04 00 00\r\r>"),
)
POST_ACK_SCAN = (
    ("03", "7E8 02 43 00\r7EA 02 43 00\r\r>"),
    ("07", "7E8 02 47 00\r7EA 02 47 00\r\r>"),
    ("0A", "7E8 04 4A 01 04 20\r7EA 02 4A 00\r\r>"),
    ("0101", "7E8 06 41 01 00 77 01 01\r7EA 06 41 01 00 44 00 00\r\r>"),
)


@pytest.mark.parametrize(
    "scenario_id, reply, post_action",
    [
        ("can_clear_acknowledged", "7E8 01 44\r7EA 01 44\r\r>", "none"),
        ("can_clear_negative", "7E8 03 7F 04 22\r7EA 03 7F 04 22\r\r>", "none"),
        ("can_clear_lost_ack", "", "disconnect"),
        ("can_clear_timeout", "", "stall"),
        ("can_clear_partial_ack", "7E8 01 44\r\r>", "none"),
        ("can_clear_pending", "7E8 01 44\r7EA 03 7F 04 78\r", "none"),
    ],
)
def test_clear_wire_expectations(scenario_id, reply, post_action):
    conversation = Conversation(load_bundled(scenario_id))
    for request, expected in PRE_SCAN:
        assert conversation.send(request) == expected

    assert conversation.send("04") == reply
    assert conversation.transcript[-1]["matched_request"] == "04"
    assert conversation.transcript[-1]["post_action"] == post_action


@pytest.mark.parametrize(
    "scenario_id, expected_post_scan",
    [
        ("can_clear_acknowledged", POST_ACK_SCAN),
        ("can_clear_negative", PRE_SCAN),
    ],
)
def test_readback_preserves_permanent_codes(scenario_id, expected_post_scan):
    conversation = Conversation(load_bundled(scenario_id))
    for request, expected in PRE_SCAN:
        assert conversation.send(request) == expected
    conversation.send("04")

    for request, expected in expected_post_scan:
        assert conversation.send(request) == expected


@pytest.mark.parametrize(
    "scenario_id, error, message",
    [
        ("can_clear_lost_ack", ConnectionError, "peer closed before a prompt"),
        ("can_clear_timeout", TimeoutError, "no prompt"),
        ("can_clear_pending", TimeoutError, "no prompt"),
    ],
)
def test_tcp_distinguishes_missing_prompt_from_eof(scenario_id, error, message):
    stop, port = serve_in_background(load_bundled(scenario_id))
    try:
        with Client(port=port) as client:
            request, expected = PRE_SCAN[0]
            assert client.send(request) == expected
            with pytest.raises(error, match=message):
                client.send("04", timeout=0.5)
    finally:
        stop()
