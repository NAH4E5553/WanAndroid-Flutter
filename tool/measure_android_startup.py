"""Local Launcher cold-start sampling; requires explicit public-network consent.

Build/install main.dart with --profile --dart-define=STARTUP_METRICS=true first.
Use coordinates of the verified WanAndroid Flutter icon on the desktop page.
Does not clear application data, clear logcat, upload logs, or write server data.
"""
import argparse
import json
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
          "first_raster", "home_first_raster", "home_articles_raster",
          "home_content_raster", "home_terminal_raster")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--tap-x", type=int, required=True)
    parser.add_argument("--tap-y", type=int, required=True)
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--desktop-page", help="Observed Launcher page accessibility label")
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument("--label", default="WanAndroid Flutter")
    parser.add_argument("--allow-real-network", action="store_true")
    parser.add_argument("--output", default="build/startup_metrics.json")
    args = parser.parse_args()
    if not args.allow_real_network:
        parser.error("Real public-interface sampling requires current user authorization.")
    if args.count < 1 or args.count > 20 or min(args.tap_x, args.tap_y) < 0:
        parser.error("Invalid sample count or Launcher coordinates")
    if args.package not in {PACKAGE, PACKAGE + ".startup"}:
        parser.error("Only this project and its isolated startup guest package are supported")
    package = args.package
    adb = [args.adb, "-s", args.device]

    def shell(*command):
        result = subprocess.run(adb + ["shell", *command],
                                capture_output=True, text=True)
        if result.returncode and not (command[0] == "pidof" and result.returncode == 1):
            raise RuntimeError(f"ADB shell {command[0]} failed: {result.returncode}")
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
                    raise RuntimeError("Verified Launcher page control is absent")
                bounds = [int(v) for v in re.findall(r"\d+", pages[0].get("bounds", ""))]
                if len(bounds) != 4:
                    raise RuntimeError("Invalid Launcher page bounds")
                left, top, right, bottom = bounds
                shell("input", "tap", str((left + right) // 2), str((top + bottom) // 2))
                time.sleep(0.5)
                shell("uiautomator", "dump", temporary)
                root = ET.fromstring(shell("cat", temporary))
            icons = [node for node in root.iter("node")
                     if node.get("content-desc") == args.label
                     and node.get("clickable") == "true"]
            verified = False
            for icon in icons:
                bounds = [int(v) for v in re.findall(r"\d+", icon.get("bounds", ""))]
                if len(bounds) == 4:
                    left, top, right, bottom = bounds
                    verified |= left <= args.tap_x < right and top <= args.tap_y < bottom
            if not verified:
                raise RuntimeError("Verified Flutter desktop icon is absent at the supplied coordinates")
        finally:
            shell("rm", "-f", temporary)
        token = f"launch_{index}_{time.monotonic_ns()}"
        lines = queue.Queue()
        process = subprocess.Popen(
            adb + ["logcat", "-v", "epoch", "-T", "1", "flutter:I",
                   "WAN_STARTUP_MARK:I", "ActivityTaskManager:I", "ActivityManager:I", "*:S"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        def ingest():
            for line in process.stdout:
                lines.put(line)
        reader = threading.Thread(target=ingest, daemon=True)
        reader.start()
        events = {}
        launch_us = None
        system_start_us = None
        system_ttid_ms = None
        terminal_at = None
        try:
            time.sleep(0.2)
            # Device marker immediately precedes the input command; includes
            # Android input command dispatch overhead, not literal finger contact.
            shell(f"log -t WAN_STARTUP_MARK {token}; input tap {args.tap_x} {args.tap_y}")
            deadline = time.monotonic() + 35
            while time.monotonic() < deadline:
                if terminal_at is not None and time.monotonic() - terminal_at > 0.5:
                    break
                try:
                    line = lines.get(timeout=0.1)
                except queue.Empty:
                    continue
                stamp = re.match(r"\s*(\d+\.\d+)", line)
                if not stamp:
                    continue
                epoch_us = round(float(stamp[1]) * 1_000_000)
                if token in line and "WAN_STARTUP_MARK" in line:
                    launch_us = epoch_us
                if launch_us is None or epoch_us < launch_us:
                    continue
                if "START u0" in line and f"cmp={package}/" in line:
                    system_start_us = epoch_us
                if f"Displayed {package}/" in line:
                    duration = re.search(r": \+(?:(\d+)s)?(\d+)ms", line)
                    if duration:
                        system_ttid_ms = int(duration[1] or 0) * 1000 + int(duration[2])
                if "WAN_STARTUP {" in line:
                    event = json.loads(line.split("WAN_STARTUP ", 1)[1])
                    if event.get("point") not in POINTS or event.get("schema") != 1:
                        continue
                    events.setdefault(event["point"], event)
                    if event["point"] == "home_terminal_raster":
                        terminal_at = time.monotonic()
        finally:
            process.terminate()
            process.wait(timeout=5)
            reader.join(timeout=1)
        if launch_us is None:
            raise RuntimeError("Missing device launch marker")
        if "dart_main" not in events:
            raise RuntimeError("No diagnostic main event: verify icon, APK and build flag")
        times = {key: round((value["epoch_us"] - launch_us) / 1000, 3)
                 for key, value in events.items()}
        if any(value < 0 for value in times.values()):
            raise RuntimeError("Clock correlation failed")
        sample = {"sample": index + 1, "kind": "force_stop_cold",
                  "launcher_request_ms": times,
                  "system_start_after_request_ms": None if system_start_us is None
                  else round((system_start_us - launch_us) / 1000, 3),
                  "system_ttid_ms": system_ttid_ms,
                  "events": events}
        sample["system_start_ms"] = (
            {key: round(value - sample["system_start_after_request_ms"], 3)
             for key, value in times.items()}
            if system_start_us is not None else {}
        )
        samples.append(sample)
        print(json.dumps({"sample": index + 1, "ms": times,
                          "outcome": events.get("home_terminal_raster", {}).get("outcome", "timeout")},
                         ensure_ascii=False), flush=True)
    summary = {}
    for point in POINTS:
        values = [sample["launcher_request_ms"][point] for sample in samples
                  if point in sample["launcher_request_ms"]]
        if values:
            summary[point] = {"n": len(values), "median_ms": statistics.median(values),
                              "min_ms": min(values), "max_ms": max(values)}
    system_summary = {}
    for point in POINTS:
        values = [sample["system_start_ms"][point] for sample in samples
                  if point in sample["system_start_ms"]]
        if values:
            system_summary[point] = {"n": len(values), "median_ms": statistics.median(values),
                                     "min_ms": min(values), "max_ms": max(values)}
    values = [sample["system_ttid_ms"] for sample in samples
              if sample["system_ttid_ms"] is not None]
    if values:
        system_summary["android_ttid"] = {"n": len(values), "median_ms": statistics.median(values),
                                          "min_ms": min(values), "max_ms": max(values)}
    result = {"schema": 1, "device": args.device, "mode": "profile",
              "package": package, "label": args.label,
              "guest_isolated": package.endswith(".startup"),
              "origin": "device log marker immediately before desktop input tap",
              "endpoint": "Flutter rasterFinish; excludes display scanout",
              "network": "authorized real public read-only interfaces",
              "samples": samples, "summary": summary, "system_start_summary": system_summary}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(summary, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
