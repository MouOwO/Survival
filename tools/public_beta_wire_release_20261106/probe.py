"""Actual candidate Python/Lua, with isolated memory receipts only.

Executed by the controlled remote recipe after complete candidate verification.
No database client is constructed, and no real player/HTTP request is issued.
"""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch


def need(ok, code):
    if not ok:
        raise RuntimeError(code)


def run(old, new, parent_hash, new_hash, decoder_source, vector_runner, lua='/usr/bin/lua'):
    old, new = Path(old), Path(new)
    sys.path.insert(0, str(new / 'backend'))
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveError, ArchiveService
    from archive_backend.settlement_runner import clear_cache
    from archive_backend.http_profile_wire import pack, MARKER
    from archive_backend import match_modes
    import archive_backend.command_timing as timing
    bundle = Bundle(new / 'addon/server/bundles' / new_hash)
    parent_bundle = Bundle(old / 'addon/server/bundles' / parent_hash)
    need(bundle.tables['archive_benefit_rewards']['public_beta_login']['base_counts'] == ['2'],
         'candidate_public_beta_rule_missing')
    spec = importlib.util.spec_from_file_location('archive_backend.actual_parent_probe', old / 'backend/archive_backend/service.py')
    previous = importlib.util.module_from_spec(spec)
    parent_service_path = old / 'backend/archive_backend/service.py'
    exec(compile(parent_service_path.read_bytes(), str(parent_service_path), 'exec'), previous.__dict__)
    modes_spec = importlib.util.spec_from_file_location('archive_backend.actual_parent_modes_probe', old / 'backend/archive_backend/match_modes.py')
    previous_modes = importlib.util.module_from_spec(modes_spec)
    parent_modes_path = old / 'backend/archive_backend/match_modes.py'
    exec(compile(parent_modes_path.read_bytes(), str(parent_modes_path), 'exec'), previous_modes.__dict__)
    frozen = 1793944800
    defaults = {row['field_id']: row['default_value'] for row in bundle.configs['player_gameplay_stats']['rows']}
    synthetic = dict(schema_version=1, account_id='100', revision=1,
                     entitlements={}, achievements={}, public={},
                     save=dict(archive={}, gameplay_stats=defaults,
                               content_inventory={'lottery_ticket': 1000, 'special_lottery_ticket': 1000}))

    class MemoryReceipt:
        def __init__(self, selected_bundle):
            self.bundle = selected_bundle
            self.profile = copy.deepcopy(synthetic)
            self.ops = {}
            self.calls = []
            self.timestamp = frozen

        def resume(self, identifier):
            op = self.ops[identifier]
            if op.get('done'):
                return copy.deepcopy(op['reply'])
            return dict(ok=True, done=False, profile=copy.deepcopy(self.profile),
                        command=copy.deepcopy(op['command']), has_pass=False,
                        config_hash=op['hash'], event_at=op['timestamp'])

        def rpc(self, name, values):
            self.calls.append(name)
            if name == 'match_profile_context':
                good = values.get('p_account') == '100' and values.get('p_session') == 'synthetic-beta-session-0001'
                return dict(ok=good, account_id='100', match_session_id=values.get('p_session'), mode='standard')
            if name == 'archive_prepare':
                identity = values['p_id']
                existing = self.ops.get(identity)
                if existing:
                    need(existing['fingerprint'] == values['p_fingerprint'], 'probe_receipt_fingerprint_changed')
                else:
                    self.ops[identity] = dict(command=copy.deepcopy(values['p_command']),
                                             hash=values['p_hash'], fingerprint=values['p_fingerprint'],
                                             timestamp=self.timestamp)
                return self.resume(identity)
            if name == 'archive_resume':
                return self.resume(values['p_id'])
            need(name == 'archive_commit_lottery', 'probe_unexpected_rpc:' + name)
            need(values['p_revision'] == self.profile['revision'], 'probe_revision_conflict')
            op = self.ops[values['p_id']]
            need(not op.get('done'), 'probe_duplicate_commit')
            ok = not values['p_error']
            if ok:
                self.profile['save']['archive'] = copy.deepcopy(values['p_archive'])
                self.profile['save']['content_inventory'] = copy.deepcopy(values['p_inventory'])
                for key, value in values['p_deltas'].items():
                    self.profile['save']['gameplay_stats'][key] += value
                self.profile['revision'] += 1
            op['done'] = True
            op['reply'] = dict(ok=ok, done=True, terminal=True, profile=copy.deepcopy(self.profile),
                               response=copy.deepcopy(values['p_response']))
            if not ok:
                op['reply']['error'] = values['p_error']
            return copy.deepcopy(op['reply'])

    def instance(implementation, selected_bundle):
        db = MemoryReceipt(selected_bundle)
        app = SimpleNamespace(account_id_pepper='synthetic-public-beta-wire-probe', rpc_client=db,
                              _database_account_id=lambda account: account,
                              _ensure_gameplay_stats=lambda account: None,
                              _public_response=lambda response, database_account, public_account: copy.deepcopy(response))
        return implementation(app, selected_bundle, lua), db

    def beta_request(identifier, digest=new_hash):
        return dict(account_id='100', match_session_id='synthetic-beta-session-0001', config_hash=digest,
                    command=dict(id=identifier, kind='benefit_claim', tier_id='public_beta_login', track='public_beta_login'))

    summaries, vectors = {}, []
    try:
        with patch('archive_backend.service.time.time', return_value=frozen), patch.object(timing, '_emit', lambda row: None):
            server, db = instance(ArchiveService, bundle)
            request = beta_request('synthetic-beta:first')
            before = db.profile['save']['content_inventory']['special_lottery_ticket']
            reply = server.command(request)
            need(reply.get('ok') is True and db.profile['save']['content_inventory']['special_lottery_ticket'] == before + 2,
                 'probe_public_beta_exact_reward_failed')
            committed = copy.deepcopy(db.profile)
            need(server.command(request).get('ok') is True and db.profile == committed, 'probe_beta_lost_ack_replay_changed')
            need(server.command(beta_request('synthetic-beta:second')).get('ok') is False and db.profile == committed,
                 'probe_beta_same_day_duplicate_granted')
            bad = beta_request('synthetic-beta:bad-session')
            bad['match_session_id'] = 'synthetic-wrong-session'
            try:
                server.command(bad)
                raise AssertionError('probe_bad_session_accepted')
            except ArchiveError:
                pass
            need(db.profile == committed, 'probe_bad_session_mutated_profile')
            summaries['beta'] = dict(exact_two=True, replay_unchanged=True, second_claim_rejected=True,
                                     wrong_session_rejected=True, real_rpc_calls=0)
            # Exercise successful old ordinary-tier replay using its old reducer.
            server, db = instance(ArchiveService, bundle)
            day = str((frozen + 10800) // 86400)
            db.profile['save']['archive']['benefits'] = {'days': {day: {'seconds': 3600, 'claimed': {}}}}
            ordinary = dict(account_id='100', config_hash=parent_hash,
                            command=dict(id='synthetic-ordinary:claim', kind='benefit_claim', track='daily_time', tier_id='daily_time_30'))
            first = server.command(ordinary)
            need(first.get('ok') is True, 'probe_legacy_benefit_failed')
            saved = copy.deepcopy(db.profile)
            need(server.command(ordinary).get('ok') is True and saved == db.profile, 'probe_legacy_benefit_replay_changed')
            summaries['ordinary'] = dict(old_hash_success=True, replay_unchanged=True, real_rpc_calls=0)
            # Same RNG/input, parent and new narrow bundle: beta addition must
            # not alter any lottery rules or authoritative settlement outcome.
            draws = []
            for ordinal in range(3):
                observations = []
                for implementation, selected, compact in ((previous.ArchiveService, parent_bundle, False),
                                                           (ArchiveService, bundle, False), (ArchiveService, bundle, True)):
                    server, db = instance(implementation, selected)
                    request = dict(account_id='100', config_hash=selected.hash,
                                   command=dict(kind='lottery_draw', id='synthetic-draw:%d' % ordinal,
                                                request_id='synthetic-draw-%d' % ordinal, pool_id='map', count=10))
                    if compact:
                        request['response_capabilities'] = {'lottery_committed_profile_v1': True}
                    start = time.perf_counter()
                    reply = server.command(request)
                    need(reply.get('ok') is True, 'probe_synthetic_draw_failed')
                    core = {key: value for key, value in reply.items()
                            if key not in ('lottery_snapshots', 'snapshot_config_hash', 'snapshot_projection_ms')}
                    observations.append((core, db.profile, dict(ms=(time.perf_counter() - start) * 1000,
                        bytes=len(json.dumps(reply, separators=(',', ':')).encode()), real_rpc_calls=0)))
                need(observations[0][:2] == observations[1][:2] == observations[2][:2], 'probe_lottery_rules_rng_or_state_changed')
                draws.append(dict(ordinal=ordinal, parent=observations[0][2], legacy=observations[1][2], compact=observations[2][2], equal=True))
            summaries['lottery'] = draws

        def api():
            def original(application, payload, response, context, *, login=False):
                return copy.deepcopy(response)
            return SimpleNamespace(_validate_context=lambda *args: None, login=lambda *args: None, project=original)

        legacy_api, compact_api = api(), api()
        previous_modes.install(legacy_api)
        match_modes.install(compact_api)
        wire_sizes = []
        for mode in ('standard', 'pure', 'rich', 'cold'):
            account = copy.deepcopy(synthetic)
            account['save']['archive']['synthetic_padding'] = [{'id': str(i), 'count': i} for i in range(80)]
            profile = copy.deepcopy(account)
            profile['account_profile'] = copy.deepcopy(account)
            if mode == 'pure':
                profile['save'] = {'content_inventory': {}, 'gameplay_stats': {'attack': 0}}
            daily = {'by_key': {'synthetic_%d' % i: {'current': i, 'limit': 100} for i in range(24)}}
            profile.update(daily_limits=copy.deepcopy(daily), progression={'loaded': True, 'daily_limits': copy.deepcopy(daily)})
            response = {'ok': True, 'profile': profile, 'daily_limits': daily}
            context = {'mode': mode}
            app = SimpleNamespace()
            legacy = legacy_api.project(app, {}, response, context)
            need(compact_api.project(app, {}, response, context) == legacy, 'probe_legacy_projection_changed')
            packed = compact_api.project(app, {'response_capabilities': {'archive_profile_refs_v1': True}}, response, context)
            need(MARKER in packed, 'probe_match_modes_wire_hook_missing')
            old_size = len(json.dumps(legacy, separators=(',', ':')).encode())
            new_size = len(json.dumps(packed, separators=(',', ':')).encode())
            need(new_size < old_size, 'probe_wire_no_reduction')
            vectors.append({'wire': packed, 'expected': legacy})
            wire_sizes.append(dict(mode=mode, before=old_size, after=new_size))
        need(']=====]' not in decoder_source, 'probe_decoder_delimiter_changed')
        runner = vector_runner.replace("package.path='scripts/vscripts/?.lua;'..package.path",
                                       'package.path=' + json.dumps((bundle.directory / '?.lua').as_posix() + ';') + '..package.path', 1)
        runner = "package.preload['systems/http_profile_wire']=function()return assert(loadstring([=====[" + decoder_source + "]=====]))()end\n" + runner
        completed = subprocess.run([lua, '-e', runner], input=json.dumps(vectors, ensure_ascii=False).encode('utf8'),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=True)
        need('HTTP_PROFILE_WIRE_VECTORS_PASS 4' in completed.stdout.decode(), 'probe_actual_lua_wire_roundtrip_failed')
        summaries['wire'] = dict(real_lua_vectors=4, sizes=wire_sizes, modes=['standard', 'pure', 'rich', 'cold'], legacy_unchanged=True)
    finally:
        clear_cache()
    return dict(ok=True, status='ACTUAL_WS4_PREPARED_PUBLIC_BETA_WIRE_PARITY_PASS', checks=summaries,
                rpc_calls=0, database_writes=0, real_player_data_used=False, source_files_unchanged=True,
                boundary='Real candidate Python/Linux Lua with memory receipts; not PostgreSQL/HTTP/auth/transit latency')
