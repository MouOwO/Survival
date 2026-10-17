"""Pure report-validation tests; never sample windows or contact a running game.

Run after the observer API is implemented:
    python -B tools/test_live_perf_focus.py
"""
from __future__ import annotations

from copy import deepcopy
import sys
import unittest

sys.dont_write_bytecode = True

import observe_live_perf_focus as focus


TARGET_PID = 4242
TARGET_HWND = 3675722


def game_window(hwnd: int = TARGET_HWND) -> dict:
    return {
        "hwnd": hwnd,
        "pid": TARGET_PID,
        "title": "Dota 2",
        "visible": True,
        "iconic": False,
        "client_rect_valid": True,
        "client_width": 1600,
        "client_height": 900,
    }


def focus_sample(seconds: float) -> dict:
    return {
        "seconds": seconds,
        "game_foreground": True,
        "foreground_iconic": False,
        "foreground_hwnd": TARGET_HWND,
        "foreground_pid": TARGET_PID,
        "target_window_valid": True,
        "target_client_width": 1600,
        "target_client_height": 900,
    }


def report_for(seconds: int = 30) -> dict:
    """One focus observation per second, with explicit capture clock bounds."""
    return {
        "target_pid": TARGET_PID,
        "target_hwnd": TARGET_HWND,
        "target_window": game_window(),
        "requested_seconds": seconds,
        "samples": [focus_sample(float(index)) for index in range(seconds)],
        "observation_start_unix_seconds": 1700000000.0,
        "observation_end_unix_seconds": 1700000000.0 + seconds,
        "observation_start_monotonic_seconds": 1000.0,
        "observation_end_monotonic_seconds": 1000.0 + seconds,
    }


class FocusReportValidationTests(unittest.TestCase):
    def validate(self, report: dict, seconds: int = 30,
                 expected_hwnd: int | None = None) -> dict:
        original = deepcopy(report)
        result = focus.validate_focus_report(
            report, TARGET_PID, seconds, expected_hwnd=expected_hwnd,
        )
        self.assertEqual(report, original, "validation must leave evidence unchanged")
        self.assertIsInstance(result, dict)
        self.assertTrue({
            "valid", "invalid_reasons", "sample_count", "expected_sample_count",
            "coverage_seconds", "max_gap_seconds",
        }.issubset(result))
        self.assertIsInstance(result["valid"], bool)
        self.assertIsInstance(result["invalid_reasons"], list)
        return result

    def assert_invalid(self, report: dict, seconds: int = 30,
                       expected_hwnd: int | None = None) -> dict:
        result = self.validate(report, seconds, expected_hwnd)
        self.assertFalse(result["valid"])
        self.assertTrue(result["invalid_reasons"], "invalid evidence needs an explanation")
        return result

    def test_complete_30_and_120_second_reports(self):
        for seconds in (30, 120):
            with self.subTest(seconds=seconds):
                result = self.validate(report_for(seconds), seconds, TARGET_HWND)
                self.assertTrue(result["valid"], result["invalid_reasons"])
                self.assertEqual(result["invalid_reasons"], [])
                self.assertEqual(result["sample_count"], seconds)
                self.assertGreater(result["expected_sample_count"], 0)
                self.assertLessEqual(result["expected_sample_count"], seconds)
                self.assertGreaterEqual(result["coverage_seconds"], seconds - 1.25)
                self.assertLessEqual(result["max_gap_seconds"], 1.75)

    def test_empty_samples_cannot_pass_by_vacuous_all(self):
        report = report_for()
        report["samples"] = []
        report["all_game_foreground"] = True
        result = self.assert_invalid(report)
        self.assertEqual(result["sample_count"], 0)

    def test_insufficient_samples_despite_long_enough_duration(self):
        report = report_for()
        # Cover 28.9 seconds without any gap exceeding 1.75 seconds.
        report["samples"] = [
            focus_sample(index * 1.7)
            for index in range(18)
        ]
        result = self.assert_invalid(report)
        self.assertEqual(result["sample_count"], 18)
        self.assertGreater(result["expected_sample_count"], result["sample_count"])

    def test_report_pid_must_match_requested_game(self):
        report = report_for()
        report["target_pid"] = TARGET_PID + 1
        self.assert_invalid(report)

    def test_requested_seconds_must_match_validation_request(self):
        report = report_for()
        report["requested_seconds"] = 120
        self.assert_invalid(report)

    def test_one_nonforeground_sample_invalidates_capture(self):
        report = report_for()
        report["samples"][10]["game_foreground"] = False
        report["samples"][10]["foreground_iconic"] = None
        self.assert_invalid(report)

    def test_one_iconic_sample_invalidates_capture(self):
        report = report_for()
        report["samples"][10]["foreground_iconic"] = True
        self.assert_invalid(report)

    def test_unknown_or_nonboolean_focus_is_not_positive_evidence(self):
        for field, value in (
            ("game_foreground", None),
            ("game_foreground", "true"),
            ("foreground_iconic", None),
            ("foreground_iconic", "false"),
        ):
            with self.subTest(field=field, value=value):
                report = report_for()
                report["samples"][10][field] = value
                self.assert_invalid(report)

    def test_sample_gap_exceeding_1_75_seconds(self):
        report = report_for()
        del report["samples"][10]
        result = self.assert_invalid(report)
        self.assertGreater(result["max_gap_seconds"], 1.75)

    def test_observed_duration_below_requested_minus_1_25_seconds(self):
        report = report_for()
        duration = 28.0
        report["observation_end_unix_seconds"] = report["observation_start_unix_seconds"] + duration
        report["observation_end_monotonic_seconds"] = report["observation_start_monotonic_seconds"] + duration
        for index, sample in enumerate(report["samples"]):
            sample["seconds"] = index * duration / 29
        self.assert_invalid(report)

    def test_start_and_end_clock_fields_are_required(self):
        for field in (
            "observation_start_unix_seconds",
            "observation_end_unix_seconds",
            "observation_start_monotonic_seconds",
            "observation_end_monotonic_seconds",
        ):
            with self.subTest(field=field):
                report = report_for()
                del report[field]
                self.assert_invalid(report)

    def test_sample_times_must_strictly_increase(self):
        for replacement in (9.0, 8.5):
            with self.subTest(replacement=replacement):
                report = report_for()
                report["samples"][10]["seconds"] = replacement
                self.assert_invalid(report)

    def test_end_clocks_must_follow_start_clocks(self):
        for clock in ("unix", "monotonic"):
            for offset in (0.0, -1.0):
                with self.subTest(clock=clock, offset=offset):
                    report = report_for()
                    report[f"observation_end_{clock}_seconds"] = (
                        report[f"observation_start_{clock}_seconds"] + offset
                    )
                    self.assert_invalid(report)

    def test_sample_times_must_be_finite(self):
        for value in (float("inf"), float("-inf")):
            with self.subTest(value=value):
                report = report_for()
                report["samples"][10]["seconds"] = value
                self.assert_invalid(report)

    def test_foreground_same_pid_but_different_hwnd_is_not_the_game_window(self):
        report = report_for()
        report["samples"][10]["foreground_hwnd"] = TARGET_HWND + 1
        self.assert_invalid(report, expected_hwnd=TARGET_HWND)

    def test_foreground_pid_must_match_even_when_hwnd_matches(self):
        report = report_for()
        report["samples"][10]["foreground_pid"] = TARGET_PID + 1
        self.assert_invalid(report, expected_hwnd=TARGET_HWND)

    def test_report_hwnd_must_match_expected_capture_window(self):
        self.assert_invalid(report_for(), expected_hwnd=TARGET_HWND + 1)

    def test_report_window_metadata_must_match_target_hwnd(self):
        report = report_for()
        report["target_window"]["hwnd"] = TARGET_HWND + 1
        self.assert_invalid(report, expected_hwnd=TARGET_HWND)

    def test_target_window_becoming_invalid_during_capture_is_rejected(self):
        report = report_for()
        report["samples"][10]["target_window_valid"] = False
        self.assert_invalid(report, expected_hwnd=TARGET_HWND)

    def test_missing_window_identity_or_validity_is_rejected(self):
        for field in ("foreground_hwnd", "foreground_pid", "target_window_valid"):
            with self.subTest(field=field):
                report = report_for()
                del report["samples"][10][field]
                self.assert_invalid(report, expected_hwnd=TARGET_HWND)

    def test_target_client_collapsing_during_capture_is_rejected(self):
        report = report_for()
        report["samples"][10]["target_client_width"] = 0
        report["samples"][10]["target_client_height"] = 0
        self.assert_invalid(report, expected_hwnd=TARGET_HWND)


class GameWindowSelectionTests(unittest.TestCase):
    def select(self, windows: list[dict]) -> dict:
        original = deepcopy(windows)
        result = focus.select_game_window(windows, TARGET_PID)
        self.assertEqual(windows, original, "selection must leave window evidence unchanged")
        self.assertTrue({"valid", "invalid_reasons", "window", "candidate_count"}.issubset(result))
        self.assertIsInstance(result["valid"], bool)
        self.assertIsInstance(result["invalid_reasons"], list)
        return result

    def assert_invalid(self, windows: list[dict]) -> dict:
        result = self.select(windows)
        self.assertFalse(result["valid"])
        self.assertTrue(result["invalid_reasons"])
        return result

    def test_single_real_game_window_is_selected(self):
        window = game_window()
        result = self.select([window])
        self.assertTrue(result["valid"], result["invalid_reasons"])
        self.assertEqual(result["window"], window)
        self.assertEqual(result["candidate_count"], 1)

    def test_same_pid_empty_title_zero_size_fake_window_is_rejected(self):
        window = game_window()
        window.update(title="", client_width=0, client_height=0)
        result = self.assert_invalid([window])
        self.assertEqual(result["candidate_count"], 0)

    def test_real_and_fake_windows_select_only_the_real_one(self):
        real = game_window()
        fake = game_window(TARGET_HWND + 1)
        fake.update(title="", client_width=0, client_height=0)
        for windows in ([fake, real], [real, fake]):
            with self.subTest(fake_first=windows[0] is fake):
                result = self.select(windows)
                self.assertTrue(result["valid"], result["invalid_reasons"])
                self.assertEqual(result["candidate_count"], 1)
                self.assertEqual(result["window"]["hwnd"], TARGET_HWND)

    def test_two_real_windows_are_ambiguous(self):
        result = self.assert_invalid([game_window(), game_window(TARGET_HWND + 1)])
        self.assertEqual(result["candidate_count"], 2)

    def test_unknown_title_visibility_or_client_rect_is_rejected(self):
        for field in ("title", "visible", "client_rect_valid"):
            for missing in (True, False):
                with self.subTest(field=field, missing=missing):
                    window = game_window()
                    if missing:
                        del window[field]
                    else:
                        window[field] = None
                    result = self.assert_invalid([window])
                    self.assertEqual(result["candidate_count"], 0)

    def test_iconic_game_window_is_rejected(self):
        window = game_window()
        window["iconic"] = True
        result = self.assert_invalid([window])
        # Its identity remains diagnosable, but a minimized window cannot be
        # positive foreground evidence or an accepted target.
        self.assertTrue(result["invalid_reasons"])

    def test_wrong_pid_window_is_rejected(self):
        window = game_window()
        window["pid"] = TARGET_PID + 1
        self.assert_invalid([window])

    def test_invisible_or_invalid_rect_window_is_rejected(self):
        for field in ("visible", "client_rect_valid"):
            with self.subTest(field=field):
                window = game_window()
                window[field] = False
                self.assert_invalid([window])

    def test_undersized_client_window_is_rejected(self):
        for width, height in ((639, 900), (1600, 359), (0, 0)):
            with self.subTest(width=width, height=height):
                window = game_window()
                window.update(client_width=width, client_height=height)
                self.assert_invalid([window])


if __name__ == "__main__":
    unittest.main()
