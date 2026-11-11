"""Deploy the reviewed gold-pool bundle to WS4 with the existing drain and rollback controller.

The default action is a local plan. No draw, purchase, or player-account command is run.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOL = 'tools/ws4_lottery_rates_20261111/deploy.py'
PROBE = 'tools/ws4_lottery_rates_20261111/probe.py'
PRIOR = 'tools/ws4_redemption_transport_20261110/deploy.py'
PRIOR_SHA = '6075c112d085dee6f5f19d95fe097ff579bdb19c6ad07551fd533c4994d9c2c8'
PARENT = '20261110-ws4-redemption-transport-ae3e77c24300'
MANIFEST = '25d4ea97b6c1a91ba868a978a975873c87ea65a616ffc9ff088db420fbda5cd4'
UNIT_SHA = '112df06baeabf564d2c71586a003ac79c88c46c673252dab5f1ae77f0dcd9cd4'
PARENT_BUNDLE = 'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
BUNDLE = '98761e2a9386174e696fada8efdc2fc6891365dc661215b576b5f90f02fc8fac'
RECIPE = 'gold-pool-ur3-exact-ssr-ten-v1'
RUN = Path('D:/Survival_本地工具/runs/20261111_gold_pool_3pct01')
ARTIFACT = RUN / 'candidate' / BUNDLE
RECEIPT = RUN / 'candidate_receipt.json'
RECEIPT_SHA = '2e5b0c524102cfdb37b3781ea8e15ffb85d8ac62979ce759cc4500655da140c2'
OUT = RUN / 'server_deploy'
CONFIGS = ('lottery_quality_weights', 'lottery_pity_rules',
           'lottery_pool_definitions', 'lottery_pool_updates')
SOURCE_FILE = 'scripts/vscripts/systems/lottery_http_settlement.lua'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def need(ok, code):
    if not ok: raise RuntimeError(code)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), value.__dict__)
    return value


def git_blob(revision, path):
    need(bool(re.fullmatch('[a-f0-9]{40}', revision or '')), 'immutable_revision_required')
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(ROOT),
                                    'show', revision + ':' + path]).replace(b'\r\n', b'\n')


need(sha((ROOT / PRIOR).read_bytes().replace(b'\r\n', b'\n')) == PRIOR_SHA,
     'audited_parent_controller_changed')
prior = load('lottery_frozen_ws4_rollout', ROOT / PRIOR)
replace_once, replace_function = prior.replace_once, prior.replace_function


def compose_remote():
    text = prior.REMOTE
    start = text.index('need(old.is_dir() and not old.is_symlink()')
    end = text.index("control_root=base.parent/'deployment_records'", start)
    text = text[:start] + '''need(old.is_dir() and not old.is_symlink() and sha((old/'release_manifest.json').read_bytes())==expected_manifest,'ws4_parent_manifest_changed')
manifest=json.loads((old/'release_manifest.json').read_bytes())
need(json.loads((old/'addon/server/bundles/current.json').read_bytes())['hash']==PARENT_BUNDLE,'ws4_parent_bundle_changed')
payloads={name:base64.b64decode(value,validate=True) for name,value in PAYLOADS.items()}
pins={name:sha(raw) for name,raw in payloads.items()}
need(pins==PAYLOAD_PINS and pins==BINDING['payload_sha256'],'lottery_payload_binding_changed')
need(RECIPE=='gold-pool-ur3-exact-ssr-ten-v1' and BINDING['source_revision']==SOURCE,'lottery_source_binding_changed')
need(BINDING['parent_release']==old.name and BINDING['parent_manifest_sha256']==expected_manifest and BINDING['bundle']==bundle_hash,'lottery_parent_binding_changed')
need('addon/server/bundles/'+bundle_hash+'/bundle.json' in pins and 'addon/server/bundles/current.json' in pins,'lottery_bundle_payload_missing')
need(sha(payloads['addon/server/bundles/'+bundle_hash+'/bundle.json'])==bundle_hash,'lottery_bundle_hash_changed')
need(json.loads(payloads['addon/server/bundles/current.json'])['hash']==bundle_hash,'lottery_current_pointer_changed')
method_binding=BINDING
new=base/('20261111-ws4-lottery-rates-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE,source=SOURCE,operator=OPERATOR),sort_keys=True).encode())[:12])
''' + text[end:]
    text = replace_once(text, "old=base/'" + prior.PARENT + "'", "old=base/'" + PARENT + "'")
    text = replace_once(text, "expected_manifest='" + prior.MANIFEST + "'", "expected_manifest='" + MANIFEST + "'")
    text = replace_once(text, "expected_service='ec0748b94f3e7581b9271dc23c8ab0eb0f46a0901d796c6fcbca2b434b08c4b3'",
                        "expected_service='" + UNIT_SHA + "'")
    text = replace_once(text, "bundle_hash='" + prior.BUNDLE + "'", "bundle_hash='" + BUNDLE + "'")
    text = replace_function(text, 'candidate_manifest', '''def candidate_manifest(original):
 return {**manifest,'release':new.name,'files':{**original,**pins},
  'lottery_rates_parent_manifest_sha256':expected_manifest_digest,
  'lottery_rates_source_revision':SOURCE,'lottery_rates_operator_revision':OPERATOR,
  'lottery_rates_changed_files':sorted(pins),'lottery_rates_recipe':RECIPE,
  'lottery_rates_source_sha256':SOURCE_PINS,'lottery_rates_parent_inventory_sha256':sha(canonical(original)),
  'lottery_rates_parent_unit_sha256':UNIT_SHA,'lottery_rates_method_binding':method_binding,
  'archive_bundle':bundle_hash,'database_schema_or_config_changed':True,'startup_sync_policy_unchanged':True,
  'candidate_addon_root':str(new/'addon'),'addon_bytes_unchanged':False}
''')
    text = replace_function(text, 'verify_config_admission', '''def verify_config_admission():
 name='addon/server/bundles/'+bundle_hash+'/bundle.json'
 need(sha(safe(new,name).read_bytes())==bundle_hash,'lottery_bundle_bytes_changed')
 need(json.loads(safe(new,'addon/server/bundles/current.json').read_bytes())['hash']==bundle_hash,'lottery_pointer_bytes_changed')
 need(set(pins)==set(payloads) and len(pins)==36,'lottery_configuration_scope_changed')
 return dict(configuration_changed=True,sql_schema_changes=0,config_registration_expected=True)
''')
    text = replace_function(text, 'validate_probe', '''def validate_probe(original):
 value=json.loads(safe(records,'probe.json').read_bytes())
 need(value.get('ok') is True and value.get('status')=='ACTUAL_WS4_PREPARED_LOTTERY_RATES_PASS','exact_candidate_probe_required')
 need(value.get('binding')==control_binding(original),'probe_binding_changed')
 need(value.get('rpc_calls')==0 and value.get('database_writes')==0 and value.get('real_player_data_used') is False,'probe_isolation_changed')
 need(value.get('gold_pools_verified')==3 and value.get('map_unchanged') is True and value.get('exact_ssr_guarantee') is True,'lottery_probe_missing')
 need(value.get('changed_files')==sorted(pins),'lottery_probe_scope_changed')
 return value
''')
    text = text.replace('DAILY_REFS_V2', 'LOTTERY_RATES').replace('REDEMPTION_TRANSPORT', 'LOTTERY_RATES')
    need(text.count('config_unchanged_on_api_rollback=True') >= 2,
         'audited_rollback_status_anchor_changed')
    text = text.replace('config_unchanged_on_api_rollback=True',
                        'config_unchanged_on_api_rollback=False')
    need(text.count('config_registration_expected=False') >= 2,
         'audited_registration_status_anchor_changed')
    text = text.replace('config_registration_expected=False', 'config_registration_expected=True')
    need(text.count("result['config_unchanged_on_api_rollback']=True") == 2,
         'audited_recovery_status_anchor_changed')
    text = text.replace("result['config_unchanged_on_api_rollback']=True",
                        "result['config_unchanged_on_api_rollback']=False")
    compile(text, '<lottery-rates-remote>', 'exec')
    return text


REMOTE = compose_remote()
OPERATOR_FILES = tuple(dict.fromkeys((TOOL, PROBE, PRIOR) + prior.OPERATOR_FILES))


def source_inputs(source_revision, operator_revision):
    need(Path(__file__).resolve() == (ROOT / TOOL).resolve(), 'promote_reviewed_operator_before_remote')
    operator_pins = {}
    for name in OPERATOR_FILES:
        raw = git_blob(operator_revision, name)
        need(raw == (ROOT / name).read_bytes().replace(b'\r\n', b'\n'), 'operator_worktree_drift')
        operator_pins[name] = sha(raw)
    need(operator_pins[PRIOR] == PRIOR_SHA, 'audited_parent_controller_changed')
    need(sha(RECEIPT.read_bytes()) == RECEIPT_SHA, 'lottery_candidate_receipt_changed')
    receipt = json.loads(RECEIPT.read_bytes())
    need(receipt['parent_bundle_hash'] == PARENT_BUNDLE and receipt['candidate_bundle_hash'] == BUNDLE,
         'lottery_candidate_parent_changed')
    bundle_raw = (ARTIFACT / 'bundle.json').read_bytes()
    need(sha(bundle_raw) == BUNDLE, 'lottery_bundle_artifact_changed')
    bundle = json.loads(bundle_raw)
    source_pins = {}
    for key in CONFIGS:
        path = 'data/csv/抽奖系统/' + key + '.csv'
        raw = git_blob(source_revision, path)
        need(raw == (ROOT / path).read_bytes().replace(b'\r\n', b'\n'), 'lottery_source_worktree_drift')
        need(bundle['csv_hashes'][path] == sha(raw), 'lottery_bundle_csv_binding_changed')
        source_pins[path] = sha(raw)
    raw = git_blob(source_revision, SOURCE_FILE)
    need(raw == (ROOT / SOURCE_FILE).read_bytes().replace(b'\r\n', b'\n'), 'lottery_source_worktree_drift')
    need(bundle['sources']['systems/lottery_http_settlement.lua'].encode() == raw,
         'lottery_bundle_settlement_binding_changed')
    source_pins[SOURCE_FILE] = sha(raw)
    payloads = {'addon/server/bundles/' + BUNDLE + '/' + p.relative_to(ARTIFACT).as_posix(): p.read_bytes()
                for p in ARTIFACT.rglob('*') if p.is_file()}
    need(len(payloads) == 35, 'lottery_bundle_artifact_file_set_changed')
    payloads['addon/server/bundles/current.json'] = json.dumps({'hash': BUNDLE, 'protocol': 1},
                                                                 sort_keys=True, separators=(',', ':')).encode() + b'\n'
    pins = {name: sha(data) for name, data in payloads.items()}
    binding = dict(recipe=RECIPE, source_revision=source_revision, parent_release=PARENT,
                   parent_manifest_sha256=MANIFEST, bundle=BUNDLE, parent_bundle=PARENT_BUNDLE,
                   payload_sha256=pins, candidate_receipt_sha256=RECEIPT_SHA,
                   configuration_changes=True, client_catalog_required=True)
    return payloads, binding, source_pins, operator_pins


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='plan',
                        choices=('plan', 'audit', 'prepare', 'probe', 'activate', 'verify', 'rollback', 'recover'))
    parser.add_argument('--source-revision'); parser.add_argument('--operator-revision')
    parser.add_argument('--receipt-directory', type=Path)
    args = parser.parse_args(argv)
    if args.mode == 'plan':
        print(json.dumps(dict(status='WS4_LOTTERY_RATES_PLAN_NOT_EXECUTED', parent=PARENT,
                              parent_manifest_sha256=MANIFEST, candidate_bundle=BUNDLE,
                              phases=['audit', 'prepare', 'probe', 'activate', 'verify'], remote_actions=0)))
        return 0
    output = args.receipt_directory.resolve() if args.receipt_directory else OUT.resolve()
    need(output.parent == RUN.resolve() and output.name.startswith('server_deploy'),
         'receipt_directory_outside_reviewed_run')
    report = output / (args.mode + '.json')
    need(not report.exists(), 'preserve_existing_local_receipt')
    payloads, binding, source_pins, operator_pins = source_inputs(args.source_revision, args.operator_revision)
    audit = {} if args.mode == 'audit' else json.loads((output / 'audit.json').read_bytes())
    if audit:
        need(audit.get('ok') is True and audit.get('source_revision') == args.source_revision
             and audit.get('source_sha256') == source_pins and audit.get('payload_sha256') == binding['payload_sha256']
             and audit.get('operator_file_sha256') == operator_pins and audit.get('method_binding') == binding,
             'reviewed_audit_binding_changed')
    context = dict(MODE=args.mode, SOURCE=args.source_revision, OPERATOR=args.operator_revision,
                   SOURCE_PINS=source_pins, RECIPE=RECIPE, BINDING=binding,
                   PARENT_BUNDLE=PARENT_BUNDLE, PAYLOADS={name: base64.b64encode(raw).decode('ascii')
                                                           for name, raw in payloads.items()},
                   PAYLOAD_PINS=binding['payload_sha256'],
                   AUDITED_ADDON_ROOT='/opt/goufayu-ws4/releases/' + PARENT + '/addon',
                   UNIT_SHA=audit.get('unit_sha256'),
                   PARENT_INVENTORY_SHA=audit.get('parent_inventory_sha256'),
                   GATE_SOURCE=git_blob(args.operator_revision, prior.prior.prior.GATE_TOOL).decode('utf8'),
                   GATE_EXECUTABLE=audit.get('gate_environment', {}).get('executable'),
                   GATE_EXECUTABLE_SHA=audit.get('gate_environment', {}).get('executable_sha256'),
                   PROBE_SOURCE=git_blob(args.operator_revision, PROBE).decode('utf8'))
    recovery = '\n'.join(key + '=' + repr(value) for key, value in {**context, 'MODE': 'recover'}.items()) + '\n' + REMOTE
    context['WATCHDOG_RECOVERY_SOURCE'] = recovery
    remote = '\n'.join(key + '=' + repr(value) for key, value in context.items()) + '\n' + REMOTE
    need(sha(prior.prior.prior.TRANSPORT.read_bytes()) == prior.prior.prior.TRANSPORT_SHA, 'pinned_transport_changed')
    transport = load('lottery_pinned_transport', prior.prior.prior.TRANSPORT)
    result = transport.remote(remote, timeout=240)
    output.mkdir(parents=True, exist_ok=True)
    result['operator_file_sha256'] = operator_pins
    with report.open('x', encoding='utf8') as stream:
        json.dump(result, stream, sort_keys=True, indent=2); stream.write('\n')
    print(json.dumps(result)); return 0 if result.get('ok') is True else 2


if __name__ == '__main__': raise SystemExit(main())
