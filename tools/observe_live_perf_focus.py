"""Observe one requested game's focus, or validate saved evidence without Windows APIs."""
from __future__ import annotations

import json
import math
from pathlib import Path
import sys
import time


def _number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def select_game_window(windows, target_pid):
    """Pure identity selection. Process.MainWindowHandle/PID alone are insufficient."""
    candidates = []
    if isinstance(windows, list):
        for window in windows:
            if not isinstance(window, dict):
                continue
            if (type(window.get("pid")) is int and window["pid"] == target_pid
                    and type(window.get("hwnd")) is int and window["hwnd"] > 0
                    and window.get("title") == "Dota 2" and window.get("visible") is True
                    and window.get("client_rect_valid") is True
                    and type(window.get("client_width")) is int and window["client_width"] >= 640
                    and type(window.get("client_height")) is int and window["client_height"] >= 360):
                candidates.append(window)
    result = {"valid": False, "invalid_reasons": [], "window": None, "candidate_count": len(candidates)}
    if len(candidates) != 1:
        result["invalid_reasons"].append("real_game_window_missing_or_ambiguous")
        return result
    result["window"] = dict(candidates[0])
    if candidates[0].get("iconic") is not False:
        result["invalid_reasons"].append("real_game_window_iconic_or_unknown")
    result["valid"] = not result["invalid_reasons"]
    return result


def validate_focus_report(report, expected_pid, seconds, expected_hwnd=None):
    """Pure validation. One-Hz observations cannot prove uninterrupted focus."""
    reasons = []
    expected_count = max(1, math.ceil(seconds) - 1)
    result = {"valid": False, "invalid_reasons": reasons, "sample_count": 0,
              "expected_sample_count": expected_count, "coverage_seconds": None,
              "max_gap_seconds": None, "sampling_interval_seconds": 1,
              "maximum_accepted_gap_seconds": 1.75,
              "minimum_accepted_coverage_seconds": seconds - 1.25,
              "measurement_limit": "Positive once-per-second observations do not prove continuous foreground visibility between observations."}
    if not isinstance(report, dict):
        reasons.append("focus_report_not_object")
        return result
    if type(report.get("target_pid")) is not int or report["target_pid"] != expected_pid:
        reasons.append("focus_pid_mismatch")
    if type(report.get("requested_seconds")) is not int or report["requested_seconds"] != seconds:
        reasons.append("focus_requested_duration_mismatch")
    target_hwnd = report.get("target_hwnd")
    selection = select_game_window([report.get("target_window")], expected_pid)
    if not selection["valid"] or type(target_hwnd) is not int or target_hwnd != selection["window"]["hwnd"]:
        reasons.append("focus_real_target_window_unconfirmed")
    if expected_hwnd is not None and target_hwnd != expected_hwnd:
        reasons.append("focus_target_window_differs_from_restore")
    clock_keys = ("observation_start_unix_seconds", "observation_end_unix_seconds",
                  "observation_start_monotonic_seconds", "observation_end_monotonic_seconds")
    valid_clocks = all(_number(report.get(key)) for key in clock_keys)
    if not valid_clocks:
        reasons.append("focus_clock_bounds_missing_or_nonfinite")
    else:
        duration = report[clock_keys[3]] - report[clock_keys[2]]
        unix_duration = report[clock_keys[1]] - report[clock_keys[0]]
        result["coverage_seconds"] = duration
        if duration <= 0 or unix_duration <= 0:
            reasons.append("focus_clock_bounds_not_increasing")
        if duration < seconds - 1.25:
            reasons.append("focus_observation_duration_too_short")
        if abs(unix_duration - duration) > .5:
            reasons.append("focus_wall_clock_changed")
    samples = report.get("samples")
    if not isinstance(samples, list):
        reasons.append("focus_samples_not_list")
        return result
    result["sample_count"] = len(samples)
    if len(samples) < expected_count:
        reasons.append("focus_observation_count_too_low")
    times = []
    for sample in samples:
        if not isinstance(sample, dict):
            reasons.append("focus_sample_not_object")
            continue
        value = sample.get("seconds")
        if not _number(value) or value < 0:
            reasons.append("focus_sample_time_invalid")
        else:
            if times and value <= times[-1]:
                reasons.append("focus_sample_times_not_increasing")
            times.append(value)
        if sample.get("game_foreground") is not True:
            reasons.append("game_not_foreground_or_unknown")
        if sample.get("foreground_iconic") is not False:
            reasons.append("game_iconic_or_unknown")
        if (type(sample.get("foreground_hwnd")) is not int or sample["foreground_hwnd"] != target_hwnd
                or type(sample.get("foreground_pid")) is not int or sample["foreground_pid"] != expected_pid):
            reasons.append("foreground_window_identity_mismatch")
        if (sample.get("target_window_valid") is not True
                or type(sample.get("target_client_width")) is not int or sample["target_client_width"] < 640
                or type(sample.get("target_client_height")) is not int or sample["target_client_height"] < 360):
            reasons.append("focus_real_target_window_invalid_during_capture")
    if valid_clocks and times:
        duration = result["coverage_seconds"]
        if times[-1] > duration + .05:
            reasons.append("focus_sample_outside_observation_bounds")
        gaps = [times[0], duration - times[-1]] + [b - a for a, b in zip(times, times[1:])]
        result["max_gap_seconds"] = max(gaps)
        if result["max_gap_seconds"] > 1.75:
            reasons.append("focus_observation_gap_too_large")
    result["invalid_reasons"] = sorted(set(reasons))
    result["valid"] = not result["invalid_reasons"]
    return result


def observe(target_pid, seconds, delay):
    # Importing the module for pure validation never initializes Windows APIs.
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.IsIconic.argtypes = [wintypes.HWND]
    user32.IsIconic.restype = wintypes.BOOL
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowTextW.restype = ctypes.c_int

    class Rect(ctypes.Structure):
        _fields_ = [(name, wintypes.LONG) for name in ("left", "top", "right", "bottom")]

    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(Rect)]
    user32.GetClientRect.restype = wintypes.BOOL
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL

    def enumerate_windows():
        windows = []

        @callback_type
        def callback(handle, _argument):
            owner = wintypes.DWORD()
            user32.GetWindowThreadProcessId(handle, ctypes.byref(owner))
            if owner.value == target_pid:
                title = ctypes.create_unicode_buffer(512)
                user32.GetWindowTextW(handle, title, len(title))
                rect = Rect()
                valid_rect = bool(user32.GetClientRect(handle, ctypes.byref(rect)))
                windows.append({"hwnd": int(handle), "pid": owner.value, "title": title.value,
                                "visible": bool(user32.IsWindowVisible(handle)), "iconic": bool(user32.IsIconic(handle)),
                                "client_rect_valid": valid_rect, "client_width": rect.right - rect.left if valid_rect else 0,
                                "client_height": rect.bottom - rect.top if valid_rect else 0})
            return True

        if not user32.EnumWindows(callback, 0):
            return []
        return windows

    time.sleep(delay)
    start, unix_start = time.perf_counter(), time.time()
    initial_selection = select_game_window(enumerate_windows(), target_pid)
    initial_window = initial_selection["window"]
    target_hwnd = initial_window["hwnd"] if initial_window else None
    samples, tick = [], 0
    while time.perf_counter() - start < seconds:
        handle = user32.GetForegroundWindow()
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(handle, ctypes.byref(owner))
        selection = select_game_window(enumerate_windows(), target_pid)
        window = selection["window"]
        target_valid = selection["valid"] and window["hwnd"] == target_hwnd
        foreground_hwnd = int(handle or 0)
        samples.append({"seconds": round(time.perf_counter() - start, 6),
                        "foreground_pid": owner.value,
                        "foreground_hwnd": foreground_hwnd,
                        "target_window_valid": target_valid,
                        "target_client_width": window["client_width"] if window else None,
                        "target_client_height": window["client_height"] if window else None,
                        "window_candidate_count": selection["candidate_count"],
                        "game_foreground": target_valid and owner.value == target_pid and foreground_hwnd == target_hwnd,
                        "foreground_iconic": window["iconic"] if window and window["hwnd"] == target_hwnd else None})
        tick += 1
        # Fixed deadlines avoid cumulative sleep drift during a long capture.
        time.sleep(max(0, min(start + tick, start + seconds) - time.perf_counter()))
    end, unix_end = time.perf_counter(), time.time()
    report = {"target_pid": target_pid, "requested_seconds": seconds, "delay_seconds": delay,
              "target_hwnd": target_hwnd, "target_window": initial_window, "initial_window_selection": initial_selection,
              "observation_start_unix_seconds": unix_start, "observation_end_unix_seconds": unix_end,
              "observation_start_monotonic_seconds": start, "observation_end_monotonic_seconds": end,
              "samples": samples,
              "all_game_foreground": bool(samples) and all(x["game_foreground"] and x["foreground_iconic"] is False for x in samples)}
    report["validation"] = validate_focus_report(report, target_pid, seconds)
    return report


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] == "--validate-json":
        if len(args) not in (4, 5):
            raise SystemExit("usage: --validate-json report.json pid seconds [expected_hwnd]")
        report = json.loads(Path(args[1]).read_text(encoding="utf-8"))
        expected_hwnd = int(args[4]) if len(args) == 5 else None
        print(json.dumps(validate_focus_report(report, int(args[2]), int(args[3]), expected_hwnd), allow_nan=False))
        return
    if len(args) not in (2, 3):
        raise SystemExit("usage: pid seconds [delay]")
    target_pid, seconds = int(args[0]), int(args[1])
    delay = int(args[2]) if len(args) == 3 else 0
    if not (target_pid > 0 and 1 <= seconds <= 140 and 0 <= delay <= 20):
        raise SystemExit("invalid observer arguments")
    print(json.dumps(observe(target_pid, seconds, delay), allow_nan=False))


if __name__ == "__main__":
    main()
