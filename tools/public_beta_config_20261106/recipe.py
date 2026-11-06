"""Exact WS4 public-beta config admission, with no transport or side effects.

One operator-time O(config bytes + function bytes) transformation. No player
table is read and no runtime loop is introduced. SQL entry points are fixed.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = next(path for path in HERE.parents if (path / 'AGENTS.md').is_file())
SOURCE_PATH = 'server/bundles/f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42/bundle.json'
PARENT_RELEASE = '20261106-ws4-compact-receipt-d15b405cfb16'
PARENT_MANIFEST = '5ae22761341595aa94731e6f226f598ad6665dc8c18c8db03fe857e254d8ba1c'
PARENT_FUNCTION = '8d2b3fc8c8948c3d9d34ac1232f8f827fe8c388053c0e9aec99b975c8b868673'
NEW_BUNDLE = 'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
CONFIG_SHA = 'b5e0a903d02aebb119c54f07e0b7e8375c2a6d5dfde84abf18cad6c454c4b7bb'
PG_CONFIG_SHA = 'a74510bf5115419b76be7026a2cd309fb018ed37e93ab22cb1b4929f6b6d2871'
OLD_CONFIGS = {
    '47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e': '6a86920ab19b093497d104b1bb85e0d43c11a1d7fd8761cf7f9680e69ffd6025',
    'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488': '93e950784f60e92e718506eb6c8ef770c6f2a60771a3abdabc35a3f8b8366d81',
}
METADATA = {'owner': 'goufayu_owner', 'security_definer': True,
            'configuration': ['search_path=pg_catalog, public, extensions, pg_temp'],
            'acl': ['goufayu_owner=X/goufayu_owner', 'goufayu_app=X/goufayu_owner']}
SIGNATURE = 'public.archive_sync_config(text,jsonb)'
RECIPE = 'public-beta-exact-config-v1'


def need(ok, code):
    if not ok:
        raise RuntimeError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf8')


def quote(value):
    need(isinstance(value, str) and '\0' not in value, 'sql_literal_required')
    return "'" + value.replace("'", "''") + "'"


def document(value):
    return quote(canonical(value).decode()) + '::jsonb'


def git_blob(revision, path):
    need(bool(re.fullmatch('[0-9a-f]{40}', revision or '')), 'immutable_revision_required')
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(ROOT), 'show', revision + ':' + path]).replace(b'\r\n', b'\n')


def configuration(bundle_raw):
    need(sha(bundle_raw) == NEW_BUNDLE, 'fixed_bundle_changed')
    bundle = json.loads(bundle_raw)
    value = {'configs': bundle['configs']}
    if bundle.get('compatible_config_hashes'):
        value['compatible_config_hashes'] = {
            digest: {'commands': sorted(rule['commands']), 'upgrade_commands': sorted(rule['upgrade_commands'])}
            for digest, rule in bundle['compatible_config_hashes'].items()}
    raw = canonical(value)
    need(sha(raw) == CONFIG_SHA, 'exact_service_sync_config_changed')
    return raw


def derive_function(parent):
    need(sha(parent) == PARENT_FUNCTION, 'audited_sync_function_changed')
    text = parent.decode('utf8')
    anchor = 'begin\n -- Exact published WS4 catalog contract, 20261031.\n'
    need(text.count(anchor) == 1 and NEW_BUNDLE not in text, 'exact_sync_anchor_changed')
    branch = (" -- Public-beta 20261106: only the reviewed immutable two-ticket configuration.\n"
        " IF p_hash='" + NEW_BUNDLE + "' THEN\n"
        "  IF p_config IS NULL OR jsonb_typeof(p_config) IS DISTINCT FROM 'object' OR\n"
        "     encode(sha256(convert_to(p_config::text,'UTF8')),'hex') IS DISTINCT FROM '" + PG_CONFIG_SHA + "' THEN\n"
        "   RAISE EXCEPTION 'public_beta_configuration_mismatch';\n"
        "  END IF;\n"
        "  INSERT INTO public.archive_config_sets(config_hash,config) VALUES(p_hash,p_config) ON CONFLICT DO NOTHING;\n"
        "  SELECT config INTO v FROM public.archive_config_sets WHERE config_hash=p_hash;\n"
        "  IF v IS DISTINCT FROM p_config THEN RAISE EXCEPTION 'archive_config_immutable'; END IF;\n"
        "  RETURN jsonb_build_object('ok',true);\n"
        " END IF;\n")
    result = text.replace(anchor, 'begin\n' + branch + anchor[len('begin\n'):], 1)
    need(result.replace(branch, '', 1) == text, 'unrelated_sync_function_change')
    return result.encode('utf8')


def parent_function():
    raw = (HERE / 'archive_sync_config.parent.sql').read_bytes().replace(b'\r\n', b'\n')
    need(sha(raw) == PARENT_FUNCTION, 'frozen_sync_parent_changed')
    return raw


def guard_sql(function_sha, include_new):
    expected = dict(OLD_CONFIGS)
    if include_new:
        expected[NEW_BUNDLE] = PG_CONFIG_SHA
    return f"""DO $beta_guard$
DECLARE definition text; meta jsonb; configs jsonb;
BEGIN
 IF current_database()<>'goufayu_ws4' THEN RAISE EXCEPTION 'fixed_ws4_database_required'; END IF;
 SELECT pg_get_functiondef(p.oid),jsonb_build_object('owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,
  'configuration',p.proconfig,'acl',p.proacl) INTO definition,meta FROM pg_proc p WHERE p.oid='{SIGNATURE}'::regprocedure;
 IF encode(sha256(convert_to(definition,'UTF8')),'hex') IS DISTINCT FROM '{function_sha}' THEN RAISE EXCEPTION 'sync_function_drift'; END IF;
 IF meta IS DISTINCT FROM {document(METADATA)} THEN RAISE EXCEPTION 'sync_function_metadata_drift'; END IF;
 SELECT coalesce(jsonb_object_agg(config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex')),'{{}}'::jsonb)
  INTO configs FROM public.archive_config_sets;
 IF configs IS DISTINCT FROM {document(expected)} THEN RAISE EXCEPTION 'config_inventory_drift'; END IF;
END; $beta_guard$;
"""


def verify_sql():
    """Statements for a caller-owned READ ONLY transaction; no COMMIT/ROLLBACK."""
    return guard_sql(sha(derive_function(parent_function())), True)


def body(source):
    text = source.decode('utf8') if isinstance(source, bytes) else source
    need(text.count('$function$') == 2, 'function_body_delimiters_changed')
    return text.split('$function$')[1]


def isolated_function(source, name):
    need(name in ('public_beta_parent_probe', 'public_beta_candidate_probe'), 'fixed_probe_name_required')
    text = source.decode('utf8')
    head = 'CREATE OR REPLACE FUNCTION public.archive_sync_config('
    need(text.count(head) == 1, 'function_signature_changed')
    derived = text.replace(head, 'CREATE OR REPLACE FUNCTION pg_temp.' + name + '(', 1)
    references = list(re.finditer(r'(?<![A-Za-z0-9_\.])(?:public\.)?archive_config_sets\b', derived))
    need(len(references) >= 4, 'config_table_references_missing')
    # Replace in reverse and prove all other bytes (including the real reducer
    # control flow) remain exact. No public function/table can be called/written.
    parts = list(derived)
    for match in reversed(references):
        parts[match.start():match.end()] = 'pg_temp.archive_config_sets'
    isolated = ''.join(parts)
    need(len(re.findall(r'pg_temp\.archive_config_sets\b', isolated)) == len(references)
         and not re.search(r'(?<![A-Za-z0-9_\.])(?:public\.)?archive_config_sets\b', isolated)
         and 'public.archive_sync_config(' not in isolated, 'probe_public_reference_rejected')
    return isolated


def probe_sql(config):
    need(sha(config) == CONFIG_SHA, 'probe_config_changed')
    original = parent_function()
    candidate = derive_function(original)
    old_clone = isolated_function(original, 'public_beta_parent_probe')
    new_clone = isolated_function(candidate, 'public_beta_candidate_probe')
    target = quote(config.decode()) + '::jsonb'
    return ("BEGIN ISOLATION LEVEL REPEATABLE READ;\nSET LOCAL statement_timeout='15000ms';\nSET LOCAL lock_timeout='1000ms';\n"
        + guard_sql(PARENT_FUNCTION, False)
        + "CREATE TEMP TABLE archive_config_sets(config_hash text PRIMARY KEY,config jsonb NOT NULL) ON COMMIT DROP;\n"
        + "INSERT INTO pg_temp.archive_config_sets SELECT config_hash,config FROM public.archive_config_sets WHERE config_hash IN ("
        + ','.join(quote(key) for key in OLD_CONFIGS) + ");\n"
        + old_clone + ';\n' + new_clone + ';\n'
        + f"""DO $beta_probe$
DECLARE target jsonb:={target}; row record; bad jsonb; before_rows jsonb; after_rows jsonb; rejected boolean;
 normalized text; clone_body text; namespace text; original_rejected boolean:=false;
 physical_prefix text; alias_prefix text; target_prefix text; selected_prefix text;
BEGIN
 SELECT jsonb_object_agg(config_hash,config) INTO before_rows FROM pg_temp.archive_config_sets;
 FOR row IN SELECT config_hash,config FROM pg_temp.archive_config_sets ORDER BY config_hash LOOP
  IF pg_temp.public_beta_parent_probe(row.config_hash,row.config) IS DISTINCT FROM '{{"ok":true}}'::jsonb
   OR pg_temp.public_beta_candidate_probe(row.config_hash,row.config) IS DISTINCT FROM '{{"ok":true}}'::jsonb THEN RAISE EXCEPTION 'old_config_replay_changed'; END IF;
 END LOOP;
 BEGIN PERFORM pg_temp.public_beta_parent_probe('{NEW_BUNDLE}',target);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'archive_compatibility_invalid' THEN RAISE; END IF; original_rejected:=true;
 END;
 IF NOT original_rejected THEN RAISE EXCEPTION 'old_function_accepts_new_configuration'; END IF;
 FOREACH bad IN ARRAY ARRAY[NULL::jsonb,'null'::jsonb,'[]'::jsonb,'1'::jsonb,'{{}}'::jsonb,target||'{{"forged":true}}'::jsonb,
  jsonb_set(target,'{{configs,archive_benefit_rewards,rows,20,base_counts}}','["200"]'::jsonb)] LOOP
  rejected:=false;
  BEGIN PERFORM pg_temp.public_beta_candidate_probe('{NEW_BUNDLE}',bad);
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM<>'public_beta_configuration_mismatch' THEN RAISE; END IF; rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'forged_config_accepted'; END IF;
 END LOOP;
 IF pg_temp.public_beta_candidate_probe('{NEW_BUNDLE}',target) IS DISTINCT FROM '{{"ok":true}}'::jsonb
  OR pg_temp.public_beta_candidate_probe('{NEW_BUNDLE}',target) IS DISTINCT FROM '{{"ok":true}}'::jsonb THEN RAISE EXCEPTION 'new_config_registration_failed'; END IF;
 SELECT jsonb_object_agg(config_hash,config) INTO after_rows FROM pg_temp.archive_config_sets;
 IF after_rows IS DISTINCT FROM before_rows||jsonb_build_object('{NEW_BUNDLE}',target) THEN RAISE EXCEPTION 'old_configs_changed'; END IF;
 -- An exception after temporary registration must roll back the entire nested
 -- transaction. This exercises PostgreSQL failure semantics with real code.
 DELETE FROM pg_temp.archive_config_sets WHERE config_hash='{NEW_BUNDLE}';
 BEGIN
  PERFORM pg_temp.public_beta_candidate_probe('{NEW_BUNDLE}',target);
  RAISE EXCEPTION 'synthetic_transaction_failure';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'synthetic_transaction_failure' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM pg_temp.archive_config_sets WHERE config_hash='{NEW_BUNDLE}') THEN RAISE EXCEPTION 'transaction_failure_not_rolled_back'; END IF;
 SELECT p.prosrc,n.nspname,pg_get_functiondef(p.oid) INTO clone_body,namespace,normalized FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid='pg_temp.public_beta_candidate_probe(text,jsonb)'::regprocedure;
 IF clone_body IS DISTINCT FROM {quote(body(new_clone))} THEN RAISE EXCEPTION 'probe_function_body_changed'; END IF;
 physical_prefix:='CREATE OR REPLACE FUNCTION '||quote_ident(namespace)||'.public_beta_candidate_probe(';
 alias_prefix:='CREATE OR REPLACE FUNCTION pg_temp.public_beta_candidate_probe(';
 target_prefix:='CREATE OR REPLACE FUNCTION public.archive_sync_config(';
 -- PostgreSQL 17 displays a session's temporary namespace using pg_temp,
 -- while pg_namespace.nspname retains pg_temp_N. Accept exactly one known
 -- leading prefix, preserving every following byte for the strict comparison.
 IF starts_with(normalized,physical_prefix)=starts_with(normalized,alias_prefix) THEN
  RAISE EXCEPTION 'temporary_function_header_invalid';
 END IF;
 selected_prefix:=CASE WHEN starts_with(normalized,physical_prefix) THEN physical_prefix ELSE alias_prefix END;
 normalized:=target_prefix||substr(normalized,length(selected_prefix)+1);
 normalized:=replace(normalized,clone_body,{quote(body(candidate))});
 IF normalized IS DISTINCT FROM {quote(candidate.decode())} THEN RAISE EXCEPTION 'postgres_function_canonicalization_changed'; END IF;
END; $beta_probe$;
"""
        + guard_sql(PARENT_FUNCTION, False)
        + "ROLLBACK;\nSELECT json_build_object('ok',true,'status','PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS','old_configs',2,'forged_configs_rejected',7,'transaction_rollback_verified',true,'persistent_writes',0,'player_rows_read',0,'canonical_function_sha256',"
        + quote(sha(candidate)) + ");\n")


def activate_sql(config):
    need(sha(config) == CONFIG_SHA, 'activation_config_changed')
    candidate = derive_function(parent_function())
    return ("BEGIN ISOLATION LEVEL SERIALIZABLE;\nSET LOCAL statement_timeout='15000ms';\nSET LOCAL lock_timeout='1500ms';\n"
        + "DO $lock$ BEGIN PERFORM pg_advisory_xact_lock(719232014021); END; $lock$;\n"
        + "LOCK TABLE public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE;\n"
        + guard_sql(PARENT_FUNCTION, False)
        + "SET LOCAL ROLE goufayu_owner;\n" + candidate.decode() + ';\n'
        + "DO $register$ BEGIN IF public.archive_sync_config(" + quote(NEW_BUNDLE) + ',' + quote(config.decode())
        + "::jsonb) IS DISTINCT FROM '{\"ok\":true}'::jsonb THEN RAISE EXCEPTION 'exact_config_registration_failed'; END IF; END; $register$;\n"
        + verify_sql()
        + "COMMIT;\nSELECT json_build_object('ok',true,'status','PUBLIC_BETA_EXACT_CONFIG_REGISTERED','new_configs',1,'changed_functions',1,'player_rows_read',0,'player_rows_written',0,'old_configs_preserved',true,'old_function_sha256',"
        + quote(PARENT_FUNCTION) + ",'new_function_sha256'," + quote(sha(candidate)) + ",'new_bundle'," + quote(NEW_BUNDLE)
        + ",'config_jsonb_sha256'," + quote(PG_CONFIG_SHA) + ");\n")


def artifacts(source_revision):
    config = configuration(git_blob(source_revision, SOURCE_PATH))
    parent = parent_function()
    candidate = derive_function(parent)
    values = {'archive_sync_config.parent.sql': parent, 'archive_sync_config.candidate.sql': candidate,
              'config.json': config, 'probe.sql': probe_sql(config).encode(), 'activate.sql': activate_sql(config).encode(),
              'verify.sql': verify_sql().encode()}
    binding = {'recipe': RECIPE, 'source_revision': source_revision, 'source_bundle': NEW_BUNDLE,
               'parent_release': PARENT_RELEASE, 'parent_manifest_sha256': PARENT_MANIFEST,
               'parent_function_sha256': PARENT_FUNCTION, 'candidate_function_sha256': sha(candidate),
               'config_sha256': CONFIG_SHA, 'config_jsonb_sha256': PG_CONFIG_SHA,
               'old_configs': OLD_CONFIGS, 'function_metadata': METADATA,
               'artifacts': {name: sha(raw) for name, raw in values.items()}}
    return values, binding
