"""One exact config admission branch, using the audited rollback-only PG probe."""
from pathlib import Path
import hashlib
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
PRIOR = 'tools/ws4_lottery_config_20261111/recipe.py'
PRIOR_SHA = '775955117f10065eddf98c2681cb8dff428a11fdf184298dc830a6d5b5f227ca'
NEW_BUNDLE = 'd38866d1be2dec7b3b8c27ddd1315bab9cb27a1c7e0a136b670e5e9df12e3ed1'
PARENT_RELEASE = '20261111-ws4-lottery-rates-e487206a31dc'
PARENT_MANIFEST = 'f969459e60e0f7f29423b3ee320ec8ce0e129e8605fb762f402242a347c7fd66'
PARENT_FUNCTION = 'd405353adf214b97152bec809ac217fb6227a3f91978a6c7ecdde38b2e2e04e5'
CONFIG_SHA = '6300665c42d0eb44a494dedf06f99cc871e74a829be43a5ecf9503595b55db5b'
PG_CONFIG_SHA = '19d649831d4d7d1337fc02c7987269ab62680bb59be0b038d2b029c5141a5b0a'
RECIPE = 'gold-ur1-fifty-exact-config-v1'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def need(ok, code):
    if not ok: raise RuntimeError(code)


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(),str(path),'exec'),module.__dict__)
    return module


need(sha((ROOT/PRIOR).read_bytes().replace(b'\r\n',b'\n')) == PRIOR_SHA,'audited_config_recipe_changed')
previous = load('ur50_parent_recipe',ROOT/PRIOR)
current_function = previous.derive_function(previous.parent_function())
need(sha(current_function) == PARENT_FUNCTION,'current_function_binding_changed')
base = previous.prior
OLD_CONFIGS = {**previous.OLD_CONFIGS,previous.NEW_BUNDLE:previous.PG_CONFIG_SHA}


def parent_function(): return current_function


def derive_function(parent):
    need(sha(parent) == PARENT_FUNCTION,'sync_parent_changed')
    text = parent.decode('utf8')
    anchor = ' -- Gold-pool 20261111: only the reviewed immutable UR3/SSR10 configuration.\n'
    need(text.count(anchor) == 1 and NEW_BUNDLE not in text,'sync_anchor_changed')
    branch = (" -- Gold UR1/50 and cultivation unlock, exact reviewed 20261111 config.\n"
        " IF p_hash='"+NEW_BUNDLE+"' THEN\n"
        "  IF p_config IS NULL OR jsonb_typeof(p_config) IS DISTINCT FROM 'object' OR\n"
        "     encode(sha256(convert_to(p_config::text,'UTF8')),'hex') IS DISTINCT FROM '"+PG_CONFIG_SHA+"' THEN\n"
        "   RAISE EXCEPTION 'public_beta_configuration_mismatch';\n"
        "  END IF;\n"
        "  INSERT INTO public.archive_config_sets(config_hash,config) VALUES(p_hash,p_config) ON CONFLICT DO NOTHING;\n"
        "  SELECT config INTO v FROM public.archive_config_sets WHERE config_hash=p_hash;\n"
        "  IF v IS DISTINCT FROM p_config THEN RAISE EXCEPTION 'archive_config_immutable'; END IF;\n"
        "  RETURN jsonb_build_object('ok',true);\n"
        " END IF;\n")
    result=text.replace(anchor,branch+anchor,1)
    need(result.replace(branch,'',1) == text,'unrelated_function_change')
    return result.encode('utf8')


for key in ('NEW_BUNDLE','PARENT_FUNCTION','CONFIG_SHA','PG_CONFIG_SHA','OLD_CONFIGS','parent_function','derive_function'):
    setattr(base,key,globals()[key])


def artifacts(bundle_raw,source_revision,source_pins,receipt_sha):
    config=base.configuration(bundle_raw);candidate=derive_function(current_function)
    probe=base.probe_sql(config).replace("'old_configs',2","'old_configs',4").replace('PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS','GOLD_UR1_FIFTY_CONFIG_PG_PROBE_PASS')
    activate=base.activate_sql(config).replace('PUBLIC_BETA_EXACT_CONFIG_REGISTERED','GOLD_UR1_FIFTY_CONFIG_REGISTERED')
    values={'archive_sync_config.parent.sql':current_function,'archive_sync_config.candidate.sql':candidate,
            'config.json':config,'probe.sql':probe.encode(),'activate.sql':activate.encode(),'verify.sql':base.verify_sql().encode()}
    binding=dict(recipe=RECIPE,source_revision=source_revision,source_bundle=NEW_BUNDLE,source_sha256=source_pins,
                 candidate_receipt_sha256=receipt_sha,parent_release=PARENT_RELEASE,parent_manifest_sha256=PARENT_MANIFEST,
                 parent_function_sha256=PARENT_FUNCTION,candidate_function_sha256=sha(candidate),config_sha256=CONFIG_SHA,
                 config_jsonb_sha256=PG_CONFIG_SHA,old_configs=OLD_CONFIGS,function_metadata=base.METADATA,
                 artifacts={name:sha(raw) for name,raw in values.items()})
    return values,binding
