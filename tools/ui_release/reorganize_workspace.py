"""Archive first, then migrate UI authoring files. Deletion is a separate verified PS step."""
from pathlib import Path
import hashlib, json, re, shutil, sys, zipfile

ROOT = Path(__file__).resolve().parents[2]
BACKUP = Path('D:/survival_ui_backups/release_5d5c1152eb/workspace_reorganization.zip')
REPORT = ROOT / 'tools/ui_release/reorganization.json'
MAPPING = {'spikes': 'ui', 'output': 'design'}
TEXT = {'.py', '.js', '.cjs', '.ps1', '.json', '.md', '.html', '.css', '.xml', '.txt', '.csv', '.gitignore'}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def discarded(p):
    parts = p.relative_to(ROOT).parts
    if any(x in {'evidence', 'screenshots', '_frames', 'backups', '__pycache__', 'edge_profile', 'browser_profile', '.font_inspect_deps'} or x.startswith('browser_cache') for x in parts):
        return 'Generated evidence, cache or historical backup'
    if p.suffix.lower() in {'.log', '.pyc', '.mp4', '.avi', '.webm'}:
        return 'Generated log, bytecode or recording'
    if len(parts) == 3 and p.suffix.lower() == '.png' and (p.stem.endswith('_gallery') or re.match(r'^preview(?:-\d+)?$', p.stem)):
        return 'Generated gallery or browser screenshot'
    return None

def files():
    return [p for base in MAPPING for p in (ROOT / base).rglob('*') if p.is_file()]

def rewrite(data):
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return data
    for old, new in MAPPING.items():
        text = text.replace(old + '/', new + '/').replace(old + '\\', new + '\\')
        for q in ('"', "'"):
            text = text.replace(q + old + q, q + new + q)
    return text.encode('utf-8')

if sys.argv[1] == 'backup':
    rows = []
    with zipfile.ZipFile(BACKUP, 'x', compression=zipfile.ZIP_STORED) as archive:
        for p in files():
            rel = p.relative_to(ROOT).as_posix()
            data = p.read_bytes()
            archive.writestr(rel, data)
            rows.append({'path': rel, 'bytes': len(data), 'sha256': digest(data), 'discard': discarded(p)})
        # Preserve external scripts/docs before their dependency paths change.
        for base in ['tools', 'docs']:
            for p in (ROOT / base).rglob('*'):
                if p.is_file() and p.suffix in TEXT and 'ui_release' not in p.parts:
                    data = p.read_bytes()
                    if rewrite(data) != data:
                        archive.writestr(p.relative_to(ROOT).as_posix(), data)
        archive.write(ROOT / '.gitignore', '.gitignore')
    with zipfile.ZipFile(BACKUP) as archive:
        for row in rows:
            assert digest(archive.read(row['path'])) == row['sha256'], row['path']
    REPORT.write_text(json.dumps({'backup': str(BACKUP), 'files': rows}, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Backup verified:', len(rows), 'files')
elif sys.argv[1] == 'migrate':
    report = json.loads(REPORT.read_text(encoding='utf-8'))
    assert BACKUP.exists()
    changed = []
    for row in report['files']:
        src = ROOT / row['path']
        assert digest(src.read_bytes()) == row['sha256'], src
        if row['discard']:
            continue
        parts = Path(row['path']).parts
        dest = ROOT / MAPPING[parts[0]] / Path(*parts[1:])
        assert not dest.exists(), dest
        data = src.read_bytes()
        if src.suffix in TEXT:
            data = rewrite(data)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        row['destination'] = dest.relative_to(ROOT).as_posix()
        row['destination_sha256'] = digest(data)
    for base in ['tools', 'docs']:
        for p in (ROOT / base).rglob('*'):
            if not p.is_file() or p.suffix not in TEXT or 'ui_release' in p.parts:
                continue
            data = p.read_bytes()
            updated = rewrite(data)
            if updated != data:
                p.write_bytes(updated)
                changed.append(p.relative_to(ROOT).as_posix())
    p = ROOT / '.gitignore'
    p.write_bytes(rewrite(p.read_bytes()))
    with p.open('a', encoding='utf-8') as f:
        f.write('\n# UI authoring generated artifacts (source assets remain tracked).\n/ui/**/evidence/\n/ui/**/backups/\n/ui/**/browser_cache*/\n/ui/**/.font_inspect_deps/\n/ui/**/*.log\n/design/**/backups/\n/design/**/__pycache__/\n')
    report['updated_dependents'] = changed + ['.gitignore']
    report['removed_bytes'] = sum(r['bytes'] for r in report['files'] if r['discard'])
    report['migrated_files'] = sum(1 for r in report['files'] if not r['discard'])
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Migrated:', report['migrated_files'], 'discard bytes:', report['removed_bytes'], 'updated:', len(changed))
