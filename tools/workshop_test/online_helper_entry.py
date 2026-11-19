"""One closed-test entry for the verified Workshop package and its live helper.

No install switch, authentication bypass, task registration or background process
inventory. Startup uses at most three bounded inventories and a WMI start event.
The per-game supervisor waits on two native handles; helper logs go directly to
files, so closing a spawning PowerShell does not remove a stdout pipe reader.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT.parents[1]
RUNS = Path('D:/Survival_本地工具/runs/online_helper_sessions')
CLIENT = Path(__file__).with_name('online_helper_client.ps1')
HELPER = Path(__file__).with_name('file_http_bridge.py')
POWERSHELL = 'D:/7/pwsh.exe'
READY = b'[SFB_HELPER] ready; enter the original Workshop game'


class EntryError(RuntimeError):
    pass


def write_json(path, value, *, immutable=False):
    raw = (json.dumps(value, ensure_ascii=True, sort_keys=True) + '\n').encode()
    if immutable:
        with path.open('xb') as output:
            output.write(raw)
    else:
        temporary = path.with_suffix('.tmp')
        temporary.write_bytes(raw)
        temporary.replace(path)


def git(*args):
    result = subprocess.run(['git', '-c', 'safe.directory=' + ROOT.as_posix(), '-C', str(ROOT), *args],
                            capture_output=True, timeout=15, creationflags=0x08000000)
    if result.returncode:
        raise EntryError('source_binding_unavailable')
    return result.stdout


def equal_source(pinned, physical):
    return pinned.replace(b'\r\n', b'\n') == physical.replace(b'\r\n', b'\n')


def check_sources():
    sys.path.insert(0, str(ROOT / 'tools'))
    from release_packager.core import baseline
    from published_route import inspect_current
    current = baseline(ROOT)
    route = inspect_current()
    if not route.get('ok'):
        raise EntryError('published_installation_not_verified')
    revision = current['report']['source_revisions']['game']
    if not equal_source(git('show', revision + ':tools/workshop_test/file_http_bridge.py'), HELPER.read_bytes()):
        raise EntryError('helper_source_changed')
    operator = git('rev-parse', 'HEAD').decode().strip()
    for name in ('online_helper_entry.py', 'online_helper_client.ps1'):
        path = HELPER.with_name(name)
        if not equal_source(git('show', operator + ':tools/workshop_test/' + name), path.read_bytes()):
            raise EntryError('entry_source_not_committed')
    return route, revision, operator, hashlib.sha256(HELPER.read_bytes()).hexdigest()


def client_call(mode, steam=None):
    command = [POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(CLIENT), '-Mode', mode]
    if steam:
        command.extend(['-SteamExe', str(steam)])
    result = subprocess.run(command, capture_output=True, timeout=200 if mode == 'start' else 15,
                            creationflags=0x08000000)
    if result.returncode:
        raise EntryError('client_start_failed_preserve_client')
    return json.loads(result.stdout.decode('utf-8-sig'))


def validate_client(client):
    if (not isinstance(client, dict) or type(client.get('pid')) is not int or client['pid'] <= 0
            or not str(client.get('filetime', '')).isdigit()
            or not client.get('expected_exe') or not client.get('ordinary') or not client.get('consolelog')
            or Path(client.get('exe', '')).resolve() != (GAME / 'bin/win64/dota2.exe').resolve()):
        raise EntryError('client_start_settings_invalid')
    return client


def helper_command(client, private):
    # The helper uses only the standard library. Bypass the venv launcher shim.
    return [str(Path(sys._base_executable).resolve()), '-u', '-B', '-X', 'utf8', str(HELPER),
            '--game-root', str(GAME), '--pid', str(client['pid']), '--filetime', client['filetime'],
            '--state-dir', str(private), '--apply']


def wait_ready(child, game, log, *, clock=time.monotonic, sleep=time.sleep, seconds=30):
    deadline, offset, tail = clock() + seconds, 0, b''
    while clock() < deadline:
        if child.poll() is not None:
            raise EntryError('helper_exited_before_ready')
        if not game.alive():
            raise EntryError('client_exited_before_ready')
        with log.open('rb') as stream:
            stream.seek(offset)
            data = stream.read(4096)
            offset += len(data)
        tail = (tail + data)[-4096:]
        if READY in tail:
            return
        sleep(0.1)
    raise EntryError('helper_ready_timeout_preserve_processes')


def supervise(game, child):
    kernel = game.kernel
    kernel.WaitForMultipleObjects.argtypes = [wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE),
                                             wintypes.BOOL, wintypes.DWORD]
    kernel.WaitForMultipleObjects.restype = wintypes.DWORD
    handles = (wintypes.HANDLE * 2)(game.handle, int(child._handle))
    result = kernel.WaitForMultipleObjects(2, handles, False, 0xFFFFFFFF)
    if result == 1 and game.alive():
        raise EntryError('helper_stopped_while_game_running')
    if result not in (0, 1):
        raise EntryError('client_supervision_failed')
    try:
        child.wait(timeout=40)
    except subprocess.TimeoutExpired:
        raise EntryError('helper_cleanup_pending_preserve_process')


MESSAGES = {
    'existing_client_requires_normal_exit': '当前 Dota 没有通过本入口建立联网环境。请先正常退出 Dota，再双击此入口。',
    'entry_already_running': '联网入口已在运行，请使用当前客户端；若正在启动，请稍候。',
    'helper_stopped_while_game_running': '联网环境意外退出，当前局无法继续联网。请正常退出 Dota，再从本入口重开。',
    'backend_health_failed': '暂时无法连接游戏后台，请保留此提示并联系作者。',
}


def launch(run, *, no_dialog=False):
    from file_http_bridge import Process, private_acl
    import msvcrt
    import winreg
    RUNS.mkdir(parents=True, exist_ok=True)
    lock = (RUNS / 'online_entry.lock').open('a+b')
    game = None
    try:
        if lock.tell() == 0:
            lock.write(b'0'); lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise EntryError('entry_already_running')
        run.mkdir(exist_ok=False)
        private_acl(run)
        state = dict(kind='SUPERVISED_WORKSHOP_ENTRY', phase='checking_client', manager_pid=os.getpid())
        write_json(run / 'status.json', state)
        if client_call('inspect'):
            raise EntryError('existing_client_requires_normal_exit')
        route, source, operator, helper_sha = check_sources()
        state.update(phase='checking_backend', release_sequence=route['release_sequence'])
        write_json(run / 'status.json', state)
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open('https://pay.xiaofengnet.com/ws4-web/health', timeout=8) as response:
                if response.status != 200 or json.loads(response.read(8192)).get('ok') is not True:
                    raise ValueError('health_unavailable')
        except Exception:
            raise EntryError('backend_health_failed')
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
            steam = Path(winreg.QueryValueEx(key, 'SteamExe')[0])
        state['phase'] = 'waiting_for_client'
        write_json(run / 'status.json', state)
        client = validate_client(client_call('start', steam))
        game = Process(client['pid'], int(client['filetime']), GAME / 'bin/win64/dota2.exe')
        if not game.alive():
            raise EntryError('client_exited_before_ready')
        if hashlib.sha256(HELPER.read_bytes()).hexdigest() != helper_sha:
            raise EntryError('helper_source_changed')
        state.update(phase='waiting_for_helper', game_pid=client['pid'], game_filetime=client['filetime'])
        write_json(run / 'status.json', state)
        output, error = run / 'helper.stdout.log', run / 'helper.stderr.log'
        with output.open('xb') as stdout, error.open('xb') as stderr:
            child = subprocess.Popen(helper_command(client, run / 'private_helper'),
                                     stdout=stdout, stderr=stderr, close_fds=True,
                                     creationflags=0x08000000)
        wait_ready(child, game, output)
        receipt = dict(kind='ACTUAL_SUPERVISED_OFFICIAL_WORKSHOP_HELPER_LAUNCH',
                       at_utc=datetime.now(timezone.utc).isoformat(), artifact_root=str(run),
                       pid=client['pid'], native_created_filetime=client['filetime'], helper_pid=child.pid,
                       manager_pid=os.getpid(), release_sequence=route['release_sequence'],
                       steam_manifest=route['steam_manifest'], source_helper_revision=source,
                       operator_revision=operator, helper_source_sha256=helper_sha,
                       helper_ready_observed=True, consolelog=True, formal_workshop=True,
                       installation_changed=False, local_candidate_staged=False)
        write_json(run / 'launch_receipt.json', receipt, immutable=True)
        state.update(phase='ready', helper_pid=child.pid)
        write_json(run / 'status.json', state)
        supervise(game, child)
        state['phase'] = 'closed_normally'
        write_json(run / 'status.json', state)
    except Exception as error:
        code = str(error) if isinstance(error, EntryError) else 'online_entry_failed_preserve_client'
        if run.exists():
            write_json(run / 'failure.json', dict(status='FAILED_CLOSED', code=code,
                                                 error_type=type(error).__name__,
                                                 at_utc=datetime.now(timezone.utc).isoformat()), immutable=True)
        if not no_dialog:
            ctypes.WinDLL('user32').MessageBoxW(None, MESSAGES.get(code,
                '联网准备未完成，请保留当前客户端并联系作者。') + '\n错误码：' + code,
                '我在dota2苟发育', 0x10)
        raise EntryError(code) from None
    finally:
        if game:
            game.close()
        lock.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path)
    parser.add_argument('--no-dialog', action='store_true')
    args = parser.parse_args()
    name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '_' + uuid.uuid4().hex[:8]
    run = (args.run_dir or RUNS / name).resolve()
    if run.parent != RUNS.resolve():
        raise EntryError('run_directory_invalid')
    launch(run, no_dialog=args.no_dialog)


if __name__ == '__main__':
    main()
