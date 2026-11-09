from __future__ import annotations
import hashlib, json, os, subprocess, sys, uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path
DEFAULT_DATA = Path('D:/Survival_本地工具/runs/packaging_jobs')
RUNTIME_ROOTS = {'scripts', 'panorama', 'materials', 'models', 'particles', 'sounds', 'soundevents', 'resource', 'maps', 'data', 'art'}

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':')) + '\n').encode()

def read(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError('文件不存在或不是有效的构建记录：' + str(path))
    return json.loads(path.read_bytes())

def write_new(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(canonical(value))

def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with temp.open('xb') as stream:
        stream.write(canonical(value))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)

def git(root, *args):
    q = subprocess.run(['git', '-c', 'safe.directory=' + Path(root).as_posix(), '-C', str(root), *args], capture_output=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if q.returncode:
        raise RuntimeError(q.stderr.decode('utf8', 'replace').strip())
    return q.stdout

def relevant(name):
    parts = name.split('/')
    return (name == 'addoninfo.txt' or parts[0] in RUNTIME_ROOTS) and (not any((p in {'tests', '__pycache__', 'node_modules'} or p.startswith('.') for p in parts)))

def baseline(project):
    project = Path(project).resolve()
    cursor = read(project / 'output/release_baselines/complete_active.json')
    p = project / cursor['baseline']
    raw = p.read_bytes()
    if digest(raw) != cursor['baseline_sha256']:
        raise ValueError('已发布版本检查点摘要不一致，不能打包')
    base = json.loads(raw)
    lineage = read(project / 'output/release_lineage_20261101/state.json')
    journal = project / 'output/four_accounts_20261022/steam_upload_state.json'
    if lineage.get('pending') is not None:
        raise ValueError('上次上传结果尚未收口，禁止重复上传；请先核对上次发行')
    if lineage['head']['sequence'] != base['parent_sequence'] or lineage['head']['canonical_journal_sha256'] != digest(journal.read_bytes()):
        raise ValueError('上次发布的官方下载验证或检查点尚未完成')
    evidence = base['complete_delivery']
    report_path = Path(evidence['report_path'])
    report_raw = report_path.read_bytes()
    if digest(report_raw) != evidence['report_sha256']:
        raise ValueError('当前正式包回执已改变')
    report = json.loads(report_raw)
    return {'cursor': cursor, 'baseline': base, 'report': report, 'journal_sha256': digest(journal.read_bytes()), 'lineage': lineage}

def source_state(project, base):
    project = Path(project)
    content = project.parents[2] / 'content/dota_addons/Survival'
    roots = {'game': project, 'content': content}
    heads = {}
    trees = {}
    dirty = []
    for role, root in roots.items():
        heads[role] = git(root, 'rev-parse', 'HEAD').decode().strip()
        entries = {}
        for line in git(root, 'ls-tree', '-r', '-z', heads[role]).split(b'\x00'):
            if not line:
                continue
            left, name = line.split(b'\t', 1)
            mode, kind, oid = left.decode().split()
            name = name.decode('utf8')
            if relevant(name):
                entries[name] = (mode, kind, oid)
        trees[role] = entries
        fields = git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all').split(b'\x00')
        index = 0
        while index < len(fields):
            field = fields[index]
            index += 1
            if not field:
                continue
            status = field[:2].decode()
            name = field[3:].decode('utf8')
            if relevant(name):
                dirty.append(role + ':' + name)
            if 'R' in status or 'C' in status:
                old = fields[index].decode('utf8')
                index += 1
                if relevant(old):
                    dirty.append(role + ':' + old)
    pending = []
    for role in roots:
        previous = base['source_inventory'][role]
        current = trees[role]
        for name in sorted({p for p in previous if relevant(p)} | set(current)):
            old = previous.get(name)
            old_entry = (old.get('mode'), old.get('kind'), old.get('oid')) if old else None
            if old_entry != current.get(name):
                pending.append(role + ':' + name)
    return {'heads': heads, 'roots': {k: str(v) for k, v in roots.items()}, 'pending_sources': pending, 'dirty_runtime': sorted(set(dirty)), 'runtime_fingerprint': digest(canonical(trees))}

def inspect(project):
    current = baseline(project)
    sources = source_state(project, current['baseline'])
    return {'version': current['baseline']['parent_sequence'], 'steam_manifest': current['baseline']['official_parent_manifest'], 'package_directory': str(Path(current['report']['output']).parent), 'source': sources, 'native_acceptance_status': current['baseline']['complete_delivery'].get('native_acceptance_status', 'NOT_ASSERTED')}

class LocalLock:

    def __init__(self, path):
        self.path = Path(path)
        self.stream = None

    def __enter__(self):
        import msvcrt
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = self.path.open('a+b')
        if self.path.stat().st_size == 0:
            self.stream.write(b'0')
            self.stream.flush()
        self.stream.seek(0)
        try:
            msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            self.stream.close()
            raise RuntimeError('已有打包任务正在运行，请等待完成')
        return self

    def __exit__(self, *args):
        import msvcrt
        if self.stream:
            self.stream.seek(0)
            msvcrt.locking(self.stream.fileno(), msvcrt.LK_UNLCK, 1)
            self.stream.close()

class Job:

    def __init__(self, folder):
        self.folder = Path(folder)
        self.config = read(self.folder / 'job.json')
        self.project = Path(self.config['project'])
        self.state = read(self.folder / 'state.json')
        self.events = self.folder / 'events.jsonl'

    def emit(self, event, **values):
        message = {'event': event, 'at_utc': datetime.now(timezone.utc).isoformat(), **values}
        with self.events.open('ab') as stream:
            stream.write(canonical(message))
        print(json.dumps(message, ensure_ascii=False), flush=True)

    def save(self):
        atomic(self.folder / 'state.json', self.state)

    def stage(self, name, title, action):
        old = self.state.setdefault('stages', {}).get(name)
        if old and old.get('status') == 'done':
            self.emit('stage_reused', stage=name, title=title)
            return old.get('result')
        self.state.update(status='running', current_stage=name, current_title=title, pid=os.getpid())
        self.save()
        self.emit('stage_started', stage=name, title=title)
        try:
            result = action()
        except Exception as error:
            self.state.update(status='failed', error=str(error), error_type=type(error).__name__)
            self.save()
            self.emit('failed', stage=name, title=title, message=str(error))
            raise
        self.state['stages'][name] = {'status': 'done', 'result': result}
        self.save()
        self.emit('stage_completed', stage=name, title=title)
        return result

    def call(self, label, tool, *args):
        attempt = self.state.setdefault('attempts', {}).get(label, 0) + 1
        self.state['attempts'][label] = attempt
        self.save()
        log_label = label + '_' + str(attempt)
        command = [sys.executable, '-B', '-X', 'utf8', str(self.project / tool), *map(str, args)]
        start = datetime.now(timezone.utc).isoformat()
        q = subprocess.run(command, cwd=self.project, capture_output=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        (self.folder / (log_label + '.stdout')).write_bytes(q.stdout)
        (self.folder / (log_label + '.stderr')).write_bytes(q.stderr)
        write_new(self.folder / (log_label + '.execution_receipt.json'), {'kind': 'ACTUAL_PACKAGER_COMMAND_EXECUTION_RECEIPT', 'argv': command, 'started_utc': start, 'returncode': q.returncode, 'stdout_sha256': digest(q.stdout), 'stderr_sha256': digest(q.stderr)})
        if q.returncode:
            raise RuntimeError(label + ' 失败：\n' + (q.stdout + q.stderr).decode('utf8', 'replace')[-4500:])
        try:
            return json.loads(q.stdout)
        except ValueError:
            values = []
            for line in q.stdout.decode('utf8', 'replace').splitlines():
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if isinstance(value, dict):
                    values.append(value)
            return values[-1] if values else {'returncode': q.returncode}

def create_job(project, mode, data=DEFAULT_DATA):
    project = Path(project).resolve()
    data = Path(data)
    data.mkdir(parents=True, exist_ok=True)
    current = baseline(project)
    source = source_state(project, current['baseline'])
    if source['dirty_runtime']:
        raise ValueError('请先提交运行文件，再开始打包：\n' + '\n'.join(source['dirty_runtime'][:30]))
    now = datetime.now(timezone(timedelta(hours=8)))
    index_path = data / 'index.json'
    index = read(index_path) if index_path.exists() else {'jobs': []}
    version = max([int(now.strftime('%Y%m%d')) * 100, current['baseline']['parent_sequence'], *[int(j['version']) for j in index['jobs']]]) + 1 if source['pending_sources'] else current['baseline']['parent_sequence']
    identity = 'pack_' + str(version) + '_' + uuid.uuid4().hex[:8]
    folder = data / identity
    folder.mkdir()
    config = {'schema': 1, 'id': identity, 'version': version, 'mode': mode, 'project': str(project), 'data_root': str(data), 'created_utc': datetime.now(timezone.utc).isoformat(), 'source': source, 'parent_cursor': current['cursor'], 'parent_journal_sha256': current['journal_sha256'], 'no_runtime_changes': not source['pending_sources']}
    write_new(folder / 'job.json', config)
    write_new(folder / 'state.json', {'status': 'created', 'stages': {}, 'expected_heads': source['heads']})
    index['jobs'].append({'id': identity, 'version': version, 'folder': str(folder)})
    atomic(index_path, index)
    return Job(folder)

def latest_job(data, project):
    index = read(Path(data) / 'index.json')
    for entry in reversed(index['jobs']):
        job = Job(entry['folder'])
        if job.project.resolve() == Path(project).resolve():
            return job
    raise ValueError('没有此项目的历史打包任务，请先执行打包')
