"""Build a fixed-scope payment release from the already reviewed payment02."""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from payment_backend import ucoin_recharge as recharge
from payment_backend.upgrade_ucoin_recharge import BASELINE,BASELINE_MANIFEST_SHA256,CANDIDATE,ARCHIVE_RELEASE,ARCHIVE_BUNDLE,REPLACED,ADDED


def sha(data):return hashlib.sha256(data).hexdigest()


def main():
    baseline=ROOT/'output/payment_release'/BASELINE
    destination=ROOT/'output/payment_release'/CANDIDATE
    raw=(baseline/'manifest.json').read_bytes()
    assert sha(raw)==BASELINE_MANIFEST_SHA256,'reviewed_baseline_manifest_changed'
    prior=json.loads(raw);files={}
    for name,digest in prior.items():
        rel=Path(name);path=baseline/rel
        assert not rel.is_absolute() and '..' not in rel.parts and '\\' not in name
        assert baseline.resolve() in path.resolve().parents and not path.is_symlink()
        data=path.read_bytes();assert sha(data)==digest,'baseline_source_changed:'+name;files[name]=data
    replacements=sorted(REPLACED)
    for name in replacements:
        files[name]=(ROOT/'server'/name).read_text(encoding='utf-8-sig').replace('\r\n','\n').encode()
    for name in ADDED:
        if not name.startswith('payment_backend/'):continue
        files[name]=(ROOT/'server'/name).read_text(encoding='utf-8-sig').replace('\r\n','\n').encode()
    audit=json.loads((ROOT/'design_refs/ucoin_recharge_20261017/remote/current_schema.json').read_bytes())
    assert audit['payment_release']==BASELINE and audit['archive_release']==ARCHIVE_RELEASE
    assert audit['status']=='READONLY_SCHEMA_PASS' and audit['database_writes']==0
    scope=dict(baseline_release=BASELINE,baseline_manifest_sha256=BASELINE_MANIFEST_SHA256,
        archive_release=ARCHIVE_RELEASE,archive_bundle=ARCHIVE_BUNDLE,
        database_function_sha256={k:v['sha256'] for k,v in audit['functions'].items()},
        catalog_hash=audit['catalog_hash'],existing_product_count=audit['product_count'],
        existing_products_md5=audit['existing_products_md5'],
        replacement=replacements,additions=sorted(ADDED),product=recharge.product(),
        existing_catalog_republished=False,existing_product_prices_changed=False,
        archive_bundle_rebuilt=False,old_order_snapshots_rewritten=False,gateway_orders_created=0)
    files['recharge_release.json']=(json.dumps(scope,ensure_ascii=False,indent=2)+'\n').encode()
    files['UCOIN_RECHARGE_RELEASE.md']='''# Recharge-only payment release

Baseline: 20261016-shop-functional-v2. The baseline manifest is pinned in recharge_release.json.
Only service.py, order_quantity.py, ucoin_catalog.py and sync_catalog.py are replaced.
All other baseline release files, reference CSVs, products and archive bundles remain unchanged.
No credential, real account, real payment order or new package dependency is included.

Fixed SKU u_coin_recharge: each unit costs CNY 1.00 (100 fen) and credits 100 U-coins.
Quantity is 1..999999. The largest total is 99999900 fen and 99999900 U-coins.
Ordinary products keep their 100-unit/1000000-fen caps and 1000-U-per-yuan item quotes.
Public recharge responses explicitly identify product_type=recharge, unit reward 100 and total reward.

After explicit deployment approval, upload/extract the reviewed tarball to the named
/opt/goufayu/payments/20261017-payment02 directory. Independently check the tarball
and manifest SHA256 from the review report. Do not overlay the current release.
From that named directory, use the existing reviewed production virtualenv:

```sh
/opt/goufayu/payments/20261016-shop-functional-v2/.venv/bin/python -m payment_backend.upgrade_ucoin_recharge validate /opt/goufayu/payments/20261016-shop-functional-v2
/opt/goufayu/payments/20261016-shop-functional-v2/.venv/bin/python -m payment_backend.upgrade_ucoin_recharge activate /opt/goufayu/payments/20261016-shop-functional-v2
```

Validation pins the current archive release/bundle, both payment manifests and
12 reviewed live payment/VIP function definitions before applying only recharge SQL. It runs
nonce synthetic database fixtures and validates one-SKU publication in savepoints.
Every DDL/data change from validation is rolled back; no payment gateway is called.
It compares 15 existing tables, and separately all non-recharge product rows.

Activation backs up first and briefly stops only the payment service. Under bounded
table/advisory locks it installs the additive SQL and inserts only the fixed new SKU.
Catalog categories and every existing SKU/price are retained; the catalog revision hash
records the old revision plus the new fixed product. It never replays workspace CSVs
or archive bundles. Existing receipt amounts, rewards and QR snapshots are untouched.
It then switches to this version-6-compatible reader, starts payment and checks health.
The game API process is verified unchanged. No real payment order is created.

After the new SQL/catalog commits, recovery retains this compatible reader; never
restore an older reader or replay quantity/monthly/bundle migrations. Recovery refuses
to overwrite another operator's changed current release. Any refusal/failure requires
review before retrying. The actual current symlink must still be the reviewed shop-functional-v2;
if it differs, STOP and prepare a new baseline review rather than bypassing the guard.
The pinned archive is 20261016-vip-recharge-v1, bundle ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb.
After a COMMIT attempt, even if its acknowledgement is lost, recovery conservatively
keeps the compatible new reader. A stop timeout also restores payment availability.
The current pointer is checked again after COMMIT before any code switch.

No deployment has been performed while preparing this archive.
'''.replace('20261017-payment02',CANDIDATE).encode()
    manifest={name:sha(data) for name,data in sorted(files.items())}
    changed={name for name in prior if manifest.get(name)!=prior[name]}
    assert changed==REPLACED and set(manifest)-set(prior)==ADDED and not set(prior)-set(manifest)
    if destination.exists():
        known=set(files)|{'manifest.json'}
        actual={p.relative_to(destination).as_posix() for p in destination.rglob('*') if p.is_file()}
        assert actual<=known and not any(p.is_symlink() for p in destination.rglob('*')),'candidate_contains_unknown_material'
    for name,data in files.items():
        path=destination/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    (destination/'manifest.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    archive=destination.with_suffix('.tar.gz')
    with tarfile.open(archive,'w:gz') as stream:
        for name in sorted([*files,'manifest.json']):
            path=destination/name;info=stream.gettarinfo(str(path),arcname=destination.name+'/'+name)
            info.uid=info.gid=0;info.uname=info.gname='';info.mode=0o644;info.mtime=0
            with path.open('rb') as content:stream.addfile(info,content)
    report=dict(release=destination.name,baseline=BASELINE,baseline_manifest_sha256=BASELINE_MANIFEST_SHA256,
        tarball=str(archive.relative_to(ROOT)),tarball_sha256=sha(archive.read_bytes()),
        manifest_sha256=sha((destination/'manifest.json').read_bytes()),manifest_entries=len(manifest),
        replaced=sorted(changed),added=sorted(ADDED),unchanged_baseline_files=len(prior)-len(changed),
        existing_catalog_republished=False,archive_bundle_rebuilt=False,existing_product_prices_changed=False,
        deployed=False,gateway_orders_created=0)
    target=ROOT/'design_refs/ucoin_recharge_20261017/server_release_rebased.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':main()
