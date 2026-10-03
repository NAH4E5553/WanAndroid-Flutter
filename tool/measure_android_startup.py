"""Local Launcher cold-start sampling; requires an explicit consent mode.

Build/install the entry with --profile --dart-define=STARTUP_METRICS=true first.
Use coordinates of the verified WanAndroid Flutter icon on the desktop page.
Does not clear application data, clear logcat, upload logs, or write server data.

Two mutually exclusive consent modes:
- --allow-real-network: real public-interface sampling (needs current user
  authorization, as in the STARTUP-01 guest baseline).
- --fixed-fake: the installed entry uses fixed fake repositories and performs
  no network access (STARTUP-02 animation A/B comparison).
"""
import argparse
import json
import math
import queue
import re
import statistics
import subprocess
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "com.personal.wanandroid.flutter"
POINTS = ("dart_main", "binding_ready", "dependencies_ready", "run_app",
          "first_raster", "startup_layer_exit", "home_first_raster",
          "home_articles_raster", "home_content_raster",
          "home_terminal_raster")
# 首页展示测点必须不早于启动层退出(遮挡层后的帧不算已展示)。
_HOME_POINTS_AFTER_EXIT = ("home_first_raster", "home_articles_raster",
                           "home_terminal_raster")

STAMP_RE = re.compile(r"\s*(\d+\.\d+)")


def extract_stamp(line):
    """logcat -v epoch 行首时间戳 → 微秒;无法解析返回 None。"""
    match = STAMP_RE.match(line)
    if not match:
        return None
    return round(float(match.group(1)) * 1_000_000)


def extract_startup_event(line):
    """WAN_STARTUP {json} 行 → 事件字典;其他行返回 None。"""
    if "WAN_STARTUP {" not in line:
        return None
    try:
        return json.loads(line.split("WAN_STARTUP ", 1)[1])
    except json.JSONDecodeError:
        return None


def ingest_line(line, state):
    """按行更新采样状态;与设备轮询主循环保持同一判定次序。

    state 键:launch_us, system_start_us, system_ttid_ms, events, counts,
    terminal_seen(布尔)。
    """
    epoch_us = extract_stamp(line)
    if epoch_us is None:
        return
    token = state["token"]
    if token in line and "WAN_STARTUP_MARK" in line:
        state["launch_us"] = epoch_us
    if state["launch_us"] is None or epoch_us < state["launch_us"]:
        return
    package = state["package"]
    if "START u0" in line and f"cmp={package}/" in line:
        state["system_start_us"] = epoch_us
    if f"Displayed {package}/" in line:
        duration = re.search(r": \+(?:(\d+)s)?(\d+)ms", line)
        if duration:
            state["system_ttid_ms"] = (int(duration.group(1) or 0) * 1000
                                       + int(duration.group(2)))
    event = extract_startup_event(line)
    if event is None:
        return
    if event.get("point") not in POINTS or event.get("schema") != 1:
        return
    state["counts"][event["point"]] = state["counts"].get(event["point"], 0) + 1
    state["events"].setdefault(event["point"], event)
    if event["point"] == "home_terminal_raster":
        state["terminal_seen"] = True


def valid_time(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value >= 0)


def contract_check(counts, times, layer_exit_expected, outcome="success"):
    """Validate a complete home result; no-animation exempts only layer exit.

    Error terminals have no content frame. Empty results do have a content
    frame, but remain distinct from success. A timeout is never complete.
    """
    details = []
    if outcome not in ("success", "empty", "error"):
        details.append(f"Incomplete or unknown terminal outcome: {outcome}")
    required = ["first_raster", *_HOME_POINTS_AFTER_EXIT]
    if outcome in ("success", "empty"):
        required.append("home_content_raster")
    elif "home_content_raster" in times or counts.get("home_content_raster", 0):
        details.append("Content frame is incompatible with terminal outcome")
    if layer_exit_expected:
        required.append("startup_layer_exit")
    for point in required:
        count = counts.get(point, 0)
        if count != 1:
            details.append(f"{point} occurred {count} times, expected 1")
        if not valid_time(times.get(point)):
            details.append(f"{point} missing or invalid frame time")
    pairs = list(zip(required[:4], required[1:4]))
    if outcome in ("success", "empty"):
        pairs.append(("home_terminal_raster", "home_content_raster"))
    if layer_exit_expected:
        pairs.append(("first_raster", "startup_layer_exit"))
        pairs.extend(("startup_layer_exit", point)
                     for point in (*_HOME_POINTS_AFTER_EXIT,
                                   "home_content_raster") if point in times)
    for before, after in pairs:
        if (valid_time(times.get(before)) and valid_time(times.get(after))
                and times[after] < times[before]):
            details.append(f"{after} ({times[after]}ms) precedes "
                           f"{before} ({times[before]}ms)")
    return not details, details


def validate_sample(sample, expected_outcome=None):
    """Recompute validity instead of trusting a saved contract_ok flag."""
    outcome = sample.get("events", {}).get(
        "home_terminal_raster", {}).get("outcome", "timeout")
    _, details = contract_check(
        sample.get("point_occurrences", {}),
        sample.get("launcher_request_ms", {}),
        sample.get("layer_exit_expected", True), outcome)
    if expected_outcome is not None and outcome != expected_outcome:
        details.append(f"Expected {expected_outcome} result, got {outcome}")
    return not details, details, outcome


def point_statistics(values, total):
    values = [value for value in values if valid_time(value)]
    return {"n": len(values), "total": total,
            "missing_or_invalid": total - len(values),
            "median_ms": statistics.median(values) if values else None,
            "min_ms": min(values) if values else None,
            "max_ms": max(values) if values else None}


def summarize(samples):
    """Keep every point and its denominator, even when all values are absent."""
    def collect(origin):
        return {point: point_statistics(
            [sample.get(origin, {}).get(point) for sample in samples], len(samples))
            for point in POINTS}
    summary = collect("launcher_request_ms")
    system_summary = collect("system_start_ms")
    system_summary["android_ttid"] = point_statistics(
        [sample.get("system_ttid_ms") for sample in samples], len(samples))
    return summary, system_summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--tap-x", type=int, required=True)
    parser.add_argument("--tap-y", type=int, required=True)
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--desktop-page",
                        help="Observed Launcher page accessibility label")
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument("--label", default="WanAndroid Flutter")
    parser.add_argument("--allow-real-network", action="store_true")
    parser.add_argument("--fixed-fake", action="store_true",
                        help="Fixed fake repositories; no network access")
    parser.add_argument("--group-label", default="",
                        help="Recorded verbatim into the output sample set")
    parser.add_argument("--layer-exit", choices=("expected", "not-applicable"),
                        default="expected",
                        help="Whether the Flutter startup overlay exit point "
                             "is expected in this build (no-animation "
                             "control builds mark not-applicable)")
    parser.add_argument("--output", default="build/startup_metrics.json")
    args = parser.parse_args()
    if args.allow_real_network == args.fixed_fake:
        parser.error("Choose exactly one consent mode: --allow-real-network "
                     "or --fixed-fake")
    if args.count < 1 or args.count > 20 or min(args.tap_x, args.tap_y) < 0:
        parser.error("Invalid sample count or Launcher coordinates")
    if args.package not in {PACKAGE, PACKAGE + ".startup"}:
        parser.error("Only this project and its isolated startup guest "
                     "package are supported")
    package = args.package
    adb = [args.adb, "-s", args.device]

    def shell(*command):
        result = subprocess.run(adb + ["shell", *command],
                                capture_output=True, text=True)
        if result.returncode and not (command[0] == "pidof"
                                      and result.returncode == 1):
            raise RuntimeError(f"ADB shell {command[0]} failed: "
                               f"{result.returncode}")
        return result.stdout

    samples = []
    for index in range(args.count):
        shell("input", "keyevent", "KEYCODE_HOME")
        shell("am", "force-stop", package)
        if shell("pidof", package).strip():
            raise RuntimeError("Cold-start premise failed: process still alive")
        time.sleep(1)
        temporary = "/data/local/tmp/wan_startup_probe.xml"
        try:
            shell("uiautomator", "dump", temporary)
            root = ET.fromstring(shell("cat", temporary))
            if args.desktop_page:
                pages = [node for node in root.iter("node")
                         if node.get("content-desc") == args.desktop_page
                         and node.get("package") == "com.miui.home"
                         and node.get("clickable") == "true"]
                if len(pages) != 1:
                    raise RuntimeError("Verified Launcher page control is "
                                       "absent")
                bounds = [int(v) for v in
                          re.findall(r"\d+", pages[0].get("bounds", ""))]
                if len(bounds) != 4:
                    raise RuntimeError("Invalid Launcher page bounds")
                left, top, right, bottom = bounds
                shell("input", "tap", str((left + right) // 2),
                      str((top + bottom) // 2))
                time.sleep(0.5)
                shell("uiautomator", "dump", temporary)
                root = ET.fromstring(shell("cat", temporary))
            icons = [node for node in root.iter("node")
                     if node.get("content-desc") == args.label
                     and node.get("clickable") == "true"]
            verified = False
            for icon in icons:
                bounds = [int(v) for v in
                          re.findall(r"\d+", icon.get("bounds", ""))]
                if len(bounds) == 4:
                    left, top, right, bottom = bounds
                    verified |= (left <= args.tap_x < right
                                 and top <= args.tap_y < bottom)
            if not verified:
                raise RuntimeError("Verified Flutter desktop icon is absent "
                                   "at the supplied coordinates")
        finally:
            shell("rm", "-f", temporary)
        token = f"launch_{index}_{time.monotonic_ns()}"
        lines = queue.Queue()
        process = subprocess.Popen(
            adb + ["logcat", "-v", "epoch", "-T", "1", "flutter:I",
                   "WAN_STARTUP_MARK:I", "ActivityTaskManager:I",
                   "ActivityManager:I", "*:S"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )

        def ingest():
            for line in process.stdout:
                lines.put(line)

        reader = threading.Thread(target=ingest, daemon=True)
        reader.start()
        state = {"token": token, "package": package, "launch_us": None,
                 "system_start_us": None, "system_ttid_ms": None,
                 "events": {}, "counts": {}, "terminal_seen": False}
        try:
            time.sleep(0.2)
            # Device marker immediately precedes the input command; includes
            # Android input command dispatch overhead, not literal finger
            # contact.
            shell(f"log -t WAN_STARTUP_MARK {token}; "
                  f"input tap {args.tap_x} {args.tap_y}")
            deadline = time.monotonic() + 35
            terminal_at = None
            while time.monotonic() < deadline:
                if terminal_at is not None and time.monotonic() - terminal_at > 0.5:
                    break
                try:
                    line = lines.get(timeout=0.1)
                except queue.Empty:
                    continue
                ingest_line(line, state)
                if state["terminal_seen"] and terminal_at is None:
                    terminal_at = time.monotonic()
        finally:
            process.terminate()
            process.wait(timeout=5)
            reader.join(timeout=1)
        if state["launch_us"] is None:
            raise RuntimeError("Missing device launch marker")
        if "dart_main" not in state["events"]:
            raise RuntimeError("No diagnostic main event: verify icon, APK "
                               "and build flag")
        times = {key: round((value["epoch_us"] - state["launch_us"]) / 1000, 3)
                 for key, value in state["events"].items()}
        if any(value < 0 for value in times.values()):
            raise RuntimeError("Clock correlation failed")
        sample = {"sample": index + 1, "kind": "force_stop_cold",
                  "group": args.group_label,
                  "launcher_request_ms": times,
                  "system_start_after_request_ms":
                      None if state["system_start_us"] is None
                      else round((state["system_start_us"]
                                  - state["launch_us"]) / 1000, 3),
                  "system_ttid_ms": state["system_ttid_ms"],
                  "point_occurrences": state["counts"],
                  "layer_exit_expected": args.layer_exit == "expected",
                  "events": state["events"]}
        ok, contract_details, outcome = validate_sample(
            sample, "success" if args.fixed_fake else None)
        sample.update(contract_ok=ok, contract_details=contract_details,
                      outcome=outcome)
        sample["system_start_ms"] = (
            {key: round(value - sample["system_start_after_request_ms"], 3)
             for key, value in times.items()}
            if state["system_start_us"] is not None else {})
        samples.append(sample)
        print(json.dumps({"sample": index + 1, "ms": times,
                          "outcome": state["events"].get(
                              "home_terminal_raster", {}).get(
                                  "outcome", "timeout"),
                          "layer_exit_count":
                              state["counts"].get("startup_layer_exit", 0),
                          "contract_ok": ok},
                         ensure_ascii=False), flush=True)
    summary, system_summary = summarize(samples)
    result = {"schema": 2, "device": args.device, "mode": "profile",
              "package": package, "label": args.label,
              "group": args.group_label,
              "guest_isolated": package.endswith(".startup"),
              "origin": "device log marker immediately before desktop "
                        "input tap",
              "endpoint": "Flutter rasterFinish; excludes display scanout",
              "network": ("authorized real public read-only interfaces"
                          if args.allow_real_network
                          else "fixed fake repositories; no network"),
              "layer_exit": args.layer_exit,
              "samples": samples, "summary": summary,
              "system_start_summary": system_summary}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    failures = [sample["sample"] for sample in samples
                if not sample["contract_ok"]]
    if failures:
        raise SystemExit(f"Startup layer contract violated in samples: "
                         f"{failures}; see {output}")


if __name__ == "__main__":
    main()
