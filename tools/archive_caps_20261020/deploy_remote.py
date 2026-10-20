"""Reviewed archive-mode/quota deployment. Importing this module does nothing.

This operator runs on the TEST host only after an explicitly pinned stage has
been uploaded. Default mode is a read-only check. It never grants player rewards,
restarts payments, changes an old ledger hash, or restores/drops player data.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

sys.dont_write_bytecode = True

RELEASES = Path('/opt/goufayu/releases')
PAYMENTS = Path('/opt/goufayu/payments')
BACKUPS = Path('/var/backups/goufayu')
SERVICE = 'goufayu-api.service'
PAYMENT_SERVICE = 'goufayu-payment.service'
MIGRATIONS = (
    '202610170001_rich_match_mode.sql',
    '202610200002_archive_match_modes.sql',
    '202610200003_archive_daily_limits.sql',
)
HASH = re.compile(r'[0-9a-f]{64}\Z')
RELEASE_ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.-]{5,95}\Z')
BASE_TABLES = {
    'survival_players', 'player_gameplay_stats', 'reward_grants', 'player_effect_totals',
    'out_of_match_reward_idempotency', 'online_time_sessions', 'online_time_idempotency',
    'star_blessing_reward_definition_sets', 'star_blessing_reward_definitions',
    'archive_config_sets', 'player_archive_state', 'archive_entitlements', 'archive_operations',
    'archive_online_outbox', 'survival_data_migrations', 'match_profile_sessions', '_goufayu_migrations',
}
BASE_FUNCTIONS = {
    'reject_fishing_immutable_mutation', 'fishing_profile_json', 'get_fishing_profile',
    'ensure_player_gameplay_stats', 'sync_star_blessing_reward_definitions',
    'grant_out_of_match_reward', 'checkpoint_online_time', 'archive_sync_config',
    'archive_resume', 'archive_prepare', 'archive_commit', 'archive_capture_online',
    'archive_online_pending', 'archive_pending', 'archive_commit_lottery',
    'match_profile_login', 'match_profile_context',
}
# These seven objects were read-only audited on the current release. They are
# already deployed outside the historical ledger and must remain untouched.
EXTRA_TABLES = {'archive_daily_unique_backups', 'archive_leaderboard_identities'}
EXTRA_FUNCTIONS = {
    'archive_bind_leaderboard_identity', 'archive_endless_leaderboard',
    'archive_leaderboard_integer', 'archive_seed_leaderboard_identity',
    'archive_unique_points_20261019_valid',
}
NEW_FUNCTIONS = {
    'archive_fishing_daily_limit', 'archive_finalize_fishing_checkpoint',
    'grant_out_of_match_reward_before_daily_limits',
    'checkpoint_online_time_before_daily_limits', 'fishing_profile_json_before_daily_limits',
}
CHANGED_FUNCTIONS = {
    'fishing_profile_json', 'grant_out_of_match_reward', 'checkpoint_online_time',
    'archive_online_pending', 'match_profile_login', 'archive_sync_config',
}
BACKEND_OVERLAYS = {
    'backend/archive_backend/service.py', 'backend/archive_backend/bundle.py',
    'backend/archive_backend/match_modes.py', 'backend/archive_backend/daily_limits.py',
    'backend/archive_backend/clear_receipts.py',
    'backend/archive_backend/config_compatibility.py', 'backend/archive_backend/unique_points.py',
    'backend/fishing_api/server.py', 'backend/fishing_api/match_profiles.py',
    'backend/fishing_api/postgres.py',
}


class Refused(RuntimeError):
    """The message is a fixed, non-sensitive operator error code."""


def need(condition, code):
    if not condition:
        raise Refused(code)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def file_hash(path):
    return digest(Path(path).read_bytes())


def relative(name):
    need(isinstance(name, str) and name != '' and '\\' not in name and ':' not in name, 'unsafe_relative_path')
    value = PurePosixPath(name)
    need(not value.is_absolute() and '..' not in value.parts and value.as_posix() == name, 'unsafe_relative_path')
    return value


def safe(root, name):
    value = relative(name)
    current = root
    for component in value.parts:
        current = current/component
        need(not current.is_symlink(), 'release_file_symlink_refused')
    return current


def sql_body(source):
    text = source.lstrip('\ufeff')
    start = re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;', text, re.I)
    end = re.search(r'\bcommit\s*;\s*\Z', text, re.I)
    need(start and end and start.end() < end.start(), 'migration_transaction_wrapper_invalid')
    return text[start.end():end.start()]


def lottery_projection(bundle):
    sources = bundle['sources']
    names = ('systems/lottery_http_settlement.lua', 'config/lottery_config.lua',
             'config/content_id_aliases.lua', 'core/json_decoder.lua', 'core/json_encoder.lua',
             'systems/archive_starjoy_rewards.lua', 'worker.lua')
    selected = {name: sources[name] for name in names}
    shared = sources['systems/archive_settlement.lua']
    start, end = shared.index('local function apply_effects('), shared.index('function M.settle(')
    selected['shared_apply_effects'] = shared[start:end]
    return {'configs': {name: config for name, config in bundle['configs'].items() if name.startswith('lottery_')},
            'sources': selected}


def exact_sync_branch(definition, bundle_hash, configuration_jsonb_sha256):
    need(HASH.fullmatch(bundle_hash) and HASH.fullmatch(configuration_jsonb_sha256), 'sync_exact_digest_invalid')
    marker = ' -- Reviewed daily unique points: exact configuration with backed-up inventory repair.'
    need(definition.startswith('CREATE OR REPLACE FUNCTION public.archive_sync_config(')
         and definition.count(marker) == 1 and "if p_hash='"+bundle_hash+"'" not in definition,
         'sync_definition_anchor_changed')
    addition = (" -- Reviewed archive modes and final daily quotas: one exact immutable configuration.\n"
        " if p_hash='"+bundle_hash+"' then\n"
        "  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'"+configuration_jsonb_sha256+"' then\n"
        "   raise exception 'archive_modes_daily_caps_configuration_mismatch';\n"
        "  end if;\n"
        "  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;\n"
        "  select config into v from archive_config_sets where config_hash=p_hash;\n"
        "  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;\n"
        "  return jsonb_build_object('ok',true);\n"
        " end if;\n")
    result = definition.replace(marker, addition+marker, 1)
    need(result.replace(addition, '', 1) == definition, 'sync_previous_policy_changed')
    return result


class Operator:
    def __init__(self, stage, plan_sha256):
        self.stage = Path(stage).resolve(strict=True)
        if os.name == 'posix':
            need(self.stage.stat().st_uid == 0 and self.stage.stat().st_mode & 0o022 == 0, 'stage_permissions_invalid')
        need(HASH.fullmatch(plan_sha256), 'plan_digest_invalid')
        need(file_hash(self.stage/'plan.json') == plan_sha256, 'plan_digest_changed')
        self.plan_hash = plan_sha256
        self.plan = json.loads((self.stage/'plan.json').read_bytes())
        self.expected, self.candidate = self.plan['expected'], self.plan['candidate']
        old_name = Path(self.expected['release']).name
        new_name = self.candidate['release_id']
        need(RELEASE_ID.fullmatch(old_name) and RELEASE_ID.fullmatch(new_name)
             and new_name != old_name and new_name != 'current', 'release_identity_invalid')
        self.old, self.new = RELEASES/old_name, RELEASES/new_name
        self.parent, self.bundle = self.expected['bundle_hash'], self.candidate['bundle_hash']
        need(HASH.fullmatch(self.parent) and HASH.fullmatch(self.bundle) and self.parent != self.bundle, 'bundle_identity_invalid')
        self.overlay = self.candidate['overlay']
        need(isinstance(self.overlay, dict) and bool(self.overlay), 'overlay_manifest_invalid')
        for name, sha256 in self.overlay.items():
            relative(name)
            need(isinstance(sha256, str) and HASH.fullmatch(sha256), 'overlay_digest_invalid')
        self.migrations = self.candidate['migrations']
        need([Path(entry['path']).name for entry in self.migrations] == list(MIGRATIONS), 'migration_sequence_invalid')
        for entry, name in zip(self.migrations, MIGRATIONS):
            need(entry['id'] == 'target/'+name and entry['path'] == 'database/migrations/target/'+name,
                 'migration_scope_invalid')
            need(self.overlay.get(entry['path']) == entry['sha256'], 'migration_overlay_digest_mismatch')
        self.old_ledger = {entry['id']: entry['sha256'] for entry in self.expected['ledger']}
        need(len(self.old_ledger) == 26 and all(HASH.fullmatch(value) for value in self.old_ledger.values()), 'baseline_ledger_invalid')

    def save(self, name, value):
        target = self.stage/(name+'.json')
        temporary = self.stage/(name+'.'+secrets.token_hex(8)+'.tmp')
        with temporary.open('xb') as stream:
            temporary.chmod(0o600)
            stream.write(canonical(value)); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, target)
        return value

    def service_state(self, service):
        need(service in (SERVICE, PAYMENT_SERVICE), 'service_scope_invalid')
        result = subprocess.run(['systemctl', 'show', service, '--property=ActiveState,MainPID'],
                                capture_output=True, timeout=10, check=False)
        need(result.returncode == 0, 'service_state_unavailable')
        values = dict(line.split('=', 1) for line in result.stdout.decode().splitlines() if '=' in line)
        need(values.get('MainPID', '').isdigit(), 'service_pid_invalid')
        return {'active': values.get('ActiveState'), 'pid': int(values['MainPID'])}

    def systemctl(self, action):
        need(action in ('stop', 'start'), 'service_action_invalid')
        result = subprocess.run(['systemctl', action, SERVICE], capture_output=True, timeout=45, check=False)
        need(result.returncode == 0, 'archive_service_action_failed')

    def pointer(self, new=False):
        need((RELEASES/'current').resolve(strict=True) == (self.new if new else self.old), 'archive_pointer_changed')

    def payment_pin(self):
        payment = (PAYMENTS/'current').resolve(strict=True)
        need(payment.parent == PAYMENTS and payment.is_dir(), 'payment_pointer_invalid')
        return {'release': str(payment), 'manifest_sha256': file_hash(payment/'manifest.json'),
                'service': self.service_state(PAYMENT_SERVICE)}

    def payment_module(self):
        payment = Path(self.payment_pin()['release'])
        sys.path.insert(0, str(payment))
        spec = importlib.util.spec_from_file_location('archive_caps_payment_connection', payment/'deploy.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        return module

    def manifest(self, root):
        result = json.loads((root/'release_manifest.json').read_bytes())
        need(isinstance(result.get('files'), dict), 'release_manifest_invalid')
        for name, sha256 in result['files'].items():
            need(file_hash(safe(root, name)) == sha256, 'release_file_digest_changed')
        return result

    def baseline(self):
        self.pointer()
        need(file_hash(self.old/'release_manifest.json') == self.expected['release_manifest_sha256'], 'baseline_manifest_changed')
        result = self.manifest(self.old)
        need(json.loads((self.old/'addon/server/bundles/current.json').read_bytes())['hash'] == self.parent, 'baseline_bundle_changed')
        need(file_hash(self.old/'addon/server/bundles'/self.parent/'bundle.json') == self.parent, 'baseline_bundle_corrupt')
        need((self.old/'.venv').is_dir(), 'baseline_virtualenv_missing')
        return result

    def payload(self):
        actual = {path.relative_to(self.stage/'overlay').as_posix() for path in (self.stage/'overlay').rglob('*') if path.is_file()}
        need(actual == set(self.overlay), 'overlay_file_set_changed')
        prefix = 'addon/server/bundles/'+self.bundle+'/'
        for name, sha256 in self.overlay.items():
            allowed = (name in BACKEND_OVERLAYS or name.startswith(prefix)
                       or name in {'addon/server/bundles/current.json', 'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
                                   'game-config/archive_http_bundle.lua', 'database/dbtool.py', 'database/migration_manifest.json',
                                   'addon/data/csv/存档系统/archive_achievements.csv', 'addon/data/csv/存档系统/archive_daily_limits.csv'}
                       or name in {entry['path'] for entry in self.migrations})
            need(allowed, 'overlay_scope_invalid')
            need(file_hash(safe(self.stage/'overlay', name)) == sha256, 'overlay_file_digest_changed')
        expected = self.candidate.get('release_manifest_sha256') or self.candidate.get('manifest_sha256')
        need(expected and file_hash(self.stage/'release_manifest.json') == expected, 'candidate_manifest_digest_changed')
        document = json.loads((self.stage/'release_manifest.json').read_bytes())
        baseline = self.baseline()
        need(document['files'] == {**baseline['files'], **self.overlay}, 'candidate_manifest_scope_changed')
        need(document['release'] == self.new.name and document['archive_bundle'] == self.bundle, 'candidate_manifest_identity_changed')
        raw = safe(self.stage/'overlay', prefix+'bundle.json').read_bytes()
        need(digest(raw) == self.bundle, 'candidate_bundle_digest_changed')
        bundle = json.loads(raw)
        for name, source in bundle['sources'].items():
            need(safe(self.stage/'overlay', prefix+name).read_text(encoding='utf-8') == source, 'candidate_bundle_source_changed')
        parent = json.loads((self.old/'addon/server/bundles'/self.parent/'bundle.json').read_bytes())
        need(lottery_projection(parent) == lottery_projection(bundle), 'lottery_semantics_changed')
        need(isinstance(self.plan['proof']['lottery'], dict), 'lottery_proof_missing')
        compatible = bundle.get('compatible_config_hashes', {}).get(self.parent, {})
        need({'lottery_draw', 'lottery_exchange', 'lottery_read'} <= set(compatible.get('commands', [])), 'parent_lottery_compatibility_missing')
        for previous, rule in parent.get('compatible_config_hashes', {}).items():
            candidate_rule = bundle.get('compatible_config_hashes', {}).get(previous, {})
            need(set(rule.get('commands', [])) <= set(candidate_rule.get('commands', [])), 'historical_compatibility_removed')
        self.configuration(bundle)
        return bundle

    def configuration(self, bundle):
        expected_hash = self.candidate.get('configuration_sha256') or self.plan.get('configuration_sha256')
        need(expected_hash and file_hash(self.stage/'configuration.json') == expected_hash, 'configuration_file_digest_changed')
        value = json.loads((self.stage/'configuration.json').read_bytes())
        expected = {'configs': bundle['configs']}
        if bundle.get('compatible_config_hashes'):
            expected['compatible_config_hashes'] = bundle['compatible_config_hashes']
        need(value == expected, 'configuration_payload_differs_from_bundle')
        return value

    def sync_change(self, connection, configuration):
        from psycopg.types.json import Jsonb
        pin = self.expected.get('archive_sync_sha256')
        if not pin and self.expected.get('schema_path'):
            metadata = json.loads(safe(self.stage, self.expected['schema_path']).read_bytes())
            pin = metadata['functions'].get('public.archive_sync_config(text,jsonb)', {}).get('sha256')
        need(pin and HASH.fullmatch(pin), 'sync_definition_pin_missing')
        definition = connection.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
        need(digest(definition.encode()) == pin, 'sync_definition_changed')
        jsonb_hash = connection.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(configuration),)).fetchone()[0]
        updated = exact_sync_branch(definition, self.bundle, jsonb_hash)
        return updated, {'before_sha256': pin, 'candidate_sha256': digest(updated.encode()), 'configuration_jsonb_sha256': jsonb_hash}

    def schema(self, connection):
        need(connection.execute('SELECT current_database()').fetchone()[0] == 'goufayu_test', 'database_scope_invalid')
        tables = {row[0] for row in connection.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'")}
        need(tables <= BASE_TABLES | EXTRA_TABLES | {'fishing_daily_limit_receipts'}, 'unknown_database_table')
        need(EXTRA_TABLES <= tables, 'existing_extension_table_missing')
        functions = {}
        for oid, name, arguments, definition, executable in connection.execute("""
          SELECT p.oid,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),
           has_function_privilege('goufayu_app',p.oid,'EXECUTE')
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.prokind IN ('f','p')
          AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
        """):
            need(name in BASE_FUNCTIONS | EXTRA_FUNCTIONS | NEW_FUNCTIONS, 'unknown_database_function')
            functions[name+'('+arguments+')'] = {'name': name, 'sha256': digest(definition.encode()), 'app': executable}
        need(EXTRA_FUNCTIONS <= {item['name'] for item in functions.values()}, 'existing_extension_function_missing')
        ledger = dict(connection.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations'))
        return {'tables': sorted(tables), 'functions': functions, 'ledger': ledger}

    def unchanged_schema(self, before, after):
        need(set(after['tables']) == set(before['tables']) | {'fishing_daily_limit_receipts'}, 'database_table_set_changed')
        for signature, item in before['functions'].items():
            need(signature in after['functions'], 'existing_database_function_removed')
            if item['name'] not in CHANGED_FUNCTIONS:
                need(after['functions'][signature]['sha256'] == item['sha256'], 'unrelated_database_function_changed')
            need(after['functions'][signature]['app'] == item['app'], 'existing_rpc_privilege_changed')
        for signature, item in after['functions'].items():
            if signature not in before['functions']:
                need(item['name'] in NEW_FUNCTIONS and not item['app'], 'new_application_rpc_refused')

    def database_check(self):
        with self.payment_module().connection() as connection:
            connection.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
            state = self.schema(connection)
            need(state['ledger'] == self.old_ledger, 'baseline_ledger_changed')
            need('fishing_daily_limit_receipts' not in state['tables']
                 and not ({item['name'] for item in state['functions'].values()} & NEW_FUNCTIONS), 'candidate_schema_already_present')
            metadata_name = self.expected.get('schema_path')
            metadata_hash = self.expected.get('schema_sha256')
            if metadata_name or metadata_hash:
                need(metadata_name and metadata_hash and HASH.fullmatch(metadata_hash), 'schema_pin_invalid')
                metadata_file = safe(self.stage, metadata_name)
                need(file_hash(metadata_file) == metadata_hash, 'schema_metadata_digest_changed')
                metadata = json.loads(metadata_file.read_bytes())
                for signature, item in metadata['functions'].items():
                    definition = connection.execute('SELECT pg_get_functiondef(to_regprocedure(%s))', (signature,)).fetchone()[0]
                    need(definition and digest(definition.encode()) == item['sha256'], 'baseline_function_definition_changed')
            bundle = self.payload()
            _, state['sync'] = self.sync_change(connection, self.configuration(bundle))
            connection.rollback()
        return state

    def check(self):
        self.baseline(); self.payload(); state = self.database_check()
        need(self.service_state(SERVICE)['active'] == 'active', 'archive_service_not_active')
        need(self.payment_pin()['service']['active'] == 'active', 'payment_service_not_active')
        return {'ok': True, 'phase': 'CHECKED_READ_ONLY', 'release': self.new.name, 'bundle': self.bundle,
                'sync': state['sync'], 'database_writes': 0}

    def prepare(self):
        # Root may use a private umask. The dedicated API user must be able to
        # traverse the new public source tree; reports still get explicit 0600.
        previous_umask = os.umask(0o022)
        try:
            return self._prepare()
        finally:
            os.umask(previous_umask)

    def _prepare(self):
        checked = self.check()
        need(not self.new.exists() and not self.new.is_symlink(), 'candidate_directory_exists')
        self.new.mkdir(mode=0o755)
        baseline = self.manifest(self.old)
        # Keep every manifested parent file and the complete existing backend
        # source tree. Only byte-pinned task overlays can replace those files.
        for name in baseline['files']:
            source, target = safe(self.old, name), safe(self.new, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        for source in (self.old/'backend').rglob('*'):
            need(not source.is_symlink(), 'baseline_backend_symlink_refused')
            if source.is_file() and '__pycache__' not in source.parts and source.suffix != '.pyc':
                target = self.new/source.relative_to(self.old)
                target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
        (self.new/'.venv').symlink_to(self.old/'.venv', target_is_directory=True)
        for name in self.overlay:
            target = safe(self.new, name); target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(safe(self.stage/'overlay', name), target); target.chmod(0o644)
        shutil.copyfile(self.stage/'release_manifest.json', self.new/'release_manifest.json')
        self.manifest(self.new)
        self.validate_legacy_lottery_guard()
        return self.save('prepared', {'ok': True, 'phase': 'PREPARED_NOT_ACTIVATED', 'plan_sha256': self.plan_hash,
                                     'release': self.new.name, 'bundle': self.bundle, 'payment': self.payment_pin(), 'sync': checked['sync']})

    def validate_legacy_lottery_guard(self):
        name = self.new/'backend/archive_backend/unique_points.py'
        spec = importlib.util.spec_from_file_location('archive_caps_candidate_unique_points', name)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        for kind in ('lottery_draw', 'lottery_exchange'):
            need(module.legacy_lottery_error(self.bundle, self.parent, kind) is None, 'parent_lottery_guard_not_admitted')
            need(module.legacy_lottery_error(self.bundle, '0'*64, kind) == 'lottery_config_refresh_required', 'unreviewed_lottery_guard_relaxed')

    def backup(self):
        directory = BACKUPS/self.new.name/self.plan_hash
        need(not directory.exists() and not directory.is_symlink(), 'backup_directory_exists')
        directory.mkdir(mode=0o700, parents=True)
        for parent in (BACKUPS, BACKUPS/self.new.name, directory):
            need(not parent.is_symlink(), 'backup_directory_symlink_refused'); parent.chmod(0o700)
        dump = directory/'database.dump'
        environment = {**os.environ, 'PGSERVICEFILE': '/etc/goufayu/pg_service.conf', 'PGPASSFILE': '/etc/goufayu/admin.pgpass'}
        arguments = [str(self.old/'deploy/pg-bin/pg_dump'), '--dbname=service=goufayu_admin', '--no-password',
                     '--format=custom', '--schema=public', '--schema=extensions', '--schema=payments',
                     '--no-owner', '--no-acl', '--no-publications', '--no-subscriptions', '--file='+str(dump)]
        result = subprocess.run(arguments, env=environment, capture_output=True, timeout=180, check=False)
        need(result.returncode == 0 and dump.is_file() and dump.stat().st_size > 0, 'private_database_backup_failed')
        dump.chmod(0o600)
        listing = subprocess.run([str(self.old/'deploy/pg-bin/pg_restore'), '--list', str(dump)], capture_output=True, timeout=30)
        need(listing.returncode == 0 and b'payments orders' in listing.stdout, 'private_database_backup_incomplete')
        sources = directory/'parent_sources.tar.gz'
        with tarfile.open(sources, 'w:gz') as archive:
            archive.add(self.old/'release_manifest.json', arcname='release_manifest.json', recursive=False)
            for name in self.manifest(self.old)['files']:
                archive.add(safe(self.old, name), arcname=name, recursive=False)
        sources.chmod(0o600)
        record = {'ok': True, 'phase': 'PRIVATE_BACKUP_COMPLETE', 'directory': str(directory),
                  'database_sha256': file_hash(dump), 'source_sha256': file_hash(sources), 'downloaded': False}
        (directory/'backup.json').write_bytes(canonical(record)); (directory/'backup.json').chmod(0o600)
        return self.save('backup', record)

    def admit(self):
        from psycopg.types.json import Jsonb
        bundle = self.payload()
        configuration = self.configuration(bundle)
        with self.payment_module().connection() as connection:
            connection.execute("SET LOCAL lock_timeout='5s'")
            connection.execute("SET LOCAL statement_timeout='120s'")
            connection.execute('SET ROLE goufayu_owner')
            connection.execute('SELECT pg_advisory_xact_lock(719232014003)')
            connection.execute('LOCK TABLE public._goufayu_migrations,public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
            before = self.schema(connection)
            need(before['ledger'] == self.old_ledger, 'baseline_ledger_changed')
            sync_definition, sync_proof = self.sync_change(connection, configuration)
            prepared = json.loads((self.stage/'prepared.json').read_bytes())
            need(prepared['sync'] == sync_proof, 'reviewed_sync_definition_changed')
            config_hashes = dict(connection.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets"))
            for entry in self.migrations:
                source = safe(self.stage/'overlay', entry['path'])
                need(file_hash(source) == entry['sha256'], 'migration_digest_changed')
                connection.execute(sql_body(source.read_text(encoding='utf-8')))
                connection.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)', (entry['id'], entry['sha256']))
            # Add a single exact-digest exception. Every prior branch and every
            # generic compatibility/schema check remains byte-for-byte intact.
            connection.execute(sync_definition)
            registered_definition = connection.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
            need(digest(registered_definition.encode()) == sync_proof['candidate_sha256'], 'registered_sync_definition_changed')
            result = connection.execute('SELECT public.archive_sync_config(%s,%s)', (self.bundle, Jsonb(configuration))).fetchone()[0]
            need(result.get('ok') is True, 'candidate_configuration_rejected')
            after = self.schema(connection)
            self.unchanged_schema(before, after)
            need(after['ledger'] == {**self.old_ledger, **{entry['id']: entry['sha256'] for entry in self.migrations}}, 'new_ledger_mismatch')
            new_config_hashes = dict(connection.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets"))
            need(all(new_config_hashes.get(key) == value for key, value in config_hashes.items()), 'existing_configuration_changed')
            need(set(new_config_hashes) <= set(config_hashes) | {self.bundle}, 'unexpected_configuration_added')
            connection.commit()
        return self.save('database_committed', {'ok': True, 'phase': 'DDL_AND_CONFIG_COMMITTED', 'bundle': self.bundle,
                                               'migration_ids': [entry['id'] for entry in self.migrations], 'player_updates': 0})

    def switch(self, target):
        need(target in (self.old, self.new), 'pointer_target_invalid')
        temporary = RELEASES/('current.archive-caps.'+secrets.token_hex(8))
        temporary.symlink_to(target, target_is_directory=True)
        os.replace(temporary, RELEASES/'current')
        descriptor = os.open(RELEASES, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

    def health(self):
        deadline = time.monotonic()+20
        while time.monotonic() < deadline:
            ready = True
            for port in (8765, 8766):
                try:
                    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health', timeout=1) as response:
                        ready = ready and response.status == 200 and json.load(response).get('ok') is True
                except Exception:
                    ready = False
            if ready:
                return
            time.sleep(.5)
        raise Refused('service_health_check_failed')

    def activate(self):
        self.check()
        prepared = json.loads((self.stage/'prepared.json').read_bytes())
        need(prepared['plan_sha256'] == self.plan_hash and prepared['bundle'] == self.bundle, 'prepared_plan_changed')
        need(prepared['payment'] == self.payment_pin(), 'payment_state_changed')
        need(self.manifest(self.new)['files'] == json.loads((self.stage/'release_manifest.json').read_bytes())['files'], 'prepared_files_changed')
        self.validate_legacy_lottery_guard()
        stopped = False
        try:
            stopped = True
            self.systemctl('stop')
            state = self.service_state(SERVICE)
            need(state['active'] == 'inactive' and state['pid'] == 0, 'old_archive_process_still_running')
            self.pointer(); self.backup(); self.admit()
            self.switch(self.new); self.systemctl('start'); self.pointer(new=True); self.health()
            need(prepared['payment'] == self.payment_pin(), 'payment_state_changed')
        except Exception:
            if stopped:
                # Compatible additive DDL stays committed. Never undo tables,
                # rewards, ledgers or configuration after another service used it.
                try:
                    self.systemctl('stop')
                    if (RELEASES/'current').resolve(strict=True) == self.new:
                        self.switch(self.old)
                    self.pointer(); self.systemctl('start'); self.health()
                    self.save('rollback', {'ok': False, 'phase': 'OLD_CODE_RESTORED_DDL_PRESERVED', 'payment_untouched': True})
                except Exception:
                    self.save('rollback', {'ok': False, 'phase': 'RECOVERY_REQUIRED', 'payment_untouched': True})
                    raise Refused('code_recovery_required') from None
            raise
        return self.save('activated', {'ok': True, 'phase': 'ACTIVATED', 'release': self.new.name,
                                       'bundle': self.bundle, 'payment_untouched': True, 'player_updates': 0})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True, type=Path)
    parser.add_argument('--plan-sha256', required=True)
    parser.add_argument('--mode', choices=('check', 'prepare', 'activate'), default='check')
    arguments = parser.parse_args()
    need(os.name == 'posix' and os.geteuid() == 0, 'test_host_root_required')
    operator = Operator(arguments.stage, arguments.plan_sha256)
    print(json.dumps(getattr(operator, arguments.mode)(), ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Refused as error:
        code = str(error)
        print(json.dumps({'ok': False, 'error': code if re.fullmatch(r'[a-z0-9_]{1,80}', code) else 'operator_refused'}))
        raise SystemExit(1)
    except Exception:
        # Driver diagnostics, process stderr, environments and DSNs stay private.
        print(json.dumps({'ok': False, 'error': 'operator_failed_private_details_suppressed'}))
        raise SystemExit(1)
