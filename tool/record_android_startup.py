"""Android Launcher cold-start screen recording for the STARTUP-02 review.

Starts the device-side screenrecord BEFORE anything else so the launcher
desktop is captured, force-stops only the target test package and confirms
the process is gone, verifies the desktop icon via accessibility bounds
(uiautomator dump is parsed on the host from the pulled XML; only the target
icon node is inspected), taps it, then waits for the fixed-duration recording
to finish and pulls the unedited video. No splicing, no slow motion.
"""
import argparse
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--label", required=True,
                        help="Exact launcher content-desc of the target icon")
    parser.add_argument("--output", required=True, help="Local mp4 path")
    parser.add_argument("--duration", type=float, default=15.0)
    parser.add_argument("--bit-rate", type=int, default=12_000_000)
    parser.add_argument("--desktop-page",
                        help="MIUI launcher page label to navigate to first")
    parser.add_argument("--drawer", action="store_true",
                        help="Icon lives in the launcher app drawer: swipe "
                             "up from the hotseat, then locate and tap the "
                             "verified icon (recorded deviation from a "
                             "home-screen tap)")
    parser.add_argument("--pre-tap-settle", type=float, default=1.0)
    args = parser.parse_args()
    adb = [args.adb, "-s", args.device]

    def shell(*command, check=True):
        result = subprocess.run(adb + ["shell", *command],
                                capture_output=True, text=True)
        if check and result.returncode:
            raise RuntimeError(f"ADB shell {command[0]} failed: "
                               f"{result.returncode}")
        return result.stdout

    device_path = "/sdcard/startup_review_rec.mp4"
    shell("input", "keyevent", "KEYCODE_HOME")
    time.sleep(0.8)
    recorder = subprocess.Popen(
        adb + ["shell", "screenrecord", "--time-limit", str(args.duration),
               "--bit-rate", str(args.bit_rate), device_path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.0)
    # 录制已在跑、桌面已入镜;现在仅终止本次测试身份并确认退出。
    shell("am", "force-stop", args.package)
    if shell("pidof", args.package, check=False).strip():
        raise RuntimeError("Cold-start premise failed: process still alive")
    time.sleep(0.5)
    if args.drawer:
        subprocess.run(adb + ["shell", "input", "swipe", "540", "1900",
                              "540", "900", "200"], check=True,
                       capture_output=True)
        time.sleep(1.2)
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
            bounds = [int(v) for v in
                      re.findall(r"\d+", pages[0].get("bounds", ""))]
            left, top, right, bottom = bounds
            shell("input", "tap", str((left + right) // 2),
                  str((top + bottom) // 2))
            time.sleep(0.5)
            shell("uiautomator", "dump", temporary)
            root = ET.fromstring(shell("cat", temporary))
        icons = [node for node in root.iter("node")
                 if node.get("content-desc") == args.label
                 and node.get("clickable") == "true"]
        target = None
        for icon in icons:
            bounds = [int(v) for v in
                      re.findall(r"\d+", icon.get("bounds", ""))]
            if len(bounds) == 4:
                target = ((bounds[0] + bounds[2]) // 2,
                          (bounds[1] + bounds[3]) // 2)
        if target is None:
            raise RuntimeError(f"Desktop icon {args.label!r} not found")
        time.sleep(max(0.0, args.pre_tap_settle - 0.5))
        print(json.dumps({"stage": "tap", "icon": target}), flush=True)
        shell("input", "tap", str(target[0]), str(target[1]))
    finally:
        shell("rm", "-f", temporary)
    recorder.wait(timeout=args.duration + 30)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(adb + ["pull", device_path, str(output)], check=True,
                   capture_output=True)
    shell("rm", "-f", device_path)
    print(json.dumps({"video": str(output), "icon_tap": target,
                      "duration_s": args.duration,
                      "bytes": output.stat().st_size}, ensure_ascii=False))


if __name__ == "__main__":
    main()
