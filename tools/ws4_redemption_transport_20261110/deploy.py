"""Exact one-file WS4 redemption transport repair; default is local plan only.

Reuse the pinned rollout's drain, watchdog and exact recovery. No client build,
SQL, code registration, payment/auth update or real-player redemption occurs.
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
TOOL = 'tools/ws4_redemption_transport_20261110/deploy.py'
PROBE = 'tools/ws4_redemption_transport_20261110/probe.py'
PRIOR = 'tools/ws4_daily_refs_20261106/deploy.py'
PRIOR_SHA = '99b6f27216e4f327f8d0b95e3a2ba7e2a67eac392c5d872a748a20b699c06276'
PARENT = '20261106-ws4-daily-refs-ed532ea60d2b'
MANIFEST = '839fa42cf775453bf90807b5b4eeb5d714a7a821f4cbfddd0046e015a927f106'
BUNDLE = 'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
PARENT_MODULE = '2d469e089f0a8f6602dfbf68e15696c4c790444f07dde53ced1752b08d33c178'
SOURCE_FILE = 'server/archive_backend/redemption_codes.py'
TARGET = 'backend/archive_backend/redemption_codes.py'
RECIPE = 'redemption-response-capabilities-v1'
OUT = ROOT / 'output/ws4_redemption_transport_20261110_v01'


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
prior = load('redemption_frozen_rollout', ROOT / PRIOR)
replace_once, replace_function = prior.replace_once, prior.replace_function


def compose_remote():
    text = prior.REMOTE
    start = text.index('need(old.is_dir() and not old.is_symlink()')
    end = text.index("control_root=base.parent/'deployment_records'", start)
    text = text[:start] + '''need(old.is_dir() and not old.is_symlink() and sha((old/'release_manifest.json').read_bytes())==expected_manifest,'ws4_parent_manifest_changed')
manifest=json.loads((old/'release_manifest.json').read_bytes())
need(json.loads((old/'addon/server/bundles/current.json').read_bytes())['hash']==PARENT_BUNDLE,'ws4_parent_bundle_changed')
need(sha(safe(old,TARGET).read_bytes())==PARENT_MODULE_SHA,'actual_parent_redemption_changed')
payloads={name:base64.b64decode(value,validate=True) for name,value in PAYLOADS.items()}
pins={name:sha(raw) for name,raw in payloads.items()}
need(set(payloads)=={TARGET} and pins==PAYLOAD_PINS and pins==BINDING['payload_sha256'],'exact_one_redemption_file_required')
need(RECIPE=='redemption-response-capabilities-v1' and BINDING['source_revision']==SOURCE,'redemption_source_binding_changed')
need(BINDING['parent_release']==old.name and BINDING['parent_manifest_sha256']==expected_manifest and BINDING['bundle']==bundle_hash,'redemption_parent_binding_changed')
need(sha(payloads[TARGET])!=PARENT_MODULE_SHA,'redemption_change_required')
compile(payloads[TARGET],TARGET,'exec')
method_binding=BINDING
new=base/('20261110-ws4-redemption-transport-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE,source=SOURCE,operator=OPERATOR),sort_keys=True).encode())[:12])
''' + text[end:]
    text = replace_once(text, "old=base/'" + prior.PARENT + "'", "old=base/'" + PARENT + "'")
    text = replace_once(text, "expected_manifest='" + prior.MANIFEST + "'", "expected_manifest='" + MANIFEST + "'")
    text = replace_function(text, 'verify_config_admission', '''def verify_config_admission():
 need(bundle_hash==PARENT_BUNDLE and set(pins)=={TARGET},'redemption_configuration_scope_changed')
 name='addon/server/bundles/'+bundle_hash+'/bundle.json'
 need(sha(safe(old,name).read_bytes())==bundle_hash and sha(safe(new,name).read_bytes())==bundle_hash,'redemption_bundle_bytes_changed')
 return dict(configuration_unchanged=True,sql_changes=0)
''')
    text = replace_function(text, 'validate_probe', '''def validate_probe(original):
 value=json.loads(safe(records,'probe.json').read_bytes())
 need(value.get('ok') is True and value.get('status')=='ACTUAL_WS4_PREPARED_REDEMPTION_TRANSPORT_PARITY_PASS','exact_candidate_probe_required')
 need(value.get('binding')==control_binding(original),'probe_binding_changed')
 need(value.get('rpc_calls')==0 and value.get('database_writes')==0 and value.get('real_player_data_used') is False,'probe_isolation_changed')
 need(value.get('parent_failure_reproduced') is True and value.get('real_lua_vectors',0)>=16 and value.get('malformed_vectors',0)>=11,'redemption_probe_missing')
 need(value.get('changed_files')==[TARGET] and value.get('bundle_unchanged') is True,'redemption_probe_scope_changed')
 return value
''')
    text = replace_once(text, "result=namespace['run'](old,new,bundle_hash,LUA_DECODER_SOURCE,LUA_VECTOR_RUNNER)",
                        "result=namespace['run'](old,new,bundle_hash)")
    text = text.replace('DAILY_REFS_V2', 'REDEMPTION_TRANSPORT').replace('daily_refs_v2_', 'redemption_transport_')
    compile(text, '<redemption-transport-remote>', 'exec')
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
    raw = git_blob(source_revision, SOURCE_FILE)
    need(raw == (ROOT / SOURCE_FILE).read_bytes().replace(b'\r\n', b'\n'), 'runtime_source_worktree_drift')
    compile(raw, SOURCE_FILE, 'exec')
    need(b'RESPONSE_CAPABILITIES' in raw and sha(raw) != PARENT_MODULE, 'reviewed_transport_repair_required')
    pins = {TARGET: sha(raw)}
    binding = dict(recipe=RECIPE, source_revision=source_revision, parent_release=PARENT,
                   parent_manifest_sha256=MANIFEST, parent_module_sha256=PARENT_MODULE,
                   bundle=BUNDLE, payload_sha256=pins, sql_changes=False,
                   configuration_changes=False, only_one_runtime_file=True,
                   client_changes=False, new_codes_registered=False)
    return {TARGET: raw}, binding, {SOURCE_FILE: sha(raw)}, operator_pins


def plan():
    return dict(status='REDEMPTION_TRANSPORT_PLAN_NOT_EXECUTED', parent_release=PARENT,
                parent_manifest_sha256=MANIFEST, bundle_unchanged=BUNDLE,
                changed_runtime_files=[TARGET], remote_actions=0, client_changes=False,
                phases=['audit', 'prepare', 'probe', 'activate', 'verify'],
                rollback='exact retained parent unit/release with existing drain/watchdog')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='plan',
                        choices=('plan', 'audit', 'prepare', 'probe', 'activate', 'verify', 'rollback', 'recover'))
    parser.add_argument('--source-revision'); parser.add_argument('--operator-revision')
    args = parser.parse_args(argv)
    if args.mode == 'plan':
        print(json.dumps(plan(), indent=2)); return 0
    report = OUT / (args.mode + '.json')
    need(not report.exists(), 'preserve_existing_local_receipt')
    payloads, binding, source_pins, operator_pins = source_inputs(args.source_revision, args.operator_revision)
    audit = {} if args.mode == 'audit' else json.loads((OUT / 'audit.json').read_bytes())
    if audit:
        need(audit.get('ok') is True and audit.get('source_revision') == args.source_revision
             and audit.get('source_sha256') == source_pins and audit.get('payload_sha256') == binding['payload_sha256']
             and audit.get('operator_file_sha256') == operator_pins and audit.get('method_binding') == binding,
             'reviewed_audit_binding_changed')
    context = dict(MODE=args.mode, SOURCE=args.source_revision, OPERATOR=args.operator_revision,
                   SOURCE_PINS=source_pins, RECIPE=RECIPE, BINDING=binding,
                   PARENT_BUNDLE=BUNDLE, TARGET=TARGET, PARENT_MODULE_SHA=PARENT_MODULE,
                   AUDITED_ADDON_ROOT='/opt/goufayu-ws4/releases/' + PARENT + '/addon',
                   PAYLOADS={name: base64.b64encode(raw).decode('ascii') for name, raw in payloads.items()},
                   PAYLOAD_PINS=binding['payload_sha256'], UNIT_SHA=audit.get('unit_sha256'),
                   PARENT_INVENTORY_SHA=audit.get('parent_inventory_sha256'),
                   GATE_SOURCE=git_blob(args.operator_revision, prior.prior.GATE_TOOL).decode('utf8'),
                   GATE_EXECUTABLE=audit.get('gate_environment', {}).get('executable'),
                   GATE_EXECUTABLE_SHA=audit.get('gate_environment', {}).get('executable_sha256'),
                   PROBE_SOURCE=git_blob(args.operator_revision, PROBE).decode('utf8'))
    recovery = '\n'.join(key + '=' + repr(value) for key, value in {**context, 'MODE': 'recover'}.items()) + '\n' + REMOTE
    context['WATCHDOG_RECOVERY_SOURCE'] = recovery
    remote = '\n'.join(key + '=' + repr(value) for key, value in context.items()) + '\n' + REMOTE
    need(sha(prior.prior.TRANSPORT.read_bytes()) == prior.prior.TRANSPORT_SHA, 'pinned_transport_changed')
    transport = load('redemption_pinned_transport', prior.prior.TRANSPORT)
    result = transport.remote(remote, timeout=240)
    OUT.mkdir(parents=True, exist_ok=True)
    result['operator_file_sha256'] = operator_pins
    with report.open('x', encoding='utf8') as stream:
        json.dump(result, stream, sort_keys=True, indent=2); stream.write('\n')
    print(json.dumps(result)); return 0 if result.get('ok') is True else 2


if __name__ == '__main__': raise SystemExit(main())
