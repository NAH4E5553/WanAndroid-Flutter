"""Pixel-level phase timeline for STARTUP-02 review recordings.

For every extracted frame (PNG, extracted at a fixed fps by ffmpeg) this
script records:
- corner background color (splash background vs home surface),
- launcher-glyph pixel count and centroid (icon presence/position/size),
- phase inferred from those two signals.

Output: one CSV per video plus an anomaly summary (blank non-splash frames
between splash frames, icon centroid jumps, background flips mid-splash,
unexpected second icon size). Pixel values only — no vision-model guessing.
"""
import argparse
import csv
import subprocess
import sys
from pathlib import Path


def frame_size(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True).stdout.strip()
    w, h = out.split(",")
    return int(w), int(h)


def region_rgb(path, x, y, w, h):
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", str(path), "-vf",
         f"crop={w}:{h}:{x}:{y}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True).stdout
    n = len(raw) // 3
    if n == 0:
        return None
    r = sum(raw[i * 3] for i in range(n)) // n
    g = sum(raw[i * 3 + 1] for i in range(n)) // n
    b = sum(raw[i * 3 + 2] for i in range(n)) // n
    return r, g, b


def glyph_stats(path, width, height):
    """Blue glyph mask over the center band via ffmpeg rawvideo decode."""
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", str(path), "-vf",
         f"crop={width//2}:{height//3}:{width//4}:{height//3},"
         f"scale=120:160", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True).stdout
    count = 0
    sx = sy = 0
    for i in range(0, len(raw) // 3):
        r, g, b = raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]
        # 启动图标蓝 #465CFF=(70,92,255);淡出时亮度升高,放宽上界
        if b > 150 and b > r + 60 and b > g + 40 and r < 200:
            x = i % 120
            y = i // 120
            sx += x
            sy += y
            count += 1
    if count == 0:
        return 0, None, None
    return count, sx / count, sy / count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", required=True,
                        help="Directory of frame PNGs")
    parser.add_argument("--pattern", default="f_*.png",
                        help="Frame filename glob (default f_*.png)")
    parser.add_argument("--output", required=True, help="CSV output path")
    parser.add_argument("--dark-splash", action="store_true",
                        help="Expect black splash background (night mode)")
    args = parser.parse_args()
    frames = sorted(Path(args.dir).glob(args.pattern))
    if not frames:
        sys.exit("no frames")
    w, h = frame_size(frames[0])
    rows = []
    for index, frame in enumerate(frames, start=1):
        corner = region_rgb(frame, w // 2 - 20, 150, 40, 40)
        count, cx, cy = glyph_stats(frame, w, h)
        r, g, b = corner
        if args.dark_splash:
            splash_bg = r < 40 and g < 40 and b < 40
        else:
            splash_bg = r > 215 and g > 215 and b > 215
        phase = "other"
        if count > 40 and splash_bg:
            phase = "splash"
        elif count > 40:
            phase = "splash_blend"
        elif splash_bg:
            phase = "blank_splashbg"
        rows.append({"frame": index, "time_s": round(index / 5, 2),
                     "corner_rgb": f"{r},{g},{b}", "glyph_px": count,
                     "glyph_cx": None if cx is None else round(cx, 1),
                     "glyph_cy": None if cy is None else round(cy, 1),
                     "phase": phase})
    anomalies = []
    splash_rows = [row for row in rows if row["phase"].startswith("splash")]
    for prev, cur in zip(rows, rows[1:]):
        if (prev["phase"] == "splash" and cur["phase"] == "splash"
                and prev["glyph_cx"] is not None
                and cur["glyph_cx"] is not None):
            jump = max(abs(prev["glyph_cx"] - cur["glyph_cx"]),
                       abs(prev["glyph_cy"] - cur["glyph_cy"]))
            if jump > 12:
                anomalies.append(
                    f"frame {cur['frame']}: icon centroid jump {jump:.0f}px")
    for i in range(1, len(rows) - 1):
        if (rows[i - 1]["phase"] == "splash" and rows[i]["phase"] == "other"
                and rows[i + 1]["phase"].startswith("splash")):
            anomalies.append(
                f"frame {rows[i]['frame']}: non-splash frame between splash "
                f"frames (corner={rows[i]['corner_rgb']})")
    sizes = [row["glyph_px"] for row in splash_rows]
    if sizes and max(sizes) > 2.5 * min(sizes):
        anomalies.append("splash glyph size varies more than 2.5x "
                         "(possible second composition)")
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"frames={len(rows)} splash_like={len(splash_rows)} "
          f"anomalies={len(anomalies)}")
    for line in anomalies:
        print("ANOMALY:", line)


if __name__ == "__main__":
    main()
