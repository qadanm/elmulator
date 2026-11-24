"""Exercise an independent TCP client against public synthetic diagnostic scenarios."""
from elmulator import Client, load_bundled, serve_in_background


def exercise_report() -> None:
    stop, port = serve_in_background(load_bundled("can_full_report"), host="127.0.0.1", port=0)
    try:
        with Client(port=port) as adapter:
            assert adapter.send("ATDPN").strip().startswith("A6")
            assert "7E8 04 43 01 04 20" in adapter.send("03")
            readiness = adapter.send("0141")
            assert "7E8" in readiness and "7EA" in readiness
    finally:
        stop()


def exercise_lost_connection() -> None:
    stop, port = serve_in_background(load_bundled("can_delayed_link_loss"), host="127.0.0.1", port=0)
    try:
        with Client(port=port) as adapter:
            assert "41 0C 1A F8" in adapter.send("010C")
            try:
                adapter.send("03")
            except (ConnectionError, BrokenPipeError):
                return
            raise AssertionError("The adapter should have closed after the live reply")
    finally:
        stop()


if __name__ == "__main__":
    exercise_report()
    exercise_lost_connection()
    print("PASS: two-ECU report and connection loss")
