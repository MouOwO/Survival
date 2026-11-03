"""Explicit isolated gb/d sizing sweep. Preparation never starts a game.

The operator separately invokes launch/close. Only an unchanged normal map VPK
and a minimal Activate Lua script are mounted; no project or backend is loaded.
Native results require the entire normally closed log, not an envelope estimate.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, math, re, shutil, subprocess, time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('n50_base', Path(__file__).with_name('network50_native_probe_20261103.py'))
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)
STORE = Path('D:/Survival_本地排演/network50_probe_20261103/bulk02')
LAB = STORE / 'addon'
MOUNT = ROOT.parent / 'svt_network50_bulk'
LOG = ROOT / 'output/network50_native_probe_20261103/bulk02/engine.log'
DEST = LOG.parent / 'native_budget.json'
EXPECTED = (64, 128, 256, 512, 896)
SOURCE = '''function Precache(context) end
function Activate()
    if not IsInToolsMode() or GetMapName()~="template_map" then return end
    local started, index, announced=Time(),1,false
    local sizes={64,128,256,512,896}
    GameRules:GetGameModeEntity():SetContextThink("n50_gb_packet_probe",function()
        if Time()-started>60 then print("[N50_GB_PROBE] NO_PLAYER");return nil end
        local player=PlayerResource:GetPlayer(0)
        if not player then return 0.1 end
        if not announced then
            announced=true
            print("[N50_GB_PROBE] BEGIN event=gb key=d")
            return 1
        end
        local n=sizes[index]
        print("[N50_GB_PROBE] SEND value_ascii_bytes="..n)
        CustomGameEventManager:Send_ServerToPlayer(player,"gb",{d=string.rep("A",n)})
        index=index+1
        if index>#sizes then print("[N50_GB_PROBE] END sends=5 transactions=0");return nil end
        return 0.25
    end,0)
end
'''
ADDON_INFO = b'"AddonInfo"\n{\n "addon_title" "Isolated gb native sizing"\n "addon_type" "1"\n "maps" "template_map"\n "max_players" "1"\n}\n'


def file_sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def json_new(path, value):
    p.write_new(path, (json.dumps(value, indent=2, ensure_ascii=True)+'\n').encode())


def plan():
    return dict(status='ISOLATED_GB_PLAN_NO_ACTIONS', external_lab=str(LAB), mount=str(MOUNT),
                log=str(LOG), event='gb', key='d', value_lengths=list(EXPECTED),
                source_sha256=p.sha(SOURCE.encode()), transactions=0, sdk_calls=0,
                launch_argv=[str(p.EXE), '-steam', '-tools', '-noassetbrowser', '-dev', '-addon', MOUNT.name,
                             '-novid', '-console', '-vconsole', '-vconport', '29068', '-condebug',
                             '-con_logfile', str(LOG), '+sv_cheats', '1', '+net_showmsg',
                             'CUserMsg_CustomGameEvent', '+net_restrict_showmsg_socket', 'client',
                             '+dota_launch_custom_game', MOUNT.name, 'template_map'])


def prepare():
    if p.clients():
        raise ValueError('existing_client_preserved_no_mount_changes')
    parent = Path('D:/Survival_本地排演/network50_probe_20261103').resolve()
    if STORE.resolve().parent != parent or MOUNT.parent.resolve() != ROOT.parent.resolve():
        raise ValueError('fixed_external_namespace_required')
    if STORE.exists() or MOUNT.exists() or LOG.exists() or DEST.exists():
        raise ValueError('fresh_bulk02_namespace_required_preserve_existing')
    source_map = ROOT / 'maps/template_map.vpk'
    if not source_map.is_file() or not p.EXE.is_file():
        raise ValueError('official_executable_and_normal_map_required')
    LAB.mkdir(parents=True)
    p.write_new(LAB/'addoninfo.txt', ADDON_INFO)
    p.write_new(LAB/'scripts/vscripts/addon_game_mode.lua', SOURCE.encode())
    target = LAB / 'maps/template_map.vpk'
    target.parent.mkdir()
    shutil.copyfile(source_map, target)
    digest = file_sha(source_map)
    if file_sha(target) != digest:
        raise ValueError('normal_map_copy_digest_mismatch')
    # Both paths are fixed, independently checked above; no shell interpolation
    # of user text and no moves/deletions or production directory changes.
    command = "New-Item -ItemType Junction -Path '"+str(MOUNT)+"' -Target '"+str(LAB)+"' | Out-Null"
    subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', command], check=True)
    if MOUNT.resolve() != LAB.resolve():
        raise ValueError('isolated_junction_target_mismatch')
    result = plan()
    result.update(status='ISOLATED_GB_PREPARED_NOT_LAUNCHED', normal_map_sha256=digest,
                  executable_sha256=file_sha(p.EXE), networksystem_sha256=file_sha(p.GAME/'bin/win64/networksystem.dll'),
                  workshop_install_written=False, processes_started=0, files_removed=0,
                  ordinary_production_acceptance=False, backend_imports=False)
    json_new(STORE/'prepared.json', result)
    return result


def verify():
    result = json.loads((STORE/'prepared.json').read_bytes())
    if result.get('status') != 'ISOLATED_GB_PREPARED_NOT_LAUNCHED' or result.get('launch_argv') != plan()['launch_argv']:
        raise ValueError('exact_prepared_bulk02_receipt_required')
    if MOUNT.resolve() != LAB.resolve():
        raise ValueError('prepared_mount_drift')
    if (LAB/'addoninfo.txt').read_bytes() != ADDON_INFO or (LAB/'scripts/vscripts/addon_game_mode.lua').read_bytes() != SOURCE.encode():
        raise ValueError('prepared_minimal_source_drift')
    for path, key in ((LAB/'maps/template_map.vpk', 'normal_map_sha256'), (p.EXE, 'executable_sha256'),
                      (p.GAME/'bin/win64/networksystem.dll', 'networksystem_sha256')):
        if file_sha(path) != result[key]:
            raise ValueError('prepared_artifact_drift:'+key)
    return result


def launch():
    prepared = verify()
    if p.clients():
        raise ValueError('existing_client_preserved')
    if LOG.exists() or (STORE/'process.json').exists():
        raise ValueError('fresh_log_and_process_receipt_required')
    LOG.parent.mkdir(parents=True, exist_ok=True)
    child = subprocess.Popen(prepared['launch_argv'], cwd=p.GAME/'dota',
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    identity = None
    for _ in range(10):
        rows = p.clients()
        rows = rows if isinstance(rows, list) else [rows]
        identity = next((row for row in rows if row and row['pid'] == child.pid), None)
        if identity:
            break
        time.sleep(.1)
    if not identity:
        raise ValueError('owned_process_identity_not_observed_preserve_lab')
    result = dict(status='ISOLATED_GB_NATIVE_PROBE_STARTED', **identity,
                  argv=prepared['launch_argv'], prepared_sha256=file_sha(STORE/'prepared.json'),
                  workshop_install_written=False, transactions=0)
    json_new(STORE/'process.json', result)
    return result


def close():
    previous = p.STORE
    try:
        p.STORE = STORE
        return p.close()  # Exact PID+created, visible owned HWND, WM_CLOSE only.
    finally:
        p.STORE = previous


def parse_closed_log(raw):
    """Pure bounded parser; no fixed/native envelope assumption and no raw output."""
    if not raw or len(raw) > 16*1024*1024:
        raise ValueError('bounded_complete_native_log_required')
    text = raw.decode('latin1')
    if text.count('[N50_GB_PROBE] BEGIN event=gb key=d') != 1 or text.count('[N50_GB_PROBE] END sends=5 transactions=0') != 1:
        raise ValueError('exact_complete_probe_lifecycle_required')
    if 'ShutdownSource2Logging' not in text:
        raise ValueError('normally_closed_native_log_required')
    sends = tuple(map(int, re.findall(r'\[N50_GB_PROBE\] SEND value_ascii_bytes=(\d+)', text)))
    if sends != EXPECTED:
        raise ValueError('complete_ordered_probe_send_markers_required')
    header, event, matched, samples = None, False, False, []
    # Do not splitlines(): Latin1 NEL in unrelated KV bytes is not a line break.
    for line in text.split('\n'):
        found = re.search(r'\((\d+) bits/(\d+) bytes\):', line)
        if found:
            header, event, matched = tuple(map(int, found.groups())), False, False
        elif 'CUserMsg_CustomGameEvent [148]' in line:
            event = True
        elif event and 'event_name:' in line:
            matched = 'event_name: "gb"' in line
        elif event and matched and 'data:' in line:
            payload = re.search(r'data: "VBKV[^"\n]*?\\000\\000\\001d\\000(A*)\\000\\013\\013"\s*$', line)
            if not payload or not header:
                raise ValueError('exact_single_string_d_native_encoding_required')
            bits, size = header
            if math.ceil(bits/8) != size:
                raise ValueError('native_bit_rounding_mismatch')
            length = len(payload[1])
            if size <= length:
                raise ValueError('native_envelope_missing')
            samples.append(dict(value_ascii_bytes=length, native_bits=bits, native_bytes=size,
                                observed_envelope_bytes=size-length))
            header, event, matched = None, False, False
    if tuple(row['value_ascii_bytes'] for row in samples) != EXPECTED:
        raise ValueError('complete_ordered_exact_native_gb_sweep_required')
    build = re.search(r'\[Client\] Build: (\d+) \(revision (\d+)\)', text)
    if not build:
        raise ValueError('actual_native_engine_build_required')
    return dict(method='net_showmsg', layer='CUserMsg_CustomGameEvent [148]', event='gb', key='d',
                engine_build=build[1]+':'+build[2], source_log_sha256=p.sha(raw), samples=samples,
                max_native_bytes=max(row['native_bytes'] for row in samples),
                all_samples_within_1KiB=all(row['native_bytes'] <= 1024 for row in samples),
                envelope_assumed=False, raw_payloads_disclosed=False, tools_only=True,
                ordinary_production_acceptance=False, fps_measured=False, transactions=0,
                layer_note='Incoming engine message bits rounded to bytes; excludes UDP/IP/Steam packet headers. Rare bulk exception, not a 50-byte high-frequency claim.')


def measure():
    prepared = verify()
    process = json.loads((STORE/'process.json').read_bytes())
    if process.get('prepared_sha256') != file_sha(STORE/'prepared.json') or process.get('argv') != prepared['launch_argv']:
        raise ValueError('exact_owned_process_binding_required')
    rows = p.clients()
    rows = rows if isinstance(rows, list) else [rows]
    if any(row and row['pid'] == process['pid'] and row['created'] == process['created'] for row in rows):
        raise ValueError('owned_process_still_running_no_measurement')
    if LOG.is_symlink() or not LOG.is_file() or LOG.stat().st_size > 16*1024*1024:
        raise ValueError('bounded_regular_native_log_required')
    result = parse_closed_log(LOG.read_bytes())
    result.update(status='CLOSED_ISOLATED_GB_NATIVE_SWEEP_MEASURED',
                  prepared_sha256=file_sha(STORE/'prepared.json'), process_receipt_sha256=file_sha(STORE/'process.json'),
                  networksystem_sha256=prepared['networksystem_sha256'], normal_map_sha256=prepared['normal_map_sha256'],
                  probe_source_sha256=prepared['source_sha256'], workshop_install_written=False)
    json_new(DEST, result)
    return result


def retire():
    """Remove only the exact owned junction; preserve external LAB and evidence."""
    if p.clients():
        raise ValueError('all_clients_must_exit_before_mount_retirement')
    prepared = verify()
    process = json.loads((STORE/'process.json').read_bytes())
    measured = json.loads(DEST.read_bytes())
    if process.get('prepared_sha256') != file_sha(STORE/'prepared.json') or process.get('argv') != prepared['launch_argv']:
        raise ValueError('exact_owned_process_binding_required')
    if measured.get('status') != 'CLOSED_ISOLATED_GB_NATIVE_SWEEP_MEASURED' or measured.get('process_receipt_sha256') != file_sha(STORE/'process.json'):
        raise ValueError('owned_closed_measurement_required_preserve_mount')
    if parse_closed_log(LOG.read_bytes())['source_log_sha256'] != measured.get('source_log_sha256'):
        raise ValueError('closed_log_measurement_drift')
    target = LAB.resolve()
    parent = Path('D:/Survival_本地排演/network50_probe_20261103').resolve()
    if STORE.resolve().parent != parent or MOUNT.parent.resolve() != ROOT.parent.resolve():
        raise ValueError('fixed_namespace_required_no_removal')
    if not MOUNT.is_junction() or MOUNT.resolve() != target or not target.is_relative_to(parent):
        raise ValueError('exact_owned_junction_required_no_removal')
    before = {str(path.relative_to(STORE)): file_sha(path) for path in (
        LAB/'addoninfo.txt', LAB/'scripts/vscripts/addon_game_mode.lua', LAB/'maps/template_map.vpk',
        STORE/'prepared.json', STORE/'process.json')}
    # No recurse: this removes the checked reparse point only. All target
    # bytes and actual log/receipts remain at their original external paths.
    MOUNT.rmdir()  # Windows nonrecursive RemoveDirectory on checked junction.
    if MOUNT.exists() or MOUNT.is_junction() or not LAB.is_dir():
        raise ValueError('junction_retirement_not_complete_preserve_evidence')
    after = {name: file_sha(STORE/name) for name in before}
    if after != before or file_sha(LOG) != measured['source_log_sha256']:
        raise ValueError('preserved_lab_or_log_changed')
    result = dict(status='OWNED_BULK02_JUNCTION_RETIRED_LAB_PRESERVED', removed_mount=str(MOUNT),
                  preserved_lab=str(LAB), prepared_sha256=before['prepared.json'],
                  source_log_sha256=measured['source_log_sha256'], lab_files_verified=len(before),
                  processes_started=0, processes_closed=0, target_files_removed=0,
                  workshop_install_written=False, transactions=0)
    json_new(STORE/'retired.json', result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'prepare', 'verify', 'launch', 'close', 'measure', 'retire'))
    args = parser.parse_args()
    print(json.dumps(globals()[args.action](), ensure_ascii=True))
