"""Acceptance regressions: missing home timings must not pass sampling."""
import unittest
import json
import tempfile
from pathlib import Path

from summarize_startup_perf import aggregate

from measure_android_startup import contract_check, summarize


class StartupMeasureContractAcceptance(unittest.TestCase):
    def test_animation_exit_alone_is_not_a_complete_home_sample(self):
        ok, _ = contract_check(
            {"startup_layer_exit": 1}, {"startup_layer_exit": 100.0}, True
        )
        self.assertFalse(ok, "Missing all required home timings must fail")

    def test_no_animation_empty_sample_is_not_valid(self):
        ok, _ = contract_check({}, {}, False)
        self.assertFalse(ok, "No-animation mode still requires home timings")

    def test_complete_ordered_sample_remains_valid(self):
        times = {
            "first_raster": 50.0,
            "startup_layer_exit": 100.0,
            "home_first_raster": 110.0,
            "home_articles_raster": 120.0,
            "home_terminal_raster": 130.0,
            "home_content_raster": 130.0,
        }
        counts = {point: 1 for point in times}
        self.assertTrue(contract_check(counts, times, True)[0])
        del times["startup_layer_exit"]
        del counts["startup_layer_exit"]
        self.assertTrue(contract_check(counts, times, False)[0])

    def complete(self):
        names = ["first_raster", "startup_layer_exit", "home_first_raster",
                 "home_articles_raster", "home_terminal_raster", "home_content_raster"]
        return {p: 1 for p in names}, {p: (i + 1) * 100 for i, p in enumerate(names)}

    def test_each_missing_duplicate_or_invalid_point_is_rejected(self):
        counts, times = self.complete()
        for expected in (True, False):
            for point in times:
                if point == "startup_layer_exit" and not expected:
                    continue
                with self.subTest(expected=expected, point=point):
                    missing = dict(times)
                    del missing[point]
                    self.assertFalse(contract_check(counts, missing, expected)[0])
                    self.assertFalse(contract_check({**counts, point: 2}, times, expected)[0])
                    for value in (None, -1, float("nan"), float("inf"), True):
                        self.assertFalse(contract_check(counts, {**times, point: value}, expected)[0])

    def test_content_cannot_precede_exit_or_terminal(self):
        counts, times = self.complete()
        self.assertFalse(contract_check(counts, {**times, "home_content_raster": 350}, True)[0])

    def test_empty_error_and_timeout_remain_distinct(self):
        counts, times = self.complete()
        self.assertTrue(contract_check(counts, times, True, "empty")[0])
        self.assertFalse(contract_check(counts, times, True, "error")[0])
        del times["home_content_raster"]
        del counts["home_content_raster"]
        self.assertTrue(contract_check(counts, times, True, "error")[0])
        self.assertFalse(contract_check(counts, times, True, "timeout")[0])

    def test_summary_rechecks_saved_true_and_keeps_missing_denominator(self):
        counts, times = self.complete()
        sample = {"sample": 1, "contract_ok": True,
                  "point_occurrences": counts, "launcher_request_ms": times,
                  "layer_exit_expected": True,
                  "events": {"home_terminal_raster": {"outcome": "success"}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.json"
            path.write_text(json.dumps({"group": "anim_fast", "samples": [sample]}))
            self.assertFalse(aggregate([path])["contract_violations"])
            del times["home_first_raster"]
            path.write_text(json.dumps({"group": "anim_fast", "samples": [sample]}))
            result = aggregate([path])
            self.assertTrue(result["contract_violations"])
            group = result["groups"]["anim_fast"]
            self.assertEqual(group["valid_samples"], 0)
            self.assertEqual(group["home_first_raster"]["n"], 0)
            self.assertEqual(group["home_first_raster"]["total"], 1)
            self.assertIsNone(group["home_first_raster"]["median_ms"])

    def test_sampler_summary_keeps_absent_points(self):
        summary, system = summarize([{"launcher_request_ms": {"first_raster": 100}}])
        self.assertEqual(summary["home_content_raster"]["missing_or_invalid"], 1)
        self.assertEqual(summary["home_content_raster"]["total"], 1)
        self.assertIsNone(summary["home_content_raster"]["median_ms"])
        self.assertEqual(system["android_ttid"]["n"], 0)


if __name__ == "__main__":
    unittest.main()
