from pathlib import Path
import hashlib,json,zipfile,sys,re
R=Path(__file__).resolve().parents[2]
REPORT=R/'tools/ui_release/legacy_prune.json'
BACKUP=Path('D:/survival_ui_backups/release_5d5c1152eb/legacy_ui_prune.zip')
KEEP={'remaining_ui_handoff_v1','shop_preview_v1','ui_stage3_v1','archive_polish_v1','ui_handoff_v1','font_import','ui_reuse_import','daily_rewards_import','player_hosted_feasibility'}
if sys.argv[1]=='plan':
    removed=[p for p in (R/'ui').iterdir() if p.is_dir() and p.name not in KEEP]
    removed += [R/'ui/ui_handoff_v1/candidate',R/'ui/ui_handoff_v1/baseline',R/'ui/font_import/engine_probe_fonts']
    # Retire old entry points too, instead of keeping whole obsolete UI trees for them.
    retired=set()
    prefixes=[p.relative_to(R).as_posix()+'/' for p in removed]
    for p in (R/'tools').iterdir():
        if p.suffix not in {'.js','.cjs','.py','.ps1'}:continue
        text=p.read_text(encoding='utf-8',errors='replace').replace('\\','/')
        if any(prefix in text for prefix in prefixes):retired.add(p)
    retired.add(R/'tools/test_handoff_release.cjs')
    # Remove obsolete tests that assert retired art, but keep behavioral suites.
    for name in ['test_lottery_v3_assets.js','test_archive_kit_assets.js','test_lottery_v2_assets.js']:
        retired.add(R/'tools'/name)
    targets=[p for p in removed+sorted(retired) if p.exists()]
    files={p for t in targets for p in (t.rglob('*') if t.is_dir() else [t]) if p.is_file()}
    rows=[{'path':p.relative_to(R).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(files)]
    report={'targets':[p.relative_to(R).as_posix() for p in targets],'files':rows,'bytes':sum(x['bytes'] for x in rows),'kept_directories':sorted(KEEP),'backup':str(BACKUP)}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('files',len(rows),'MiB',report['bytes']/1048576,'targets',report['targets'])
elif sys.argv[1]=='backup':
    report=json.loads(REPORT.read_text(encoding='utf-8'))
    with zipfile.ZipFile(BACKUP,'x',compression=zipfile.ZIP_STORED) as z:
        for row in report['files']:
            data=(R/row['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==row['sha256']
            z.writestr(row['path'],data)
    with zipfile.ZipFile(BACKUP) as z:
        for row in report['files']:assert hashlib.sha256(z.read(row['path'])).hexdigest()==row['sha256']
    print('Backup verified')
