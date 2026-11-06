"""Bounded deployment-only WS4 admission drain and independent cleanup watchdog.

No imports perform I/O. Runtime/game requests incur no work. A rollout samples
at most 200 times over 20 seconds; each sample is O(T+C+S), with T<=256 threads,
C<=256 children, S<=4096 namespace TCP rows. No DB calls or business retries.
"""
from pathlib import Path
import hashlib
import http.client
import json
import contextlib
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time


PORT = 18765
MAX_DRAIN_SECONDS = 20
CONTROLLER_SECONDS = 60
WATCHDOG_SECONDS = 75
DEPLOYMENT_LOCKS = ('/var/lock/goufayu_admission_five.lock', '/var/lock/goufayu_ws4_worker_cache.lock')


class DrainError(RuntimeError):
    pass


def require(ok, code):
    if not ok:
        raise DrainError(code)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode('utf8')


def durable_new(path, value):
    path = Path(path)
    require(not path.is_symlink(), 'control_symlink_rejected')
    with path.open('xb') as stream:
        stream.write(canonical(value))
        stream.flush()
        os.fsync(stream.fileno())
    path.chmod(0o600)


def bounded_text(path, limit=4 * 1024 * 1024):
    with Path(path).open('r', encoding='ascii') as stream:
        value = stream.read(limit + 1)
    require(len(value) <= limit, 'process_probe_size_budget')
    return value


def process_identity(pid, expected_cwd=None, expected_start=None):
    require(isinstance(pid, int) and pid > 0, 'process_pid_invalid')
    root = Path('/proc') / str(pid)
    value = bounded_text(root / 'stat', 65536)
    fields = value[value.rfind(')') + 2:].split()
    start = int(fields[19])
    cwd = Path(os.readlink(root / 'cwd')).resolve()
    if expected_start is not None:
        require(start == expected_start, 'process_start_changed')
    if expected_cwd is not None:
        require(cwd == Path(expected_cwd).resolve(), 'process_cwd_changed')
    return dict(pid=pid, start=start, cwd=str(cwd))


def same_process(identity):
    try:
        return process_identity(identity['pid'], identity['cwd'], identity['start']) == identity
    except (OSError, DrainError, ValueError, IndexError):
        return False


def port_rows(pid):
    rows = []
    total = 0
    for protocol in ('tcp', 'tcp6'):
        lines = bounded_text(Path('/proc') / str(pid) / 'net' / protocol).splitlines()[1:]
        total += len(lines)
        require(total <= 4096, 'socket_probe_count_budget')
        for line in lines:
            columns = line.split()
            require(len(columns) >= 10, 'socket_probe_shape')
            address, port = columns[1].split(':')
            if int(port, 16) == PORT:
                rows.append(dict(protocol=protocol, address=address, state=columns[3], inode=columns[9]))
    return rows


def validate_listener(rows):
    listeners = [row for row in rows if row['state'] == '0A']
    require(len(listeners) == 1 and listeners[0]['protocol'] == 'tcp'
            and listeners[0]['address'] == '0100007F', 'only_ipv4_loopback_ws4_listener_required')
    return listeners[0]


def drain_sample(identity, require_listener=True):
    process_identity(identity['pid'], identity['cwd'], identity['start'])
    root = Path('/proc') / str(identity['pid'])
    tasks = list((root / 'task').iterdir())
    require(len(tasks) <= 256, 'thread_probe_count_budget')
    children = set()
    try:
        for task in tasks:
            children.update(bounded_text(task / 'children', 65536).split())
    except FileNotFoundError:
        return dict(idle=False, task_count=len(tasks), child_count=-1, active_namespace_sockets=-1)
    require(len(children) <= 256, 'child_probe_count_budget')
    rows = port_rows(identity['pid'])
    if require_listener:
        validate_listener(rows)
    active = sum(row['state'] not in ('06', '07', '0A') for row in rows)
    process_identity(identity['pid'], identity['cwd'], identity['start'])
    return dict(idle=len(tasks) == 1 and tasks[0].name == str(identity['pid']) and not children and active == 0,
                task_count=len(tasks), child_count=len(children), active_namespace_sockets=active)


def gate_audit(pid):
    """Read-only availability. Does not execute HTTP/SQL or modify any rule."""
    executable = shutil.which('iptables')
    require(executable is not None, 'iptables_required')
    executable = str(Path(executable).absolute())
    pin = digest(Path(executable).resolve().read_bytes())
    capabilities = dict(row.split(':', 1) for row in bounded_text('/proc/self/status').splitlines() if ':' in row)
    require(os.geteuid() == 0 and int(capabilities.get('CapEff', '0').strip(), 16) & (1 << 12), 'root_net_admin_required')
    require(hasattr(socket, 'SO_MARK'), 'socket_mark_required')
    result = subprocess.run([executable, '-w', '2', '-S', 'OUTPUT'], capture_output=True, timeout=4)
    require(result.returncode == 0, 'output_rules_unreadable')
    rules = result.stdout.decode('ascii')
    require('ws4-compact-' not in rules, 'previous_ws4_gate_requires_recovery')
    listener = validate_listener(port_rows(pid))
    identity = process_identity(pid)
    return dict(executable=executable, executable_sha256=pin, listener=listener,
                api_identity=identity, sample=drain_sample(identity), existing_owned_gate_count=0,
                rule_changes=0, http_calls=0, database_calls=0)


class NewConnectionGate:
    def __init__(self, executable, pin, binding, record):
        require(Path(executable).is_absolute() and re.fullmatch('[a-f0-9]{64}', pin or '') is not None, 'gate_tool_pin_required')
        self.executable, self.pin = str(executable), pin
        self.binding, self.record = binding, Path(record)
        operation = digest(canonical(binding))[:24]
        self.marker = 0x53000000 | int(operation[:6], 16)
        self.operation = operation
        self.rule = ['OUTPUT', '-o', 'lo', '-d', '127.0.0.1/32', '-p', 'tcp', '--dport', str(PORT),
                     '-m', 'conntrack', '--ctstate', 'NEW', '-m', 'mark', '!', '--mark', hex(self.marker),
                     '-m', 'comment', '--comment', 'ws4-compact-' + operation,
                     '-j', 'REJECT', '--reject-with', 'tcp-reset']
        self.intent = dict(kind='WS4_NEW_CONNECTION_GATE_V1', executable=self.executable,
                           executable_sha256=pin, binding=binding, marker=self.marker,
                           operation=operation, rule=self.rule)

    def execute(self, action):
        require(digest(Path(self.executable).resolve().read_bytes()) == self.pin, 'gate_tool_changed')
        command = [self.executable, '-w', '2', action]
        command += [self.rule[0], '1'] + self.rule[1:] if action == '-I' else self.rule
        return subprocess.run(command, capture_output=True, timeout=4).returncode

    def presence(self):
        code = self.execute('-C')
        require(code in (0, 1), 'gate_presence_unknown')
        return code == 0

    def validate_intent(self):
        require(not self.record.is_symlink() and json.loads(self.record.read_bytes()) == self.intent, 'gate_intent_changed')

    def install(self):
        require(not self.record.exists() and not self.presence(), 'gate_existing_control_or_rule')
        result = subprocess.run([self.executable, '-w', '2', '-S', 'OUTPUT'], capture_output=True, timeout=4)
        require(result.returncode == 0 and b'ws4-compact-' not in result.stdout, 'previous_ws4_gate_requires_recovery')
        durable_new(self.record, self.intent)
        # On timeout this may already be installed. Cleanup relies on the exact
        # durable intent/presence, never an in-memory installed flag.
        require(self.execute('-I') == 0, 'gate_insert_failed')
        self.verify()

    def verify(self):
        self.validate_intent()
        require(self.presence(), 'gate_missing')

    def reconcile_remove(self):
        if not self.record.exists():
            require(not self.presence(), 'unrecorded_gate_requires_review')
            return dict(removed=False, absent=True)
        self.validate_intent()
        present = self.presence()
        if present:
            # A timed-out delete is reconciled by its actual result as well.
            try:
                self.execute('-D')
            except subprocess.TimeoutExpired:
                pass
        require(not self.presence(), 'exact_gate_cleanup_failed')
        return dict(removed=present, absent=True)


def wait_for_drain(gate, identity, timeout=MAX_DRAIN_SECONDS, clock=time.monotonic, sleep=time.sleep):
    require(0 < timeout <= MAX_DRAIN_SECONDS, 'drain_budget_invalid')
    end = clock() + timeout
    stable = samples = 0
    while samples < 200 and clock() < end:
        gate.verify()
        value = drain_sample(identity)
        samples += 1
        stable = stable + 1 if value['idle'] else 0
        if stable >= 2:
            gate.verify()
            return dict(drained=True, samples=samples, final=value)
        sleep(min(.1, max(0, end - clock())))
    raise DrainError('drain_timeout_service_untouched')


class MarkedHealthConnection(http.client.HTTPConnection):
    def __init__(self, marker):
        super().__init__('127.0.0.1', PORT, timeout=3)
        self.marker = marker

    def connect(self):
        require(hasattr(socket, 'SO_MARK'), 'health_mark_unavailable')
        stream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            stream.settimeout(3)
            stream.setsockopt(socket.SOL_SOCKET, socket.SO_MARK, self.marker)
            stream.connect(('127.0.0.1', PORT))
        except BaseException:
            stream.close()
            raise
        self.sock = stream


@contextlib.contextmanager
def cleanup_locks(timeout=30):
    """Do not reopen admission while another owner might be stopping WS4."""
    import fcntl
    deadline = time.monotonic() + timeout
    with contextlib.ExitStack() as stack:
        for name in DEPLOYMENT_LOCKS:
            stream = stack.enter_context(open(name, 'a'))
            while True:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    require(time.monotonic() < deadline, 'watchdog_cleanup_lock_busy')
                    time.sleep(.1)
        yield


def watchdog_recover(context):
    """Exact gate cleanup remains available if full recovery prologue fails."""
    recovery = context['recovery_source']
    record = Path(context['record'])
    result = dict(kind='WS4_WATCHDOG_RECONCILIATION', binding=context['binding'], recovery_returned=False)
    try:
        require(digest(recovery.encode()) == context['recovery_sha256'], 'watchdog_recovery_source_changed')
        exec(compile(recovery, 'immutable_ws4_watchdog_recovery', 'exec'), {'__name__': '__main__'})
        result['recovery_returned'] = True
    except BaseException as error:
        result['recovery_error_type'] = type(error).__name__
    finally:
        try:
            gate = NewConnectionGate(context['gate_executable'], context['gate_executable_sha256'],
                                     context['binding'], record / 'gate_intent.json')
            with cleanup_locks():
                result['gate_cleanup'] = gate.reconcile_remove()
        except BaseException as error:
            result['gate_cleanup'] = dict(absent=False, error_type=type(error).__name__)
            result['operator_recovery_required'] = True
        durable_new(record / 'gate_watchdog.cleanup.json', result)
    return result


def watchdog_main(context):
    """Detached, finite controller watchdog; only the owned controller is signalled.

    Parent completion is accepted only after exact gate absence is confirmed.
    Controller death or >75 s enters the exact bound recovery program, which
    reacquires the same deployment locks and reconciles this operation only.
    """
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    parent = context['controller']
    record = Path(context['record'])
    done = record / 'gate_watchdog.done.json'
    ready = record / 'gate_watchdog.ready.json'
    binding = context['binding']
    def completed():
        try:
            return not done.is_symlink() and json.loads(done.read_bytes()) == dict(binding=binding, gate_absent=True)
        except (OSError, ValueError):
            return False
    identity = process_identity(os.getpid())
    durable_new(ready, dict(binding=binding, identity=identity, controller=parent))
    deadline = time.monotonic() + WATCHDOG_SECONDS
    reason = 'controller_exited'
    while same_process(parent):
        if completed():
            return
        if time.monotonic() >= deadline:
            reason = 'controller_deadline'
            # Only our exact Python rollout controller, never API/Dota/player
            # processes. Its catchable signal handler attempts compensation.
            require(same_process(parent), 'watchdog_controller_changed')
            os.kill(parent['pid'], signal.SIGTERM)
            for _ in range(30):
                if not same_process(parent):
                    break
                time.sleep(.1)
            if same_process(parent):
                os.kill(parent['pid'], signal.SIGKILL)
            break
        time.sleep(.2)
    # Avoid PID reuse and wait for kernel release of the controller's flock.
    for _ in range(30):
        if not same_process(parent):
            break
        time.sleep(.1)
    require(not same_process(parent), 'watchdog_controller_not_stopped')
    if completed():
        return
    try:
        durable_new(record / 'gate_watchdog.trigger.json', dict(binding=binding, reason=reason, controller=parent))
    except OSError:
        # Disk-full/receipt failure must not skip actual rule reconciliation.
        pass
    watchdog_recover(context)
