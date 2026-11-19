"""Verify explicit launcher evidence stages without inventing a user approval.

AUTHORIZATION_READY proves the cold EXE, exact package and actual auth roundtrip.
It deliberately does not claim a completed Steam approval or in-game archive.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path


def need(value, reason):
    if not value:
        raise ValueError(reason)


def referenced(value, *, binary=False):
    path = Path(value['path'])
    roots = (Path('D:/Survival_本地工具'),
             Path(os.environ['LOCALAPPDATA']) / 'Goufayu/Launcher/sessions')
    need(path.is_absolute() and not path.is_symlink() and path.is_file()
         and any(path.resolve().is_relative_to(root.resolve()) for root in roots),
         'owned_launcher_evidence_path_required')
    need(path.stat().st_size <= 12 * 1024 * 1024, 'launcher_evidence_budget_exceeded')
    raw = path.read_bytes()
    need(hashlib.sha256(raw).hexdigest() == value['sha256'], 'launcher_evidence_changed')
    return raw if binary else json.loads(raw)


def verify(build, evidence):
    binding = build['binding']
    need(evidence.get('exe_sha256') == build['exe_sha256']
         and evidence.get('release_sequence') == binding['release_sequence']
         and evidence.get('steam_manifest') == binding['steam_manifest']
         and evidence.get('helper_ready_observed') is True, 'exact_actual_launcher_binding_required')
    if evidence.get('user_confirmed_entered_game') is True:
        need(evidence.get('current_client_ingame_visually_observed') is True,
             'actual_ingame_observation_required')
        return 'FULL_GAMEPLAY'
    need(evidence.get('validation_stage') == 'AUTHORIZATION_READY'
         and evidence.get('user_confirmed_entered_game') is False
         and evidence.get('post_authorization_gameplay_verified') is False
         and evidence.get('authorization_code_visually_observed') is True,
         'honest_authorization_ready_stage_required')
    launch = referenced(evidence['launch_receipt'])
    trace = referenced(evidence['network_receipt'])
    referenced(evidence['authorization_frame'], binary=True)
    need(launch['version'] == binding['version']
         and launch['release_sequence'] == binding['release_sequence']
         and launch['steam_manifest'] == binding['steam_manifest']
         and launch['helper_source_sha256'] == binding['helper_sha256']
         and launch['manager_pid'] == evidence['actual_gui_pid']
         and launch['game_pid'] == evidence['game_pid']
         and str(launch['game_filetime']) == str(evidence['game_filetime'])
         and launch['helper_ready_observed'] is True
         and launch['workshop_verification'] == {
             'files': len(binding['package_files']),
             'bytes': sum(row['bytes'] for row in binding['package_files']),
             'full_sha256_verified': True}, 'real_cold_launcher_receipt_required')
    need(trace['kind'] == 'ACTUAL_AUTHORIZATION_TRANSPORT_ACKS'
         and trace['game_pid'] == evidence['game_pid']
         and trace['release_sequence'] == binding['release_sequence']
         and trace['private_payloads_excluded'] is True, 'matching_anonymous_auth_trace_required')
    for path in ('/v1/player-auth/start', '/v1/player-auth/poll'):
        row = trace['routes'][path]
        need(row['http_200_acknowledged'] >= 1, 'real_auth_start_and_poll_ack_required')
    return 'AUTHORIZATION_READY'
