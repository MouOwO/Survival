from pathlib import Path
import hashlib,json,re,sys,zipfile
R=Path(__file__).resolve().parents[2]
C=R.parents[2]/'content/dota_addons/Survival/panorama/images'
REPORT=R/'tools/art_assets/unification.json'
BACKUP=Path('D:/survival_ui_backups/release_5d5c1152eb/art_source_unification.zip')
TEXT={'.js','.cjs','.py','.ps1','.json','.md','.html','.css','.xml','.csv','.txt'}
def sha(b):return hashlib.sha256(b).hexdigest()
def rewrite(data,rel,names):
    try:s=data.decode('utf-8-sig');bom=data.startswith(b'\xef\xbb\xbf')
    except UnicodeDecodeError:return data
    for name in names:
        s=re.sub(r'(?<!art/)(?<!development/)ui/'+re.escape(name)+r'(?=[/\\\'"\s)]|$)','art/ui/development/'+name,s)
        s=s.replace('ui\\'+name,'art\\ui\\development\\'+name)
    if rel.startswith('ui/') and not any('/'+x+'/' in rel for x in ['candidate','baseline','before','received']):
        # Moved module directories are two levels deeper; sibling paths stay valid.
        s=re.sub(r"((?:__dirname|here)\s*,\s*['\"])\.\./\.\.(?=/|['\"])",r'\1../../../..',s)
        s=re.sub(r"(\$PSScriptRoot\s+['\"])\.\./\.\.(?=/|['\"])",r'\1../../../..',s)
        s=re.sub(r"(require\(['\"])\.\./\.\./tools/",r'\1../../../../tools/',s)
        depth=len(Path(rel).parts)-1
        s=s.replace('Path(__file__).resolve().parents['+str(depth)+']','Path(__file__).resolve().parents['+str(depth+2)+']')
    return (b'\xef\xbb\xbf' if bom else b'')+s.encode('utf-8')

if sys.argv[1]=='backup':
    names=[p.name for p in (R/'ui').iterdir() if p.is_dir()]
    rows=[]
    with zipfile.ZipFile(BACKUP,'x',compression=zipfile.ZIP_STORED) as z:
        for base in ['ui','panorama/src/images']:
            for p in (R/base).rglob('*'):
                if not p.is_file():continue
                rel=p.relative_to(R).as_posix();b=p.read_bytes();z.writestr(rel,b);rows.append({'path':rel,'sha256':sha(b)})
        for base in ['tools','docs']:
            for p in (R/base).rglob('*'):
                if not p.is_file() or p.suffix not in TEXT or 'ui_release' in p.parts or p.name=='unify_sources.py':continue
                rel=p.relative_to(R).as_posix();b=p.read_bytes()
                if rewrite(b,rel,names)!=b:z.writestr(rel,b);rows.append({'path':rel,'sha256':sha(b)})
        z.write(R/'.gitignore','.gitignore')
    with zipfile.ZipFile(BACKUP) as z:
        for row in rows:assert sha(z.read(row['path']))==row['sha256']
    # content sources must be identical before replacing them with a shared source junction.
    for p in C.rglob('*'):
        if p.is_file():assert sha(p.read_bytes())==sha((R/'panorama/src/images'/p.relative_to(C)).read_bytes()),p
    REPORT.write_text(json.dumps({'backup':str(BACKUP),'names':names,'files':rows},ensure_ascii=False,indent=2),encoding='utf-8')
    print('Backed up and verified',len(rows))
elif sys.argv[1]=='migrate':
    report=json.loads(REPORT.read_text(encoding='utf-8'));changed=[]
    for row in report['files']:
        rel=row['path'];p=R/rel;b=p.read_bytes();assert sha(b)==row['sha256'],p
        if rel.startswith('ui/'):
            dest=R/'art/ui/development'/p.relative_to(R/'ui')
        elif rel.startswith('panorama/src/images/'):
            dest=R/'art/ui/sources'/p.relative_to(R/'panorama/src/images')
        else:dest=p
        if dest!=p:assert not dest.exists(),dest
        if p.suffix in TEXT:b=rewrite(b,rel,report['names'])
        dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
        row['destination']=dest.relative_to(R).as_posix();row['destination_sha256']=sha(b)
    p=R/'.gitignore';b=p.read_bytes();p.write_bytes(rewrite(b,'.gitignore',report['names']))
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Migrated and updated',len(report['files']))
