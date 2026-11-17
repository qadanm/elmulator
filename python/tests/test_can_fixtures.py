"""Immutable synthetic oracle bytes; these tests do not implement a decoder."""
from elmulator import Conversation, load_bundled


def test_authored_can_bytes():
    cases = [
        ("can_wrong_service", "03", "7E8 04 47 01 04 20\r\r>"),
        ("can_invalid_hex", "03", "7E8 04 43 01 GG 20\r\r>"),
        ("can_truncated_payload", "03", "7E8 06 43 01 04 20\r\r>"),
        ("can_padded_rpm", "010C", "7E8 04 41 0C 1A F8 AA BB CC\r\r>"),
    ]
    for name, request, expected in cases:
        assert Conversation(load_bundled(name)).send(request) == expected
