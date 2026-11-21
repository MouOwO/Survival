"""Windows integration without an elevated process-event subscription.

One startup process snapshot; startup-only, out-of-context window notifications;
one PID-specific command-line read. No injection or periodic process inventory.
"""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


class LaunchError(RuntimeError):
    pass


def vdf(raw):
    if len(raw) > 1024 * 1024:
        raise LaunchError('steam_config_invalid')
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', raw)
    stack, result, key = [], {}, None
    current = result
    for text, brace in tokens:
        if brace == '{':
            if key is None or key in current:
                raise LaunchError('steam_config_invalid')
            child = {}; current[key] = child
            stack.append(current); current = child; key = None
        elif brace == '}':
            if not stack or key is not None:
                raise LaunchError('steam_config_invalid')
            current = stack.pop()
        elif key is None:
            key = text
        else:
            if key in current:
                raise LaunchError('steam_config_invalid')
            current[key] = text.replace('\\\\', '\\').replace('\\"', '"'); key = None
    if stack or key is not None:
        raise LaunchError('steam_config_invalid')
    return result


def discover():
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
            steam = Path(winreg.QueryValueEx(key, 'SteamExe')[0]).resolve(strict=True)
    except (OSError, ValueError):
        raise LaunchError('steam_not_found') from None
    if steam.name.lower() != 'steam.exe':
        raise LaunchError('steam_not_found')
    libraries = [steam.parent]
    config = steam.parent / 'steamapps/libraryfolders.vdf'
    if config.is_file():
        data = vdf(config.read_text(encoding='utf-8-sig'))
        entries = data.get('libraryfolders', data.get('LibraryFolders', {}))
        for index, item in entries.items():
            if index.isdigit():
                value = item.get('path') if isinstance(item, dict) else item
                if value:
                    path = Path(value).resolve()
                    if path not in libraries:
                        libraries.append(path)
    for library in libraries:
        manifest = library / 'steamapps/appmanifest_570.acf'
        if not manifest.is_file():
            continue
        app = vdf(manifest.read_text(encoding='utf-8-sig')).get('AppState', {})
        folder = app.get('installdir', '')
        if app.get('appid') != '570' or not folder or Path(folder).name != folder:
            continue
        game = (library / 'steamapps/common' / folder / 'game').resolve()
        if (game / 'bin/win64/dota2.exe').is_file():
            return steam, game, library / 'steamapps/workshop'
    raise LaunchError('dota_not_found')


def kernel():
    api = C.WinDLL('kernel32', use_last_error=True)
    api.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]; api.OpenProcess.restype = W.HANDLE
    api.CloseHandle.argtypes = [W.HANDLE]
    api.GetProcessTimes.argtypes = [W.HANDLE] + [C.POINTER(W.FILETIME)] * 4
    api.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
    return api


def identity(pid):
    api = kernel(); handle = api.OpenProcess(0x1000, False, pid)
    if not handle:
        return None
    try:
        name, size = C.create_unicode_buffer(32768), W.DWORD(32768)
        times = [W.FILETIME() for _ in range(4)]
        if not api.QueryFullProcessImageNameW(handle, 0, name, C.byref(size)):
            return None
        if not api.GetProcessTimes(handle, *[C.byref(t) for t in times]):
            return None
        return Path(name.value).resolve(), times[0].dwLowDateTime | (times[0].dwHighDateTime << 32)
    finally:
        api.CloseHandle(handle)


def existing_dota():
    class Entry(C.Structure):
        _fields_ = [('size', W.DWORD), ('usage', W.DWORD), ('pid', W.DWORD),
                    ('heap', C.c_size_t), ('module', W.DWORD), ('threads', W.DWORD),
                    ('parent', W.DWORD), ('priority', W.LONG), ('flags', W.DWORD),
                    ('exe', W.WCHAR * 260)]
    api = kernel()
    api.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    api.CreateToolhelp32Snapshot.restype = W.HANDLE
    api.Process32FirstW.argtypes = [W.HANDLE, C.POINTER(Entry)]
    api.Process32NextW.argtypes = [W.HANDLE, C.POINTER(Entry)]
    handle = api.CreateToolhelp32Snapshot(2, 0)
    if handle == W.HANDLE(-1).value:
        raise LaunchError('process_check_failed')
    try:
        item = Entry(); item.size = C.sizeof(item)
        found = None
        ok, count = api.Process32FirstW(handle, C.byref(item)), 0
        while ok:
            if item.exe.lower() == 'dota2.exe':
                if found is not None:
                    raise LaunchError('multiple_dota_clients')
                found = item.pid
            count += 1
            if count > 20000:
                raise LaunchError('process_check_failed')
            ok = api.Process32NextW(handle, C.byref(item))
        if C.get_last_error() not in (0, 18):
            raise LaunchError('process_check_failed')
        return found
    finally:
        api.CloseHandle(handle)


def arguments(pid):
    # Built-in Windows PowerShell 5.1, never an executable from the working dir.
    ps = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    script = ("$ErrorActionPreference='Stop'; [Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false); $p=Get-CimInstance Win32_Process -Filter "
              + "'ProcessId=" + str(int(pid)) + "'; "
              + "[Console]::Out.Write((ConvertTo-Json -InputObject $p.CommandLine -Compress))")
    with system_dlls():
        result = subprocess.run([str(ps), '-NoProfile', '-NonInteractive', '-Command', script],
                                capture_output=True, timeout=15, creationflags=0x08000000)
    if result.returncode:
        raise LaunchError('client_identity_unavailable')
    try:
        command = json.loads(result.stdout.decode('utf-8-sig'))
    except (ValueError, UnicodeError):
        raise LaunchError('client_identity_unavailable') from None
    if not isinstance(command, str) or not command:
        raise LaunchError('client_identity_unavailable')
    shell = C.WinDLL('shell32'); api = kernel()
    shell.CommandLineToArgvW.argtypes = [W.LPCWSTR, C.POINTER(C.c_int)]
    shell.CommandLineToArgvW.restype = C.POINTER(W.LPWSTR)
    api.LocalFree.argtypes = [C.c_void_p]
    count = C.c_int(); argv = shell.CommandLineToArgvW(command, C.byref(count))
    if not argv:
        raise LaunchError('client_identity_unavailable')
    try:
        return [argv[i].lower() for i in range(count.value)]
    finally:
        api.LocalFree(argv)


def validate_arguments(args, *, attaching=False):
    blocked = ('-tools', '-dev', '-addon', '-dedicated', '-insecure', '-con_logfile',
               '+map', '+dota_launch_custom_game')
    if any(a.split('=', 1)[0] in blocked for a in args[1:]):
        raise LaunchError('client_settings_invalid')
    if '-consolelog' not in args[1:] and '-condebug' not in args[1:]:
        raise LaunchError('existing_client_without_log' if attaching else 'client_settings_invalid')


def attach_client(pid, game):
    expected = game / 'bin/win64/dota2.exe'
    observed = identity(pid)
    if observed is None or observed[0] != expected:
        raise LaunchError('client_identity_unavailable')
    validate_arguments(arguments(pid), attaching=True)
    if identity(pid) != observed:
        raise LaunchError('client_identity_unavailable')
    return pid, observed[1], dict(window_events=0, pid_identity_reads=2,
                                  startup_process_snapshots=1)


def system_dlls():
    from contextlib import contextmanager
    @contextmanager
    def scope():
        api = kernel(); api.SetDllDirectoryW.argtypes = [W.LPCWSTR]
        frozen = bool(getattr(sys, 'frozen', False))
        if frozen: api.SetDllDirectoryW(None)
        try:
            yield
        finally:
            if frozen: api.SetDllDirectoryW(sys._MEIPASS)
    return scope()


class WindowStart:
    """Own-thread message pump; only window-create/show/foreground events.

    No input capture, remote memory, DLL injection, or accessibility traversal.
    Per-PID results are cached for this <=180s launch attempt, then discarded.
    """
    def __init__(self, expected, seconds=180):
        self.expected, self.seconds = Path(expected).resolve(), seconds
        self.result, self.seen, self.handles = None, set(), []
        self.events, self.identity_reads = 0, 0

    def run(self, start):
        user = C.WinDLL('user32', use_last_error=True)
        callback_type = C.WINFUNCTYPE(None, W.HANDLE, W.DWORD, W.HWND, W.LONG,
                                     W.LONG, W.DWORD, W.DWORD)
        user.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
        user.SetWinEventHook.argtypes = [W.DWORD, W.DWORD, W.HMODULE, callback_type,
                                        W.DWORD, W.DWORD, W.DWORD]
        user.SetWinEventHook.restype = W.HANDLE
        user.UnhookWinEvent.argtypes = [W.HANDLE]
        user.SetTimer.argtypes = [W.HWND, C.c_size_t, W.UINT, C.c_void_p]
        user.SetTimer.restype = C.c_size_t
        user.KillTimer.argtypes = [W.HWND, C.c_size_t]
        user.GetMessageW.argtypes = [C.POINTER(W.MSG), W.HWND, W.UINT, W.UINT]
        user.GetMessageW.restype = W.BOOL
        user.TranslateMessage.argtypes = [C.POINTER(W.MSG)]
        user.DispatchMessageW.argtypes = [C.POINTER(W.MSG)]
        user.DispatchMessageW.restype = C.c_ssize_t
        cutoff = int((time.time() + 11644473600) * 10000000) - 10000000

        def event(hook, code, hwnd, obj, child, thread, tick):
            if not hwnd or obj != 0 or child != 0 or self.result:
                return
            self.events += 1
            pid = W.DWORD(); user.GetWindowThreadProcessId(hwnd, C.byref(pid))
            if not pid.value or pid.value in self.seen or len(self.seen) >= 4096:
                return
            self.seen.add(pid.value); self.identity_reads += 1
            detail = identity(pid.value)
            if detail and detail[0] == self.expected and detail[1] >= cutoff:
                self.result = (pid.value, detail[1])
                user.PostQuitMessage(0)

        callback = callback_type(event)
        timer = 0
        try:
            for low, high in ((3, 3), (0x8000, 0x8002)):
                handle = user.SetWinEventHook(low, high, None, callback, 0, 0, 2)
                if not handle:
                    raise LaunchError('window_events_unavailable')
                self.handles.append(handle)
            timer = user.SetTimer(None, 0, int(self.seconds * 1000), None)
            if not timer:
                raise LaunchError('window_events_unavailable')
            start()
            msg = W.MSG()
            while True:
                value = user.GetMessageW(C.byref(msg), None, 0, 0)
                if value == -1:
                    raise LaunchError('window_events_unavailable')
                if value == 0 or (msg.message == 0x0113 and msg.wParam == timer):
                    break
                user.TranslateMessage(C.byref(msg)); user.DispatchMessageW(C.byref(msg))
            if not self.result:
                raise LaunchError('client_start_timeout')
            return self.result
        finally:
            for handle in self.handles:
                user.UnhookWinEvent(handle)
            self.handles.clear()
            if timer:
                user.KillTimer(None, timer)


def start_client(steam, game):
    watcher = WindowStart(game / 'bin/win64/dota2.exe')
    def start():
        with system_dlls():
            subprocess.Popen([str(steam), '-applaunch', '570', '-novid', '-console',
                              '-consolelog', '+sv_cheats', '0', '+net_showmsg', '0'],
                             creationflags=0x08000000, close_fds=True)
    pid, created = watcher.run(start)
    validate_arguments(arguments(pid))
    if identity(pid) != (game / 'bin/win64/dota2.exe', created):
        raise LaunchError('client_identity_unavailable')
    return pid, created, dict(window_events=watcher.events,
                             pid_identity_reads=watcher.identity_reads,
                             startup_process_snapshots=1)
