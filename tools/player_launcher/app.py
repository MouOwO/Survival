"""Portable player entry, bundled with the exact published helper and admission."""
from __future__ import annotations
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import uuid
import webbrowser
import traceback

import file_http_bridge as bridge
import storage
from windows import LaunchError, discover, existing_dota, start_client, vdf

TITLE = '我在dota2苟发育 · 专用登录器'
WORKSHOP = '3824360109'
ICON = Path(__file__).with_name('goufayu.ico')
READY = '[SFB_HELPER] ready; enter the original Workshop game'
MESSAGES = {
    'steam_not_found': '未找到 Steam。请先安装 Steam，并登录你的 Steam 账号。',
    'dota_not_found': '未找到 Dota 2。请先通过 Steam 安装并更新 Dota 2。',
    'existing_client': 'Dota 已在运行。请先正常退出 Dota，再点击“启动游戏”。',
    'entry_already_running': '专用登录器已在运行，请使用已打开的窗口。',
    'workshop_missing': '尚未下载本游戏。请点击“游廊页面”订阅，并等待 Steam 下载完成。',
    'workshop_version': '游戏版本与登录器不匹配。请等待 Steam 更新完成；仍有提示时到官方群获取新版登录器。',
    'workshop_files': '游戏文件不完整。请在 Steam 中等待下载完成，或重新订阅本游戏。',
    'backend_unavailable': '暂时无法连接游戏后台。请检查网络，稍后重试。',
    'client_settings_invalid': 'Dota 启动参数不符合联网要求。请退出 Dota，移除 Steam 中的 Tools 或自动进地图参数后重试。',
    'client_start_timeout': '没有等到 Dota 窗口。请确认 Steam 已登录、Dota 已更新，再正常退出 Dota 后重试。',
    'client_identity_unavailable': '无法确认当前 Dota 进程。请让 Steam 与登录器使用同一个 Windows 用户和权限运行。',
    'console_log_unavailable': 'Dota 未能创建联网所需日志。请正常退出 Dota，确认游戏目录可写后重试。',
    'bridge_files_already_exist': '发现上次异常退出的联网文件。请保留当前提示并联系作者协助恢复。',
    'private_acl_failed': '无法保护联网文件。请确认 Dota 安装在可写的 NTFS 磁盘，并使用同一个 Windows 用户运行。',
    'window_events_unavailable': '无法等待 Dota 启动窗口。请使用常规 Windows 桌面运行并联系作者。',
    'helper_stopped_while_game_running': '联网助手已停止。请先正常退出 Dota，再从登录器重开。',
    'transport_files_busy': '联网文件持续被占用。请正常退出 Dota 后重试；诊断文件已保留。',
    'bridge_recovery_required': '旧联网目录中存在无法确认的文件。请保留诊断目录并联系官方群。',
    'bridge_file_changed': '联网文件被其他程序改动。请正常退出 Dota，并保留诊断目录。',
}


def bundle():
    return json.loads(Path(__file__).with_name('launcher_binding.json').read_bytes())


def write_json(path, value):
    raw = json.dumps(value, ensure_ascii=True, sort_keys=True).encode() + b'\n'
    temp = path.with_suffix('.tmp')
    temp.write_bytes(raw); os.replace(temp, path)


def verify_workshop(root, binding, notify):
    acf = root / 'appworkshop_570.acf'
    if not acf.is_file():
        raise LaunchError('workshop_missing')
    data = vdf(acf.read_text(encoding='utf-8-sig')).get('AppWorkshop', {})
    installed = data.get('WorkshopItemsInstalled', {}).get(WORKSHOP, {})
    if not installed:
        raise LaunchError('workshop_missing')
    if installed.get('manifest') != binding['steam_manifest']:
        raise LaunchError('workshop_version')
    folder = root / 'content/570' / WORKSHOP
    files = binding['package_files']
    if not folder.is_dir() or {p.name for p in folder.glob('*.vpk')} != {f['name'] for f in files}:
        raise LaunchError('workshop_files')
    # One finite pass before launch, on a worker. No timer rescans or cached
    # "verified" flags. All 3.8GB are read once; each read is <=1MiB.
    total, done = sum(f['bytes'] for f in files), 0
    last = -1
    for item in files:
        name = item['name']
        if Path(name).name != name:
            raise LaunchError('workshop_files')
        path = folder / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size != item['bytes']:
            raise LaunchError('workshop_files')
        digest = hashlib.sha256()
        before = path.stat()
        with path.open('rb') as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk); done += len(chunk)
                percent = int(done * 100 / total)
                if percent != last:
                    notify('phase', '核对已下载的游戏文件 ' + str(percent) + '%')
                    last = percent
        after = path.stat()
        if (digest.hexdigest() != item['sha256'] or
                (before.st_size, before.st_mtime_ns, before.st_ino) !=
                (after.st_size, after.st_mtime_ns, after.st_ino)):
            raise LaunchError('workshop_files')
    return dict(files=len(files), bytes=done, full_sha256_verified=True)


class Output:
    def __init__(self, stream, ready):
        self.stream, self.ready = stream, ready

    def write(self, text):
        self.stream.write(text); self.stream.flush()
        if text.strip() == READY:
            self.ready()
        return len(text)

    def flush(self):
        self.stream.flush()


def session(binding, run, notify):
    state = dict(kind='PORTABLE_PLAYER_ENTRY', version=binding['version'], phase='checking',
                 release_sequence=binding['release_sequence'], steam_manifest=binding['steam_manifest'],
                 source_revision=binding['source_revision'], manager_pid=os.getpid(),
                 storage_source_sha256=binding.get('storage_sha256'))
    process = None
    stdout, stderr, argv = sys.stdout, sys.stderr, sys.argv
    try:
        run.mkdir(parents=True, exist_ok=False); bridge.private_acl(run)
        write_json(run / 'status.json', state)
        if existing_dota():
            raise LaunchError('existing_client')
        steam, game, workshop = discover()
        verification = verify_workshop(workshop, binding, notify)
        notify('phase', '正在连接游戏后台')
        try:
            status, raw = bridge.https('GET', '/health', {}, b'', 8)
            if status != 200 or json.loads(raw).get('ok') is not True:
                raise ValueError()
        except Exception:
            raise LaunchError('backend_unavailable') from None
        state['recovery'] = storage.recover(game / 'dota/cfg', run, bridge.private_acl)
        notify('phase', '正在通过 Steam 启动 Dota 2，请稍候')
        pid, created, counts = start_client(steam, game)
        process = bridge.Process(pid, created, game / 'bin/win64/dota2.exe')
        state.update(game_pid=pid, game_filetime=str(created), phase='waiting_for_log', **counts)
        write_json(run / 'status.json', state)
        log = game / 'dota/console.log'; deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if not process.alive():
                raise LaunchError('client_exited')
            if log.is_file() and log.stat().st_mtime_ns // 100 >= created - 116444736000000000:
                break
            time.sleep(0.1)
        else:
            raise LaunchError('console_log_unavailable')
        def ready():
            if not process.alive():
                raise LaunchError('client_exited')
            state['phase'] = 'ready'
            write_json(run / 'status.json', state)
            write_json(run / 'launch_receipt.json', dict(state, artifact_root=str(run),
                       helper_ready_observed=True, workshop_verification=verification,
                       helper_source_sha256=binding['helper_sha256'], installation_changed=False))
            notify('ready', '联网已准备完成。请在 Dota 游廊进入“我在dota2苟发育”。')
        notify('phase', '正在准备联网，请先停留在 Dota 主菜单')
        with (run / 'helper.log').open('x', encoding='utf-8') as output:
            sys.stdout = sys.stderr = Output(output, ready)
            sys.argv = ['file_http_bridge', '--game-root', str(game), '--pid', str(pid),
                        '--filetime', str(created), '--state-dir', str(run / 'private_helper'), '--apply']
            if binding.get('access_mode') == 'public':
                sys.argv.extend(['--access-mode', 'public'])
            with storage.adapter(bridge) as storage_metrics:
                try:
                    bridge.main()
                finally:
                    write_json(run / 'storage_receipt.json', dict(storage_metrics,
                               kind='PLAYER_BRIDGE_STORAGE_COUNTERS', artifact_root=str(run)))
        if state['phase'] != 'ready':
            raise LaunchError('helper_not_ready')
        if process.alive():
            raise LaunchError('helper_stopped_while_game_running')
        state['phase'] = 'game_exited_helper_cleaned'
        write_json(run / 'status.json', state)
        notify('closed', 'Dota 已退出，联网文件已清理。可再次点击“启动游戏”。')
    except Exception as error:
        code = str(error) if isinstance(error, (LaunchError, ValueError)) and re.fullmatch(r'[a-z_]{3,80}', str(error)) else 'launcher_failed'
        state.update(phase='failed', code=code, error_type=type(error).__name__,
                     winerror=getattr(error, 'winerror', None), errno=getattr(error, 'errno', None),
                     cause_type=type(error.__cause__).__name__ if error.__cause__ else None,
                     cause_winerror=getattr(error.__cause__, 'winerror', None),
                     frames=[dict(file=Path(frame.filename).name, function=frame.name, line=frame.lineno)
                             for frame in traceback.extract_tb(error.__traceback__)[-8:]])
        if run.exists():
            write_json(run / 'failure.json', state)
            write_json(run / 'status.json', state)
        notify('failed', code)
    finally:
        sys.stdout, sys.stderr, sys.argv = stdout, stderr, argv
        if process:
            process.close()


def selfcheck(destination):
    binding = bundle()
    import tkinter
    # Instantiates Tcl/Tk: checks bundled DLL/data availability, not just imports.
    icon_sha = hashlib.sha256(ICON.read_bytes()).hexdigest()
    if icon_sha != binding['icon_sha256']:
        raise LaunchError('launcher_icon_changed')
    root = tkinter.Tk()
    try:
        root.withdraw()
        root.iconbitmap(default=str(ICON))
        root.update()
    finally:
        root.destroy()
    result = dict(kind='FROZEN_PLAYER_LAUNCHER_SELFCHECK', frozen=bool(getattr(sys, 'frozen', False)),
                  version=binding['version'], protocol=bridge.PROTOCOL,
                  access_mode=binding.get('access_mode', 'test'),
                  storage_source_sha256=binding.get('storage_sha256'), startup_recovery_supported=True,
                  icon_sha256=icon_sha,
                  fallback_test_accounts=len(bridge.ACCOUNTS), gui_initialized=True,
                  external_python_required=not bool(getattr(sys, 'frozen', False)), git_required=False, powershell7_required=False,
                  automatic_game_start=False, http_requests=0, game_files_changed=False)
    write_json(destination, result)


def gui():
    import msvcrt
    import tkinter as tk
    from tkinter import messagebox, ttk
    binding = bundle()
    base = Path(os.environ['LOCALAPPDATA']) / 'Goufayu/Launcher'
    base.mkdir(parents=True, exist_ok=True); bridge.private_acl(base)
    lock = (base / 'entry.lock').open('a+b')
    if lock.tell() == 0:
        lock.write(b'0'); lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        ctypes.WinDLL('user32').MessageBoxW(None, MESSAGES['entry_already_running'], TITLE, 0x40)
        lock.close(); return
    events = queue.Queue(maxsize=256)
    root = tk.Tk(); root.title(TITLE); root.geometry('620x375'); root.resizable(False, False)
    root.iconbitmap(default=str(ICON))
    root.configure(bg='#142029')
    frame = tk.Frame(root, bg='#142029'); frame.pack(fill='both', expand=True, padx=30, pady=24)
    tk.Label(frame, text='我在dota2苟发育', fg='#f1d490', bg='#142029', font=('Microsoft YaHei UI', 22, 'bold')).pack(anchor='w')
    tk.Label(frame, text='这一把，先苟到成型。', fg='#b6c7ce', bg='#142029', font=('Microsoft YaHei UI', 11)).pack(anchor='w', pady=(4,18))
    status = tk.StringVar(value='请先登录 Steam；首次使用请先订阅游廊游戏。')
    tk.Label(frame, textvariable=status, fg='#eff5f7', bg='#142029', wraplength=550, justify='left',
             height=3, anchor='w', font=('Microsoft YaHei UI', 11)).pack(fill='x')
    bar = ttk.Progressbar(frame, mode='indeterminate'); bar.pack(fill='x', pady=(8,18))
    row = tk.Frame(frame, bg='#142029'); row.pack(fill='x')
    active, current_run = [False], [None]
    def notify(kind, value):
        events.put_nowait((kind, value))
    def start():
        if active[0]: return
        name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '_' + uuid.uuid4().hex[:8]
        current_run[0] = base / 'sessions' / name
        active[0] = True; button.configure(state='disabled'); bar.start(20)
        status.set('正在检查 Steam 和游戏文件，请稍候')
        threading.Thread(target=session, args=(binding, current_run[0], notify), daemon=False).start()
    button = ttk.Button(row, text='启动游戏', command=start); button.pack(side='left', ipadx=24, ipady=8)
    ttk.Button(row, text='游廊页面', command=lambda: webbrowser.open('https://steamcommunity.com/sharedfiles/filedetails/?id=' + WORKSHOP)).pack(side='left', padx=12, ipady=8)
    ttk.Button(row, text='打开诊断目录', command=lambda: os.startfile(str(current_run[0] or base))).pack(side='left', ipady=8)
    tk.Label(frame, text='官方 QQ 群 1098603739\n联网期间请保留此窗口，可最小化。Steam 授权请使用本局同一账号。',
             fg='#9eafb8', bg='#142029', font=('Microsoft YaHei UI', 9), justify='left').pack(anchor='w', pady=(18,0))
    tk.Label(frame, text='版本 ' + binding['version'] + ' · Windows 10 / 11 · 64 位', fg='#718892', bg='#142029', font=('Microsoft YaHei UI', 8)).pack(anchor='w', pady=(5,0))
    def drain():
        for _ in range(32):
            try: kind, value = events.get_nowait()
            except queue.Empty: break
            if kind in ('ready', 'closed', 'failed'): bar.stop()
            if kind in ('closed', 'failed'):
                active[0] = False; button.configure(state='normal')
            if kind == 'failed':
                text = MESSAGES.get(value, '联网准备未完成，请将错误码告知官方群。') + '\n错误码：' + value
                status.set(text); root.deiconify(); messagebox.showerror('联网准备未完成', text, parent=root)
            else: status.set(value)
        root.after(100, drain)
    def close():
        if active[0]:
            messagebox.showinfo(TITLE, '联网期间登录器需要保持运行。现在将最小化；正常退出 Dota 后即可关闭。', parent=root)
            root.iconify()
        else: root.destroy()
    root.protocol('WM_DELETE_WINDOW', close)
    root.after(100, drain)
    try: root.mainloop()
    finally: lock.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--selfcheck', type=Path)
    args = parser.parse_args()
    if args.selfcheck:
        selfcheck(args.selfcheck)
    else:
        gui()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        ctypes.WinDLL('user32').MessageBoxW(None, '登录器未能启动，请从官方群获取完整文件。', TITLE, 0x10)
        raise SystemExit(1)
