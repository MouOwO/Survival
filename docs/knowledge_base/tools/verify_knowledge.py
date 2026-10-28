"""Read-only knowledge-bundle verification; no application or session changes."""
from pathlib import Path
import hashlib,json,re,sys

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'MANIFEST.json').read_text(encoding='utf8'))
excluded={'MANIFEST.json','SHA256SUMS.txt','MD5SUMS.md5'}
actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
expected={row['path'] for row in manifest['files']}
errors=[]
if actual-excluded != expected:errors.append('inventory mismatch')
for row in manifest['files']:
    p=root/row['path']
    if not p.is_file():errors.append('missing '+row['path']);continue
    raw=p.read_bytes()
    if len(raw)!=row['bytes'] or hashlib.sha256(raw).hexdigest()!=row['sha256']:errors.append('hash '+row['path'])
    if p.suffix in {'.md','.json','.txt','.py'}:
        try:text=raw.decode('utf8')
        except UnicodeDecodeError:errors.append('encoding '+row['path']);continue
        if '\r' in text:errors.append('line endings '+row['path'])
        if p.suffix=='.json':
            try:json.loads(text)
            except ValueError:errors.append('json '+row['path'])
    if p.suffix=='.md' and not row['path'].startswith('history/'):
        for target in re.findall(r'\]\(([^)]+)\)',raw.decode('utf8')):
            target=target.strip('<>').split('#',1)[0]
            if not target or '://' in target or target.startswith('#'):continue
            if not (p.parent/target).is_file():errors.append('link '+row['path']+' -> '+target)
for file,algo in [('SHA256SUMS.txt','sha256'),('MD5SUMS.md5','md5')]:
    for line in (root/file).read_text(encoding='utf8').splitlines():
        digest,name=line.split('  ',1);p=root/name
        if not p.is_file() or hashlib.new(algo,p.read_bytes()).hexdigest()!=digest:errors.append('checksum '+name)
print(json.dumps({'ok':not errors,'files':len(expected),'errors':errors},ensure_ascii=False))
sys.exit(bool(errors))
