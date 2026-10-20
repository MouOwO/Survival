"""Seal the locally verified caps-baseline mode-chain overlay; no deployment or activation."""
from __future__ import annotations
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT=Path(__file__).resolve().parents[2]
def canonical(v): return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def sha(v): return hashlib.sha256(v).hexdigest()

def main(report_path):
    report_path=report_path.resolve()
    assert report_path.is_relative_to(ROOT/'output/mode_progression_release_20261020/gate_fix')
    report=json.loads(report_path.read_bytes())
    assert report['status']=='PASS' and report['cluster_stopped'] is True
    candidate=ROOT/report['candidate']
    assert candidate.is_relative_to(ROOT/'output/mgate20')
    review=json.loads((candidate/'review.json').read_bytes())
    assert review['bundle']==report['bundle'] and review['changed_configs']==[]
    assert review['pointer_changed'] is False and review['remote_deployment'] is False
    files={}
    for name,expected in review['files'].items():
        source=candidate/name
        assert source.is_file() and not source.is_symlink() and sha(source.read_bytes())==expected
        files['overlay/'+name]=source.read_bytes()
    files['review.json']=(candidate/'review.json').read_bytes()
    files['verification/mode_only.json']=report_path.read_bytes()
    guard=ROOT/report['registration']['sql']
    files['database/archive_sync_registration_REVIEW_ONLY.sql']=guard.read_bytes()
    package_review={'status':'LOCALLY_VERIFIED_MODE_ONLY_PACKAGE_NOT_DEPLOYED',
        'bundle':review['bundle'],'parent':review['parent'],'baseline_release':review['baseline_release'],
        'baseline_manifest_sha256':review['baseline_manifest_sha256'],
        'changed_configs':[],'changed_lua_sources':review['changed_lua_sources'],
        'daily_parent_behavior_preserved':True,'historical_compatibility_preserved':review['historical_compatibility_preserved'],
        'old_bundles_retained':len(review['retained_old_bundles']),'mode_checks':report['checks'],
        'running_pointer_changed':False,'remote_deployment':False,
        'sql_guard_note':'Based on the local frozen guard. Compare fresh live definition, release fingerprint and ledger before applying; this package is not a deployment authorization.',
        'migration_scope':'Only new 202610200004_mode_unlock_chain.sql. Applied002/003 bytes and ledger remain unchanged; the current daily, clear scope, catalogue and commerce behavior is retained.',
        'not_tested':['Live deployment','Real accounts','Native game rendering','Real four-player transport','Payment'],
        'files':{name:sha(raw) for name,raw in sorted(files.items())}}
    files['package_review.json']=canonical(package_review)
    output=io.BytesIO()
    with gzip.GzipFile(fileobj=output,mode='wb',mtime=0) as compressed:
        with tarfile.open(fileobj=compressed,mode='w') as tar:
            for name,raw in sorted(files.items()):
                item=tarfile.TarInfo(name);item.size=len(raw);item.mode=0o600;item.mtime=0
                tar.addfile(item,io.BytesIO(raw))
    raw=output.getvalue()
    destination=ROOT/'output/mode_progression_release_20261020/mode_only_sealed'/sha(raw)
    destination.mkdir(parents=True,exist_ok=True)
    package=destination/'mode_only_candidate.tar.gz'
    assert not package.exists() or package.read_bytes()==raw
    package.write_bytes(raw)
    (destination/'package_review.json').write_bytes(canonical(package_review))
    pointer={'status':package_review['status'],'package':str(package.relative_to(ROOT)),
        'sha256':sha(raw),'bundle':review['bundle'],'review':str((destination/'package_review.json').relative_to(ROOT)),
        'report':str(report_path.relative_to(ROOT))}
    (ROOT/'output/mode_progression_release_20261020/sealed_mode_only_candidate.json').write_bytes(canonical(pointer))
    print(json.dumps(pointer))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',required=True,type=Path)
    main(parser.parse_args().report)
