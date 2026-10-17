"""Analyze PresentMon --v1_metrics CSV without contacting or changing the game.

Each ProcessID/SwapChainAddress has an independent cadence. Never combine swap
chains or processes into one FPS value. MsBetweenPresents measures application
present cadence, including presents marked Dropped, rather than GPU work or the
cadence of frames actually displayed on a monitor.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import statistics


REQUIRED = {"ProcessID", "SwapChainAddress", "TimeInSeconds", "MsBetweenPresents"}
COLUMN_ALIASES = {"MsBetweenPresents": ("MsBetweenPresents", "msBetweenPresents")}
THRESHOLDS = (33.33, 50.0, 100.0)


def _finite(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("nonfinite")
    return number


def _pid(value: str) -> int:
    value = value.strip()
    if not re.fullmatch(r"[0-9]+", value) or int(value) <= 0:
        raise ValueError("invalid_process_id")
    return int(value)


def _swapchain(value: str) -> str:
    value = value.strip().lower()
    if not value:
        raise ValueError("missing_swapchain")
    # Native v1 uses a hexadecimal address. Keep the address opaque so a later
    # schema variant cannot accidentally merge two different identities.
    return value


def _percentile(ordered: list[float], fraction: float) -> float:
    index = (len(ordered) - 1) * fraction
    lower = math.floor(index)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


def _dropped(value: str | None) -> bool | None:
    if value is None:
        return None
    value = value.strip().lower()
    if value in {"0", "false"}:
        return False
    if value in {"1", "true"}:
        return True
    return None


def _group_report(key, group):
    intervals = group["intervals"]
    ordered = sorted(intervals)
    total_ms = math.fsum(intervals)
    start = group["first_timestamp"]
    end = group["last_timestamp"]
    span = end - start if start is not None and end is not None else None
    warnings = []
    invalid = sum(group["discarded"].values())
    if invalid:
        warnings.append("Invalid rows were excluded; accepted intervals do not cover the entire timestamp span.")
    if group["dropped_unknown"]:
        warnings.append("Some Dropped values were missing or unrecognized; displayed-frame completeness is unknown.")
    if not intervals:
        warnings.append("No usable intervals remain after excluding the first row and invalid rows.")
    difference = total_ms / 1000 - span if span is not None else None
    if intervals and not invalid and difference is not None and abs(difference) > max(.001, span * .001):
        warnings.append("Summed native intervals and timestamp span differ; inspect capture boundaries or CSV integrity.")
    statistics_report = None
    slowest_report = None
    if intervals:
        statistics_report = {name: round(value, 6) for name, value in {
            "mean": statistics.fmean(intervals),
            "p50": _percentile(ordered, .5),
            "p95": _percentile(ordered, .95),
            "p99": _percentile(ordered, .99),
            "max": ordered[-1],
        }.items()}
        worst_count = max(1, math.ceil(len(intervals) * .01))
        worst = ordered[-worst_count:]
        slowest_report = {
            "fps": round(1000 / statistics.fmean(worst), 6),
            "interval_count": worst_count,
            "fraction_of_accepted_intervals": worst_count / len(intervals),
            "mean_interval_ms": round(statistics.fmean(worst), 6),
            "definition": "1000 divided by the arithmetic mean of the slowest ceil(accepted_interval_count * 0.01) present intervals; not the reciprocal of P99.",
        }
    return {
        "process_id": key[0], "swapchain_address": key[1],
        "applications": sorted(group["applications"]),
        "observed_present_rows": group["rows"],
        "excluded_first_present_rows": 1,
        "discarded_invalid_rows": invalid,
        "discarded_invalid_reasons": dict(sorted(group["discarded"].items())),
        "accepted_interval_count": len(intervals),
        "mean_present_fps": round(1000 * len(intervals) / total_ms, 6) if intervals else None,
        "mean_fps_definition": "accepted_interval_count / sum(accepted MsBetweenPresents in seconds). With no invalid rows this equals (observed_present_rows - 1) / sum.",
        "present_interval_ms": statistics_report,
        "slowest_1_percent_fps": slowest_report,
        "intervals_at_least_ms": {f"{limit:g}": sum(value >= limit for value in intervals) for limit in THRESHOLDS},
        "dropped_present_rows": group["dropped_true"],
        "dropped_status_unknown_rows": group["dropped_unknown"],
        "dropped_metric_note": "Dropped presents remain in present-cadence intervals; mean FPS does not assert displayed FPS.",
        "first_timestamp_seconds": start,
        "last_timestamp_seconds": end,
        "timestamp_span_seconds": round(span, 6) if span is not None else None,
        "accepted_interval_sum_seconds": round(total_ms / 1000, 6),
        "interval_sum_minus_timestamp_span_seconds": round(difference, 6) if difference is not None else None,
        "warnings": warnings,
    }


def analyze(path: Path, process_id: int | None = None, swapchain: str | None = None):
    groups = {}
    global_discarded = Counter()
    filtered_rows = 0
    csv_rows = 0
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, skipinitialspace=True)
        fields = [field.strip() for field in reader.fieldnames or []]
        if len(fields) != len(set(fields)):
            raise ValueError("presentmon_v1_csv_header_invalid")
        # Intel PresentMon 2.6 v1 metrics spell this as msBetweenPresents;
        # older v1 captures use MsBetweenPresents. Accept only these exact
        # native aliases and reject a capture containing both ambiguous forms.
        column_mapping = {}
        for canonical in sorted(REQUIRED):
            matches = [alias for alias in COLUMN_ALIASES.get(canonical, (canonical,)) if alias in fields]
            if len(matches) != 1:
                raise ValueError("presentmon_v1_csv_header_invalid")
            column_mapping[canonical] = matches[0]
        for raw in reader:
            csv_rows += 1
            if None in raw or any(value is None for value in raw.values()):
                global_discarded["malformed_csv_row"] += 1
                continue
            row = {key.strip(): value.strip() for key, value in raw.items()}
            for canonical, native in column_mapping.items():
                row[canonical] = row[native]
            try:
                identity = (_pid(row["ProcessID"]), _swapchain(row["SwapChainAddress"]))
            except (TypeError, ValueError):
                global_discarded["invalid_group_identity"] += 1
                continue
            if process_id is not None and identity[0] != process_id:
                filtered_rows += 1
                continue
            group = groups.setdefault(identity, {
                "rows": 0, "applications": set(), "intervals": [], "discarded": Counter(),
                "first_timestamp": None, "last_timestamp": None,
                "dropped_true": 0, "dropped_unknown": 0,
            })
            group["rows"] += 1
            if row.get("Application"):
                group["applications"].add(row["Application"])
            dropped = _dropped(row.get("Dropped"))
            group["dropped_true"] += dropped is True
            group["dropped_unknown"] += dropped is None
            first = group["rows"] == 1
            try:
                timestamp = _finite(row["TimeInSeconds"])
                if timestamp < 0 or (group["last_timestamp"] is not None and timestamp <= group["last_timestamp"]):
                    raise ValueError("timestamp_not_increasing")
            except (TypeError, ValueError):
                group["discarded"]["invalid_timestamp"] += 1
                continue
            # Preserve timestamp boundaries even when an interval is corrupt.
            if first:
                group["first_timestamp"] = timestamp
            group["last_timestamp"] = timestamp
            if first:
                # This duration precedes the first captured event and may be 0,
                # so it never contributes to this capture's cadence statistics.
                continue
            try:
                interval = _finite(row["MsBetweenPresents"])
                if interval <= 0:
                    raise ValueError("nonpositive_interval")
            except (TypeError, ValueError):
                group["discarded"]["invalid_interval"] += 1
                continue
            group["intervals"].append(interval)
    reports = [_group_report(key, groups[key]) for key in sorted(groups)]
    usable = [group for group in reports if group["accepted_interval_count"]]
    if not usable:
        raise ValueError("presentmon_v1_no_usable_intervals")
    requested_swapchain = _swapchain(swapchain) if swapchain is not None else None
    processes = sorted({group["process_id"] for group in usable})
    if requested_swapchain is not None:
        candidates = [group for group in usable if group["swapchain_address"] == requested_swapchain]
        if len(candidates) != 1:
            raise ValueError("presentmon_swapchain_selection_missing_or_ambiguous")
        primary = candidates[0]
        strategy = "explicit_swapchain"
    elif len(processes) == 1:
        primary = sorted(usable, key=lambda group: (-group["accepted_interval_count"], -group["accepted_interval_sum_seconds"], group["swapchain_address"]))[0]
        strategy = "most_accepted_intervals_then_longest_interval_sum_then_lexical_address"
    else:
        primary = None
        strategy = "multiple_processes_no_combined_primary_use_process_id"
    return {
        "source": "presentmon_v1_csv", "input_file": str(path.resolve()),
        "input_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "canonical_to_native_columns": column_mapping,
        "input_columns": fields,
        "csv_rows": csv_rows, "filtered_other_process_rows": filtered_rows,
        "discarded_ungrouped_rows": sum(global_discarded.values()),
        "discarded_ungrouped_reasons": dict(sorted(global_discarded.items())),
        "selection": {
            "requested_process_id": process_id, "requested_swapchain_address": requested_swapchain,
            "strategy": strategy, "group_count": len(reports), "usable_group_count": len(usable),
            "selected_process_id": primary["process_id"] if primary else None,
            "selected_swapchain_address": primary["swapchain_address"] if primary else None,
            "note": "Automatic selection is a recorded heuristic, not proof of the main game window. Every process/swapchain is reported independently; no groups are pooled.",
        },
        "primary": primary, "groups": reports,
        "percentile_method": "Linear interpolation at (N - 1) * fraction, over accepted native MsBetweenPresents values.",
        "measurement_limits": [
            "Present cadence is measured, not GPU render duration, server tick time, or monitor displayed-frame cadence.",
            "The CSV alone cannot prove foreground visibility, absence of pause/loading, capture completeness, or four connected network clients.",
            "Process and swapchain values are never mixed; explicit selection is preferable when a window-to-swapchain mapping is available.",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--process-id", type=int)
    parser.add_argument("--swapchain", help="Explicit opaque SwapChainAddress; otherwise record an automatic main-chain heuristic.")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.process_id is not None and args.process_id <= 0:
        parser.error("--process-id must be positive")
    try:
        report = analyze(args.csv, args.process_id, args.swapchain)
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        code = str(error) if isinstance(error, ValueError) else "presentmon_v1_csv_unavailable"
        raise SystemExit(code) from None
    if args.output:
        if args.output.resolve() == args.csv.resolve():
            parser.error("--output must not overwrite the input CSV")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"selection": report["selection"], "primary": report["primary"],
                      "discarded_ungrouped_rows": report["discarded_ungrouped_rows"]}, sort_keys=True))
