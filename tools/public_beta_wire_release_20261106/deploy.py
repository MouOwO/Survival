"""One immutable WS4 beta/profile-wire release; default plan has no remote action.

Reuses the exact audited drain/watchdog/recovery implementation. The previous
operator is never edited. Requires new Git source/operator commits before audit.
"""
from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TOOL = 'tools/public_beta_wire_release_20261106/deploy.py'
OLD_TOOL = 'tools/ws4_compact_receipt_20261106/deploy.py'
OLD_SHA = '9c970e2e7d3d44cec4d22e64536099b1d9256b223dc65158c2e77b1fc2ee7e9a'
GATE_TOOL = 'tools/ws4_compact_receipt_20261106/drain_gate.py'
GATE_SHA = '70f9cffbb2ede3c58eaf84fabb495bcc32dc20623371ec0617f832b478ec3446'
TRANSPORT = ROOT / 'tools/archive_release_20261029/server_deploy.py'
TRANSPORT_SHA = '66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
OUT = ROOT / 'output/public_beta_wire_release_20261106_v01'
SOURCE_AUDIT = ROOT / 'output/http_profile_refs_20261106/active_sources_02'
ADDON_AUDIT = ROOT / 'output/public_beta_0601_repair_20261106_v01/addon_root_audit_001.json'
PARENT_SOURCE = HERE / 'parent_sources'
CONFIG_TOOL = 'tools/public_beta_config_20261106/deploy.py'
CONFIG_VERIFY = ROOT / 'output/public_beta_config_20261106_v01/verify.json'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def need(ok, code):
    if not ok:
        raise RuntimeError(code)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


recipe = load('public_beta_wire_recipe', HERE / 'recipe.py')
old_raw = (ROOT / OLD_TOOL).read_bytes().replace(b'\r\n', b'\n')
need(sha(old_raw) == OLD_SHA, 'audited_prior_operator_changed')
legacy = load('frozen_prior_ws4_operator', ROOT / OLD_TOOL)


def replace_once(text, before, after):
    need(text.count(before) == 1, 'frozen_remote_anchor_changed')
    return text.replace(before, after, 1)


def replace_function(text, name, source):
    tree = ast.parse(text)
    found = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == name]
    need(len(found) == 1, 'frozen_remote_function_missing')
    node = found[0]
    lines = text.splitlines(keepends=True)
    lines[node.lineno - 1:node.end_lineno] = [source.rstrip() + '\n']
    return ''.join(lines)


def compose_remote():
    text = legacy.REMOTE
    start = text.index("need(old.is_dir() and not old.is_symlink()")
    finish = text.index("control_root=base.parent/'deployment_records'", start)
    # Business inputs are derived locally from immutable Git bytes and the
    # audited exact parent files, then re-bound to actual remote parent bytes.
    text = text[:start] + '''need(old.is_dir() and not old.is_symlink() and sha((old/'release_manifest.json').read_bytes())==expected_manifest,'ws4_parent_manifest_changed')
manifest=json.loads((old/'release_manifest.json').read_bytes())
need(json.loads((old/'addon/server/bundles/current.json').read_bytes())['hash']==PARENT_BUNDLE,'ws4_parent_bundle_changed')
need(sha(safe(old,'backend/archive_backend/service.py').read_bytes())==PARENT_SERVICE_SHA,'actual_parent_service_changed')
need(sha(safe(old,'backend/archive_backend/match_modes.py').read_bytes())==PARENT_MODES_SHA,'actual_parent_modes_changed')
for name,digest in PARENT_TIMING_PINS.items():need(sha(safe(old,name).read_bytes())==digest,'actual_parent_timing_source_changed')
payloads={name:base64.b64decode(value,validate=True) for name,value in PAYLOADS.items()}
pins={name:sha(raw) for name,raw in payloads.items()}
need(pins==PAYLOAD_PINS and BINDING['payload_sha256']==pins,'immutable_payload_binding_changed')
need(RECIPE=='public-beta-profile-wire-v1' and BINDING['source_revision']==SOURCE,'joint_recipe_source_changed')
need(set(name for name in payloads if name.startswith('backend/'))=={
 'backend/archive_backend/service.py','backend/archive_backend/public_beta_gift.py',
 'backend/archive_backend/http_profile_wire.py','backend/archive_backend/match_modes.py',
 'backend/archive_backend/http_request_timing.py','backend/fishing_api/server.py',
 'backend/fishing_api/postgres.py'},'joint_backend_scope_changed')
need(BINDING['config_admission']==CONFIG_BINDING and CONFIG_BINDING['source_bundle']==bundle_hash,'joint_config_admission_binding_changed')
need(sha(CONFIG_VERIFY_SQL.encode())==CONFIG_BINDING['artifacts']['verify.sql'],'joint_config_verify_sql_changed')
prefix='addon/server/bundles/'+bundle_hash+'/'
need(all(name.startswith('backend/') or name.startswith(prefix) or name in (
 'addon/server/bundles/current.json','addon/scripts/vscripts/config/generated/archive_http_bundle.lua') for name in payloads),'joint_addon_scope_changed')
need(sha(payloads[prefix+'bundle.json'])==bundle_hash,'joint_bundle_hash_changed')
new_document=json.loads(payloads[prefix+'bundle.json'])
need(new_document['public_beta_delivery']['parent_hash']==PARENT_BUNDLE,'joint_bundle_parent_changed')
need(json.loads(payloads['addon/server/bundles/current.json'])=={'hash':bundle_hash,'protocol':1},'joint_bundle_pointer_changed')
for name,raw in payloads.items():
 if name.endswith('.py'):compile(raw,name,'exec')
method_binding=BINDING
new=base/('20261106-ws4-public-beta-wire-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE,source=SOURCE,operator=OPERATOR),sort_keys=True).encode())[:12])
''' + text[finish:]
    text = replace_once(text, "old=base/'20261104-ws4-worker-cache-3f53908aaea0'", "old=base/'" + recipe.PARENT_RELEASE + "'")
    text = replace_once(text, "expected_manifest='39851557ce5d9c268c2deaa48b4be4697d8e3c04b10a52262566f371882481c2'", "expected_manifest='" + recipe.PARENT_MANIFEST + "'")
    text = replace_once(text, "expected_service='1e7a132537459c4436066555b1c58f9e7831d6d1e9b2c374f53f4b68c866c6e1'", "expected_service='" + recipe.PARENT_SERVICE + "'")
    text = replace_once(text, "bundle_hash='" + recipe.PARENT_BUNDLE + "'", "bundle_hash='" + recipe.NEW_BUNDLE + "'")
    text = text.replace('COMPACT_RECEIPT', 'PUBLIC_BETA_WIRE').replace('compact_receipt_', 'public_beta_wire_')
    text = replace_once(text, "'database_changed':False,", "'database_changed':None,'config_registration_expected':True,'archive_bundle':'" + recipe.NEW_BUNDLE + "','public_beta_wire_parent_bundle':'" + recipe.PARENT_BUNDLE + "',")
    text = text.replace('env_unchanged=True', 'unrelated_environment_unchanged=True,addon_root_override=True')
    text = text.replace("'addon_root_and_env_unchanged':True", "'unrelated_environment_unchanged':True,'addon_root_override':str(new/'addon')")
    text = replace_once(text, "parent_unit_sha256=UNIT_SHA,prepared_manifest_sha256=sha(canonical(candidate_manifest(original))),recipe=RECIPE)",
                        "parent_unit_sha256=UNIT_SHA,prepared_manifest_sha256=sha(canonical(candidate_manifest(original))),recipe=RECIPE,candidate_addon_root=str(new/'addon'),candidate_addon_environment_sha256=sha(addon_environment()))")
    text = replace_function(text, 'parent_inventory', '''def parent_inventory():
 entries=dict(manifest['files']);validate_files(old,entries)
 # Preserve all existing non-cache files, including parent-only runtime code.
 for directory,dirs,files in os.walk(old,followlinks=False):
  root=Path(directory)
  for name in list(dirs):
   path=root/name
   if path==old/'.venv' or name=='__pycache__':dirs.remove(name)
   else:need(not path.is_symlink(),'parent_directory_symlink_rejected')
  for name in files:
   if name=='release_manifest.json' and root==old or name.endswith('.pyc'):continue
   path=root/name;relative=path.relative_to(old).as_posix()
   need(not path.is_symlink(),'parent_file_symlink_rejected');entries[relative]=sha(safe(old,relative).read_bytes())
 return entries
''')
    text = replace_once(text, 'def canonical(value):', '''def verify_audited_addon(original):
 root=Path(AUDITED_ADDON_ROOT)
 need(root.is_absolute() and root.resolve()==root and root.name=='addon' and root.parent.parent==base,'audited_addon_root_outside_release_tree')
 expected={name[len('addon/'):]:digest for name,digest in original.items() if name.startswith('addon/')}
 need(bool(expected),'parent_addon_inventory_empty')
 if root==old/'addon':return dict(root=str(root),files=len(expected),identical_to_parent=True)
 actual=set()
 for directory,dirs,files in os.walk(root,followlinks=False):
  current=Path(directory)
  for name in list(dirs):
   path=current/name
   if name=='__pycache__':dirs.remove(name)
   else:need(not path.is_symlink(),'audited_addon_directory_symlink_rejected')
  for name in files:
   if name.endswith('.pyc'):continue
   path=current/name
   need(not path.is_symlink(),'audited_addon_file_symlink_rejected')
   actual.add(path.relative_to(root).as_posix())
 need(actual==set(expected),'actual_addon_file_set_differs_from_parent')
 validate_files(root,expected)
 return dict(root=str(root),files=len(expected),identical_to_parent=True)

def canonical(value):''')
    text = replace_once(text, ' original=parent_inventory()\n', ' original=parent_inventory()\n audited_addon_inventory=verify_audited_addon(original)\n')
    text = replace_once(text, 'def health():\n', '''def verify_config_admission():
 need(re.fullmatch(r'20261106-public-beta-config-[a-f0-9]{12}',CONFIG_BINDING.get('record_name','')) is not None,'config_record_binding_required')
 config_records=control_root/CONFIG_BINDING['record_name']
 need(control_root.is_dir() and not control_root.is_symlink() and config_records.is_dir() and not config_records.is_symlink(),'config_admission_records_required')
 need(json.loads(safe(config_records,'binding.json').read_bytes())==CONFIG_BINDING,'registered_config_binding_changed')
 proof=json.loads(safe(config_records,'verify.json').read_bytes())
 need(proof.get('ok') is True and proof.get('binding')==CONFIG_BINDING and proof.get('status')=='PUBLIC_BETA_CONFIG_ACTIVE_VERIFIED' and proof.get('config_registration_verified') is True and proof.get('read_only') is True and proof.get('database_writes')==0,'verified_config_admission_required')
 need(safe(config_records,'verify.sql').read_bytes()==CONFIG_VERIFY_SQL.encode(),'registered_config_verify_sql_changed')
 sql="BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\\nSET LOCAL statement_timeout='10000ms';\\nSET LOCAL lock_timeout='1000ms';\\n"+CONFIG_VERIFY_SQL+"\\nROLLBACK;\\nSELECT json_build_object('ok',true,'status','JOINT_CONFIG_ADMISSION_VERIFIED');\\n"
 args=['podman','exec','-i','--user','postgres','--env','PGPASSFILE=/dev/null','--env','PGSERVICEFILE=/dev/null','goufayu-ws4-db','psql','-X','-w','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','goufayu_ws4']
 process=subprocess.run(args,input=sql.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
 need(process.returncode==0,'joint_config_admission_readonly_check_failed')
 result=json.loads(process.stdout)
 need(result.get('ok') is True and result.get('status')=='JOINT_CONFIG_ADMISSION_VERIFIED','joint_config_admission_receipt_invalid')
 return dict(verified=True,new_bundle=CONFIG_BINDING['source_bundle'],function_sha256=CONFIG_BINDING['candidate_function_sha256'],database_writes=0)

def health():
''')
    text = replace_function(text, 'unit_pair', '''def addon_environment():
 return ('SURVIVAL_ADDON_ROOT='+str(new/'addon')+'\\n').encode()

def unit_pair():
 need(control_root.is_dir() and not control_root.is_symlink() and records.is_dir() and not records.is_symlink(),'independent_control_directory_missing')
 original_unit=safe(records,'unit.original').read_bytes();need(sha(original_unit)==UNIT_SHA,'original_unit_backup_changed')
 working=re.findall(rb'(?m)^\\s*WorkingDirectory=([^\\r\\n]+)',original_unit)
 need(working==[str(old/'backend').encode()],'original_unit_lineage_changed')
 need(not any(b'SURVIVAL_ADDON_ROOT=' in value for value in re.findall(rb'(?m)^\\s*ExecStart=([^\\r\\n]+)',original_unit)),'execstart_addon_override_requires_review')
 target_unit,count=re.subn(rb'(?m)^(\\s*WorkingDirectory=)[^\\r\\n]+',lambda m:m[1]+str(new/'backend').encode(),original_unit)
 need(count==1,'unit_workdir_anchor_changed')
 target_unit=target_unit.rstrip()+b'\\n\\n[Service]\\nEnvironmentFile='+str(records/'candidate-addon.env').encode()+b'\\n'
 return original_unit,target_unit
''')
    text = replace_once(text, "need(new.is_dir() and not new.is_symlink(),'prepared_ws4_release_missing')", "need(new.is_dir() and not new.is_symlink(),'prepared_ws4_release_missing')\n need(safe(records,'candidate-addon.env').read_bytes()==addon_environment(),'candidate_addon_environment_changed')")
    text = replace_once(text, "records.mkdir(mode=0o700)", "records.mkdir(mode=0o700)\n   with (records/'candidate-addon.env').open('xb') as stream:stream.write(addon_environment());stream.flush();os.fsync(stream.fileno())\n   (records/'candidate-addon.env').chmod(0o600)")
    text = replace_function(text, 'validate_probe', '''def validate_probe(original):
 value=json.loads(safe(records,'probe.json').read_bytes())
 need(value.get('ok') is True and value.get('status')=='ACTUAL_WS4_PREPARED_PUBLIC_BETA_WIRE_PARITY_PASS','exact_candidate_probe_required')
 need(value.get('binding')==control_binding(original),'probe_binding_changed')
 need(value.get('rpc_calls')==0 and value.get('database_writes')==0 and value.get('real_player_data_used') is False,'probe_isolation_changed')
 checks=value.get('checks',{})
 need(checks.get('beta',{}).get('exact_two') is True and checks['beta'].get('replay_unchanged') is True and checks['beta'].get('second_claim_rejected') is True and checks['beta'].get('wrong_session_rejected') is True,'beta_probe_missing')
 need(checks.get('ordinary',{}).get('old_hash_success') is True and checks['ordinary'].get('replay_unchanged') is True,'legacy_benefit_probe_missing')
 draws=checks.get('lottery',[]);need(len(draws)==3 and all(row.get('equal') is True for row in draws),'lottery_probe_missing')
 for row in draws:
  need(all(row.get(kind,{}).get('real_rpc_calls')==0 for kind in ('parent','legacy','compact')),'probe_real_rpc_rejected')
 need(checks.get('wire',{}).get('real_lua_vectors')==4 and checks['wire'].get('legacy_unchanged') is True,'wire_probe_missing')
 return value
''')
    # Health verifies the active process's actual environment and correct
    # release-specific bundle, including rollback to the old bundle hash.
    text = replace_once(text, 'def health():\n', '''def actual_addon_root(pid):
 with Path('/proc/%d/environ'%pid).open('rb') as stream:raw=stream.read(1048577)
 need(len(raw)<=1048576,'environment_read_budget')
 prefix=b'SURVIVAL_ADDON_ROOT='
 values=[row[len(prefix):] for row in raw.split(b'\\0') if row.startswith(prefix)]
 need(len(values)==1,'explicit_addon_root_required')
 return Path(values[0].decode()).resolve()

def health():
 release,current_state=observed()
 expected_root=new/'addon' if release==new else Path(AUDITED_ADDON_ROOT)
 need(release in (old,new) and current_state['pid']>0 and actual_addon_root(current_state['pid'])==expected_root,'active_addon_root_mismatch')
 expected_hash=bundle_hash if release==new else PARENT_BUNDLE
''')
    text = replace_once(text, "value.get('config_hash')==bundle_hash", "value.get('config_hash')==expected_hash")
    text = replace_once(text, "need(current==old and pid>0,'ws4_parent_not_active')", "need(current==old and pid>0,'ws4_parent_not_active')\n  need(actual_addon_root(pid)==Path(AUDITED_ADDON_ROOT),'audited_addon_root_changed')\n  need(json.loads((Path(AUDITED_ADDON_ROOT)/'server/bundles/current.json').read_bytes())['hash']==PARENT_BUNDLE,'actual_parent_bundle_changed')")
    text = replace_once(text, "source_revision=SOURCE,source_sha256=SOURCE_PINS,recipe=RECIPE,parent_full_inventory_verified=True,", "source_revision=SOURCE,source_sha256=SOURCE_PINS,recipe=RECIPE,parent_full_inventory_verified=True,audited_addon_root=AUDITED_ADDON_ROOT,audited_addon_inventory=audited_addon_inventory,")
    text = replace_once(text, "payload_sha256=pins,api_pid=live_state['pid'],", "payload_sha256=pins,api_pid=live_state['pid'],config_registration_expected=True,")
    text = replace_once(text, "\n   database_writes=0,unrelated_environment_unchanged=True", "\n   database_writes=None,unrelated_environment_unchanged=True")
    text = replace_once(text, "api_pid=pid,database_writes=0,unrelated_environment_unchanged=True", "api_pid=pid,database_writes=None,config_registration_expected=True,unrelated_environment_unchanged=True")
    text = replace_once(text, "   if MODE=='activate':\n    result=activate_candidate(original,current,service_state,unit_raw)", "   if MODE=='activate':\n    config_admission=verify_config_admission()\n    result=activate_candidate(original,current,service_state,unit_raw)\n    result['config_admission']=config_admission\n    result['config_retained_on_api_rollback']=True")
    text = replace_once(text, "   elif MODE=='verify':\n", "   elif MODE=='verify':\n    config_admission=verify_config_admission()\n")
    text = replace_once(text, "status='ACTUAL_WS4_PUBLIC_BETA_WIRE_ACTIVE_VERIFIED',release=new.name,", "status='ACTUAL_WS4_PUBLIC_BETA_WIRE_ACTIVE_VERIFIED',release=new.name,config_admission=config_admission,")
    text = replace_once(text, 'def record_recovery(result):\n', "def record_recovery(result):\n result['config_retained_on_api_rollback']=True\n")
    text = text.replace('candidate_files_not_required=True,database_writes=0)', 'candidate_files_not_required=True,database_writes=None,config_retained_on_api_rollback=True)')
    start = text.index("    sys.path.insert(0,str(new/'backend'))", text.index("elif MODE=='probe':"))
    finish = text.index("   elif MODE=='verify':", start)
    text = text[:start] + '''    namespace={'__name__':'immutable_joint_ws4_probe'}
    exec(compile(PROBE_SOURCE,'immutable_joint_ws4_probe','exec'),namespace)
    result=namespace['run'](old,new,PARENT_BUNDLE,bundle_hash,LUA_DECODER_SOURCE,LUA_VECTOR_RUNNER)
    validate_candidate(original);result['binding']=binding
''' + text[finish:]
    compile(text, '<joint-ws4-remote>', 'exec')
    return text


REMOTE = compose_remote()
OPERATOR_FILES = (TOOL, 'tools/public_beta_wire_release_20261106/recipe.py',
                  'tools/public_beta_wire_release_20261106/probe.py',
                  'tools/public_beta_wire_release_20261106/http_timing_patch.py',
                  'tools/public_beta_bundle_20261106/build.py',
                  'tools/public_beta_bundle_20261106/service_patch.py', OLD_TOOL, GATE_TOOL,
                  'tools/test_http_profile_wire.lua', CONFIG_TOOL,
                  'tools/public_beta_config_20261106/recipe.py',
                  'tools/public_beta_config_20261106/archive_sync_config.parent.sql') + tuple(
                      'tools/public_beta_wire_release_20261106/parent_sources/' + name for name in
                      ('service.py', 'match_modes.py', 'server.py', 'postgres.py', 'supabase.py'))


def source_inputs(source_revision, operator_revision):
    operator_pins = {}
    for name in OPERATOR_FILES:
        raw = recipe.git_blob(operator_revision, name)
        need(raw == (ROOT / name).read_bytes().replace(b'\r\n', b'\n'), 'operator_worktree_drift')
        operator_pins[name] = sha(raw)
    need(operator_pins[OLD_TOOL] == OLD_SHA and operator_pins[GATE_TOOL] == GATE_SHA, 'reviewed_gate_operator_changed')
    audited = json.loads((SOURCE_AUDIT / 'audit.json').read_bytes())
    need(audited.get('release') == recipe.PARENT_RELEASE and audited.get('manifest_sha256') == recipe.PARENT_MANIFEST,
         'actual_parent_source_audit_required')
    modes_name = 'backend/archive_backend/match_modes.py'
    modes_sha = audited['source_files'][modes_name]['sha256']
    parent_source_binding = {}
    # Once per operator invocation: O(the four source byte lengths), eight
    # local reads, no runtime polling or extra network/database calls. Retain
    # the audited raw identity even when Git stores that source with LF.
    for name, key in (('match_modes.py',modes_name),('server.py','backend/fishing_api/server.py'),
                      ('postgres.py','backend/fishing_api/postgres.py'),('supabase.py','backend/fishing_api/supabase.py')):
        actual_raw = (SOURCE_AUDIT / key).read_bytes()
        actual_sha = sha(actual_raw)
        need(actual_sha == audited['source_files'][key]['sha256'], 'audited_parent_source_raw_mismatch')
        git_lf = (PARENT_SOURCE / name).read_bytes().replace(b'\r\n', b'\n')
        need(git_lf == actual_raw.replace(b'\r\n', b'\n'), 'frozen_parent_source_audit_mismatch')
        parent_source_binding[key] = dict(audited_raw_sha256=actual_sha,
                                         git_lf_sha256=sha(git_lf), normalization='crlf_to_lf')
    paths = json.loads(ADDON_AUDIT.read_bytes())
    need(paths.get('ok') is True and paths.get('release') == recipe.PARENT_RELEASE
         and paths.get('addon_root_present') is True and not paths.get('execstart_contains_addon_root_override'),
         'actual_addon_path_audit_required')
    payloads, binding = recipe.payloads(source_revision, (PARENT_SOURCE/'service.py').read_bytes(),
                                        (PARENT_SOURCE/'match_modes.py').read_bytes(), modes_sha,
                                        (PARENT_SOURCE/'server.py').read_bytes(), (PARENT_SOURCE/'postgres.py').read_bytes())
    configuration = load('joint_exact_config_deploy', ROOT / CONFIG_TOOL)
    config_artifacts, config_binding = configuration.inputs(source_revision, operator_revision)
    binding['config_admission'] = config_binding
    # Provenance only; the raw audited files are not extra runtime payloads.
    binding['audited_parent_sources'] = parent_source_binding
    source_pins = {name: sha(recipe.git_blob(source_revision, name)) for name in (
        'server/archive_backend/service.py', 'server/archive_backend/public_beta_gift.py',
        'server/archive_backend/match_modes.py', 'server/archive_backend/http_profile_wire.py',
        'server/archive_backend/http_request_timing.py',
        'scripts/vscripts/systems/http_profile_wire.lua',
        'scripts/vscripts/config/generated/archive_http_bundle.lua',
        'server/bundles/' + recipe.NEW_BUNDLE + '/bundle.json')}
    return payloads, binding, source_pins, operator_pins, modes_sha, paths['addon_root_resolved'], config_artifacts, config_binding


def plan():
    return dict(status='JOINT_WS4_PUBLIC_BETA_PROFILE_WIRE_PLAN_NOT_EXECUTED',
                parent_release=recipe.PARENT_RELEASE, parent_manifest_sha256=recipe.PARENT_MANIFEST,
                new_bundle=recipe.NEW_BUNDLE, backend_files=7, sql_changes='separate exact config admission, verified before activation',
                addon_root_override='SURVIVAL_ADDON_ROOT -> new release/addon',
                phases=['audit', 'prepare', 'probe', 'activate', 'verify'],
                recovery=['explicit rollback', 'controller watchdog'],
                requires=['immutable source/operator commits', 'actual match_modes source audit',
                               'actual addon-root path audit', 'full source payloads and client binding',
                               'exact new-bundle config admission audit and registration',
                               'joint deployment safety and probe tests'], remote_actions=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='plan', choices=('plan','audit','prepare','probe','activate','verify','rollback','recover'))
    parser.add_argument('--source-revision')
    parser.add_argument('--operator-revision')
    args = parser.parse_args()
    if args.mode == 'plan':
        result = plan()
        if args.source_revision is not None or args.operator_revision is not None:
            values = source_inputs(args.source_revision, args.operator_revision)
            payloads, binding, source_pins, operator_pins = values[:4]
            result.update(immutable_source_verified=True, binding=binding,
                          payload_files=len(payloads), payload_bytes=sum(map(len,payloads.values())),
                          source_sha256=source_pins, operator_sha256=operator_pins)
        print(json.dumps(result, ensure_ascii=False, indent=2)); return 0
    report = OUT / (args.mode + '.json')
    need(not report.exists(), 'preserve_existing_local_receipt')
    payloads, binding, source_pins, operator_pins, modes_sha, addon_root, config_artifacts, config_binding = source_inputs(args.source_revision, args.operator_revision)
    if args.mode in ('activate','verify'):
        proof = json.loads(CONFIG_VERIFY.read_bytes())
        need(proof.get('ok') is True and proof.get('status')=='PUBLIC_BETA_CONFIG_ACTIVE_VERIFIED'
             and proof.get('binding')==config_binding and proof.get('config_registration_verified') is True
             and proof.get('read_only') is True and proof.get('database_writes')==0,
             'local_exact_config_verification_required')
    audit = {} if args.mode == 'audit' else json.loads((OUT / 'audit.json').read_bytes())
    if audit:
        need(audit.get('ok') is True and audit.get('source_revision') == args.source_revision
             and audit.get('source_sha256') == source_pins and audit.get('payload_sha256') == binding['payload_sha256']
             and audit.get('operator_file_sha256')==operator_pins and audit.get('method_binding')==binding,
             'reviewed_audit_binding_changed')
    context = dict(MODE=args.mode, SOURCE=args.source_revision, OPERATOR=args.operator_revision,
                   SOURCE_PINS=source_pins, RECIPE=recipe.RECIPE, BINDING=binding,
                   PARENT_BUNDLE=recipe.PARENT_BUNDLE, PARENT_SERVICE_SHA=recipe.PARENT_SERVICE,
                   PARENT_MODES_SHA=modes_sha, AUDITED_ADDON_ROOT=addon_root,
                   PARENT_TIMING_PINS={name: binding['http_timing'][key] for name,key in (
                       ('backend/fishing_api/server.py','parent_server_sha256'),
                       ('backend/fishing_api/postgres.py','parent_postgres_sha256'))},
                   CONFIG_BINDING=config_binding, CONFIG_VERIFY_SQL=config_artifacts['verify.sql'].decode('utf8'),
                   PAYLOADS={name: base64.b64encode(raw).decode('ascii') for name,raw in payloads.items()},
                   PAYLOAD_PINS=binding['payload_sha256'], UNIT_SHA=audit.get('unit_sha256'),
                   PARENT_INVENTORY_SHA=audit.get('parent_inventory_sha256'),
                   GATE_SOURCE=recipe.git_blob(args.operator_revision,GATE_TOOL).decode('utf8'),
                   GATE_EXECUTABLE=audit.get('gate_environment',{}).get('executable'),
                   GATE_EXECUTABLE_SHA=audit.get('gate_environment',{}).get('executable_sha256'),
                   PROBE_SOURCE=recipe.git_blob(args.operator_revision,'tools/public_beta_wire_release_20261106/probe.py').decode('utf8'),
                   LUA_DECODER_SOURCE=recipe.git_blob(args.source_revision,'scripts/vscripts/systems/http_profile_wire.lua').decode('utf8'),
                   LUA_VECTOR_RUNNER=recipe.git_blob(args.operator_revision,'tools/test_http_profile_wire.lua').decode('utf8'))
    recovery = '\n'.join(key+'='+repr(value) for key,value in {**context,'MODE':'recover'}.items())+'\n'+REMOTE
    context['WATCHDOG_RECOVERY_SOURCE'] = recovery
    remote = '\n'.join(key+'='+repr(value) for key,value in context.items())+'\n'+REMOTE
    need(sha(TRANSPORT.read_bytes()) == TRANSPORT_SHA, 'pinned_transport_changed')
    transport = load('joint_ws4_transport', TRANSPORT)
    result = transport.remote(remote, timeout=240)
    OUT.mkdir(parents=True, exist_ok=True)
    result['operator_file_sha256'] = operator_pins
    with report.open('x', encoding='utf8') as stream:
        json.dump(result, stream, ensure_ascii=False, sort_keys=True, indent=2); stream.write('\n')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get('ok') is True else 2


if __name__ == '__main__':
    raise SystemExit(main())
