"""Exact WS4 admission for the reviewed 2026-11-11 lottery bundle.

Reuses the audited public-beta SQL guard and temporary-clone probe. Only one
new immutable config and one SQL function branch are admitted. No player rows
are read or written by this recipe.
"""
from pathlib import Path
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[2]
PRIOR = 'tools/public_beta_config_20261106/recipe.py'
PRIOR_SHA = '54a4114361ae69e7b7fba1cb2942ebd334a7284f8b263f7246f4de976844aa97'
NEW_BUNDLE = '98761e2a9386174e696fada8efdc2fc6891365dc661215b576b5f90f02fc8fac'
PARENT_BUNDLE = 'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
PARENT_RELEASE = '20261110-ws4-redemption-transport-ae3e77c24300'
PARENT_MANIFEST = '25d4ea97b6c1a91ba868a978a975873c87ea65a616ffc9ff088db420fbda5cd4'
PARENT_FUNCTION = 'b32ffb324573cad653c70c37e4dcb64f725d35af436d1557e5ffda5c9c92775b'
CONFIG_SHA = '6260347d74c1ca16d8a5e0351a9c60808a860010e6ce463ee8b4df1b088399e2'
PG_CONFIG_SHA = '015a31e33a12a8e292cb6775becae9b10e92568c14c07bf15e088f7057eebe65'
RECIPE = 'gold-pool-ur3-exact-config-v1'
OLD_CONFIGS = {
    '47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e': '6a86920ab19b093497d104b1bb85e0d43c11a1d7fd8761cf7f9680e69ffd6025',
    'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488': '93e950784f60e92e718506eb6c8ef770c6f2a60771a3abdabc35a3f8b8366d81',
    PARENT_BUNDLE: 'a74510bf5115419b76be7026a2cd309fb018ed37e93ab22cb1b4929f6b6d2871',
}


def sha(raw): return hashlib.sha256(raw).hexdigest()
def need(ok, code):
    if not ok: raise RuntimeError(code)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


need(sha((ROOT / PRIOR).read_bytes().replace(b'\r\n', b'\n')) == PRIOR_SHA,
     'audited_config_recipe_changed')
prior = load('lottery_parent_config_recipe', ROOT / PRIOR)
current_function = prior.derive_function(prior.parent_function())
need(sha(current_function) == PARENT_FUNCTION, 'audited_ws4_sync_function_changed')


def parent_function(): return current_function


def derive_function(parent):
    need(sha(parent) == PARENT_FUNCTION, 'lottery_sync_parent_changed')
    text = parent.decode('utf8')
    anchor = ' -- Public-beta 20261106: only the reviewed immutable two-ticket configuration.\n'
    need(text.count(anchor) == 1 and NEW_BUNDLE not in text,
         'lottery_sync_anchor_changed')
    branch = (" -- Gold-pool 20261111: only the reviewed immutable UR3/SSR10 configuration.\n"
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
    result = text.replace(anchor, branch + anchor, 1)
    need(result.replace(branch, '', 1) == text, 'unrelated_sync_function_change')
    return result.encode('utf8')


# The frozen probe/guard functions read these globals from their own module.
# Bind all new values explicitly and retain their audited SQL control flow.
prior.NEW_BUNDLE = NEW_BUNDLE
prior.PARENT_FUNCTION = PARENT_FUNCTION
prior.CONFIG_SHA = CONFIG_SHA
prior.PG_CONFIG_SHA = PG_CONFIG_SHA
prior.OLD_CONFIGS = OLD_CONFIGS
prior.parent_function = parent_function
prior.derive_function = derive_function


def artifacts(bundle_raw, source_revision, source_pins, candidate_receipt_sha256):
    config = prior.configuration(bundle_raw)
    candidate = derive_function(current_function)
    probe = prior.probe_sql(config).replace("'old_configs',2", "'old_configs',3")
    probe = probe.replace('PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS',
                          'LOTTERY_RATES_CONFIG_PG_PROBE_PASS')
    activate = prior.activate_sql(config).replace('PUBLIC_BETA_EXACT_CONFIG_REGISTERED',
                                                  'LOTTERY_RATES_CONFIG_REGISTERED')
    values = {'archive_sync_config.parent.sql': current_function,
              'archive_sync_config.candidate.sql': candidate,
              'config.json': config,
              'probe.sql': probe.encode(),
              'activate.sql': activate.encode(),
              'verify.sql': prior.verify_sql().encode()}
    binding = dict(recipe=RECIPE, source_revision=source_revision,
                   source_bundle=NEW_BUNDLE, source_sha256=source_pins,
                   candidate_receipt_sha256=candidate_receipt_sha256,
                   parent_release=PARENT_RELEASE, parent_manifest_sha256=PARENT_MANIFEST,
                   parent_function_sha256=PARENT_FUNCTION,
                   candidate_function_sha256=sha(candidate),
                   config_sha256=CONFIG_SHA, config_jsonb_sha256=PG_CONFIG_SHA,
                   old_configs=OLD_CONFIGS, function_metadata=prior.METADATA,
                   artifacts={name: sha(raw) for name, raw in values.items()})
    return values, binding


def plan():
    return dict(status='LOTTERY_RATES_CONFIG_PLAN_NOT_EXECUTED',
                parent_function_sha256=PARENT_FUNCTION,
                candidate_function_sha256=sha(derive_function(current_function)),
                bundle=NEW_BUNDLE, configuration_sha256=CONFIG_SHA,
                remote_actions=0, player_rows_read=0, player_rows_written=0)
