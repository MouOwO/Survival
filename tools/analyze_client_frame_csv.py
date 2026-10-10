"""Read native cl_showfps=4 CSV; never connects to or changes the live game."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import statistics


def percentile(values, fraction):
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    lower = int(index)
    return ordered[lower] + (ordered[min(lower + 1, len(ordered) - 1)] - ordered[lower]) * (index - lower)


def statistics_ms(values):
    return {key: round(value, 3) for key, value in {
        'mean': statistics.fmean(values), 'p50': percentile(values, .5),
        'p95': percentile(values, .95), 'p99': percentile(values, .99), 'max': max(values),
    }.items()}


def analyze(path: Path):
    required = {'Time', 'Frame FPS', 'Frame MS', 'Server Frame MS'}
    samples = []
    discarded = 0
    with path.open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream, skipinitialspace=True)
        if not reader.fieldnames or not required <= {name.strip() for name in reader.fieldnames}:
            raise ValueError('native_frame_csv_header_invalid')
        for row in reader:
            row = {str(key).strip(): value for key, value in row.items()}
            try:
                sample = {name: float(row[name]) for name in required}
                if any(not math.isfinite(value) for value in sample.values()):
                    raise ValueError
                if sample['Time'] < 0 or sample['Frame MS'] <= 0 or sample['Server Frame MS'] < 0 or sample['Frame FPS'] <= 0:
                    raise ValueError
            except (ValueError, TypeError, KeyError):
                discarded += 1
                continue
            # Retain time/performance numbers only; player positions are unused.
            samples.append(sample)
    if not samples:
        raise ValueError('native_frame_csv_no_valid_samples')
    clients = [sample['Frame MS'] for sample in samples]
    servers = [sample['Server Frame MS'] for sample in samples]
    times = sorted({sample['Time'] for sample in samples})
    deltas = [second - first for first, second in zip(times, times[1:]) if second > first]
    origin = min(times)
    buckets = {}
    for sample in samples:
        index = math.floor((sample['Time'] - origin + 1e-8) / .5)
        bucket = buckets.setdefault(index, {'samples': 0, 'client_max_ms': 0., 'server_max_ms': 0.})
        bucket['samples'] += 1
        bucket['client_max_ms'] = max(bucket['client_max_ms'], sample['Frame MS'])
        bucket['server_max_ms'] = max(bucket['server_max_ms'], sample['Server Frame MS'])
    spikes = [{
        'time': sample['Time'], 'client_ms': sample['Frame MS'], 'server_ms': sample['Server Frame MS'],
    } for sample in samples if sample['Frame MS'] >= 50]
    return {
        'source': 'native_cl_showfps_4_csv', 'valid_samples': len(samples), 'discarded_rows': discarded,
        'time_span_seconds': round(max(times) - min(times), 3), 'unique_timestamps': len(times),
        'median_timestamp_step_seconds': round(statistics.median(deltas), 3) if deltas else None,
        'timestamp_precision_note': 'Engine CSV formats Time to 0.1s; repeated timestamps do not prove dropped presents.',
        'sampling_note': 'These are logged samples; the file alone does not prove that every rendered frame was recorded.',
        'client_frame_ms': statistics_ms(clients), 'server_frame_ms': statistics_ms(servers),
        'client_samples_over_ms': {str(limit): sum(value >= limit for value in clients) for limit in (33.3, 50, 100, 250, 500)},
        'half_second_buckets': [{
            'relative_start_seconds': round(index * .5, 3), **buckets[index],
        } for index in sorted(buckets)],
        'spike_samples': spikes,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path)
    parser.add_argument('--output', type=Path)
    arguments = parser.parse_args()
    try:
        report = analyze(arguments.csv)
    except (OSError, UnicodeError, ValueError) as error:
        code = str(error) if isinstance(error, ValueError) else 'native_frame_csv_unavailable'
        raise SystemExit(code) from None
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({key: report[key] for key in (
        'valid_samples', 'discarded_rows', 'time_span_seconds', 'median_timestamp_step_seconds',
        'client_frame_ms', 'server_frame_ms', 'client_samples_over_ms',
    )}, sort_keys=True))
