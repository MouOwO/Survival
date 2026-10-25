"""Host operator for a separate, reversible four-account web-login service.

Injected MODE/OVERLAY are trusted operator input, not HTTP input. No production
database connection is made. Existing API/payment/database services and release
pointers are observed and must retain the same PIDs and content hashes.
"""
from pathlib import Path
import base64
import hashlib
import json
import os
import re
import secrets
import socket
import stat
import subprocess
import time
import urllib.request
import urllib.error

BASE = Path('/opt/goufayu-ws4-web')
RELEASE = BASE / 'releases/20261024-web-auth-v1'
CONFIG = Path('/etc/goufayu-ws4-web')
STATE = Path('/var/lib/goufayu-ws4-web')
OPS = Path('/var/lib/goufayu-ws4-web-deploy')
USER = 'goufayu-ws4-web'
UNIT = Path('/etc/systemd/system/goufayu-ws4-web.service')
PINS = Path('/etc/goufayu-ws4/pins.json')
LOCATIONS = Path('/etc/nginx/goufayu-ws4-web.locations')
PYTHON = '/usr/bin/python3.11'
PUBLIC_BASE = 'https://pay.xiaofengnet.com/ws4-web'
SERVICES = ('goufayu-api.service', 'goufayu-payment.service', 'goufayu-db.service',
            'goufayu-ws4.service', 'goufayu-ws4-db.service')
SHA256 = re.compile(r'[a-f0-9]{64}\Z')
FIXED_CODE = re.compile(r'[a-z][a-z0-9_]{1,95}\Z')
STEAM_TLS_RELAY = globals().get('STEAM_TLS_RELAY')
sha = lambda raw: hashlib.sha256(raw).hexdigest()
RUNTIME_SOURCES = frozenset((
    'player_web_auth/__init__.py', 'player_web_auth/http_api.py',
    'player_web_auth/run.py', 'player_web_auth/service.py',
    'lobby_backend/__init__.py', 'lobby_backend/http_api.py', 'lobby_backend/service.py',
))
LEGACY_SOURCES = frozenset(name for name in RUNTIME_SOURCES if name.startswith('player_web_auth/'))


def failure_code(error):
    # Do not emit exception text containing host paths, HTTP bodies or secrets.
    if isinstance(error, RuntimeError) and FIXED_CODE.fullmatch(str(error)):
        return str(error)
    if isinstance(error, urllib.error.HTTPError):
        return 'http_status_' + str(error.code) if 100 <= error.code <= 599 else 'http_status_invalid'
    if isinstance(error, (urllib.error.URLError, OSError)):
        return 'host_io_failed'
    if isinstance(error, (ValueError, TypeError, KeyError)):
        return 'host_data_invalid'
    return 'host_operation_failed'


class ActivationFailure(RuntimeError):
    def __init__(self, error, stage, rollback_ok, rollback_error=None, health_error=None):
        self.summary = {'ok': False, 'phase': 'WEB_AUTH_ACTIVATION_FAILED', 'error': failure_code(error),
                        'stage': stage, 'rollback_ok': rollback_ok}
        if rollback_error is not None:
            self.summary['rollback_error'] = failure_code(rollback_error)
        if health_error is not None:
            self.summary['loopback_health_error'] = failure_code(health_error)
        super().__init__('web_activation_failed')


class ConfigurationFailure(RuntimeError):
    def __init__(self, error, restored, restore_error=None):
        self.summary = {'ok': False, 'phase': 'WEB_AUTH_TRANSPORT_CONFIGURATION_FAILED',
                        'error': failure_code(error), 'configuration_restored': restored}
        if restore_error is not None:
            self.summary['restore_error'] = failure_code(restore_error)
        super().__init__('web_transport_configuration_failed')


def need(value, code):
    if not value:
        raise RuntimeError(code)


def run(args, *, timeout=30):
    result = subprocess.run(args, capture_output=True, timeout=timeout)
    need(result.returncode == 0, 'host_command_failed')
    return result.stdout


def regular(path):
    need(not path.is_symlink() and path.is_file(), 'regular_file_required')
    need(stat.S_ISREG(path.lstat().st_mode), 'regular_file_required')
    return path.read_bytes()


def private(path, raw, *, uid=0, gid=0, mode=0o600):
    need(not path.exists() and not path.is_symlink(), 'new_private_file_required')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), mode)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.chown(path, uid, gid)
    path.chmod(mode)


def replace(path, raw, *, gid=0, mode=0o600):
    need(not path.is_symlink(), 'replace_symlink_rejected')
    temporary = path.with_name(path.name + '.web-auth-' + secrets.token_hex(6))
    private(temporary, raw, gid=gid, mode=mode)
    os.replace(temporary, path)


def document(path):
    return json.loads(regular(path))


def record(name, value):
    replace(OPS / name, json.dumps(value, sort_keys=True).encode())


def baseline():
    result = {'services': {}, 'releases': {}}
    for name in SERVICES:
        need(run(['systemctl', 'is-active', name]).strip() == b'active', 'existing_service_inactive')
        pid = run(['systemctl', 'show', name, '--property=MainPID', '--value']).decode().strip()
        need(pid.isdigit() and int(pid) > 0, 'existing_service_pid_invalid')
        fragment = Path(run(['systemctl', 'show', name, '--property=FragmentPath', '--value']).decode().strip())
        result['services'][name] = {'pid': pid, 'unit_path': str(fragment), 'unit_sha256': sha(regular(fragment))}
    for link in (Path('/opt/goufayu/releases/current'), Path('/opt/goufayu/payments/current')):
        target = link.resolve(strict=True)
        manifest = target / 'release_manifest.json'
        result['releases'][str(link)] = {'target': str(target),
            'manifest_sha256': sha(regular(manifest)) if manifest.exists() else None}
    # WS4 does not require a current symlink; pin the actual installed unit and
    # its known isolated release manifest instead of inventing a pointer.
    ws4_unit = Path('/etc/systemd/system/goufayu-ws4.service')
    ws4_release = Path('/opt/goufayu-ws4/releases/20261023-auth-v1')
    need(ws4_release.is_dir() and not ws4_release.is_symlink(), 'isolated_release_missing')
    pinned = {}
    for name in ('backend/workshop_test/auth.py', 'backend/workshop_test/run_api.py'):
        path = ws4_release / name
        pinned[name] = sha(regular(path))
    result['ws4'] = {'release': str(ws4_release), 'files': pinned, 'unit_sha256': sha(regular(ws4_unit))}
    return result


def unchanged():
    need(document(OPS / 'baseline.json') == baseline(), 'existing_service_or_release_changed')


def parse_env(raw):
    result = {}
    for line in raw.decode('utf-8').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, separator, value = line.partition('=')
        need(separator and re.fullmatch(r'[A-Z][A-Z0-9_]*', key), 'environment_format_invalid')
        result[key] = json.loads(value) if value.startswith('"') else value
    return result


def accounts(raw):
    value = parse_env(raw).get('SURVIVAL_TEST_STEAM_IDS64', '')
    ids = value.split(',')
    need(len(ids) == 4 and len(set(ids)) == 4 and all(re.fullmatch(r'7656119[0-9]{10}', i) for i in ids),
         'four_isolated_accounts_required')
    return value


def validate_pins(raw):
    pins = json.loads(raw)
    rows = pins.get('sha256')
    need(pins.get('workshop_id') == '3824360109' and isinstance(rows, list)
         and len(rows) <= 4 and all(isinstance(item, str) and SHA256.fullmatch(item) for item in rows)
         and len(set(rows)) == len(rows), 'pin_state_invalid')
    return pins


def append_pin(raw, digest):
    need(SHA256.fullmatch(digest), 'new_pin_invalid')
    pins = validate_pins(raw)
    need(digest not in pins['sha256'] and len(pins['sha256']) < 4, 'pin_capacity_or_identity_conflict')
    pins['sha256'].append(digest)
    return json.dumps(pins, sort_keys=True).encode()


def tls_candidates(files):
    candidates = []
    for path, raw in files:
        for match in re.finditer(r'\bserver\s*\{', raw):
            depth, quote, comment, escape, index = 1, None, False, False, match.end()
            while index < len(raw) and depth:
                char = raw[index]
                if comment:
                    if char == '\n':
                        comment = False
                elif quote:
                    if escape:
                        escape = False
                    elif char == '\\':
                        escape = True
                    elif char == quote:
                        quote = None
                elif char == '#':
                    comment = True
                elif char in ('"', "'"):
                    quote = char
                elif char == '{':
                    depth += 1
                elif char == '}':
                    depth -= 1
                index += 1
            need(depth == 0, 'nginx_server_unbalanced')
            body = raw[match.end():index - 1]
            if (re.search(r'\bserver_name\s+pay\.xiaofengnet\.com\s*;', body)
                    and re.search(r'\blisten\s+[^;]*\b443\b[^;]*;', body)):
                candidates.append((path, raw, index - 1))
    need(len(candidates) == 1, 'unique_tls_server_required')
    return candidates[0]


def nginx_target():
    output = run(['nginx', '-T']).decode()
    files = []
    for name in sorted(set(re.findall(r'^# configuration file (.+):$', output, re.M))):
        path = Path(name)
        if path.is_relative_to('/etc/nginx') and path.is_file() and not path.is_symlink():
            files.append((path, regular(path).decode()))
    return tls_candidates(files)


def proxy_rules():
    return b'''# Independent four-account web login; original WS4/payment routes remain unchanged.
location = /ws4-web { return 308 /ws4-web/; }
location ^~ /ws4-web/ {
    limit_except GET POST { deny all; }
    client_max_body_size 64k;
    client_body_timeout 10s;
    proxy_pass http://127.0.0.1:18767/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Connection "";
    proxy_http_version 1.1;
    proxy_connect_timeout 3s;
    proxy_send_timeout 15s;
    proxy_read_timeout 25s;
    proxy_cache off;
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
    access_log off;
}
'''


def unit_source():
    return f'''[Unit]
Description=Survival isolated four-account Steam web login
After=network-online.target goufayu-ws4.service
[Service]
User={USER}
Group={USER}
WorkingDirectory={RELEASE.as_posix()}
EnvironmentFile={CONFIG.as_posix()}/auth.env
ExecStart={PYTHON} -B -m player_web_auth.run
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={STATE.as_posix()}
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
MemoryMax=256M
TasksMax=64
[Install]
WantedBy=multi-user.target
'''.encode()


def decoded_sources():
    need(isinstance(OVERLAY, dict) and OVERLAY, 'web_source_missing')
    sources = {}
    for name, encoded in OVERLAY.items():
        need(isinstance(name, str) and name in RUNTIME_SOURCES, 'web_source_path_invalid')
        raw = base64.b64decode(encoded, validate=True)
        need(len(raw) <= 512 * 1024, 'web_source_too_large')
        compile(raw, name, 'exec')
        sources[name] = raw
    need(set(sources) == RUNTIME_SOURCES, 'web_source_incomplete')
    return sources


def source_target(name):
    """Only the two fixed packages may be read/written inside this release."""
    need(isinstance(name, str) and name in RUNTIME_SOURCES, 'prepared_source_path_invalid')
    target = RELEASE / name
    need(RELEASE.is_dir() and not any(parent.is_symlink() for parent in (RELEASE, RELEASE.parent, BASE))
         and target.parent.is_dir() and not target.parent.is_symlink(), 'prepared_source_path_invalid')
    return target


def prepare():
    import pwd
    if (OPS / 'prepared.json').is_file():
        return refresh_prepared()
    before = baseline()
    need(Path(PYTHON).is_file(), 'python311_missing')
    for path in (BASE, CONFIG, STATE, OPS, UNIT, LOCATIONS):
        need(not path.exists() and not path.is_symlink(), 'web_namespace_already_exists')
    with socket.socket() as sock:
        need(sock.connect_ex(('127.0.0.1', 18767)) != 0, 'web_port_occupied')
    try:
        pwd.getpwnam(USER)
    except KeyError:
        pass
    else:
        raise RuntimeError('web_service_account_exists')
    sources = decoded_sources()
    steam_ids = accounts(regular(Path('/etc/goufayu-ws4/api.env')))
    original_pins = regular(PINS)
    validate_pins(original_pins)
    path, nginx_before, close = nginx_target()
    need('/ws4-web' not in nginx_before and str(LOCATIONS) not in nginx_before, 'web_route_already_present')
    metadata = path.stat()
    nginx_after = (nginx_before[:close] + '\n    include ' + str(LOCATIONS) + ';\n' + nginx_before[close:]).encode()
    bearer = secrets.token_hex(32)
    digest = sha(bearer.encode('ascii'))
    pins_after = append_pin(original_pins, digest)
    run(['useradd', '--system', '--user-group', '--home-dir', str(STATE), '--shell', '/sbin/nologin', USER])
    user = pwd.getpwnam(USER)
    need(user.pw_uid > 0 and user.pw_gid > 0, 'invalid_web_service_account')
    for root in (BASE, CONFIG):
        root.mkdir(mode=0o750)
        os.chown(root, 0, user.pw_gid)
    STATE.mkdir(mode=0o700)
    os.chown(STATE, user.pw_uid, user.pw_gid)
    OPS.mkdir(mode=0o700)
    RELEASE.mkdir(parents=True, mode=0o750)
    for parent in (BASE / 'releases', RELEASE):
        os.chown(parent, 0, user.pw_gid)
        parent.chmod(0o750)
    for name, raw in sources.items():
        target = RELEASE / name
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
        for parent in target.parents:
            if parent == RELEASE:
                break
            os.chown(parent, 0, user.pw_gid)
            parent.chmod(0o750)
        private(target, raw, gid=user.pw_gid, mode=0o640)
    env = {'PLAYER_WEB_AUTH_BIND': '127.0.0.1', 'PLAYER_WEB_AUTH_PORT': '18767',
        'PLAYER_WEB_AUTH_PUBLIC_BASE': PUBLIC_BASE, 'PLAYER_WEB_AUTH_UPSTREAM': 'http://127.0.0.1:18765',
        'PLAYER_WEB_AUTH_UPSTREAM_BEARER': bearer, 'PLAYER_WEB_AUTH_SECRET': secrets.token_hex(32),
        'PLAYER_WEB_AUTH_DATABASE': str(STATE / 'auth.sqlite3'), 'PLAYER_WEB_AUTH_STEAM_IDS': steam_ids,
        'PLAYER_WEB_AUTH_STEAM_TLS_RELAY': '0',
        'ISOLATED_LOCAL_PROGRESS': '1', 'PYTHONDONTWRITEBYTECODE': '1', 'PYTHONUNBUFFERED': '1'}
    private(CONFIG / 'auth.env', ''.join(k + '=' + json.dumps(v) + '\n' for k, v in env.items()).encode(),
            gid=user.pw_gid, mode=0o640)
    for name, raw in (('nginx.before', nginx_before.encode()), ('nginx.after', nginx_after),
                      ('pins.before', original_pins), ('pins.after', pins_after),
                      ('locations.candidate', proxy_rules()), ('unit.candidate', unit_source())):
        private(OPS / name, raw)
    private(OPS / 'baseline.json', json.dumps(before, sort_keys=True).encode())
    prepared = {'release': str(RELEASE), 'files': {n: sha(r) for n, r in sources.items()},
        'nginx_path': str(path), 'nginx_mode': stat.S_IMODE(metadata.st_mode), 'nginx_gid': metadata.st_gid,
        'nginx_before_sha256': sha(nginx_before.encode()), 'nginx_after_sha256': sha(nginx_after),
        'pins_before_sha256': sha(original_pins), 'pins_after_sha256': sha(pins_after),
        'new_bearer_sha256': digest, 'env_sha256': sha(regular(CONFIG / 'auth.env'))}
    private(OPS / 'prepared.json', json.dumps(prepared, sort_keys=True).encode())
    unchanged()
    return {'ok': True, 'phase': 'WEB_AUTH_PREPARED_NOT_STARTED', 'source_files': len(sources),
            'four_account_only': True, 'public_enabled': False, 'existing_services_unchanged': True}


def prepared():
    plan = document(OPS / 'prepared.json')
    need(plan['release'] == str(RELEASE), 'prepared_release_invalid')
    files = plan.get('files')
    need(isinstance(files, dict) and files, 'prepared_source_incomplete')
    for name, digest in files.items():
        need(isinstance(name, str) and name in RUNTIME_SOURCES
             and isinstance(digest, str) and SHA256.fullmatch(digest), 'prepared_source_path_invalid')
    # Preserve verification/rollback of the complete old four-file release.
    # New preparation and activation require all seven runtime dependencies.
    need(set(files) in (LEGACY_SOURCES, RUNTIME_SOURCES), 'prepared_source_incomplete')
    need(sha(regular(CONFIG / 'auth.env')) == plan['env_sha256'], 'prepared_environment_changed')
    for name, digest in plan['files'].items():
        need(sha(regular(source_target(name))) == digest, 'prepared_source_changed')
    for kind in ('nginx', 'pins'):
        for state in ('before', 'after'):
            need(sha(regular(OPS / (kind + '.' + state))) == plan[kind + '_' + state + '_sha256'],
                 'prepared_backup_changed')
    need(regular(OPS / 'unit.candidate') == unit_source()
         and regular(OPS / 'locations.candidate') == proxy_rules(), 'prepared_config_changed')
    return plan


def refresh_prepared():
    """Refresh code only after rollback, with unchanged keys/state and a backup.

    Matching source hashes are a read-only no-op, including a previously
    prepared candidate which has never been activated. Never overwrite an
    external code edit or update a running sidecar in place.
    """
    import pwd
    plan = prepared()
    unchanged()
    sources = decoded_sources()
    hashes = {name: sha(raw) for name, raw in sources.items()}
    if hashes == plan['files']:
        return {'ok': True, 'phase': 'WEB_AUTH_PREPARED_UNCHANGED', 'source_files': len(sources),
                'candidate_updated': False, 'keys_and_state_preserved': True,
                'existing_services_unchanged': True}
    before_names, after_names = set(plan['files']), set(hashes)
    need(after_names == RUNTIME_SOURCES and before_names in (LEGACY_SOURCES, RUNTIME_SOURCES),
         'source_set_change_requires_new_release')
    added = after_names - before_names
    added_package = RELEASE / 'lobby_backend' if added else None
    if added_package is not None:
        need(not added_package.exists() and not added_package.is_symlink(), 'source_added_namespace_exists')
    need((OPS / 'activation.json').is_file() and (OPS / 'rolled-back.json').is_file(),
         'successful_rollback_required_before_refresh')
    activation_ready(plan)
    before_plan = regular(OPS / 'prepared.json')
    need(json.loads(before_plan) == plan, 'prepared_plan_changed')
    before_sources = {name: regular(source_target(name)) for name in plan['files']}
    need(all(sha(raw) == plan['files'][name] for name, raw in before_sources.items()), 'prepared_source_changed')
    backup = OPS / ('source-before-refresh-' + secrets.token_hex(8))
    backup.mkdir(mode=0o700)
    private(backup / 'prepared.json', before_plan)
    for name, raw in before_sources.items():
        target = backup / name
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        private(target, raw)
    group = pwd.getpwnam(USER).pw_gid
    after_plan = json.dumps({**plan, 'files': hashes}, sort_keys=True).encode()
    written, created_package = [], False
    try:
        need(regular(OPS / 'prepared.json') == before_plan, 'prepared_plan_changed')
        if added_package is not None:
            added_package.mkdir(mode=0o750)
            created_package = True
            os.chown(added_package, 0, group)
            added_package.chmod(0o750)
        for name, raw in sorted(sources.items()):
            target = source_target(name)
            if name in added:
                private(target, raw, gid=group, mode=0o640)
            else:
                need(sha(regular(target)) == plan['files'][name], 'prepared_source_changed')
                replace(target, raw, gid=group, mode=0o640)
            written.append(name)
        need(regular(OPS / 'prepared.json') == before_plan, 'prepared_plan_changed')
        record('prepared.json', {**plan, 'files': hashes})
        prepared()
        unchanged()
    except Exception:
        if not written and not created_package:
            raise
        # Restore only our own exact outputs. Concurrent administrator edits
        # survive; never delete an unknown file or replace an external plan.
        restored = True
        for name in reversed(written):
            try:
                target = source_target(name)
                need(regular(target) == sources[name], 'source_refresh_restore_conflict')
                if name in added:
                    target.unlink()
                else:
                    replace(target, before_sources[name], gid=group, mode=0o640)
            except Exception:
                restored = False
        try:
            current_plan = regular(OPS / 'prepared.json')
            if current_plan == after_plan:
                replace(OPS / 'prepared.json', before_plan)
            else:
                need(current_plan == before_plan, 'source_refresh_restore_conflict')
            if created_package:
                added_package.rmdir()
        except Exception:
            restored = False
        need(restored, 'source_refresh_restore_conflict')
        raise
    return {'ok': True, 'phase': 'WEB_AUTH_CANDIDATE_REFRESHED_AFTER_ROLLBACK',
            'source_files': len(sources), 'candidate_updated': True, 'keys_and_state_preserved': True,
            'previous_candidate_backup_preserved': True, 'existing_services_unchanged': True,
            'public_enabled': False}


def health(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        need(response.status == 200 and int(response.headers.get('Content-Length', '0')) <= 65536,
             'health_response_invalid')
        data = json.loads(response.read(65537))
    need(data == {'ok': True, 'kind': 'WS4-PLAYER-WEB-AUTH-1', 'steam_login': True,
        'isolated_accounts': True, 'local_progress_unverified': True}, 'health_contract_invalid')


def reject_anonymous(base):
    request = urllib.request.Request(base + '/v1/profile', data=b'{}', method='POST',
                                     headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=5):
            raise RuntimeError('anonymous_profile_unexpectedly_allowed')
    except urllib.error.HTTPError as error:
        with error:
            need(error.code == 403, 'anonymous_profile_rejection_invalid')
            body = json.loads(error.read(8193))
            need(body == {'ok': False, 'error': 'player_session_required'}, 'anonymous_profile_rejection_invalid')


def rollback():
    import pwd
    plan = prepared()
    need((OPS / 'activation.json').exists(), 'activation_record_required')
    unchanged()
    path = Path(plan['nginx_path'])
    current = sha(regular(path))
    need(current in (plan['nginx_before_sha256'], plan['nginx_after_sha256']), 'nginx_external_change_preserved')
    if current == plan['nginx_after_sha256']:
        replace(path, regular(OPS / 'nginx.before'), gid=plan['nginx_gid'], mode=plan['nginx_mode'])
        run(['nginx', '-t'])
        run(['systemctl', 'reload', 'nginx'])
    if UNIT.exists():
        need(regular(UNIT) == unit_source(), 'unit_external_change_preserved')
        run(['systemctl', 'disable', '--now', UNIT.name])
        UNIT.unlink()
        run(['systemctl', 'daemon-reload'])
    if LOCATIONS.exists():
        need(regular(LOCATIONS) == proxy_rules(), 'locations_external_change_preserved')
        LOCATIONS.unlink()
    pins_raw = regular(PINS)
    pins = validate_pins(pins_raw)
    original = validate_pins(regular(OPS / 'pins.before'))
    digest = plan['new_bearer_sha256']
    if digest in pins['sha256']:
        need(all(item in pins['sha256'] for item in original['sha256']), 'old_pin_changed_preserved')
        pins['sha256'].remove(digest)
        replace(PINS, json.dumps(pins, sort_keys=True).encode(), gid=pwd.getpwnam('goufayu-ws4').pw_gid, mode=0o640)
    record('rolled-back.json', {'ok': True, 'phase': 'WEB_AUTH_ROLLED_BACK', 'private_state_preserved': True})
    if (OPS / 'active.json').exists():
        record('active.json', {'ok': False, 'phase': 'WEB_AUTH_ROLLED_BACK'})
    unchanged()
    return {'ok': True, 'phase': 'WEB_AUTH_ROLLED_BACK', 'private_state_preserved': True,
            'existing_services_unchanged': True, 'public_enabled': False}


def activation_ready(plan):
    """Allow a retry only after a verified successful rollback of our own trial."""
    if (OPS / 'activation.json').exists():
        need((OPS / 'rolled-back.json').is_file() and document(OPS / 'rolled-back.json').get('ok') is True,
             'successful_rollback_required_before_retry')
        need(not (OPS / 'active.json').exists() or document(OPS / 'active.json').get('phase') == 'WEB_AUTH_ROLLED_BACK',
             'active_service_cannot_be_reactivated')
    path = Path(plan['nginx_path'])
    need(sha(regular(path)) == plan['nginx_before_sha256'], 'activation_nginx_baseline_changed')
    # Rollback serializes JSON canonically; semantic equality allows that
    # harmless whitespace change but refuses to overwrite any concurrent pin.
    need(validate_pins(regular(PINS)) == validate_pins(regular(OPS / 'pins.before')),
         'activation_pin_baseline_changed')
    need(not UNIT.exists() and not UNIT.is_symlink() and not LOCATIONS.exists() and not LOCATIONS.is_symlink(),
         'activation_namespace_changed')
    with socket.socket() as sock:
        need(sock.connect_ex(('127.0.0.1', 18767)) != 0, 'web_port_occupied')


def transport_environment(raw, relay):
    """Change precisely one env assignment, preserving all other bytes/values."""
    need(isinstance(relay, str) and relay in ('0', '1'), 'explicit_steam_tls_relay_required')
    key = 'PLAYER_WEB_AUTH_STEAM_TLS_RELAY'
    values = parse_env(raw)
    current = values.get(key, '0')
    need(current in ('0', '1'), 'existing_steam_tls_relay_invalid')
    prefix = (key + '=').encode('ascii')
    lines = raw.splitlines(keepends=True)
    indices = [index for index, line in enumerate(lines) if line.startswith(prefix)]
    need(len(indices) <= 1, 'duplicate_transport_environment_key')
    if relay == current:
        return raw, False
    replacement = prefix + json.dumps(relay).encode('ascii')
    if indices:
        index = indices[0]
        ending = b'\r\n' if lines[index].endswith(b'\r\n') else b'\n' if lines[index].endswith(b'\n') else b''
        lines[index] = replacement + ending
        return b''.join(lines), True
    separator = b'' if not raw or raw.endswith(b'\n') else b'\n'
    return raw + separator + replacement + b'\n', True


def transport_environment_permissions(path, group):
    metadata = path.stat()
    need(metadata.st_uid == 0 and metadata.st_gid == group and stat.S_IMODE(metadata.st_mode) == 0o640,
         'transport_environment_permissions_invalid')


def configure_transport():
    """Explicit stopped-candidate transport change; never starts a relay/service."""
    import pwd
    need(isinstance(STEAM_TLS_RELAY, str) and STEAM_TLS_RELAY in ('0', '1'),
         'explicit_steam_tls_relay_required')
    plan = prepared()
    unchanged()
    need((OPS / 'activation.json').is_file() and (OPS / 'rolled-back.json').is_file(),
         'successful_rollback_required_before_transport_change')
    activation_ready(plan)
    environment = CONFIG / 'auth.env'
    before_env = regular(environment)
    need(sha(before_env) == plan['env_sha256'], 'prepared_environment_changed')
    group = pwd.getpwnam(USER).pw_gid
    transport_environment_permissions(environment, group)
    after_env, changed = transport_environment(before_env, STEAM_TLS_RELAY)
    if not changed:
        return {'ok': True, 'phase': 'WEB_AUTH_TRANSPORT_UNCHANGED', 'candidate_updated': False,
                'steam_tls_relay': STEAM_TLS_RELAY == '1', 'keys_and_state_preserved': True,
                'existing_services_unchanged': True, 'public_enabled': False}
    before_plan = regular(OPS / 'prepared.json')
    backup = OPS / ('env-before-transport-' + secrets.token_hex(8))
    backup.mkdir(mode=0o700)
    private(backup / 'auth.env', before_env)
    private(backup / 'prepared.json', before_plan)
    try:
        replace(environment, after_env, gid=group, mode=0o640)
        record('prepared.json', {**plan, 'env_sha256': sha(after_env)})
        final_plan = prepared()
        unchanged()
        activation_ready(final_plan)
    except Exception as error:
        try:
            replace(environment, before_env, gid=group, mode=0o640)
            replace(OPS / 'prepared.json', before_plan)
        except Exception as restore_error:
            raise ConfigurationFailure(error, False, restore_error) from None
        raise ConfigurationFailure(error, True) from None
    return {'ok': True, 'phase': 'WEB_AUTH_TRANSPORT_CONFIGURED_NOT_STARTED', 'candidate_updated': True,
            'steam_tls_relay': STEAM_TLS_RELAY == '1', 'keys_and_state_preserved': True,
            'private_backup_preserved': True, 'existing_services_unchanged': True, 'public_enabled': False}


def activate():
    import pwd
    plan = prepared()
    need(set(plan['files']) == RUNTIME_SOURCES, 'prepared_source_incomplete')
    unchanged()
    activation_ready(plan)
    path = Path(plan['nginx_path'])
    # Invalidate an older successful rollback marker before doing any write;
    # an interrupted retry cannot claim its predecessor's rollback succeeded.
    if (OPS / 'rolled-back.json').exists():
        record('rolled-back.json', {'ok': False, 'phase': 'RETRY_ACTIVATION_STARTED'})
    record('activation.json', {'started': True})
    stage, last_health_error = 'register_upstream_pin', None
    try:
        replace(PINS, regular(OPS / 'pins.after'), gid=pwd.getpwnam('goufayu-ws4').pw_gid, mode=0o640)
        stage = 'start_sidecar_service'
        private(UNIT, unit_source(), mode=0o644)
        run(['systemctl', 'daemon-reload'])
        run(['systemctl', 'enable', '--now', UNIT.name])
        stage = 'wait_loopback_health'
        for _ in range(20):
            try:
                health('http://127.0.0.1:18767/health')
                break
            except Exception as error:
                last_health_error = error
                time.sleep(0.5)
        else:
            raise RuntimeError('sidecar_not_ready')
        unchanged()
        stage = 'install_sidecar_nginx_route'
        private(LOCATIONS, proxy_rules(), mode=0o644)
        replace(path, regular(OPS / 'nginx.after'), gid=plan['nginx_gid'], mode=plan['nginx_mode'])
        stage = 'validate_nginx'
        run(['nginx', '-t'])
        stage = 'reload_nginx'
        run(['systemctl', 'reload', 'nginx'])
        stage = 'verify_public_sidecar'
        result = verify()
        record('active.json', {'ok': True, 'phase': 'WEB_AUTH_ACTIVE'})
        return result
    except Exception as error:
        # Roll back only files which still match our reviewed before/after
        # versions. Unexpected concurrent edits are preserved and reported.
        try:
            rollback()
        except Exception as rollback_error:
            raise ActivationFailure(error, stage, False, rollback_error, last_health_error) from None
        raise ActivationFailure(error, stage, True, health_error=last_health_error) from None


def verify():
    plan = prepared()
    unchanged()
    need(run(['systemctl', 'is-active', UNIT.name]).strip() == b'active', 'web_service_inactive')
    need(regular(UNIT) == unit_source() and regular(LOCATIONS) == proxy_rules(), 'active_config_changed')
    need(sha(regular(Path(plan['nginx_path']))) == plan['nginx_after_sha256'], 'active_nginx_changed')
    pins = validate_pins(regular(PINS))
    need(plan['new_bearer_sha256'] in pins['sha256'], 'web_upstream_pin_missing')
    original = validate_pins(regular(OPS / 'pins.before'))
    need(all(item in pins['sha256'] for item in original['sha256']), 'original_upstream_pin_missing')
    run(['nginx', '-t'])
    health('http://127.0.0.1:18767/health')
    health(PUBLIC_BASE + '/health')
    reject_anonymous('http://127.0.0.1:18767')
    reject_anonymous(PUBLIC_BASE)
    db = STATE / 'auth.sqlite3'
    need(db.is_file() and not db.is_symlink() and stat.S_IMODE(db.stat().st_mode) == 0o600,
         'auth_database_mode_invalid')
    need(stat.S_IMODE(STATE.stat().st_mode) == 0o700, 'auth_state_mode_invalid')
    unchanged()
    return {'ok': True, 'phase': 'WEB_AUTH_VERIFIED', 'base_url': PUBLIC_BASE,
            'four_account_only': True, 'local_progress_unverified': True,
            'existing_services_unchanged': True, 'public_enabled': True, 'production_rows_copied': 0}


def audit():
    baseline()
    pins = validate_pins(regular(PINS))
    accounts(regular(Path('/etc/goufayu-ws4/api.env')))
    nginx_target()
    return {'ok': True, 'phase': 'WEB_AUTH_READ_ONLY_AUDIT',
            'existing_services_active': True, 'four_account_allowlist_valid': True,
            'upstream_pin_slots_available': 4 - len(pins['sha256']),
            'web_namespace_exists': any(p.exists() for p in (BASE, CONFIG, STATE, OPS, UNIT, LOCATIONS)),
            'private_values_emitted': False, 'production_rows_read': 0}


def main(mode):
    try:
        actions = {'audit': audit, 'prepare': prepare, 'configure-transport': configure_transport,
                   'activate': activate, 'verify': verify, 'rollback': rollback}
        need(mode in actions, 'unknown_mode')
        result = actions[mode]()
    except Exception as error:
        result = error.summary if isinstance(error, (ActivationFailure, ConfigurationFailure)) else {
            'ok': False, 'phase': 'WEB_AUTH_ACTION_FAILED', 'error': failure_code(error)}
        print(json.dumps(result, sort_keys=True))
        raise SystemExit(1) from None
    print(json.dumps(result, sort_keys=True))


if 'MODE' in globals():
    main(MODE)
