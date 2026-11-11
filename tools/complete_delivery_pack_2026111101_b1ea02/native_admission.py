"""Read-only complete signed-package ordinary-client evidence admission.

No SDK, input or process query runs on import. Explicit validation independently
authenticates the full package, hashes each bounded private evidence file once
and rehashes it at the end: O(evidence bytes + captures + volumes). Screenshots
must come from the same foreground ordinary native window. Old run07/08,
synthetic MovieError classes, logs alone and source tests cannot admit a package.
"""
from __future__ import annotations
import argparse
import base64
import copy
from collections import Counter, deque
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
import struct
import zlib
from types import ModuleType, SimpleNamespace
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
KIND = 'COMPLETE_RUNTIME_NATIVE_REVIEW'
SCOPE = 'COMPLETE_RUNTIME_UI_NETWORK_AND_CONSECUTIVE_LOTTERY'
POLICY = 'DATA_VOLUMES_USED_INDEX_AUTHENTICATED_NOT_OPEN'
POOLS = ('map', 'cultivation', 'dragon_knight', 'summer')
HELPERS = ROOT / 'tools/lottery_hotfix_release_20261102/native_admission.py'
HELPERS_SHA = '935f0958a188dce736baa08282b3b4cd2cd30794767ddb9e8060527600c7a8ab'
_HELPERS = None
_EXECUTED_HELPERS = {}
_OFFICIAL_INSTALL_SEAL = object()

class _VerifiedOfficialInstallation:
    """RAM-only capability; never selected by a request/review Boolean."""

    def __init__(self, seal, installed, report_sha, files, snapshots, protocol, receipt_sha):
        need(seal is _OFFICIAL_INSTALL_SEAL, 'complete_native_closed_official_binding_required')
        self.seal, self.installed, self.report_sha = (seal, Path(installed).resolve(), report_sha)
        self.files = tuple(((v['name'], v['bytes'], v['sha256']) for v in files))
        self.snapshots, self.protocol, self.receipt_sha = (snapshots, protocol, receipt_sha)

def _post_download_operator(relative, operator_revision, expected_raw_sha=None):
    """Execute exactly the current Git-bound, optionally authority-pinned bytes."""
    b, ops, _ = environment()
    path = (ROOT / relative).resolve()
    raw = path.read_bytes()
    need(path.is_relative_to(ROOT / 'tools') and len(raw) <= 1024 * 1024, 'complete_native_bounded_operator_required')
    if expected_raw_sha is not None:
        need(sha(raw) == expected_raw_sha, 'complete_native_official_operator_pin_changed')
    pin = sha(raw.replace(b'\r\n', b'\n'))
    b.verify_operator_paths({relative: pin}, operator_revision)
    module = ModuleType('complete_native_official_' + sha(raw)[:20])
    module.__file__ = str(path)
    with ops.capture_operator_imports():
        exec(compile(raw, str(path), 'exec'), module.__dict__)
    _EXECUTED_HELPERS.update(ops._EXECUTED_OPERATOR_PINS)
    _EXECUTED_HELPERS[relative] = pin
    return module

def _verify_official_installation(request, report, manifest, receipt_ref):
    """Real SDK lineage/official receipt and whole installed signature/VPK/CRC."""
    b, ops, p = environment()
    expected = request.get('report_sha256')
    op = report['operator_revision']
    pipeline = _post_download_operator('tools/release_pipeline.py', op)
    auth = pipeline.authority()
    complete = _post_download_operator('tools/complete_delivery_pack_2026111101_b1ea02/complete_baseline.py', op, auth.policy['baseline_completion_sha256'])
    downloaded = _post_download_operator('tools/complete_delivery_pack_2026111101_b1ea02/verify_download.py', op, auth.policy['download_sha256'])
    complete.checked_authority(auth)
    receipt, raw = b.checked_json(receipt_ref, limit=32 * 1024 * 1024)
    path = Path(receipt_ref['path']).resolve()
    need(path.is_relative_to((b.REPORT / 'download_evidence').resolve()) and path.name == 'verification.json', 'complete_native_original_official_receipt_required')
    journal, journal_raw, state, state_raw = complete.current_head(auth, report, expected, request)
    complete.verified_delivery(report, manifest, expected, journal, sha(journal_raw), receipt)
    downloaded.REPORT_SHA = expected
    downloaded.configure(report)
    protocol = downloaded.protocol()
    installed = p.regular(Path(receipt['download']['install_folder']))
    need(installed == p.regular(protocol.INSTALLED) == p.regular(p.INSTALLED), 'complete_native_official_fixed_installation_required')
    snapshots = {path: raw, Path(auth.policy['canonical_journal']): journal_raw, Path(auth.policy['lineage_state']): state_raw}
    with b.scene_maps(), b.inc.trusted_source(b.TRUSTED):
        actual = protocol.verify.verify_installed(copy.deepcopy(receipt['download']), b.VIEW, journal)
        need(actual['signature_valid'] is True and actual['package_files'] == report['package_files'] and (actual['vpk_sha256'] == report['vpk_sha256']) and (actual['verification']['files'] == report['files']) and (actual['verification']['archive_count'] == len(report['package_files']) - 1) and all((actual['verification'].get(key) is True for key in protocol.callbacks.CHECKS)), 'complete_native_actual_official_installation_failed')
        acf_raw = protocol.api.pack.read_metadata(protocol.ACF, protocol.api.pack.MAX_MANIFEST)
        observed, row = protocol.acf_manifest(acf_raw, receipt['post_query'], sum((v['bytes'] for v in report['package_files'])), receipt['steam_manifest'])
        need(observed == receipt['steam_manifest'] and row == receipt['acf_installed_entry'], 'complete_native_official_acf_changed')
        snapshots[Path(protocol.ACF)] = acf_raw
    protocol.unchanged(snapshots)
    b.verify_operator_paths(dict(downloaded._PROTOCOL_EXECUTED_PINS), op)
    return _VerifiedOfficialInstallation(_OFFICIAL_INSTALL_SEAL, installed, expected, report['package_files'], snapshots, protocol, sha(raw))

def _lifecycle_packages(folder, report, manifest, parent, parent_manifest, expected, ops, p, official):
    if official is None:
        ops.require_rows(p.INSTALLED, parent['package_files'])
        ops.full_vpk(p.INSTALLED, parent_manifest)
    else:
        need(type(official) is _VerifiedOfficialInstallation and official.seal is _OFFICIAL_INSTALL_SEAL and (official.installed == Path(p.INSTALLED).resolve()) and (official.report_sha == expected) and (official.files == tuple(((v['name'], v['bytes'], v['sha256']) for v in report['package_files']))), 'complete_native_verified_official_phase_required')
        ops.require_rows(p.INSTALLED, report['package_files'])
        ops.full_vpk(p.INSTALLED, manifest)
        official.protocol.unchanged(official.snapshots)
    ops.require_rows(folder / 'backup', parent['package_files'])
    ops.require_rows(folder / 'retained_candidate', report['package_files'])

def need(ok, why):
    if not ok:
        raise ValueError(why)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def timestamp(value):
    need(isinstance(value, str), 'complete_native_timezone_timestamp_required')
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    need(result.tzinfo is not None, 'complete_native_timezone_required')
    return result

def helpers():
    global _HELPERS
    if _HELPERS is None:
        raw = HELPERS.read_bytes()
        need(len(raw) <= 128 * 1024 and sha(raw) == HELPERS_SHA, 'complete_frozen_native_pixel_helpers_changed')
        value = ModuleType('complete_private_native_pixel_helpers')
        value.__file__ = str(HELPERS)
        exec(compile(raw, str(HELPERS), 'exec'), value.__dict__)
        _EXECUTED_HELPERS[HELPERS.relative_to(ROOT).as_posix()] = sha(raw.replace(b'\r\n', b'\n'))
        _HELPERS = value
    return _HELPERS

def environment():
    from complete_delivery_pack_2026111101_b1ea02 import pipeline_recipe, rehearsal
    b, p, _ = rehearsal.environment()
    return (pipeline_recipe, rehearsal, p)

def same_process(left, right):
    return helpers().same_process(left, right)

def screenshot(ref, process, reader, origin):
    return helpers().screenshot(ref, process, reader, origin)

def exact_bindings(document, report, expected_sha):
    return document.get('package_report_sha256') == expected_sha and document.get('source_revisions') == report['source_revisions'] and (document.get('collection_source_revisions') == report['collection_source_revisions']) and (document.get('operator_revision') == report['operator_revision']) and (document.get('content_sha256') == report['content_sha256']) and (document.get('signed_manifest_sha256') == report['signed_manifest_sha256'])

def lifecycle(review, origin, report, expected_sha, reader, b, ops, p, *, official=None, target_manifest=None):
    refs = review['rehearsal']
    tx, tx_path = reader.document(refs['transaction'], origin)
    folder = tx_path.parent
    process, process_path = reader.document(refs['process'], origin)
    need(tx_path.name == 'transaction.json' and folder.parent == ops.STORE and (process_path == folder / 'process.json') and (tx.get('schema') == 1) and (tx.get('kind') == ops.KIND) and (tx.get('transaction_id') == folder.name) and (tx.get('installed') == str(p.INSTALLED)) and (tx.get('candidate_files') == report['package_files']) and (tx.get('code_pins') == ops.own_code_pins()) and exact_bindings(tx, report, expected_sha), 'complete_native_transaction_differs')
    need(exact_bindings(process, report, expected_sha) and process.get('kind') == ops.KIND and (process.get('code_pins') == tx['code_pins']) and (process.get('tools') is False) and (process.get('offline_logic_requested') is False) and (process.get('cheats_requested') is False) and (process.get('owned_launch') is True) and (process.get('launch_route') in ops.LAUNCH_ROUTES) and (process.get('argv') == ops.arguments(Path(process['log_file']), process['launch_route'])) and (process.get('log_origin') == 'DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT') and (process.get('log_file') == str(ops.expected_log_path(folder))) and (process.get('port') == ops.PORT) and (process.get('workshop_id') == b.ITEM), 'complete_native_owned_ordinary_process_required')
    need(Path(process['executable']).resolve() == p.EXE.resolve() and process.get('command_line_sha256') == sha(subprocess.list2cmdline([str(p.EXE), *process['argv']]).encode()) and (type(process.get('native_created_filetime')) is int) and (process['native_created_filetime'] // 10 == p.utc_ticks(process['created_utc']) // 10) and same_process(review['process'], process), 'complete_native_actual_executable_generation_differs')
    names = ops.names(report['package_files'])
    held = process.get('held_files', [])
    need(len(held) == len(names) and [v['name'] for v in held] == names and ([v['path'] for v in held] == [str(p.INSTALLED / name) for name in names]) and ([v['bytes'] for v in held] == [v['bytes'] for v in report['package_files']]) and (len({(v['volume_serial'], v['file_index']) for v in held}) == len(names)) and (process.get('file_hold_mode') == 'GENERIC_READ_FILE_SHARE_READ_ONLY') and (not (folder / 'hold_failed.json').exists()), 'complete_native_continuous_exact_file_holds_required')
    refs_inspect = refs['inspections']
    need(len(refs_inspect) == 2, 'complete_native_two_bracketing_inspections_required')
    times = []
    for ref in refs_inspect:
        value, path = reader.document(ref, origin)
        rows = value.get('file_use', [])
        need(path.parent == folder / 'inspections' and exact_bindings(value, report, expected_sha) and same_process(value['process'], process) and (value.get('keeper') == process['keeper']) and (value.get('held_files') == held) and (value.get('candidate_files') == report['package_files']) and ([v.get('name') for v in rows] == names) and all((v.get('owned_keeper_uses_file') is True for v in rows)) and all((v.get('owned_dota_uses_file') is True for v in rows[1:])) and (type(rows[0].get('owned_dota_uses_file')) is bool) and (value.get('index_owned_dota_use_observed') is rows[0]['owned_dota_uses_file']) and (value.get('external_signed_manifest_binding') is True) and (value.get('external_signed_resources_verified') == report['files']) and (value.get('external_protected_modules_verified') == report['protected_modules_verified']), 'complete_native_same_process_data_volume_use_required')
        times.append(timestamp(value['observed_utc']))
    documents = {}
    for name in ('close_intent', 'close_requested', 'hold_end', 'restored'):
        document, path = reader.document(refs[name], origin)
        need(path == folder / (name + '.json') and exact_bindings(document, report, expected_sha), 'complete_native_exact_lifecycle_receipt_required')
        documents[name] = document
    intent, close, end, restored = [documents[k] for k in ('close_intent', 'close_requested', 'hold_end', 'restored')]
    need(intent.get('status') == 'ONE_OWNED_WM_CLOSE_INTENT' and same_process(intent, process) and (close.get('status') == 'WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED') and same_process(close, process) and (close.get('queued') is True) and (close.get('force_stop') is False) and (intent.get('console_connections') == close.get('console_connections') == 0), 'complete_native_one_normal_owned_close_required')
    life = end.get('process_lifetime', {})
    need(end.get('status') == 'OWNED_DOTA_EXITED_HOLDS_COMPLETED' and same_process(end, process) and (end.get('held_files') == held) and (end.get('end_no_dota_check_deferred_to_restore') is True) and (life.get('exit_observed') is True) and (life.get('executable_verified_while_alive') is True) and (life.get('exit_identity_method') == 'SAME_RETAINED_HANDLE_GETPROCESSTIMES') and (life.get('created_filetime') == process['native_created_filetime']) and (type(life.get('exit_filetime')) is int) and (life['exit_filetime'] > life['created_filetime']), 'complete_native_same_retained_handle_exit_required')
    parent, parent_manifest = b.baseline(full=True, require_current_journal=False)
    need(restored.get('status') == 'ORIGINAL1009_COMPLETE_SET_FULLY_RESTORED' and restored.get('original_files') == tx.get('original_files') == parent['package_files'] and (restored.get('original_content_sha256') == parent['content_sha256']) and (restored.get('acf_written') is False) and (restored.get('canonical_journal_written') is False) and (restored.get('backups_preserved') is True) and (restored.get('candidate_preserved') is True), 'complete_native_original_exact_restore_required')
    need(timestamp(process['created_utc']) <= times[0] < times[1] <= timestamp(close['observed_utc']) <= timestamp(end['ended_utc']) <= timestamp(restored['observed_utc']) <= timestamp(review['reviewed_utc']), 'complete_native_lifecycle_chronology_invalid')
    log = reader.file(refs['engine_log_final'], origin)
    need(log == ops.expected_log_path(folder), 'complete_native_actual_launch_log_required')
    raw = log.read_bytes()
    need(len(raw) <= 64 * 1024 * 1024, 'complete_native_log_budget')
    text = raw.decode('utf-8', 'replace')
    need('[WS4-NATIVE-HANDOFF-01]' in text and '[Survival][INFO][Addon] initialized' in text, 'complete_native_actual_handoff_and_addon_start_required')
    need(re.search('Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:|NETWORK_DISCONNECT_SNAPSHOTERROR|Failed\\s+to\\s+serialize\\s+(?:CUserMsg_)?CustomGameEvent|SendData[^\\r\\n]*reliable\\s+data\\s+too\\s+big|VPK directory corrupt', text, re.I) is None, 'complete_native_script_network_package_fatal')
    _lifecycle_packages(folder, report, target_manifest, parent, parent_manifest, expected_sha, ops, p, official)
    return (process, times, text)

def captures(case, roles, process, bounds, reader, origin):
    refs = case.get('captures', {})
    need(set(refs) == set(roles), 'complete_native_exact_capture_roles_required')
    shots = [screenshot(refs[role], process, reader, origin) for role in roles]
    need(all((a['end'] < z['start'] for a, z in zip(shots, shots[1:]))) and bounds[0] <= shots[0]['start'] <= shots[-1]['end'] <= bounds[1], 'complete_native_capture_chronology_invalid')
    need(case.get('visual_review', {}).get('reviewed_png_sha256') == [shot['sha256'] for shot in shots], 'complete_native_root_pixel_review_requires_exact_sha')
    return shots

def ui_cases(review, process, bounds, reader, origin):
    required = ('n1_gameplay', 'archive', 'hud_selection', 'grid', 'production', 'vip', 'payment', 'public_beta')
    cases = review.get('ui_cases', {})
    need(set(cases) == set(required), 'complete_native_runtime_ui_cases_required')
    windows = set()
    count = 0
    for name in required:
        case = cases[name]
        shots = captures(case, ('visible',), process, bounds, reader, origin)
        visual = case.get('visual_review', {})
        need(visual.get('actual_data_visible') is True and visual.get('normal_ui_open') is True and (visual.get('not_loading_or_placeholder') is True) and (visual.get('no_stall') is True), 'complete_native_actual_runtime_ui_pixels_required:' + name)
        windows.update(((s['hwnd'], s['width'], s['height']) for s in shots))
        count += len(shots)
    need(len(windows) == 1, 'complete_native_ui_cases_must_share_window')
    return dict(cases=list(required), captures=count, ordinary_native_pixels_reviewed=True, all_gameplay_paths_verified=False, no_purchase_or_claim_required=True)
DECODER_PROBE_RESOURCE = 'panorama/styles/custom_game/lottery_cinematic_v1.vcss_c'

def _decoder_probe_case(case, process, bounds, text, reader, origin, captures, manifest, original_evidence):
    """Optional *additional* no-consumption evidence; 4-pool/3-ten still run."""
    need(case.get('mode') == 'ZERO_CONSUMPTION_NATIVE_DECODER_PROBE' and case.get('pool') == 'map' and (case.get('resource') == DECODER_PROBE_RESOURCE) and (case.get('presentation') == 'fallback'), 'fixed_zero_consumption_decoder_probe_required')
    need(type(case.get('tickets_before')) is int and case['tickets_before'] == case.get('tickets_after') and (case.get('actual_draw_inputs') == 0) and (case.get('ordinary_client') is True), 'probe_cannot_consume_or_replace_actual_draws')
    resources = {row['path']: row for row in manifest['files']}
    actual = resources.get(DECODER_PROBE_RESOURCE)
    compiled = original_evidence['compiler']['outputs'].get(DECODER_PROBE_RESOURCE)
    need(actual and compiled and all((actual.get(k) == compiled.get(k) for k in ('bytes', 'sha256', 'md5'))), 'probe_resource_must_be_real_signed_compiler_output')
    shots = captures(case, ('window_before', 'animation_a', 'animation_b', 'window_after'), process, bounds, reader, origin)
    visual = case.get('visual_review', {})
    need(shots[1]['sha256'] != shots[2]['sha256'] and all((visual.get(k) is True for k in ('fallback_animation_content', 'animation_progressed', 'returned_to_lottery_window', 'no_movie_error_visible_after_fallback', 'no_draw_inputs'))), 'probe_requires_actual_native_pixels')
    probe = case.get('probe_id')
    need(type(probe) is int and 1 <= probe <= 1000000, 'bounded_real_probe_id_required')
    prefix = '\\[LOTTERY_DECODER_PROBE\\] stage='
    suffix = ' probe=' + str(probe) + ' pool=map'
    markers = [(match.start(), match.end(), match[1], match[2]) for match in re.finditer(prefix + '([a-z_]+)' + suffix + '([^\\r\\n]*)', text)]
    stages = [row[2] for row in markers]
    need(stages == ['begin', 'set_movie', 'error', 'fallback', 'complete'], 'probe_requires_one_actual_error_fallback_lifecycle')
    need('resource=' + DECODER_PROBE_RESOURCE in markers[0][3] and 'no_consumption=true' in markers[0][3] and ('resource=' + DECODER_PROBE_RESOURCE in markers[1][3]), 'probe_actual_setmovie_resource_evidence_required')
    reason = case.get('fallback_reason')
    need(reason in ('native_error', 'sync_error') and 'reason=' + reason in markers[3][3] and ('outcome=' + reason in markers[4][3]), 'probe_inconclusive_cannot_satisfy_decoder_failure')
    if reason == 'native_error':
        need('cause=native_error native_class=MovieError' in markers[2][3], 'probe_requires_actual_native_movie_error')
    else:
        need(re.search('cause=sync_error api=(SetMovie|Play)\\b', markers[2][3]), 'probe_requires_actual_media_api_exception')
    times = []
    for position, unused_end, unused_stage, unused_tail in markers:
        start = text.rfind('\n', 0, position) + 1
        found = re.match('(\\d\\d)/(\\d\\d) (\\d\\d):(\\d\\d):(\\d\\d)', text[start:position])
        need(found is not None, 'probe_actual_engine_timestamps_required')
        times.append(datetime(int(process['created_utc'][:4]), *map(int, found.groups()), tzinfo=timezone(timedelta(hours=8))))
    tolerance = timedelta(seconds=1)
    need(times == sorted(times) and bounds[0] <= times[0] + tolerance and (times[-1] <= bounds[1]) and (shots[0]['end'] <= times[0] + tolerance) and (times[3] <= shots[1]['start']) and (shots[2]['end'] <= times[4] + tolerance) and (times[4] <= shots[3]['start']), 'probe_lifecycle_must_match_actual_four_captures')
    segment = text[markers[0][0]:markers[-1][1]]
    need('[SURVIVAL_LOTTERY_UI] stage=result_received request=' not in segment, 'probe_must_be_isolated_from_real_reward_transactions')
    windows = {(s['hwnd'], s['width'], s['height']) for s in shots}
    need(len(windows) == 1, 'probe_requires_one_actual_native_window')
    return dict(extra_zero_consumption_decoder_probes=1, actual_movie_presentations=0, ordinary_tickets_consumed=0, real_draw_case_replacement=False, actual_decoder_fallbacks=1, _window=next(iter(windows)))

def lottery_cases(review, process, bounds, text, reader, origin, *, manifest=None, original_evidence=None):
    previews = review.get('lottery_previews', {})
    need(set(previews) == set(POOLS), 'complete_native_four_pool_previews_required')
    actual_movie = 0
    native_fallback = 0
    windows = set()
    for pool in POOLS:
        case = previews[pool]
        need(case.get('pool') == pool and case.get('mode') == 'NO_CONSUMPTION_PREVIEW', 'complete_native_pool_preview_required')
        shots = captures(case, ('window_before', 'animation_a', 'animation_b', 'window_after'), process, bounds, reader, origin)
        visual = case.get('visual_review', {})
        need(shots[1]['sha256'] != shots[2]['sha256'] and all((visual.get(key) is True for key in ('theme_matches_pool', 'animation_progressed', 'returned_to_lottery_window', 'no_movie_error_visible_after_fallback', 'no_draw_inputs'))), 'complete_native_real_moving_pool_pixels_required')
        start = '[LOTTERY_CINEMATIC] stage=preview pool=' + pool
        left = text.find(start)
        right = text.find('[LOTTERY_CINEMATIC] stage=complete pool=' + pool + ' preview=true', left + len(start))
        need(left >= 0 and right > left, 'complete_native_preview_lifecycle_missing')
        if case.get('presentation') == 'movie':
            need(visual.get('actual_movie_content') is True, 'complete_native_movie_is_distinct_from_fallback')
            actual_movie += 1
        else:
            reason = case.get('fallback_reason')
            need(case.get('presentation') == 'fallback' and reason in ('native_error', 'sync_error') and ('[LOTTERY_CINEMATIC] stage=fallback pool=' + pool + ' reason=' + reason in text[left:right]), 'complete_native_real_decoder_failure_fallback_required')
            native_fallback += 1
        need(type(case.get('tickets_before')) is int and case['tickets_before'] == case.get('tickets_after'), 'complete_native_preview_ticket_balance_changed')
        windows.update(((s['hwnd'], s['width'], s['height']) for s in shots))
    preview_movies, preview_fallbacks = (actual_movie, native_fallback)
    draws = review.get('consecutive_draws', [])
    need(len(draws) == 3, 'complete_native_three_authorized_consecutive_ten_draws_required')
    previous = None
    previous_end = None
    requests = set()
    total = 0
    response_windows = []
    for case in draws:
        need(case.get('pool') == 'map' and case.get('count') == 10 and (case.get('ticket_kind') == 'ordinary') and (case.get('real_player_transaction') is True) and (case.get('skip_animation') is False), 'complete_native_actual_ordinary_map_ten_draw_required')
        request = case.get('request_id')
        need(isinstance(request, str) and 1 <= len(request) <= 128 and (request not in requests) and re.fullmatch('[A-Za-z0-9_:-]+', request), 'complete_native_distinct_actual_draw_request_required')
        requests.add(request)
        before, after = (case.get('tickets_before'), case.get('tickets_after'))
        need(type(before) is int and type(after) is int and (before >= 10) and (after >= 0) and (before - after == 10) and (previous is None or before == previous), 'complete_native_exact_authorized_ticket_debit_required')
        total += before - after
        previous = after
        shots = captures(case, ('window_before', 'animation_a', 'animation_b', 'results', 'window_after'), process, bounds, reader, origin)
        need(previous_end is None or previous_end < shots[0]['start'], 'complete_native_draws_must_be_observed_consecutively')
        previous_end = shots[-1]['end']
        visual = case.get('visual_review', {})
        need(shots[1]['sha256'] != shots[2]['sha256'] and all((visual.get(key) is True for key in ('animation_progressed', 'ten_actual_rewards_visible', 'confirm_button_full_width', 'owned_text_visible_when_applicable', 'returned_to_lottery_window'))), 'complete_native_each_draw_requires_actual_movie_rewards_and_return')
        marker = '[SURVIVAL_LOTTERY_UI] stage=result_received request=' + request
        need(text.count(marker) == 1, 'complete_native_exact_actual_draw_ack_missing_or_duplicated')
        left = text.index(marker)
        next_ack = text.find('[SURVIVAL_LOTTERY_UI] stage=result_received request=', left + len(marker))
        stamp = _time(text[text.rfind('\n', 0, left) + 1:left])
        if stamp is not None:
            need(_engine_clock(shots[0]['start']) - 1 <= stamp <= _engine_clock(shots[-1]['end']) + 1, 'complete_native_draw_ack_must_match_its_actual_case')
            response_windows.append((stamp - 1, stamp + 1))
        segment = text[left:next_ack if next_ack >= 0 else len(text)]
        need(re.search('\\[SURVIVAL_LOTTERY_UI\\] result_count=10 server_count=10\\b', segment) and '[SURVIVAL_LOTTERY_UI] stage=cards_ready count=10' in segment and ('[SURVIVAL_LOTTERY_UI] stage=reveal_ready animated=true' in segment), 'complete_native_successful_ten_reward_native_ack_required')
        if case.get('presentation') == 'movie':
            need(visual.get('actual_movie_content') is True, 'complete_native_draw_movie_must_be_distinct_from_fallback')
            actual_movie += 1
        else:
            reason = case.get('fallback_reason')
            marker = '[LOTTERY_CINEMATIC] native playback failed; using themed presentation' if reason == 'native_error' else '[LOTTERY_CINEMATIC] playback unavailable; using themed presentation'
            need(case.get('presentation') == 'fallback' and reason in ('native_error', 'sync_error') and (visual.get('fallback_animation_content') is True) and (marker in segment), 'complete_native_draw_fallback_requires_real_decoder_evidence')
            native_fallback += 1
        windows.update(((s['hwnd'], s['width'], s['height']) for s in shots))
    need(total == 30 and len(windows) == 1, 'complete_native_authorized_30_ticket_single_window_required')
    observed_requests = re.findall('\\[SURVIVAL_LOTTERY_UI\\] stage=result_received request=([A-Za-z0-9_:-]+)', text)
    need(len(observed_requests) == 3 and set(observed_requests) == requests, 'complete_native_unexpected_additional_draw_ack_exceeds_review_scope')
    extra = None
    if review.get('decoder_probe') is not None:
        need(isinstance(manifest, dict) and isinstance(original_evidence, dict), 'complete_native_probe_requires_authenticated_package_evidence')
        extra = _decoder_probe_case(review['decoder_probe'], process, bounds, text, reader, origin, captures, manifest, original_evidence)
        windows.add(extra.pop('_window'))
    need(len(windows) == 1, 'complete_native_all_lottery_and_probe_same_window_required')
    need(actual_movie > 0 and (native_fallback > 0 or extra is not None), 'complete_native_both_actual_movie_and_decoder_fallback_must_be_observed')
    return dict(pools=list(POOLS), actual_movie_previews=preview_movies, decoder_fallback_previews=preview_fallbacks, actual_movie_presentations=actual_movie, actual_decoder_fallbacks=native_fallback, same_pool_consecutive_real_ten_draws=3, ordinary_tickets_consumed=total, additional_decoder_probe=extra, _network_response_windows=tuple(response_windows), real_player_transaction_performed=True, synthetic_results=False)
BUFFERED_PRESENTATION_POLICY = 'BUFFERED_VIDEO_OR_DIRECT_RESULTS_V1'
BUFFERED_POLICY_RELEASE = 2026110701
BUFFERED_BAD_XML = 'panorama/layout/custom_game/lottery_movie_bad_media_probe.vxml_c'
BUFFERED_BAD_MEDIA = 'panorama/videos/custom_game/lottery_cinematic_v1/bad_media_probe.webm'
BUFFERED_BAD_SHA = '4ca876efe74ee477029c49a47a700a127af8847b47c6565de4f392e85b2cc712'

def _buffered_index(text, process):
    """One log scan; an attempt ID may restart in a later world."""
    index = {}
    active = {}
    offset = 0
    pattern = re.compile('\\[LOTTERY_BUFFERED_PLAYBACK\\] stage=([a-z_]+) attempt=(\\d+) pool=([a-z_]+) probe=(true|false)([^\\r\\n]*)')
    for line in text.splitlines(keepends=True):
        marker = pattern.search(line)
        if marker:
            clock = re.match('(\\d\\d)/(\\d\\d) (\\d\\d):(\\d\\d):(\\d\\d)', line)
            need(clock is not None, 'buffered_native_timestamp_required')
            when = datetime(int(process['created_utc'][:4]), *map(int, clock.groups()), tzinfo=timezone(timedelta(hours=8)))
            stage, attempt, pool, probe, tail = marker.groups()
            key = (int(attempt), pool, probe == 'true')
            fields = dict(re.findall('(?:^| )([a-z_]+)=([^ ]+)', tail))
            row = dict(stage=stage, time=when, fields=fields, offset=offset + marker.start())
            if stage == 'begin':
                need(key not in active, 'buffered_overlapping_attempt_identity')
                run = dict(key=key, rows=[row])
                index.setdefault(key, []).append(run)
                active[key] = run
            else:
                need(key in active, 'buffered_orphan_native_event')
                active[key]['rows'].append(row)
                if stage in ('complete', 'aborted'):
                    active.pop(key)
        offset += len(line)
    return index

def _buffered_resource(resources, original, path, *, compiled=True):
    actual = resources.get(path)
    need(actual is not None, 'buffered_signed_resource_missing:' + path)
    if compiled:
        proven = original['compiler']['outputs'].get(path)
        need(proven and all((actual.get(key) == proven.get(key) for key in ('bytes', 'sha256', 'md5'))), 'buffered_signed_official_compiler_output_required:' + path)
    return actual

def _buffered_case(case, roles, process, bounds, reader, origin, index, *, preview, bad=False):
    shots = captures(case, roles, process, bounds, reader, origin)
    visual = case.get('visual_review', {})
    need(all((visual.get(key) is True for key in ('no_movie_error_visible', 'no_secondary_animation', 'no_automatic_retry'))), 'buffered_actual_return_pixels_required')
    if preview:
        need(all((visual.get(key) is True for key in ('no_draw_inputs', 'returned_to_preview_origin'))) and type(case.get('tickets_before')) is int and (case['tickets_before'] == case.get('tickets_after')) and (case.get('actual_draw_inputs') == 0), 'buffered_preview_zero_transaction_required')
    else:
        need(visual.get('returned_to_lottery_window') is True, 'buffered_actual_return_to_lottery_required')
    attempt = case.get('buffered_attempt')
    need(type(attempt) is int and 1 <= attempt <= 1000000, 'buffered_actual_attempt_required')
    tolerance = timedelta(seconds=1)
    candidates = [run for run in index.get((attempt, case['pool'], bad), []) if shots[0]['end'] <= run['rows'][0]['time'] + tolerance and run['rows'][0]['time'] <= shots[-1]['end']]
    need(len(candidates) == 1, 'buffered_unique_same_case_native_lifecycle_required')
    run = candidates[0]
    rows = run['rows']
    stages = [row['stage'] for row in rows]
    need(stages[0] == 'begin' and stages[-1] == 'complete' and ('aborted' not in stages) and ([r['time'] for r in rows] == sorted((r['time'] for r in rows))) and (bounds[0] <= rows[0]['time'] + tolerance) and (rows[-1]['time'] <= bounds[1]) and (rows[-1]['time'] <= shots[-1]['start'] + tolerance), 'buffered_native_lifecycle_must_finish_in_capture_window')
    need(rows[0]['fields'].get('loadbehavior') == 'buffer-async' and rows[0]['fields'].get('source') == ('fixed_invalid_media' if bad else 'pool_movie'), 'buffered_correct_native_media_path_required')
    presentation = case.get('presentation')
    native_failure = False
    if presentation == 'movie':
        need(not bad and stages == ['begin', 'initialized', 'ended', 'complete'] and (rows[-1]['fields'].get('outcome') == 'native_ended'), 'buffered_movie_requires_real_initialization_and_end')
        elapsed = rows[2]['fields'].get('elapsed_ms', '')
        need(elapsed.isdigit() and 6000 <= int(elapsed) <= 12000, 'buffered_actual_movie_end_elapsed_required')
        need(shots[1]['sha256'] != shots[2]['sha256'] and shots[1]['start'] >= rows[0]['time'] - tolerance and (shots[2]['end'] <= rows[2]['time'] + tolerance) and all((visual.get(key) is True for key in ('actual_movie_content', 'animation_progressed', 'theme_matches_pool'))), 'buffered_actual_movie_frames_required')
    else:
        need(presentation == ('preview_return' if preview else 'results_direct'), 'buffered_direct_return_presentation_required')
        reason = case.get('failure_reason')
        need(reason in ('ended_before_initialized', 'early_end', 'setup_error', 'startup_timeout', 'completion_timeout'), 'buffered_exact_failure_reason_required')
        need(stages in (['begin', 'failure', 'complete'], ['begin', 'initialized', 'failure', 'complete']), 'buffered_one_failure_no_retry_lifecycle_required')
        failure = rows[-2]
        need(failure['fields'].get('reason') == reason and failure['fields'].get('action') == ('return_to_preview_idle' if preview else 'return_to_received_results') and (rows[-1]['fields'].get('outcome') == 'skipped_' + reason), 'buffered_failure_must_return_directly_to_actual_caller')
        if reason in ('ended_before_initialized', 'early_end'):
            need(failure['fields'].get('event') == 'VideoPlayerEnded', 'buffered_real_child_ended_evidence_required')
            if reason == 'ended_before_initialized':
                need('initialized' not in stages and failure['fields'].get('initialized') == 'false', 'buffered_end_before_init_required')
            else:
                elapsed = failure['fields'].get('elapsed_ms', '')
                need(stages[1] == 'initialized' and failure['fields'].get('initialized') == 'true' and elapsed.isdigit() and (0 <= int(elapsed) < 6000), 'buffered_actual_early_native_end_required')
            native_failure = True
        need(rows[-1]['time'] - failure['time'] <= tolerance, 'buffered_failure_return_has_no_second_animation')
    window = {(s['hwnd'], s['width'], s['height']) for s in shots}
    need(len(window) == 1, 'buffered_one_native_window_required')
    return dict(shots=shots, movie=presentation == 'movie', native_failure=native_failure, safe_return=presentation != 'movie' and (not native_failure), window=next(iter(window)), run=run)

def buffered_lottery_cases(review, process, bounds, text, reader, origin, *, manifest, original_evidence):
    """0701 policy: real video or immediate real result, never invented fallback."""
    need(review.get('lottery_presentation_policy') == BUFFERED_PRESENTATION_POLICY and review.get('decoder_probe') is None, 'buffered_policy_cannot_use_legacy_wrapper_probe')
    previews = review.get('lottery_previews', {})
    need(set(previews) == set(POOLS), 'complete_native_four_pool_previews_required')
    index = _buffered_index(text, process)
    windows = set()
    used = set()
    results = []
    resources = {row['path']: row for row in manifest['files']}

    def record(out):
        identity = out['run']['rows'][0]['offset']
        need(identity not in used, 'buffered_native_attempt_cannot_be_reused')
        used.add(identity)
        windows.add(out['window'])
        results.append(out)
    for pool in POOLS:
        case = previews[pool]
        need(case.get('pool') == pool and case.get('mode') == 'NO_CONSUMPTION_PREVIEW', 'complete_native_pool_preview_required')
        _buffered_resource(resources, original_evidence, 'panorama/layout/custom_game/lottery_movie_' + pool + '.vxml_c')
        _buffered_resource(resources, original_evidence, 'panorama/videos/custom_game/lottery_cinematic_v1/' + pool + '.webm', compiled=False)
        roles = ('window_before', 'animation_a', 'animation_b', 'window_after') if case.get('presentation') == 'movie' else ('window_before', 'window_after')
        record(_buffered_case(case, roles, process, bounds, reader, origin, index, preview=True))
    preview_movies = sum((out['movie'] for out in results))
    preview_returns = len(results) - preview_movies
    draws = review.get('consecutive_draws', [])
    need(len(draws) == 3, 'complete_native_three_authorized_consecutive_ten_draws_required')
    requests = set()
    previous = None
    previous_end = None
    total = 0
    response_windows = []
    draw_windows = []
    ack_matches = list(re.finditer('\\[SURVIVAL_LOTTERY_UI\\] stage=result_received request=([A-Za-z0-9_:-]+)', text))
    need(len(ack_matches) == 3, 'complete_native_unexpected_additional_draw_ack_exceeds_review_scope')
    acks = {match[1]: (match, ack_matches[i + 1].start() if i + 1 < len(ack_matches) else len(text)) for i, match in enumerate(ack_matches)}
    need(len(acks) == 3, 'complete_native_exact_actual_draw_ack_missing_or_duplicated')
    for case in draws:
        need(case.get('pool') == 'map' and case.get('count') == 10 and (case.get('ticket_kind') == 'ordinary') and (case.get('real_player_transaction') is True) and (case.get('skip_animation') is False), 'complete_native_actual_ordinary_map_ten_draw_required')
        request = case.get('request_id')
        need(isinstance(request, str) and 1 <= len(request) <= 128 and re.fullmatch('[A-Za-z0-9_:-]+', request) and (request not in requests) and (request in acks), 'complete_native_distinct_actual_draw_request_required')
        requests.add(request)
        before, after = (case.get('tickets_before'), case.get('tickets_after'))
        need(type(before) is int and type(after) is int and (before >= 10) and (after >= 0) and (before - after == 10) and (previous is None or before == previous), 'complete_native_exact_authorized_ticket_debit_required')
        total += before - after
        previous = after
        roles = ('window_before', 'animation_a', 'animation_b', 'results', 'window_after') if case.get('presentation') == 'movie' else ('window_before', 'results', 'window_after')
        out = _buffered_case(case, roles, process, bounds, reader, origin, index, preview=False)
        shots = out['shots']
        record(out)
        need(previous_end is None or previous_end < shots[0]['start'], 'complete_native_draws_must_be_observed_consecutively')
        previous_end = shots[-1]['end']
        draw_windows.append((shots[0]['start'], shots[-1]['end']))
        need(all((case.get('visual_review', {}).get(key) is True for key in ('ten_actual_rewards_visible', 'confirm_button_full_width', 'owned_text_visible_when_applicable'))), 'complete_native_each_draw_requires_actual_rewards_and_return')
        ack, next_ack = acks[request]
        left = ack.start()
        segment = text[left:next_ack]
        stamp = _time(text[text.rfind('\n', 0, left) + 1:left])
        need(stamp is not None and _engine_clock(shots[0]['start']) - 1 <= stamp <= _engine_clock(shots[-1]['end']) + 1, 'complete_native_draw_ack_must_match_its_actual_case')
        response_windows.append((stamp - 1, stamp + 1))
        need(left < out['run']['rows'][0]['offset'] < out['run']['rows'][-1]['offset'] < next_ack, 'buffered_native_presentation_requires_its_received_draw')
        need(re.search('\\[SURVIVAL_LOTTERY_UI\\] result_count=10 server_count=10\\b', segment) and '[SURVIVAL_LOTTERY_UI] stage=cards_ready count=10' in segment and re.search('\\[SURVIVAL_LOTTERY_UI\\] stage=reveal_ready animated=' + ('true' if out['movie'] else '(?:true|false)') + '\\b', segment), 'complete_native_successful_ten_reward_native_ack_required')
        need(out['run']['rows'][-1]['time'] <= shots[-2]['start'] + timedelta(seconds=1), 'buffered_results_must_follow_presentation_completion')
    need(total == 30 and set(acks) == requests, 'complete_native_authorized_30_ticket_single_window_required')
    probe = review.get('buffered_failure_probe')
    extra = None
    if probe is not None:
        need(probe.get('mode') == 'ZERO_CONSUMPTION_BUFFERED_FAILURE_PROBE' and probe.get('pool') == 'map' and (probe.get('presentation') == 'preview_return') and (probe.get('ordinary_client') is True), 'buffered_fixed_production_failure_probe_required')
        _buffered_resource(resources, original_evidence, BUFFERED_BAD_XML)
        media = _buffered_resource(resources, original_evidence, BUFFERED_BAD_MEDIA, compiled=False)
        need(media.get('bytes') == 59 and media.get('sha256') == BUFFERED_BAD_SHA, 'buffered_exact_bad_media_required')
        out = _buffered_case(probe, ('window_before', 'window_after'), process, bounds, reader, origin, index, preview=True, bad=True)
        need(out['native_failure'], 'buffered_timeout_or_setup_does_not_prove_decoder_failure')
        need(all((out['shots'][-1]['end'] < start or end < out['shots'][0]['start'] for start, end in draw_windows)), 'buffered_free_probe_must_be_separate_from_real_draws')
        record(out)
        extra = dict(ordinary_tickets_consumed=0, real_draw_case_replacement=False, actual_decoder_returns=1)
    need(len(windows) == 1 and any((out['movie'] for out in results)) and any((out['native_failure'] for out in results)), 'buffered_actual_video_and_actual_production_failure_return_required')
    return dict(presentation_policy=BUFFERED_PRESENTATION_POLICY, pools=list(POOLS), actual_movie_previews=preview_movies, direct_return_previews=preview_returns, actual_movie_presentations=sum((out['movie'] for out in results)), actual_decoder_returns=sum((out['native_failure'] for out in results)), safe_timeout_or_setup_returns=sum((out['safe_return'] for out in results)), same_pool_consecutive_real_ten_draws=3, ordinary_tickets_consumed=total, additional_buffered_failure_probe=extra, _network_response_windows=tuple(response_windows), real_player_transaction_performed=True, synthetic_results=False)

def buffered_review_template(value):
    """Empty exact branch shapes; no passing flags, IDs, balances or outcomes."""
    value['lottery_presentation_policy'] = BUFFERED_PRESENTATION_POLICY
    value['decoder_probe'] = None
    value['buffered_failure_probe'] = None
    for item in list(value['lottery_previews'].values()) + value['consecutive_draws']:
        item.pop('fallback_reason', None)
        item.update(buffered_attempt=None, failure_reason=None)
        visual = item['visual_review']
        visual.pop('fallback_animation_content', None)
        visual.pop('no_movie_error_visible_after_fallback', None)
        visual.update(dict.fromkeys(('no_movie_error_visible', 'no_secondary_animation', 'no_automatic_retry', 'theme_matches_pool'), False))
        if item.get('mode') == 'NO_CONSUMPTION_PREVIEW':
            item['actual_draw_inputs'] = None
            visual['returned_to_preview_origin'] = False
    value['direct_return_capture_roles'] = {'preview_return': ['window_before', 'window_after'], 'results_direct': ['window_before', 'results', 'window_after']}
    return value
AUTH = 'survival_player_web_auth_state'
STATUSES = {'requesting', 'pending', 'approved', 'failed', 'expired'}
AUTH_KEYS = {'session_id', 'player_id', 'status', 'error', 'user_code', 'verification_uri', 'expires_in', 'diagnostic_revision', 'diagnostic_phase', 'diagnostic_stage', 'diagnostic_status'}
MAX_LOG = 64 * 1024 * 1024

def _need(ok, code):
    if not ok:
        raise ValueError(code)

def _time(line):
    match = re.match('(\\d\\d)/(\\d\\d) (\\d\\d):(\\d\\d):(\\d\\d)\\b', line)
    if not match:
        return None
    mo, day, hour, minute, second = map(int, match.groups())
    return datetime(2000, mo, day, hour, minute, second, tzinfo=timezone(timedelta(hours=8))).timestamp()

def _engine_clock(value):
    return value.astimezone(timezone(timedelta(hours=8))).replace(year=2000).timestamp()

def _unescape(text):
    if text.startswith('"'):
        _need(text.endswith('"'), 'native_data_quote_invalid')
        text = text[1:-1]
    result = bytearray()
    offset = 0
    while offset < len(text):
        char = text[offset]
        offset += 1
        if char != '\\':
            _need(ord(char) < 128, 'native_data_must_use_byte_escapes')
            result.append(ord(char))
            continue
        _need(offset < len(text), 'native_data_escape_truncated')
        if text[offset] in '01234567':
            end = offset
            while end < min(offset + 3, len(text)) and text[end] in '01234567':
                end += 1
            value = int(text[offset:end], 8)
            _need(value < 256, 'native_data_octal_invalid')
            result.append(value)
            offset = end
        else:
            escapes = {'n': 10, 'r': 13, 't': 9, '\\': 92, '"': 34, "'": 39}
            _need(text[offset] in escapes, 'native_data_escape_unknown')
            result.append(escapes[text[offset]])
            offset += 1
    return bytes(result)

def _vbkv(raw):
    """Flat Source2 VBKV event object; full bounded consumption is mandatory."""
    _need(len(raw) >= 10 and raw[:4] == b'VBKV' and (zlib.crc32(raw[8:]) == struct.unpack('<I', raw[4:8])[0]), 'native_vbkv_container_invalid')
    offset = 8

    def take(size):
        nonlocal offset
        _need(0 <= size <= len(raw) - offset, 'native_vbkv_truncated')
        value = raw[offset:offset + size]
        offset += size
        return value

    def string():
        nonlocal offset
        end = raw.find(b'\x00', offset)
        _need(end >= offset, 'native_vbkv_string_truncated')
        value = raw[offset:end].decode('utf8')
        offset = end + 1
        return value
    _need(take(2) == b'\x00\x00', 'native_vbkv_root_invalid')
    values = {}
    while True:
        kind = take(1)[0]
        if kind == 11:
            break
        key = string()
        _need(re.fullmatch('[A-Za-z0-9_]{1,64}', key) and key not in values, 'native_vbkv_key_invalid')
        if kind == 1:
            value = string()
        elif kind == 2:
            value = struct.unpack('<i', take(4))[0]
        elif kind == 3:
            value = struct.unpack('<f', take(4))[0]
            _need(math.isfinite(value), 'native_vbkv_nonfinite_number')
        elif kind == 7:
            value = struct.unpack('<Q', take(8))[0]
        elif kind == 8:
            value = take(1)[0]
        elif kind == 9:
            value = 0
        elif kind == 10:
            value = 1
        else:
            raise ValueError('native_vbkv_flat_type_unsupported')
        values[key] = value
    _need(take(1) == b'\x0b' and offset == len(raw), 'native_vbkv_trailing_or_missing_end')
    return values

def _cw(raw):
    values = _vbkv(raw)
    _need(set(values) == {'d'} and isinstance(values['d'], str) and re.fullmatch('[A-Za-z0-9_-]{1,24}', values['d']), 'native_cw_single_bounded_d_key_required')
    token = values['d']
    body = base64.urlsafe_b64decode(token + '=' * (-len(token) % 4))
    _need(0 < len(body) <= 18 and body[0] in (16, 17, 18), 'native_cw_body_invalid')
    offset = 1
    integers = []
    for unused in range(7):
        value = 0
        for shift in range(0, 35, 7):
            _need(offset < len(body), 'native_cw_header_truncated')
            byte = body[offset]
            offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                break
        else:
            raise ValueError('native_cw_header_overflow')
        integers.append(value)
    return (body[0], tuple(integers))
_BUILD_CATALOG_SEAL = object()

class _BuildCatalog:

    def __init__(self, seal, data, config, runtime, construction, building_source, research='', arrow=''):
        _need(seal is _BUILD_CATALOG_SEAL, 'internal_build_catalog_required')
        self.seal = seal
        self.fields = {row['id']: row for row in data['fields']}
        self.field_ids = {row['name']: row['id'] for row in data['fields']}
        self.records = {row['id']: row for row in data['records'] if not row.get('tombstone')}
        _need(len(self.fields) == len(self.field_ids) == len(data['fields']) and all((type(v) is int and 1 <= v <= 255 for v in self.fields)), 'unique_build_fields_required')
        keys = {row['key']: row['id'] for row in self.records.values()}
        self.commit, self.validation = (keys['grid:commit'], keys['grid:validation'])
        self.view = int(re.search('keys\\.grid=(\\d+);', runtime)[1])
        self.schema = int(re.search('return \\{schema:(\\d+),schema_sha256:C\\.sha256', runtime)[1])
        _need(re.fullmatch('[a-f0-9]{64}', data['sha256']), 'build_catalog_digest_required')
        for name in ('known', 'success', 'grid_error', 'grid_scope', 'grid_session', 'grid_profile'):
            _need(name in self.field_ids, 'build_catalog_field_missing')
        self.profiles, self.anchors, self.messages = ({}, {}, {})
        starts = list(re.finditer('\\bM\\.([A-Za-z0-9_]+)\\s*=\\s*\\{', config))
        sections = {m[1]: config[m.end():starts[i + 1].start() if i + 1 < len(starts) else len(config)] for i, m in enumerate(starts)}
        durations = {m[1]: float(m[2]) for m in re.finditer('building_id\\s*=\\s*"([A-Za-z0-9_]+)"[^\\n]*build_time\\s*=\\s*([0-9.]+)', construction)}
        research_first = {}
        for line in research.splitlines():
            if 'enabled = false' in line:
                continue
            row = {key: value for key, value in re.findall('(ability_name|building_id)\\s*=\\s*"([A-Za-z0-9_]+)"', line)}
            order = {key: int(value) for key, value in re.findall('(slot_order|chain_order)\\s*=\\s*(\\d+)', line)}
            if len(row) != 2 or len(order) != 2:
                continue
            rank = (order['slot_order'], order['chain_order'])
            old = research_first.get(row['building_id'])
            if old is None or rank < old[0]:
                research_first[row['building_id']] = (rank, row['ability_name'])
        expected = 0
        for profile in data['auxiliary']['grid']['profiles']:
            building = profile['building_id']
            if profile.get('placement_action'):
                continue
            expected += 1
            _need(building in sections and building in durations, 'known_build_source_definition_required')
            section = sections[building]
            literal = re.search('abilities\\s*=\\s*\\{\\s*"([A-Za-z0-9_]+)"', section)
            anchor = literal[1] if literal else None
            if anchor is None:
                _need(re.search('abilities\\s*=\\s*(research_lab_skill_names|research_lab_ability_sync\\.initial_abilities)', section) and building in research_first, 'known_dynamic_build_anchor_required')
                anchor = research_first[building][1]
            if building == 'arrow_tower':
                first = re.search('active_skill_ids\\s*=\\s*\\{\\s*"([A-Za-z0-9_]+)"', arrow)
                _need(first is not None and first[1] == anchor, 'actual_arrow_initial_ability_anchor_required')
            duration = durations[building]
            _need(duration > 0, 'reviewed_build_duration_required')
            record = keys['grid:profile:' + profile['ability_name']]
            item = dict(profile, record=record, anchor=anchor, duration=duration)
            self.profiles[record] = item
            _need(anchor not in self.anchors, 'unique_build_lifecycle_anchor_required')
            self.anchors[anchor] = item
            for phase, suffix in (('approach', '正在前往建造位置'), ('start', '开始建造'), ('complete', '已建造')):
                _need('.. "' + suffix + '"' in building_source, 'reviewed_build_notification_source_changed')
                self.messages[profile['display_name'] + suffix] = (item, phase)
        _need(len(self.profiles) == expected and expected > 0, 'all_known_build_profiles_required')

def _build_catalog_from_sources(raw, config, runtime, construction, building_source, research=b'', arrow=b'', training=b'', worker=b'', queue=b'', views=b'', router=b''):
    """Pure parser of already source-bound generated JSON and narrow Lua anchors."""
    text = raw.decode('utf8')
    prefix = 'var data='
    _need(text.count(prefix) == 1, 'single_generated_catalog_json_required')
    data, _ = json.JSONDecoder().raw_decode(text[text.index(prefix) + len(prefix):])
    catalog = _BuildCatalog(_BUILD_CATALOG_SEAL, data, config.decode('utf8'), runtime.decode('utf8'), construction.decode('utf8'), building_source.decode('utf8'), research.decode('utf8'), arrow.decode('utf8'))
    catalog.training = _TrainingCatalog(_TRAINING_CATALOG_SEAL, *[v.decode('utf8') for v in (training, worker, queue, views, router)]) if training and b'[WORKER_TRAINING_TRACE] v=1 phase=' in worker else None
    return catalog

def _load_build_catalog(builder, report):
    names = ('panorama/src/scripts/custom_game/common/ui_static_catalog.js', 'scripts/vscripts/config/buildings_config.lua', 'panorama/src/scripts/custom_game/common/compact_ui_runtime.js', 'scripts/vscripts/config/generated/building_construction_rules.lua', 'scripts/vscripts/systems/building_system.lua', 'scripts/vscripts/config/generated/research_lab_abilities.lua', 'scripts/vscripts/config/generated/arrow_tower_base.lua', 'scripts/vscripts/config/generated/training_definitions.lua', 'scripts/vscripts/systems/worker_system.lua', 'scripts/vscripts/systems/worker_training_queue_service.lua', 'scripts/vscripts/ui/compact_production_views.lua', 'scripts/vscripts/ui/production_ui_service.lua')
    git = builder.dependencies().package.pending._git
    raw = [git(ROOT, 'show', report['source_revisions']['game'] + ':' + name, counts=Counter()) for name in names]
    _need(sum(map(len, raw)) <= 8 * 1024 * 1024, 'bounded_build_operation_catalog_required')
    return _build_catalog_from_sources(*raw)

def _wire_uint(raw, offset):
    value = 0
    for shift in range(0, 35, 7):
        _need(offset < len(raw), 'build_wire_truncated')
        byte = raw[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            _need(value <= 4294967295, 'build_wire_integer_overflow')
            return (value, offset)
    raise ValueError('build_wire_integer_overflow')

class _BuildOperations:
    """One-world evidence index; no operation is authorized by text alone.

    Initialization O(catalogue records+fields). One pass O(log bytes+decoded
    changes+operations); indexed phase matching uses at most three clock keys.
    Retained state is bounded by the log, 256KiB/current wire assembly and the
    fixed grid schema. No native/API/runtime or recurring scene scan occurs.
    """

    def __init__(self, catalog):
        _need(type(catalog) is _BuildCatalog and catalog.seal is _BUILD_CATALOG_SEAL, 'internal_source_bound_build_catalog_required')
        self.c = catalog
        self.builders, self.pending_anchor, self.entities = ({}, {}, {})
        self.active, self.submitted = (None, None)
        self.last_cycle, self.latest = ({}, {})
        self.assembly, self.binding, self.revision, self.values = (None, None, 0, {})
        self.seen, self.operations, self.notifications = (set(), [], [])
        self.invalid = 0
        self.metrics = dict(wire_frames=0, decoded_changes=0, phase_clock_probes=0, retired_permits=0)

    def line(self, line, ordinal):
        stamp = _time(line)
        if stamp is None:
            return
        found = re.search('\\[BUILDER_READY\\] player=(\\d+)\\b.* entindex=(\\d+)\\b', line)
        if found:
            player, unit = map(int, found.groups())
            if player <= 63:
                self.builders[unit] = player
        found = re.search('\\[SURVIVAL_CAST\\]\\[CLIENT\\] POINT_TARGET_BEGIN unit=(\\d+) ability=(\\d+) name=([A-Za-z0-9_]+)\\b', line)
        if found:
            unit, ability, name = (int(found[1]), int(found[2]), found[3])
            old = self.last_cycle.get(unit)
            if old is not None:
                old['next_begin'] = ordinal
            self.active = dict(unit=unit, ability=ability, name=name, player=self.builders.get(unit), begin=ordinal, time=stamp, submit=None, next_begin=None)
            self.last_cycle[unit] = self.active
        if '[SURVIVAL_CAST][CLIENT] POINT_TARGET_CANCEL reason=' in line:
            if self.active is not None and 'POINT_TARGET_CANCEL reason=grid_submitted' in line:
                self.active.update(submit=ordinal, submit_time=stamp)
                self.submitted = self.active
            self.active = None
        found = re.search('\\[BuildingAbility\\] add begin unit=(\\d+) ability=([A-Za-z0-9_]+)\\b', line)
        if found and found[2] in self.c.anchors:
            self.pending_anchor[int(found[1]), found[2]] = (stamp, ordinal)
        found = re.search('\\[BuildingAbility\\] AddAbility OK unit=(\\d+) ability=([A-Za-z0-9_]+) index=0\\b', line)
        if not found or found[2] not in self.c.anchors:
            return
        unit, anchor = (int(found[1]), found[2])
        before = self.pending_anchor.pop((unit, anchor), None)
        if before is None or not 0 <= stamp - before[0] <= 1:
            return
        item = self.c.anchors[anchor]
        entity = self.entities.get(unit)
        if entity is None:
            operation = self.latest.get(item['record'])
            if operation is None:
                return
            cycle = operation['cycle']
            if operation['ordinal'] >= ordinal or cycle['unit'] == unit or (cycle['next_begin'] is not None and cycle['next_begin'] <= ordinal):
                return
            entity = dict(operation=operation, anchor=anchor, first=(stamp, ordinal), second=None, matched_start=False)
            self.entities[unit] = entity
            operation['entities'].append(entity)
        elif entity['anchor'] == anchor and entity['second'] is None:
            entity['second'] = (stamp, ordinal)

    def event(self, header):
        """Consume at the actual data line, before subsequent lifecycle logs."""
        event, stamp = (header['event'], header['time'])
        if stamp is None:
            return
        if event == 'ui_notification':
            try:
                value = _vbkv(_unescape(header['data']))
            except (ValueError, UnicodeError, struct.error):
                return
            match = self.c.messages.get(value.get('message'))
            if match is None:
                return
            shape = set(value) == {'audience', 'kind', 'level', 'message', 'player_id', 'rich_text'} and value['audience'] == 'player' and (value['kind'] == 'message') and (value['level'] == 'info') and (value['rich_text'] == 0) and (type(value['player_id']) is int) and (0 <= value['player_id'] <= 63)
            self.notifications.append(dict(ordinal=header['ordinal'], time=stamp, body=header['data'], profile=match[0]['record'], phase=match[1], player=value.get('player_id'), shape=shape))
            return
        if event != 'cw' or header['size'] > 50 or math.ceil(header['bits'] / 8) != header['size']:
            return
        try:
            self._wire(header)
        except (ValueError, UnicodeError, struct.error, IndexError):
            self.assembly, self.binding, self.values, self.revision = (None, None, {}, 0)
            self.invalid += 1

    def _wire(self, header):
        value = _vbkv(_unescape(header['data']))
        _need(set(value) == {'d'} and isinstance(value['d'], str), 'build_wire_shape')
        raw = base64.urlsafe_b64decode(value['d'] + '=' * (-len(value['d']) % 4))
        _need(0 < len(raw) <= 18 and raw[0] in (16, 17, 18), 'build_wire_budget')
        at, head = (1, [])
        for unused in range(7):
            item, at = _wire_uint(raw, at)
            head.append(item)
        schema, session, epoch, view, revision, index, count = head
        if view != self.c.view:
            return
        self.metrics['wire_frames'] += 1
        _need(schema == self.c.schema and session > 0 and (epoch > 0) and (1 <= index <= count <= 16383), 'build_wire_binding')
        if raw[0] == 18:
            return
        binding = (schema, session, epoch, view)
        _need(revision > 0, 'build_wire_revision')
        identity = (*binding, revision, raw[0], count)
        if self.assembly is None or identity != self.assembly['identity']:
            _need(self.assembly is None, 'build_wire_fragment_identity')
            _need(raw[0] == 17 or (self.binding == binding and revision == self.revision + 1), 'build_wire_missing_base')
            self.assembly = dict(identity=identity, parts={}, bytes=0)
        a = self.assembly
        old = a['parts'].get(index)
        _need(old is None, 'build_wire_duplicate_fragment')
        a['parts'][index] = raw[at:]
        a['bytes'] += len(raw) - at
        _need(a['bytes'] <= 262144, 'build_wire_assembly_budget')
        if len(a['parts']) != count:
            return
        body = b''.join((a['parts'][part] for part in range(1, count + 1)))
        at = 0
        previous_session = self.values.get((self.c.commit, self.c.field_ids['grid_session']))
        previous_scope = self.values.get((self.c.commit, self.c.field_ids['grid_scope']))
        changes = {}
        values = {} if raw[0] == 17 else self.values
        while at < len(body):
            record, at = _wire_uint(body, at)
            tag, at = _wire_uint(body, at)
            field = tag // 2
            _need(record in self.c.records and field in self.c.fields, 'build_wire_unknown_index')
            key = (record, field)
            _need(key not in changes, 'build_wire_duplicate_index')
            self.metrics['decoded_changes'] += 1
            v = None
            if not tag & 1:
                v, at = _wire_uint(body, at)
                definition = self.c.fields[field]
                if definition['kind'] == 'sint':
                    v = -(v // 2) - 1 if v & 1 else v // 2
                _need(definition['min'] <= v <= definition['max'], 'build_wire_value_range')
            changes[key] = v
            if v is None:
                values.pop(key, None)
            else:
                values[key] = v
        self.binding, self.revision, self.values, self.assembly = (binding, revision, values, None)
        F = self.c.field_ids
        get = lambda rec, name: values.get((rec, F[name]))
        token = get(self.c.commit, 'grid_session')
        changed_session = (self.c.commit, F['grid_session']) in changes and token != previous_session
        if raw[0] != 16 or not changed_session or (not token):
            return
        scope = get(self.c.commit, 'grid_scope')
        identity = (*binding, scope, token)
        if type(scope) is not int or scope <= 0 or type(token) is not int or (token <= 0):
            return
        if scope == previous_scope and previous_session is not None and (token <= previous_session):
            return
        _need(identity not in self.seen, 'build_operation_token_replay')
        self.seen.add(identity)
        if get(self.c.commit, 'known') != 1 or get(self.c.commit, 'success') != 1 or get(self.c.commit, 'grid_error') != 0 or (get(self.c.validation, 'known') != 1) or (get(self.c.validation, 'success') != 1) or (get(self.c.validation, 'grid_error') != 0) or (get(self.c.validation, 'grid_scope') != scope) or (get(self.c.validation, 'grid_session') != token):
            return
        profile = self.c.profiles.get(get(self.c.validation, 'grid_profile'))
        if profile is None:
            return
        cycle = self.active or self.submitted
        if cycle is None or cycle['player'] is None or cycle['name'] != profile['ability_name']:
            return
        operation = dict(identity=identity, ordinal=header['ordinal'], time=header['time'], profile=profile, cycle=cycle, entities=[], approach=False)
        self.operations.append(operation)
        self.latest[profile['record']] = operation

    def finish(self):
        permits, consumed = ({}, set())

        def put(profile, player, phase, point, operation, entity=None):
            key = (profile, player, phase, int(point[0]))
            permits.setdefault(key, deque()).append((point, operation, entity))
        valid = []
        for op in self.operations:
            cycle = op['cycle']
            if cycle['submit'] is None or abs(cycle['submit_time'] - op['time']) > 1:
                continue
            valid.append(op)
            put(op['profile']['record'], cycle['player'], 'approach', (op['time'], op['ordinal']), op)
            for entity in op['entities']:
                put(op['profile']['record'], cycle['player'], 'start', entity['first'], op, entity)
                if entity['second'] is not None and entity['second'][0] - entity['first'][0] >= op['profile']['duration'] - 1:
                    put(op['profile']['record'], cycle['player'], 'complete', entity['second'], op, entity)
        matched = set()

        def eligible(permit, notice):
            point, op, entity = permit
            cycle = op['cycle']
            return (op['identity'], notice['phase']) not in consumed and (notice['phase'] == 'approach' or op['approach']) and (notice['phase'] != 'complete' or entity['matched_start']) and (cycle['begin'] <= notice['ordinal']) and (notice['phase'] != 'approach' or cycle['next_begin'] is None or cycle['next_begin'] > notice['ordinal']) and (notice['phase'] == 'approach' or point[1] < notice['ordinal'])
        for notice in self.notifications:
            candidates = []
            for second in (int(notice['time']) - 1, int(notice['time']), int(notice['time']) + 1):
                self.metrics['phase_clock_probes'] += 1
                key = (notice['profile'], notice['player'], notice['phase'], second)
                queue = permits.get(key, deque())
                while queue:
                    permit = queue[0]
                    point, op, entity = permit
                    identity = (op['identity'], notice['phase'])
                    cycle = op['cycle']
                    impossible = identity in consumed or (notice['phase'] != 'approach' and (not op['approach'])) or (notice['phase'] == 'complete' and (not entity['matched_start'])) or (notice['phase'] == 'approach' and cycle['next_begin'] is not None and (cycle['next_begin'] <= notice['ordinal']))
                    if impossible:
                        queue.popleft()
                        self.metrics['retired_permits'] += 1
                        continue
                    if cycle['begin'] > notice['ordinal']:
                        break
                    if notice['phase'] != 'approach' and point[1] >= notice['ordinal']:
                        break
                    candidates.append((identity, permit))
                    if len(queue) > 1 and eligible(queue[1], notice):
                        candidates.append((None, None))
                    break
                if len(candidates) > 1:
                    break
            if not notice['shape'] or len(candidates) != 1:
                continue
            identity, (point, op, entity) = candidates[0]
            consumed.add(identity)
            matched.add(notice['ordinal'])
            if notice['phase'] == 'approach':
                op['approach'] = True
            elif notice['phase'] == 'start':
                entity['matched_start'] = True
        return dict(matched=matched, unproven=len(self.notifications) - len(matched), operations=len(valid), invalid_wire_transactions=self.invalid, metrics=self.metrics.copy())
_TRAINING_CATALOG_SEAL = object()

class _TrainingCatalog:
    """Only package-bound sources may create completion-message definitions."""

    def __init__(self, seal, definitions, worker, queue, views, router):
        _need(seal is _TRAINING_CATALOG_SEAL, 'internal_training_catalog_required')
        self.seal, self.definitions, self.messages = (seal, {}, {})
        anchors = ((worker, ('[WORKER_TRAINING_TRACE] v=1 phase=', 'trace = training_trace,', '_training_trace = payload._training_trace,', 'notify(city_state.player_id, tostring(training.name) .. "训练完成")')), (queue, ('trace("enqueue", job)', 'trace("start", job)', 'trace("complete", job, result)', 'result.entindex > 0', 'if queues[queue.source_entindex] ~= queue or queue.jobs[1] ~= job then return end')), (views, ('owner_serial=state.owner_serial, request_token=token,', 'production_selection=state.selection, action_code=8}', 'state.used[token]={identity=identity};state.busy=true')), (router, ('_training_trace = capture and payload._training_trace or nil,', 'worker_request(payload,false)')))
        for source, required in anchors:
            _need(all((value in source for value in required)), 'reviewed_training_trace_source_required')
        for line in definitions.splitlines():
            if 'enabled = false' in line:
                continue
            found = re.search('training_id\\s*=\\s*"(train_lumberjack_[0-9]+)"', line)
            if not found:
                continue
            name = re.search('\\bname\\s*=\\s*"([^"\\\\]+)"', line)
            duration = re.search('\\btraining_duration_seconds\\s*=\\s*([0-9.]+)', line)
            _need(name is not None and duration is not None and (float(duration[1]) >= 0.05), 'reviewed_training_definition_required')
            key, message = (found[1], name[1] + '训练完成')
            _need(key not in self.definitions and message not in self.messages, 'unique_training_definition_required')
            self.definitions[key] = dict(message=message, duration=float(duration[1]))
            self.messages[message] = key
        _need(self.definitions, 'training_definitions_required')

class _TrainingOperations:
    """One world, one credit per real successful job, never an event whitelist.

    Initialization O(definitions). Parsing O(log bytes+markers+notices), final
    matching O(jobs+notices) with indexed FIFO queues. No per-tick/gameplay scan,
    no input injection, no extra network traffic, no cold-response allowance.
    IDs remain RAM-only. Source-bound producers log at most 3 lines per job.
    """
    FIELDS = frozenset(('v', 'phase', 'world', 'queue', 'job', 'player', 'source', 'owner', 'adapter', 'token', 'selection', 'action', 'training', 'duration', 'started', 'finish', 'now', 'unit'))
    ID_FIELDS = ('world', 'queue', 'job', 'player', 'source', 'adapter', 'owner', 'token', 'selection', 'action', 'training', 'duration')

    def __init__(self, catalog):
        _need(type(catalog) is _TrainingCatalog and catalog.seal is _TRAINING_CATALOG_SEAL, 'internal_source_bound_training_catalog_required')
        self.c, self.jobs, self.origins, self.notifications = (catalog, {}, {}, [])
        self.world, self.invalid = (None, 0)
        self.completed = []
        self.metrics = dict(marker_lines=0, job_lookups=0, notification_checks=0, retired_permits=0)

    def line(self, line, ordinal):
        tag = '[WORKER_TRAINING_TRACE] '
        if tag not in line:
            return
        self.metrics['marker_lines'] += 1
        try:
            stamp = _time(line)
            _need(stamp is not None, 'training_trace_clock_required')
            body = line.split(tag, 1)[1].strip()
            pairs = [part.split('=', 1) for part in body.split(' ')]
            _need(all((len(pair) == 2 for pair in pairs)), 'training_trace_shape')
            row = dict(pairs)
            _need(len(row) == len(pairs) and set(row) == self.FIELDS, 'training_trace_fields')
            for key in self.FIELDS - {'phase', 'training', 'duration', 'started', 'finish', 'now'}:
                _need(re.fullmatch('\\d{1,10}', row[key]) is not None, 'training_trace_integer')
                row[key] = int(row[key])
                _need(row[key] <= 4294967295, 'training_trace_integer_range')
            for key in ('duration', 'started', 'finish', 'now'):
                _need(re.fullmatch('-?\\d{1,12}\\.\\d{6}', row[key]) is not None, 'training_trace_float')
                row[key] = float(row[key])
                _need(math.isfinite(row[key]), 'training_trace_finite')
            _need(row['v'] == 1 and row['action'] == 8 and (row['phase'] in ('enqueue', 'start', 'complete')) and (0 <= row['player'] <= 63) and (1 <= row['token'] <= 16383) and all((row[key] > 0 for key in ('world', 'queue', 'job', 'source', 'adapter', 'owner', 'selection'))), 'training_trace_identity')
            definition = self.c.definitions.get(row['training'])
            _need(definition is not None and abs(row['duration'] - definition['duration']) <= 1e-06, 'training_trace_definition')
            if self.world is None:
                self.world = row['world']
            _need(self.world == row['world'], 'training_trace_world_changed')
            identity = (row['world'], row['queue'], row['job'])
            origin = (row['world'], row['adapter'], row['owner'], row['token'])
            self.metrics['job_lookups'] += 1
            job = self.jobs.get(identity)
            if row['phase'] == 'enqueue':
                if identity in self.jobs or origin in self.origins:
                    if job is not None:
                        job['invalid'] = True
                    previous = self.jobs.get(self.origins.get(origin))
                    if previous is not None:
                        previous['invalid'] = True
                    raise ValueError('training_trace_replayed_action_or_job')
                _need(row['unit'] == 0 and row['started'] == 0 and (row['finish'] == 0), 'training_enqueue_state')
                self.jobs[identity] = dict(identity=identity, row=row, phase='enqueue', ordinal=ordinal, time=stamp, invalid=False, started=None, completed=None)
                self.origins[origin] = identity
                return
            _need(job is not None, 'training_trace_missing_enqueue')
            try:
                _need(not job['invalid'] and all((row[key] == job['row'][key] for key in self.ID_FIELDS)), 'training_trace_job_changed')
                _need(ordinal > job['ordinal'] and stamp >= job['time'], 'training_trace_order')
                _need(abs(row['finish'] - row['started'] - row['duration']) <= 2e-06, 'training_trace_duration')
                if row['phase'] == 'start':
                    _need(job['phase'] == 'enqueue' and row['unit'] == 0 and (row['started'] >= job['row']['now']) and (abs(row['now'] - row['started']) <= 1e-06), 'training_trace_start_state')
                    job['phase'], job['started'] = ('start', row)
                else:
                    start = job['started']
                    _need(job['phase'] == 'start' and row['unit'] > 0 and (start is not None) and (row['started'] == start['started']) and (row['finish'] == start['finish']) and (row['now'] + 1e-06 >= row['finish']), 'training_trace_completion_state')
                    job['phase'], job['completed'] = ('complete', dict(row=row, time=stamp, ordinal=ordinal))
                    self.completed.append(job)
            except (ValueError, TypeError):
                job['invalid'] = True
                raise
        except (ValueError, TypeError, KeyError):
            self.invalid += 1

    def event(self, header):
        if header['event'] != 'ui_notification' or header['time'] is None:
            return
        try:
            value = _vbkv(_unescape(header['data']))
        except (ValueError, UnicodeError, struct.error):
            return
        training = self.c.messages.get(value.get('message'))
        if training is None:
            return
        shape = set(value) == {'audience', 'kind', 'level', 'message', 'player_id', 'rich_text'} and value['audience'] == 'player' and (value['kind'] == 'message') and (value['level'] == 'info') and (value['rich_text'] == 0) and (type(value['player_id']) is int) and (0 <= value['player_id'] <= 63)
        self.notifications.append(dict(ordinal=header['ordinal'], time=header['time'], training=training, player=value.get('player_id'), shape=shape))

    def finish(self):
        permits, matched = ({}, set())
        successful = 0
        for job in self.completed:
            if job['invalid']:
                continue
            row = job['row']
            key = (row['player'], row['training'])
            permits.setdefault(key, deque()).append(job)
            successful += 1
        for notice in self.notifications:
            self.metrics['notification_checks'] += 1
            if not notice['shape']:
                continue
            queue = permits.get((notice['player'], notice['training']))
            if queue is None:
                continue
            while queue and queue[0]['completed']['time'] < notice['time'] - 1:
                queue.popleft()
                self.metrics['retired_permits'] += 1
            if not queue:
                continue
            job = queue[0]
            if job['completed']['time'] <= notice['time'] + 1 and job['ordinal'] < notice['ordinal']:
                queue.popleft()
                matched.add(notice['ordinal'])
        return dict(matched=matched, unproven=len(self.notifications) - len(matched), operations=successful, invalid_lifecycle=self.invalid, metrics=self.metrics.copy())

def _all_custom_event_audit(text, *, explicit_snapshot_budget=0, explicit_snapshot_windows=(), cold_response_windows=(), cold_event_budget=None, world_large_budget=None, build_catalog=None):
    """Budget is this reviewed native scenario's allowance, not a server cap.

    The caller binds this allowance to the exact captured native case.
    A marker alone cannot grant unlimited duplicate sends. An unknown >50B
    event sent once is cold traffic; repeated/persistent large traffic is held
    for per-operation evidence and budgets, never exempted by an event name.
    """
    _need(isinstance(text, str) and len(text.encode('utf8')) <= MAX_LOG, 'bounded_native_log_required')
    _need(type(explicit_snapshot_budget) is int and 0 <= explicit_snapshot_budget <= 1, 'one_reviewed_late_listener_snapshot_maximum')
    _need(len(explicit_snapshot_windows) == explicit_snapshot_budget, 'explicit_snapshot_case_window_required')
    _need(len(cold_response_windows) <= 3, 'only_three_validated_transaction_response_windows')
    errors = Counter()
    worlds = {}
    current = 0
    header = None
    marker = None
    accepted_request = None

    def world():
        if current not in worlds:
            worlds[current] = dict(events={}, phase='before_auth', auth_last={}, expires_last={}, auth=Counter(), used_snapshot=0, request_ordinals={}, explicit_requests={}, large_bytes=0, hello={}, authorized=False, protocol_ready=False, build=_BuildOperations(build_catalog) if build_catalog is not None else None, training=_TrainingOperations(build_catalog.training) if getattr(build_catalog, 'training', None) is not None else None)
        return worlds[current]

    def finish():
        nonlocal header, marker, accepted_request
        h = header
        header = None
        if not h or not h.get('custom'):
            return
        if not h.get('event') or h.get('data') is None or h['time'] is None:
            errors['incomplete_native_custom_event'] += 1
            return
        state = worlds[h['world']]
        event, size, stamp = (h['event'], h['size'], h['time'])
        if math.ceil(h['bits'] / 8) != size or size <= 0:
            errors['native_size_header_inconsistent'] += 1
        stats = state['events'].setdefault(event, dict(count=0, total_bytes=0, max_bytes=0, phases=Counter(), one=deque(), ten=deque(), peak_1s=0, peak_10s=0, large_count=0, large_buckets=set(), large_times=[], repeats=Counter(), large_items=[]))
        stats['count'] += 1
        stats['total_bytes'] += size
        stats['max_bytes'] = max(stats['max_bytes'], size)
        stats['phases'][h['phase']] += 1
        for seconds, key, peak in ((1, 'one', 'peak_1s'), (10, 'ten', 'peak_10s')):
            queue = stats[key]
            while queue and queue[0] < stamp - seconds:
                queue.popleft()
            queue.append(stamp)
            stats[peak] = max(stats[peak], len(queue))
        if size > 50:
            stats['large_count'] += 1
            stats['large_buckets'].add(int(stamp // 5))
            stats['large_times'].append(stamp)
            stats['large_items'].append((h['ordinal'], stamp, h['data']))
            state['large_bytes'] += size
            if cold_event_budget is not None and size > cold_event_budget:
                errors['single_cold_event_requires_smaller_total_traffic_plan'] += 1
        try:
            if event == 'cw':
                _need(size <= 50, 'frequent_cw_exceeds_50_bytes')
                kind, values = _cw(_unescape(h['data']))
                schema, session, epoch, view, revision, index, count = values
                if kind == 17 and view == 1 and (not state['protocol_ready']):
                    _need(1 <= index <= count <= 16383, 'native_cw_hello_fragments_invalid')
                    parts = state['hello'].setdefault((schema, session, epoch, revision, count), set())
                    parts.add(index)
                    if len(parts) == count:
                        state['protocol_ready'] = True
                        state['phase'] = 'protocol_ready'
                        state['hello'].clear()
            elif event == AUTH:
                raw = _unescape(h['data'])
                _need(len(raw) <= 16 * 1024, 'native_auth_payload_oversized')
                value = _vbkv(raw)
                _need(set(value) == AUTH_KEYS and value.get('status') in STATUSES, 'native_auth_shape_or_status_invalid')
                recipient = value['player_id']
                _need(isinstance(recipient, (int, float)) and (not isinstance(recipient, bool)) and math.isfinite(recipient) and (0 <= recipient <= 63) and (recipient == int(recipient)), 'native_auth_recipient_invalid')
                recipient = int(recipient)
                semantic = tuple(((key, value[key]) for key in sorted(value) if key != 'expires_in'))
                duplicate = semantic == state['auth_last'].get(recipient)
                request = state['explicit_requests'].pop(recipient, None)
                public = request.get('public_marker') if request else None
                explicit = public and request and (public['world'] == h['world']) and (request['world'] == h['world']) and (public['reason'] == 'explicit_snapshot') and (request['slot'] == value['player_id']) and (public['status'] == value['status']) and (public['time'] is not None) and (request['time'] is not None) and (0 <= stamp - public['time'] <= 1) and (0 <= public['time'] - request['time'] <= 1)
                if duplicate:
                    state['auth']['semantic_duplicates'] += 1
                    if value['expires_in'] != state['expires_last'].get(recipient):
                        state['auth']['clock_only_duplicates'] += 1
                    if explicit and request['ordinal'] == 1:
                        state['auth']['cold_listener_bootstraps'] += 1
                    elif explicit and state['used_snapshot'] < explicit_snapshot_budget and any((start <= request['time'] <= stamp <= end for start, end in explicit_snapshot_windows)):
                        state['used_snapshot'] += 1
                        state['auth']['reviewed_late_listener_snapshots'] += 1
                    else:
                        errors['auth_repeated_semantic_state_without_bounded_request'] += 1
                else:
                    state['auth']['semantic_changes'] += 1
                if accepted_request is request:
                    accepted_request = None
                state['auth_last'][recipient], state['expires_last'][recipient] = (semantic, value['expires_in'])
                if value['status'] == 'approved':
                    state['authorized'] = True
                    if not state['protocol_ready']:
                        state['phase'] = 'authorized_wait_protocol'
                elif not state['protocol_ready']:
                    state['phase'] = 'auth_pending'
            elif size > 50:
                stats['repeats'][h['data']] += 1
        except (ValueError, UnicodeError, struct.error):
            errors['native_body_validation_failed:' + event] += 1
    for ordinal, line in enumerate(text.splitlines()):
        if '[Survival][INFO][Addon] initialized' in line:
            finish()
            current += 1
            marker = None
            accepted_request = None
            world()
        if build_catalog is not None:
            world()['build'].line(line, ordinal)
        if world()['training'] is not None:
            world()['training'].line(line, ordinal)
        found = re.search('\\((\\d+) bits/(\\d+) bytes\\):', line)
        if found:
            finish()
            state = world()
            header = dict(bits=int(found[1]), size=int(found[2]), time=_time(line), world=current, phase=state['phase'], ordinal=ordinal)
        elif 'CUserMsg_CustomGameEvent [148]' in line:
            if header is None:
                errors['custom_event_without_native_size_header'] += 1
            else:
                header['custom'] = True
        elif header and header.get('custom') and ('event_name:' in line):
            found = re.search('event_name: "([A-Za-z0-9_]{1,128})"', line)
            if found:
                header['event'] = found[1]
            else:
                errors['native_event_name_invalid'] += 1
        elif header and header.get('custom') and ('data:' in line):
            found = re.search('\\bdata:\\s*(.*)$', line)
            header['data'] = found[1]
            if build_catalog is not None and header.get('event'):
                world()['build'].event(header)
            if world()['training'] is not None and header.get('event'):
                world()['training'].event(header)
        found = re.search('\\[PLAYER_WEB_AUTH_PUBLIC\\] reason=(state_change|explicit_snapshot) status=(requesting|pending|approved|failed|expired)\\b', line)
        if found:
            finish()
            marker = dict(world=current, time=_time(line), reason=found[1], status=found[2])
            if marker['reason'] == 'explicit_snapshot' and accepted_request and (accepted_request['world'] == current):
                accepted_request['public_marker'] = marker
        found = re.search('\\[PLAYER_WEB_AUTH_REQUEST\\] accepted=1 generation=(\\d+) slot=(\\d+) mode=(state_change|explicit_snapshot)\\b', line)
        if found:
            finish()
            state = world()
            slot = int(found[2])
            state['request_ordinals'][slot] = state['request_ordinals'].get(slot, 0) + 1
            if found[3] == 'explicit_snapshot':
                accepted_request = dict(world=current, time=_time(line), generation=int(found[1]), slot=slot, ordinal=state['request_ordinals'][slot])
                state['explicit_requests'][slot] = accepted_request
            else:
                previous = state['explicit_requests'].pop(slot, None)
                if accepted_request is previous:
                    accepted_request = None
        elif '[PLAYER_WEB_AUTH_REQUEST] accepted=1' in line:
            errors['native_auth_accepted_request_mode_missing_or_invalid'] += 1
    finish()
    safe_worlds = []
    for number, state in sorted(worlds.items()):
        build = state['build'].finish() if state['build'] is not None else dict(matched=set(), unproven=0, operations=0, invalid_wire_transactions=0, metrics={})
        if build['unproven']:
            errors['unproven_build_operation_notification'] += build['unproven']
        training = state['training'].finish() if state['training'] is not None else dict(matched=set(), unproven=0, operations=0, invalid_lifecycle=0, metrics={})
        if training['unproven']:
            errors['unproven_training_operation_notification'] += training['unproven']
        if training['invalid_lifecycle']:
            errors['invalid_training_lifecycle'] += training['invalid_lifecycle']
        events = {}
        for name, stats in sorted(state['events'].items()):
            if name not in (AUTH, 'cw') and stats['large_count']:
                remaining = [(stamp, body) for ordinal, stamp, body in stats['large_items'] if ordinal not in build['matched'] and ordinal not in training['matched']]
                stats['validated_build_operation_notifications'] = sum((ordinal in build['matched'] for ordinal, _, _ in stats['large_items']))
                stats['validated_training_operation_notifications'] = sum((ordinal in training['matched'] for ordinal, _, _ in stats['large_items']))
                used = set()
                unresolved = []
                for stamp, body in remaining:
                    windows = [i for i, (start, end) in enumerate(cold_response_windows) if start <= stamp <= end]
                    index = next((i for i in windows if i not in used), None)
                    if index is not None:
                        used.add(index)
                    elif windows:
                        errors['duplicate_validated_transaction_response:' + name] += 1
                        unresolved.append((stamp, body))
                    else:
                        unresolved.append((stamp, body))
                stats['validated_transaction_responses'] = len(used)
                stats['unresolved_large_count'] = len(unresolved)
                lifetime = Counter((body for stamp, body in unresolved))
                stats['unresolved_identical_lifetime_peak'] = max(lifetime.values(), default=0)
                recent = {}
                repeat_peak = 0
                for stamp, body in unresolved:
                    queue = recent.setdefault(body, deque())
                    while queue and queue[0] < stamp - 15:
                        queue.popleft()
                    queue.append(stamp)
                    repeat_peak = max(repeat_peak, len(queue))
                stats['unresolved_identical_15s_peak'] = repeat_peak
                repeated = repeat_peak >= 3
                buckets = {int(stamp // 5) for stamp, body in unresolved}
                persistent = any((bucket + 1 in buckets and bucket + 2 in buckets for bucket in buckets))
                if repeated or persistent:
                    errors['unexplained_repeated_large_event:' + name] += 1
            events[name] = {k: v for k, v in stats.items() if k not in ('one', 'ten', 'large_buckets', 'large_times', 'repeats', 'large_items')}
        if world_large_budget is not None and state['large_bytes'] > world_large_budget:
            errors['world_cold_total_traffic_budget_exceeded'] += 1
        safe_worlds.append(dict(world=number, events=events, auth=dict(state['auth']), authorization_observed=state['authorized'], protocol_ready_observed=state['protocol_ready'], profile_ready_proven=False, large_total_bytes=state['large_bytes'], build_operations=dict(accepted_operations=build['operations'], matched_notifications=len(build['matched']), invalid_wire_transactions=build['invalid_wire_transactions'], work=build['metrics']), training_operations=dict(successful_jobs=training['operations'], matched_notifications=len(training['matched']), invalid_lifecycle=training['invalid_lifecycle'], work=training['metrics'])))
    if not any((w['events'].get('cw', {}).get('count') for w in safe_worlds)):
        errors['native_cw_missing'] += 1
    return dict(kind='ALL_CUSTOM_EVENT_SAFE_NATIVE_NETWORK_AUDIT', accepted=not errors, layer='CUserMsg_CustomGameEvent; excludes UDP/IP/Steam headers', worlds=safe_worlds, blockers=dict(sorted(errors.items())), frequent_limit_bytes=50, explicit_snapshot_review_budget=explicit_snapshot_budget, event_body_or_identity_disclosed=False, payload_hashes_disclosed=False, native_fps_measured=False)

def network_summary(text, *, explicit_snapshot_windows=(), cold_response_windows=(), build_catalog=None):
    result = _all_custom_event_audit(text, explicit_snapshot_budget=len(explicit_snapshot_windows), explicit_snapshot_windows=explicit_snapshot_windows, cold_response_windows=cold_response_windows, build_catalog=build_catalog)
    need(result['accepted'], 'complete_native_all_custom_event_network_gate:' + ','.join(result['blockers']))
    cw = [w['events'].get('cw', {}) for w in result['worlds']]
    result.update(frames=sum((v.get('count', 0) for v in cw)), max_native_bytes=max((v.get('max_bytes', 0) for v in cw), default=0), total_native_bytes=sum((v.get('total_bytes', 0) for v in cw)), cold_bulk_uses_separate_total_traffic_policy=True, raw_payloads_disclosed=False)
    return result

def network_case_windows(review, process, bounds, reader, origin):
    cases = review.get('network_cases', {})
    need(isinstance(cases, dict) and set(cases) <= {'late_auth_listener_snapshot'}, 'complete_native_known_bounded_network_cases_required')
    if not cases:
        return ()
    case = cases['late_auth_listener_snapshot']
    need(case.get('mode') == 'EXPLICIT_LATE_AUTH_LISTENER_SNAPSHOT' and case.get('actual_ui_request') is True, 'complete_native_real_late_listener_ui_action_required')
    shots = captures(case, ('before', 'after'), process, bounds, reader, origin)
    visual = case.get('visual_review', {})
    need(all((visual.get(key) is True for key in ('normal_auth_ui_open', 'actual_ui_request', 'returned_state_visible', 'no_synthetic_request'))), 'complete_native_late_listener_actual_pixels_required')
    need(shots[-1]['end'] - shots[0]['start'] <= timedelta(seconds=15) and len({(s['hwnd'], s['width'], s['height']) for s in shots}) == 1, 'complete_native_bounded_same_window_late_listener_case_required')
    return ((_engine_clock(shots[0]['start']), _engine_clock(shots[-1]['end'])),)

def _validate_native_release(request, report, manifest, signed, *, official=None):
    b, ops, p = environment()
    expected = request.get('report_sha256')
    actual, actual_manifest, actual_signed = b.load_package(expected, full=True)
    need((actual, actual_manifest, actual_signed) == (report, manifest, signed), 'complete_native_authenticated_package_objects_differ')
    ops.source_binding(report, expected)
    ref = dict(path=request.get('production_evidence_path'), sha256=request.get('production_evidence_sha256'))
    reader = helpers().Evidence(b, SimpleNamespace(p=SimpleNamespace(STORE=ops.STORE)))
    review, origin = reader.document(ref, ROOT / 'output/complete_native_review_origin.json')
    need(review.get('schema') == 1 and review.get('kind') == KIND and (review.get('scope') == SCOPE) and (review.get('release_sequence') == report['release_sequence']) and exact_bindings(review, report, expected) and (review.get('runtime_paths') == report['changed_runtime_paths']) and (review.get('removed_runtime_paths') == report['removed_runtime_paths']) and (review.get('native_file_use_policy') == POLICY), 'complete_native_exact_complete_scope_review_required')
    need(review.get('synthetic') is False and review.get('tools') is False and (review.get('offline_logic_test') is False) and (review.get('cheats') is False) and (review.get('http_enabled') is True) and all((review.get('root_review', {}).get(key) is True for key in ('normal_oauth_approved', 'no_synthetic_profile', 'no_runtime_script_injection', 'no_mock_movie_error_class', 'no_crash_or_hang', 'normal_exit_without_force', 'keeper_held_continuously_reviewed'))), 'complete_native_real_authenticated_ordinary_scope_required')
    need(same_process(request['native_process_generation'], review['process']), 'complete_native_request_generation_differs')
    process, bounds, text = lifecycle(review, origin, report, expected, reader, b, ops, p, official=official, target_manifest=manifest)
    ui = ui_cases(review, process, bounds, reader, origin)
    lottery_policy = buffered_lottery_cases if report['release_sequence'] >= BUFFERED_POLICY_RELEASE else lottery_cases
    lottery = lottery_policy(review, process, bounds, text, reader, origin, manifest=manifest, original_evidence=report['original_evidence'])
    network = network_summary(text, explicit_snapshot_windows=network_case_windows(review, process, bounds, reader, origin), cold_response_windows=lottery.pop('_network_response_windows'), build_catalog=_load_build_catalog(b, report))
    reader.unchanged()
    b.verify_operator_paths(dict(_EXECUTED_HELPERS), report['operator_revision'])
    return dict(ordinary_production_acceptance=True, scope=SCOPE, release_sequence=report['release_sequence'], content_sha256=report['content_sha256'], source_revisions=report['source_revisions'], production_evidence_sha256=ref['sha256'], native_process_generation=request['native_process_generation'], ui_cases=ui, lottery=lottery, network=network, original0804_fully_restored=True, native_file_use_policy=POLICY, all_gameplay_paths_verified=False, native_fps_measured=False, official_download=False, post_upload_arcade_verified=False, sdk_initialized=False, updates_submitted=0)

def validate_native_release(request, report, manifest, signed):
    """Pre-publication always requires the actual original1009 installation."""
    return _validate_native_release(request, report, manifest, signed)

def validate_post_download_native_release(request, report, manifest, signed, *, receipt_ref):
    """Closed post-download phase; no caller Boolean can skip original evidence."""
    official = _verify_official_installation(request, report, manifest, receipt_ref)
    result = _validate_native_release(request, report, manifest, signed, official=official)
    official.protocol.unchanged(official.snapshots)
    result.update(official_full_installation_reverified=True, official_receipt_sha256=official.receipt_sha, current_installation_phase='OFFICIAL_TARGET_FULLY_REVERIFIED', native_restore_is_historical=True)
    return result

def review_template(report, report_sha256):
    """Pure private worksheet, deliberately unable to satisfy this gate.

    The operator fills references only after real captures and checks; no TRUE
    review, PID, decoder outcome, request ID or ticket balance is manufactured.
    """

    def file_ref():
        return dict(path='', sha256='')

    def case(roles, flags):
        return dict(captures={role: dict(png=file_ref(), metadata=file_ref()) for role in roles}, visual_review={**dict.fromkeys(flags, False), 'reviewed_png_sha256': []})
    value = dict(schema=1, kind=KIND, scope=SCOPE, status='TEMPLATE_NOT_NATIVE_EVIDENCE', release_sequence=report['release_sequence'], package_report_sha256=report_sha256, source_revisions=report['source_revisions'], collection_source_revisions=report['collection_source_revisions'], operator_revision=report['operator_revision'], content_sha256=report['content_sha256'], signed_manifest_sha256=report['signed_manifest_sha256'], runtime_paths=report['changed_runtime_paths'], removed_runtime_paths=report['removed_runtime_paths'], native_file_use_policy=POLICY, synthetic=None, tools=None, offline_logic_test=None, cheats=None, http_enabled=None, process=dict(pid=None, created_utc=None, native_created_filetime=None), reviewed_utc=None, root_review=dict.fromkeys(('normal_oauth_approved', 'no_synthetic_profile', 'no_runtime_script_injection', 'no_mock_movie_error_class', 'no_crash_or_hang', 'normal_exit_without_force', 'keeper_held_continuously_reviewed'), False))
    value['rehearsal'] = {name: file_ref() for name in ('transaction', 'process', 'close_intent', 'close_requested', 'hold_end', 'restored', 'engine_log_final')}
    value['rehearsal']['inspections'] = [file_ref(), file_ref()]
    value['ui_cases'] = {name: case(('visible',), ('actual_data_visible', 'normal_ui_open', 'not_loading_or_placeholder', 'no_stall')) for name in ('n1_gameplay', 'archive', 'hud_selection', 'grid', 'production', 'vip', 'payment', 'public_beta')}
    value['decoder_probe'] = None
    value['network_cases'] = {}
    value['lottery_previews'] = {}
    for pool in POOLS:
        item = case(('window_before', 'animation_a', 'animation_b', 'window_after'), ('theme_matches_pool', 'animation_progressed', 'returned_to_lottery_window', 'no_movie_error_visible_after_fallback', 'no_draw_inputs', 'actual_movie_content'))
        item.update(pool=pool, mode='NO_CONSUMPTION_PREVIEW', presentation=None, fallback_reason=None, tickets_before=None, tickets_after=None)
        value['lottery_previews'][pool] = item
    value['consecutive_draws'] = []
    for unused in range(3):
        item = case(('window_before', 'animation_a', 'animation_b', 'results', 'window_after'), ('actual_movie_content', 'fallback_animation_content', 'animation_progressed', 'ten_actual_rewards_visible', 'confirm_button_full_width', 'owned_text_visible_when_applicable', 'returned_to_lottery_window'))
        item.update(pool='map', count=10, ticket_kind='ordinary', real_player_transaction=None, skip_animation=None, request_id=None, tickets_before=None, tickets_after=None, presentation=None, fallback_reason=None)
        value['consecutive_draws'].append(item)
    return buffered_review_template(value) if report['release_sequence'] >= BUFFERED_POLICY_RELEASE else value

def main(argv=None):
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    print(json.dumps(dict(status='STATIC_COMPLETE_NATIVE_ADMISSION_PLAN_NO_EFFECTS', scope=SCOPE, ordinary_client=True, native_actions=0, sdk_initialized=False, ready_for_upload=False)))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
