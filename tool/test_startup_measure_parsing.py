"""Fixture-verified parsing for tool/measure_android_startup.py.

Runs against tool/startup_measure_logcat_fixture.txt (schema-2 rewrite,
2026-10-02): verifies stamp extraction, post-marker filtering, startup_layer_exit
occurrence counting, the home-points-not-before-exit contract and the summary
statistics, without touching any device.
"""
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from measure_android_startup import (contract_check, extract_stamp,
                                     extract_startup_event, ingest_line,
                                     summarize)

FIXTURE = Path(__file__).parent / "startup_measure_logcat_fixture.txt"


def main():
    lines = FIXTURE.read_text().splitlines()
    state = {"token": "launch_0_999",
             "package": "com.personal.wanandroid.flutter.startup",
             "launch_us": None, "system_start_us": None,
             "system_ttid_ms": None, "events": {}, "counts": {},
             "terminal_seen": False}
    for line in lines:
        ingest_line(line, state)

    assert extract_stamp(lines[0]) == 1767000000050000, "stamp extraction"
    assert extract_stamp("no stamp here") is None
    assert extract_startup_event(lines[4])["point"] == "dart_main"
    assert extract_startup_event(lines[0]) is None

    assert state["launch_us"] == 1767000000100000, "second marker wins"
    # The first marker line predates the accepted launch_us and must not
    # contribute events; everything here is after the marker anyway.
    assert state["system_ttid_ms"] == 700, "Displayed TTID"
    assert state["system_start_us"] == 1767000000200000, "system START"
    assert "unknown_point" not in state["events"], "schema/point filter"
    assert state["counts"]["startup_layer_exit"] == 2, \
        "duplicate exit must be counted"
    assert state["terminal_seen"] is True

    times = {key: round((value["epoch_us"] - state["launch_us"]) / 1000, 3)
             for key, value in state["events"].items()}
    ok, details = contract_check(state["counts"], times, True)
    assert not ok and any("occurred 2 times" in d for d in details), \
        f"duplicate exit must fail the contract: {details}"
    ok, details = contract_check(state["counts"], times, False)
    assert ok, f"not-applicable mode must not enforce count: {details}"

    bad_times = dict(times)
    bad_times["home_first_raster"] = times["startup_layer_exit"] - 5
    ok, details = contract_check({"startup_layer_exit": 1}, bad_times, True)
    assert not ok and any("precedes" in d for d in details), \
        f"home before exit must fail: {details}"

    sample = {"launcher_request_ms": times, "system_start_ms": dict(times),
              "system_ttid_ms": 700}
    summary, system_summary = summarize([sample])
    assert summary["startup_layer_exit"]["n"] == 1
    assert summary["home_terminal_raster"]["median_ms"] == \
        times["home_terminal_raster"]
    assert system_summary["android_ttid"]["median_ms"] == 700

    print("FIXTURE_OK",
          json.dumps({"points": sorted(state["events"]),
                      "counts": state["counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
