from pathlib import Path
import hashlib, json, sys, zipfile

ROOT = Path(__file__).resolve().parents[2]
ZIP = Path('D:/survival_ui_backups/release_5d5c1152eb/design_consolidation.zip')
REPORT = ROOT/'tools/ui_release/design_consolidation.json'
TEXT = {'.py','.js','.cjs','.ps1','.json','.md','.html','.css','.xml','.txt','.csv'}

def sha(data): return hashlib.sha256(data).hexdigest()
def rewrite(data):
    try: text=data.decode('utf-8')
    except UnicodeDecodeError: return data
    text=text.replace('design/','ui/').replace('design\\','ui\\')
    for q in ['"', "'"]: text=text.replace(q+'design'+q,q+'ui'+q)
    return text.encode('utf-8')

def dependents():
    for base in ['tools','ui','docs']:
        for p in (ROOT/base).rglob('*'):
            if p.is_file() and p.suffix in TEXT and 'ui_release' not in p.parts:
                data=p.read_bytes()
                if rewrite(data)!=data: yield p
    yield ROOT/'.gitignore'

if sys.argv[1]=='backup':
    rows=[]
    with zipfile.ZipFile(ZIP,'x',compression=zipfile.ZIP_STORED) as z:
        for p in list((ROOT/'design').rglob('*'))+list(dependents()):
            if not p.is_file():continue
            rel=p.relative_to(ROOT).as_posix();data=p.read_bytes()
            z.writestr(rel,data);rows.append({'path':rel,'sha256':sha(data)})
    with zipfile.ZipFile(ZIP) as z:
        for r in rows:assert sha(z.read(r['path']))==r['sha256']
    REPORT.write_text(json.dumps({'backup':str(ZIP),'originals':rows},indent=2),encoding='utf-8')
    print('Backup verified',len(rows))
elif sys.argv[1]=='migrate':
    report=json.loads(REPORT.read_text(encoding='utf-8'));moved=[];changed=[]
    for r in report['originals']:
        p=ROOT/r['path'];data=p.read_bytes();assert sha(data)==r['sha256'],p
        if r['path'].startswith('design/'):
            if r['path']=='design/README.md':continue
            dest=ROOT/'ui'/p.relative_to(ROOT/'design');assert not dest.exists(),dest
            if p.suffix in TEXT:data=rewrite(data)
            dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
            moved.append({'path':dest.relative_to(ROOT).as_posix(),'sha256':sha(data)})
        else:
            p.write_bytes(rewrite(data));changed.append(r['path'])
    report.update(migrated=moved,updated=changed)
    REPORT.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('Migrated',len(moved),'updated',len(changed))
