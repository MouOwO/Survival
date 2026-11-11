"""Exact WS4 UR1/50-pity rollout through the retained drain/rollback controller.

Default plan has no remote action. No real player draw or redemption is run.
"""
from pathlib import Path
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[2]
TOOL = 'tools/cultivation_unlock_20261111/deploy.py'
PROBE = 'tools/cultivation_unlock_20261111/probe.py'
BUILDER = 'tools/cultivation_unlock_20261111/bundle.py'
PRIOR = 'tools/ws4_lottery_rates_20261111/deploy.py'
PRIOR_SHA = '074d630efaa5a00ea6d2090900d6a2d55cc7ab57a31b67b354d310e6929fceb8'
PARENT = '20261111-ws4-lottery-rates-e487206a31dc'
MANIFEST = 'f969459e60e0f7f29423b3ee320ec8ce0e129e8605fb762f402242a347c7fd66'
UNIT_SHA = 'f7291c55334f0ac61d152f508394dd6ea149ef65b8fceed058ad7a45f0fcf555'
PARENT_BUNDLE = '98761e2a9386174e696fada8efdc2fc6891365dc661215b576b5f90f02fc8fac'
BUNDLE = 'd38866d1be2dec7b3b8c27ddd1315bab9cb27a1c7e0a136b670e5e9df12e3ed1'
RECIPE = 'gold-ur1-fifty-and-cultivation-unlock-v1'
RUN = Path('D:/Survival_本地工具/runs/20261111_cultivation_unlock01')
ARTIFACT = RUN / 'candidate_v02' / BUNDLE
RECEIPT = RUN / 'candidate_v02/candidate_receipt.json'
RECEIPT_SHA = 'c6d16e59ea4a73a99c159f0e9d9b0c0ddd23a9cc5c8f67f277de9e49aa900b0a'
OUT = RUN / 'server_deploy'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def need(ok, code):
    if not ok: raise RuntimeError(code)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


need(sha((ROOT / PRIOR).read_bytes().replace(b'\r\n',b'\n')) == PRIOR_SHA, 'audited_rollout_changed')
controller = load('ur50_frozen_rollout', ROOT / PRIOR)
builder = load('ur50_exact_bundle_builder', ROOT / BUILDER)
git_blob = controller.git_blob
OPERATOR_FILES = tuple(dict.fromkeys((TOOL,PROBE,BUILDER,'server/archive_backend/bundle.py') + controller.OPERATOR_FILES))


def compose_remote():
    text = controller.REMOTE
    for before, after in (("old=base/'"+controller.PARENT+"'", "old=base/'"+PARENT+"'"),
        ("expected_manifest='"+controller.MANIFEST+"'", "expected_manifest='"+MANIFEST+"'"),
        ("expected_service='"+controller.UNIT_SHA+"'", "expected_service='"+UNIT_SHA+"'"),
        ("bundle_hash='"+controller.BUNDLE+"'", "bundle_hash='"+BUNDLE+"'")):
        text = controller.replace_once(text,before,after)
    text = text.replace(controller.RECIPE, RECIPE)
    text = controller.replace_once(text,"new=base/('20261111-ws4-lottery-rates-'", "new=base/('20261111-ws4-ur1-fifty-'")
    text = text.replace('ACTUAL_WS4_PREPARED_LOTTERY_RATES_PASS','ACTUAL_WS4_PREPARED_GOLD_UR1_FIFTY_PASS')
    anchor = "need(value.get('gold_pools_verified')==3 and value.get('map_unchanged') is True and value.get('exact_ssr_guarantee') is True,'lottery_probe_missing')"
    text = controller.replace_once(text,anchor,anchor+"\n need(value.get('ur50_guarantee') is True and value.get('cultivation_gate_removed') is True and value.get('real_lua_vectors',0)>=322,'ur50_probe_missing')")
    compile(text,'<ur50-pinned-rollout>','exec')
    return text


REMOTE = compose_remote()


def source_inputs(source_revision, operator_revision):
    pins = {}
    for name in OPERATOR_FILES:
        raw = git_blob(operator_revision,name)
        need(raw == (ROOT/name).read_bytes().replace(b'\r\n',b'\n'),'operator_worktree_drift')
        pins[name] = sha(raw)
    need(pins[PRIOR] == PRIOR_SHA,'audited_rollout_changed')
    need(sha(RECEIPT.read_bytes()) == RECEIPT_SHA,'candidate_receipt_changed')
    receipt = json.loads(RECEIPT.read_bytes())
    need(receipt['candidate_bundle_hash'] == BUNDLE and receipt['parent_bundle_hash'] == PARENT_BUNDLE,
         'candidate_binding_changed')
    raw = (ARTIFACT/'bundle.json').read_bytes()
    need(sha(raw) == BUNDLE,'candidate_bundle_changed')
    sources = {}
    for name,digest in receipt['source_sha256'].items():
        value = git_blob(source_revision,name)
        need(sha(value) == digest and value == (ROOT/name).read_bytes().replace(b'\r\n',b'\n'), 'source_worktree_drift')
        sources[name] = digest
    csvs = {key:git_blob(source_revision,builder.CSV_PREFIX+key+'.csv') for key in builder.CONFIGS}
    modules = {key:git_blob(source_revision,'scripts/vscripts/'+key) for key in builder.SOURCES}
    need(builder.derive((ROOT/'server/bundles'/PARENT_BUNDLE/'bundle.json').read_bytes(),csvs,modules) == raw,
         'candidate_reproduction_failed')
    payloads = {'addon/server/bundles/'+BUNDLE+'/'+p.relative_to(ARTIFACT).as_posix():p.read_bytes()
                for p in ARTIFACT.rglob('*') if p.is_file()}
    need(len(payloads) == 35,'candidate_file_set_changed')
    payloads['addon/server/bundles/current.json'] = (json.dumps({'hash':BUNDLE,'protocol':1},sort_keys=True,separators=(',',':'))+'\n').encode()
    binding = dict(recipe=RECIPE,source_revision=source_revision,parent_release=PARENT,
                   parent_manifest_sha256=MANIFEST,bundle=BUNDLE,parent_bundle=PARENT_BUNDLE,
                   payload_sha256={name:sha(data) for name,data in payloads.items()},
                   candidate_receipt_sha256=RECEIPT_SHA,configuration_changes=True,client_catalog_required=True)
    return payloads,binding,sources,pins


# This is a private module instance. Reuse only the frozen controller's command
# flow; every parent, payload, receipt, source and probe binding is replaced.
for key in ('TOOL','PROBE','PARENT','MANIFEST','UNIT_SHA','PARENT_BUNDLE','BUNDLE','RECIPE','RUN','ARTIFACT','RECEIPT','RECEIPT_SHA','OUT','OPERATOR_FILES','REMOTE','source_inputs'):
    setattr(controller,key,globals()[key])


if __name__ == '__main__': raise SystemExit(controller.main())
