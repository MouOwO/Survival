"""Reconstruct only manifest-verified public release files from existing local copies."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASELINE='20261016-shop-functional-v2'
MANIFEST_SHA='59e0dc9130668f13a07794148224cd217a5a18b2436276f16c126165e787b66e'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    known=ROOT/'design_refs/vip_recharge_20261016/deployment/online_baseline/payment/manifest.json'
    raw=known.read_bytes();assert sha(raw)==MANIFEST_SHA,'current_public_manifest_changed'
    manifest=json.loads(raw);destination=ROOT/'output/payment_release'/BASELINE
    pools=[ROOT/'output/payment_release/20261015-payment02',
        ROOT/'design_refs/shop_functional_20261016/deployment_v2/online_baseline/payment',
        ROOT/'design_refs/shop_functional_20261016/deployment/online_baseline/payment',
        ROOT/'design_refs/vip_recharge_20261016/payment/baseline/payment',ROOT/'server']
    matches={};missing=[]
    for name,digest in manifest.items():
        relative=Path(name)
        assert not relative.is_absolute() and '..' not in relative.parts and '\\' not in name
        assert relative.suffix in ('.py','.sql','.csv','.json','.md','.txt')
        assert not any(x in name.lower() for x in ('.env','.pem','secret','password','private_key','config.json'))
        candidates=[pool/name for pool in pools]
        if name.startswith('reference_csv/'):
            candidates.append(ROOT/'design_refs/shop_functional_20261016/release_v2/payment_reference'/name[len('reference_csv/'):])
        source=next((p for p in candidates if p.is_file() and not p.is_symlink() and sha(p.read_bytes())==digest),None)
        if source is None:missing.append(name);continue
        dest=destination/name;data=source.read_bytes()
        if dest.exists():assert dest.read_bytes()==data,'immutable_baseline_changed:'+name
        else:dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
        matches[name]=str(source.relative_to(ROOT))
    if not missing:
        target=destination/'manifest.json'
        if target.exists():assert target.read_bytes()==raw
        else:target.write_bytes(raw)
    report=dict(baseline=BASELINE,manifest_sha256=MANIFEST_SHA,manifest_entries=len(manifest),
        matched_files=len(matches),missing_files=missing,matches=matches,
        downloaded_private_files=False,remote_operations=0,complete=not missing)
    path=ROOT/'design_refs/ucoin_recharge_20261017/current_baseline_reconstruction.json'
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='matches'},ensure_ascii=False))


if __name__=='__main__':main()
