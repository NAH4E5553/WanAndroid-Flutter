"""Aggregate MI9 Profile A/B samples from measure_android_startup.py.

Reads perf/round*.json (schema 2), groups by the recorded group label
(anim_fast/anim_delayed/noanim_fast/noanim_delayed), reports per-point
median/min/max from the launcher-request origin, the layer-exit contract
status, and the with/without-animation deltas per scenario. Five samples do
not claim a stable p95; medians are descriptive only.
"""
import argparse
import glob
import json
import sys
from pathlib import Path

from measure_android_startup import validate_sample, point_statistics

POINTS = ("first_raster", "startup_layer_exit", "home_first_raster",
          "home_articles_raster", "home_terminal_raster",
          "home_content_raster", "system_ttid")


def aggregate(paths):
    groups = {}
    bad = []
    result = {"groups": {}, "contract_violations": bad, "order": []}
    for path in paths:
        data = json.loads(Path(path).read_text())
        label = data.get("group") or Path(path).stem
        samples = data.get("samples", [])
        if not samples:
            bad.append({"file": Path(path).name, "details": ["No samples"]})
        for sample in samples:
            ok, details, outcome = validate_sample(
                sample, "success" if data.get("network", "").startswith(
                    "fixed fake") else None)
            entry = {**sample, "file": Path(path).name, "outcome": outcome,
                     "validated": ok, "validation_details": details}
            groups.setdefault(label, []).append(entry)
            if not ok:
                bad.append({"group": label, "file": Path(path).name,
                            "sample": sample.get("sample"), "details": details})
    for label in sorted(groups):
        samples = groups[label]
        total = len(samples)
        result["order"].append(f"{label}:n={total}")
        stats = {}
        for point in POINTS:
            observed = [s.get("system_ttid_ms") if point == "system_ttid"
                        else s.get("launcher_request_ms", {}).get(point)
                        for s in samples]
            stats[point] = point_statistics(observed, total)
        stats["startup_layer_exit_occurrences"] = {
            "values": [s.get("point_occurrences", {}).get(
                "startup_layer_exit", 0) for s in samples]}
        stats["samples"] = total
        stats["valid_samples"] = sum(s["validated"] for s in samples)
        stats["outcomes"] = {outcome: sum(s["outcome"] == outcome for s in samples)
                             for outcome in sorted({s["outcome"] for s in samples})}
        stats["files"] = sorted({s["file"] for s in samples})
        # Preserve failed samples and their cause, even if the old flag said OK.
        stats["sample_validation"] = [
            {key: s.get(key) for key in ("file", "sample", "outcome", "validated",
                                       "validation_details")} for s in samples]
        result["groups"][label] = stats
    deltas = {}
    for scenario in ("fast", "delayed"):
        anim = result["groups"].get(f"anim_{scenario}")
        noanim = result["groups"].get(f"noanim_{scenario}")
        if not anim or not noanim:
            continue
        if any(g["valid_samples"] != g["samples"] or
               g["outcomes"] != {"success": g["samples"]} for g in (anim, noanim)):
            deltas[scenario] = {"unavailable": "Incomplete or non-success samples"}
            continue
        deltas[scenario] = {}
        for point in POINTS:
            a, n = anim[point], noanim[point]
            if a["n"] != a["total"] or n["n"] != n["total"]:
                continue
            deltas[scenario][point] = {
                "anim_median_ms": a["median_ms"], "noanim_median_ms": n["median_ms"],
                "delta_ms": round(a["median_ms"] - n["median_ms"], 3)}
    result["animation_deltas"] = deltas
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", required=True,
                        help="Glob of per-run JSON files")
    parser.add_argument("--output", required=True, help="Summary JSON path")
    args = parser.parse_args()
    paths = sorted(glob.glob(args.inputs))
    if not paths:
        parser.error("No input samples matched")
    result = aggregate(paths)
    bad = result["contract_violations"]
    deltas = result["animation_deltas"]
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"order": result["order"], "violations": bad,
                      "deltas": deltas}, ensure_ascii=False, indent=2))
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
