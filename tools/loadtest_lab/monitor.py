"""Bounded, read-only Linux/PG aggregates for one attested isolated lab.

One initialization indexes one filesystem block device and default IPv4 NIC.
Each >=5-second sample reads fixed proc/sysfs counters and two aggregate SQL
queries. The activity view scales with bounded DB connections, never registered
accounts; no player rows, query text, credentials, process arguments, or logs
are collected. Memory is O(1); output grows O(duration / interval).
"""
from __future__ import annotations

import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys
import time

from .guard import dsn, load, marker_guard, need, production_host_guard, read_json, write_new

PROC, SYS = Path('/proc'), Path('/sys')
ACTIVITY_SQL = """SELECT count(*),
 count(*) FILTER (WHERE state='active'),
 count(*) FILTER (WHERE state='active' AND wait_event_type IS NOT NULL),
 count(*) FILTER (WHERE wait_event_type='Lock'),
 count(*) FILTER (WHERE state='idle in transaction')
 FROM pg_catalog.pg_stat_activity
 WHERE datid=(SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database())
 AND pid<>pg_backend_pid()"""
DATABASE_SQL = """SELECT xact_commit,xact_rollback,blks_read,blks_hit,
 temp_files,temp_bytes,deadlocks,blk_read_time,blk_write_time,stats_reset
 FROM pg_catalog.pg_stat_database WHERE datname=current_database()"""
DATABASE_FIELDS = ('xact_commit', 'xact_rollback', 'blks_read', 'blks_hit',
                   'temp_files', 'temp_bytes', 'deadlocks', 'blk_read_time_ms',
                   'blk_write_time_ms', 'stats_reset')
BLOCK_FIELDS = ('reads', 'reads_merged', 'read_sectors', 'read_ms', 'writes',
                'writes_merged', 'write_sectors', 'write_ms', 'inflight',
                'io_busy_ms', 'weighted_io_ms')


class ScopeError(ValueError):
    pass


def _utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _text(path, budget=65536):
    with path.open('rb') as stream:
        raw = stream.read(budget + 1)
    need(len(raw) <= budget, 'monitor_counter_budget_exceeded')
    return raw.decode('ascii')


def _devices(root):
    device = os.stat(root).st_dev
    block = SYS / 'dev/block' / (str(os.major(device)) + ':' + str(os.minor(device))) / 'stat'
    nic = None
    try:
        routes = []
        for line in _text(PROC / 'net/route').splitlines()[1:]:
            row = line.split()
            if (len(row) >= 8 and row[1] == '00000000' and int(row[3], 16) & 1
                    and row[0] != 'lo' and re.fullmatch('[A-Za-z0-9_.:-]{1,64}', row[0])):
                routes.append((int(row[6]), row[0]))
        nic = min(routes)[1] if routes else None
    except (OSError, ValueError, UnicodeError):
        pass
    return block, nic


def _host(root, block, nic):
    result, errors = {}, []
    try:
        # Only the aggregate first row is needed, independent of CPU/core count.
        with (PROC / 'stat').open('rb') as stream:
            row = stream.readline(4097).decode('ascii').split()
        need(row[0] == 'cpu' and 9 <= len(row) <= 12, 'monitor_cpu_invalid')
        ticks = [int(value) for value in row[1:9]]
        need(min(ticks) >= 0, 'monitor_cpu_invalid')
        result['cpu_ticks'] = ticks
    except (OSError, ValueError, IndexError, UnicodeError):
        errors.append('cpu_unavailable')
    try:
        wanted = {'MemTotal:', 'MemAvailable:', 'SwapTotal:', 'SwapFree:'}
        values = {}
        for line in _text(PROC / 'meminfo').splitlines():
            row = line.split()
            if row and row[0] in wanted:
                need(len(row) == 3 and row[2] == 'kB', 'monitor_memory_invalid')
                values[row[0][:-1] + '_bytes'] = int(row[1]) * 1024
        need(len(values) == 4 and min(values.values()) >= 0, 'monitor_memory_invalid')
        result['memory'] = values
    except (OSError, ValueError, UnicodeError):
        errors.append('memory_unavailable')
    try:
        values = [int(value) for value in _text(block, 4096).split()]
        need(len(values) >= 11 and min(values) >= 0, 'monitor_block_invalid')
        result['block'] = dict(zip(BLOCK_FIELDS, values[:11]))
    except (OSError, ValueError, UnicodeError):
        errors.append('filesystem_block_counters_unavailable')
    try:
        stat = os.statvfs(root)
        result['filesystem'] = {'size_bytes': stat.f_blocks * stat.f_frsize,
                                'available_bytes': stat.f_bavail * stat.f_frsize}
    except (OSError, AttributeError):
        errors.append('filesystem_space_unavailable')
    try:
        need(nic is not None, 'monitor_default_interface_missing')
        base = SYS / 'class/net' / nic / 'statistics'
        values = {key: int(_text(base / key, 128).strip()) for key in ('rx_bytes', 'tx_bytes')}
        need(min(values.values()) >= 0, 'monitor_network_invalid')
        result['network'] = values
    except (OSError, ValueError, UnicodeError):
        errors.append('network_counters_unavailable')
    return result, errors


def _rates(previous, current, elapsed):
    result = {}
    if previous is None or elapsed <= 0:
        return result
    old, new = previous.get('cpu_ticks'), current.get('cpu_ticks')
    if old and new:
        delta = [b - a for a, b in zip(old, new)]
        total = sum(delta)
        if min(delta) >= 0 and total > 0:
            result.update(cpu_busy_pct=100 * (total - delta[3] - delta[4] - delta[7]) / total,
                          cpu_iowait_pct=100 * delta[4] / total, cpu_steal_pct=100 * delta[7] / total)
        else:
            result['cpu_counter_reset_or_no_ticks'] = True
    for group, fields, suffix in (('network', ('rx_bytes', 'tx_bytes'), '_per_second'),
                                  ('block', ('read_sectors', 'write_sectors'), '_per_second')):
        if group not in previous or group not in current:
            continue
        for key in fields:
            delta = current[group][key] - previous[group][key]
            if delta < 0:
                result[group + '_counter_reset'] = True
            else:
                factor = 512 if group == 'block' else 1
                name = key.replace('sectors', 'bytes') + suffix
                result[group + '_' + name] = delta * factor / elapsed
    return result


class _Connection:
    def __init__(self, connection, counts):
        self.connection, self.counts = connection, counts

    def execute(self, sql):
        need(sql.lstrip().upper().startswith(('SELECT ', 'SHOW ')), 'monitor_read_only_query_required')
        self.counts['sql_calls_attempted'] += 1
        return self.connection.execute(sql)

    def close(self):
        self.connection.close()


def _connect(cfg, private, counts):
    import psycopg
    counts['connection_attempts'] += 1
    raw = psycopg.connect(dsn(cfg, private, admin=True), autocommit=True,
        connect_timeout=3, application_name='survival_isolated_loadtest_monitor',
        options='-c default_transaction_read_only=on -c statement_timeout=1500 -c lock_timeout=500')
    connection = _Connection(raw, counts)
    try:
        marker_guard(connection, cfg, private, seeded=True)
        need(connection.execute('SHOW transaction_read_only').fetchone() == ('on',),
             'monitor_read_only_session_required')
    except ValueError as error:
        try:
            connection.close()
        except Exception:
            pass
        raise ScopeError('database_scope_or_read_only_guard_failed') from error
    except Exception as error:
        try:
            connection.close()
        except Exception:
            pass
        if getattr(error, 'sqlstate', None) in {'42P01', '3F000', '42501'}:
            raise ScopeError('database_scope_or_read_only_guard_failed') from error
        raise
    counts['connections_verified'] += 1
    return connection


def _postgres(connection):
    activity = connection.execute(ACTIVITY_SQL).fetchone()
    database = connection.execute(DATABASE_SQL).fetchone()
    need(activity is not None and len(activity) == 5 and database is not None and len(database) == 10,
         'monitor_pg_aggregate_missing')
    statistics = dict(zip(DATABASE_FIELDS, database))
    reset = statistics['stats_reset']
    statistics['stats_reset'] = reset.isoformat() if reset is not None else None
    return {'activity': dict(zip(('connections_excluding_monitor', 'active', 'active_waiting',
                                 'waiting_for_lock', 'idle_in_transaction'), activity)),
            'database': statistics}


def monitor(directory, duration_seconds=None, interval_seconds=5):
    root, cfg, private = load(directory)
    production_host_guard(cfg)
    need(sys.platform.startswith('linux'), 'linux_monitor_host_required')
    duration = cfg['duration_seconds'] if duration_seconds is None else duration_seconds
    need(type(duration) is int and 1 <= duration <= min(18000, cfg['duration_seconds']),
         'monitor_duration_budget_invalid')
    need(type(interval_seconds) is int and 5 <= interval_seconds <= 60,
         'monitor_interval_budget_invalid')
    block, nic = _devices(root)
    tag = secrets.token_hex(8)
    output, receipt_path = root / ('monitor_' + tag + '.jsonl'), root / ('monitor_' + tag + '_receipt.json')
    counts = {'connection_attempts': 0, 'connections_verified': 0, 'sql_calls_attempted': 0,
              'samples': 0, 'postgres_samples': 0, 'samples_with_errors': 0}
    started, started_utc = time.monotonic(), _utc()
    deadline = started + duration
    connection = previous = None
    previous_at = None
    stop_reason, error_codes = 'duration_complete', set()
    digest = hashlib.sha256()
    with output.open('xb') as stream:
        output.chmod(0o600)

        def emit(value):
            raw = json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode() + b'\n'
            stream.write(raw); stream.flush(); digest.update(raw)

        emit({'kind': 'ISOLATED_LAB_MONITOR_HEADER', 'run_id': cfg['run_id'],
              'started_utc': started_utc, 'interval_seconds': interval_seconds,
              'filesystem_device': str(block.parent.name), 'network_interface': nic,
              'query_text_collected': False, 'player_rows_collected': False})
        try:
            while time.monotonic() < deadline:
                stopped = root / 'stopped_receipt.json'
                if stopped.exists():
                    try:
                        value = read_json(stopped)
                    except (OSError, ValueError):
                        raise ScopeError('invalid_lab_stop_receipt') from None
                    if (not isinstance(value, dict) or value.get('kind') != 'ISOLATED_LOADTEST_LAB_STOPPED'
                            or value.get('run_id') != cfg['run_id']):
                        raise ScopeError('invalid_lab_stop_receipt')
                    stop_reason = 'lab_stopped'
                    break
                sample_at, sampled_utc = time.monotonic(), _utc()
                host, errors = _host(root, block, nic)
                postgres = None
                scope_failed = False
                try:
                    if connection is None:
                        connection = _connect(cfg, private, counts)
                    postgres = _postgres(connection)
                    counts['postgres_samples'] += 1
                except ScopeError:
                    errors.append('database_scope_or_read_only_guard_failed')
                    scope_failed = True
                except Exception:
                    errors.append('database_aggregate_unavailable')
                    if connection is not None:
                        try:
                            connection.close()
                        except Exception:
                            pass
                        connection = None
                counts['samples'] += 1
                counts['samples_with_errors'] += int(bool(errors))
                error_codes.update(errors)
                rates = _rates(previous, host, sample_at - previous_at if previous_at is not None else 0)
                emit({'kind': 'ISOLATED_LAB_AGGREGATE_SAMPLE', 'index': counts['samples'],
                      'sampled_utc': sampled_utc, 'elapsed_seconds': sample_at - started,
                      'sample_duration_seconds': time.monotonic() - sample_at,
                      'host': host, 'rates': rates, 'postgres': postgres, 'errors': errors})
                previous, previous_at = host, sample_at
                if scope_failed:
                    stop_reason = 'database_scope_rejected'
                    break
                remaining = min(deadline - time.monotonic(), sample_at + interval_seconds - time.monotonic())
                if remaining > 0:
                    time.sleep(remaining)
        except KeyboardInterrupt:
            stop_reason = 'interrupted'
        except ScopeError:
            stop_reason = 'invalid_lab_stop_receipt'
            error_codes.add('invalid_lab_stop_receipt')
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    error_codes.add('database_connection_close_failed')
            stream.flush(); os.fsync(stream.fileno())
    receipt = {'kind': 'ISOLATED_LAB_READ_ONLY_MONITOR_RECEIPT', 'artifact_root': str(root),
        'run_id': cfg['run_id'], 'started_utc': started_utc, 'finished_utc': _utc(),
        'duration_requested_seconds': duration, 'duration_actual_seconds': time.monotonic() - started,
        'interval_seconds': interval_seconds, 'stop_reason': stop_reason, 'counts': counts,
        'error_codes': sorted(error_codes), 'output': str(output), 'output_sha256': digest.hexdigest(),
        'read_only': True, 'capacity_certified': False,
        'limits': ['system_and_database_aggregates_only_not_unique_bottleneck_diagnosis',
                   'network_interface_includes_private_traffic_not_cloud_public_billing',
                   'block_counters_cover_lab_filesystem_device_not_all_host_disks',
                   'first_sample_has_no_counter_rates', 'database_statistics_may_lag_and_include_monitor_reads',
                   'io_times_require_server_track_io_timing_no_configuration_changed',
                   'operation_timeouts_can_extend_requested_stop_time',
                   'readonly_reconnect_per_interval_only_no_business_request_or_write_replay']}
    write_new(receipt_path, receipt)
    if stop_reason == 'interrupted':
        status = 'MONITOR_INTERRUPTED'
    elif stop_reason in {'database_scope_rejected', 'invalid_lab_stop_receipt'}:
        status = 'MONITOR_REJECTED'
    else:
        status = 'MONITOR_COMPLETE' if not error_codes else 'MONITOR_COMPLETE_WITH_GAPS'
    return {'status': status,
            'receipt': str(receipt_path), 'samples': counts['samples'], 'stop_reason': stop_reason}
