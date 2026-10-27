"""Read only fixed, non-player WS4 CSV sources into a new ignored snapshot."""
from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

from deploy_plan import ROOT, TRANSPORT_PIN, WS4_BUNDLE_HASH
from catalog_validation import canonical

WS4_RELEASE = "/opt/goufayu-ws4/releases/20261023-auth-v1/addon"
PAYMENT_RELEASE = "/opt/goufayu/payments/20261018-checkout-gcoin-v1"
BUNDLE_HASH = WS4_BUNDLE_HASH


def source_names():
    sys.path.insert(0, str(ROOT / "server"))
    from payment_backend.csv_catalog import SOURCES
    from payment_backend.ucoin_catalog import COMMERCE_SOURCES
    return SOURCES + COMMERCE_SOURCES


def remote_source():
    # The pinned transport wraps this in try:; no future imports belong here.
    return "NAMES=" + repr(source_names()) + "\nWS4=" + repr(WS4_RELEASE) + "\nOLD=" + repr(PAYMENT_RELEASE) + "\nEXPECTED=" + repr(BUNDLE_HASH) + "\n" + r'''
from pathlib import Path
import base64,hashlib,json
def raw(path):
 p=Path(path)
 assert p.is_file() and not p.is_symlink()
 assert not any(x.is_symlink() for x in p.parents)
 data=p.read_bytes()
 assert 0<len(data)<=8000000
 return data
bundle_raw=raw(WS4+'/server/bundles/'+EXPECTED+'/bundle.json')
assert hashlib.sha256(bundle_raw).hexdigest()==EXPECTED
bundle=json.loads(bundle_raw)
pointer=raw(WS4+'/server/bundles/current.json')
assert json.loads(pointer)['hash']==EXPECTED
files={};summary={}
for name in NAMES:
 assert '..' not in Path(name).parts and not Path(name).is_absolute()
 candidates=[]
 for prefix in (WS4+'/data/csv/',OLD+'/reference_csv/'):
  path=Path(prefix+name)
  if path.exists():
   data=raw(path).replace(b'\r\n',b'\n')
   digest=hashlib.sha256(data).hexdigest()
   candidates.append({'source':str(path),'sha256':digest,'bytes':len(data),'matches_bundle':digest==bundle['csv_hashes'].get('data/csv/'+name)})
   if candidates[-1]['matches_bundle'] and name not in files:
    files[name]={'source':str(path),'sha256':digest,'bytes':len(data),'base64':base64.b64encode(data).decode()}
 summary[name]=candidates
print(json.dumps({'ok':True,'kind':'FIXED_WS4_CONFIG_ONLY_SNAPSHOT','bundle_sha256':EXPECTED,'bundle_base64':base64.b64encode(bundle_raw).decode(),'files':files,'candidates':summary,'player_rows_read':0,'remote_writes':0},ensure_ascii=False,separators=(',',':')))
'''


def fetch():
    driver = ROOT / "tools/archive_caps_20261020/remote_driver.py"
    if hashlib.sha256(driver.read_bytes()).hexdigest() != TRANSPORT_PIN:
        raise ValueError("pinned_transport_changed")
    spec = importlib.util.spec_from_file_location("ws4_readonly_config_transport", driver)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return json.loads(module.remote(remote_source(), timeout=55))


def save(value):
    if value.get("ok") is not True or value.get("bundle_sha256") != BUNDLE_HASH:
        raise ValueError("fixed_config_snapshot_identity_invalid")
    expected = set(source_names())
    if set(value["files"]) - expected or set(value["candidates"]) != expected:
        raise ValueError("fixed_config_source_set_invalid")
    bundle_raw = base64.b64decode(value.pop("bundle_base64"), validate=True)
    if hashlib.sha256(bundle_raw).hexdigest() != BUNDLE_HASH:
        raise ValueError("fixed_bundle_bytes_invalid")
    files = {}
    bundle = json.loads(bundle_raw)
    for name, row in value["files"].items():
        data = base64.b64decode(row.pop("base64"), validate=True)
        if hashlib.sha256(data).hexdigest() != row["sha256"] or len(data) != row["bytes"]:
            raise ValueError("fixed_config_bytes_invalid")
        files[name] = data
        row["bundle_bound"] = True
    # Some unchanged originals remain locally available even when the cloud
    # release overlay omits them. Require their actual bytes to match authority.
    for name in sorted(expected - set(files)):
        path = ROOT / "data/csv" / name
        data = path.read_bytes().replace(b"\r\n", b"\n")
        digest = hashlib.sha256(data).hexdigest()
        authority = bundle["csv_hashes"].get("data/csv/" + name)
        peers = [row for row in value["candidates"][name] if row["sha256"] == digest]
        auxiliary = name == "商店系统/entitlement_definitions.csv" and authority is None and bool(peers)
        if digest != authority and not auxiliary:
            continue
        files[name] = data
        value["files"][name] = {"source": str(path.relative_to(ROOT)), "sha256": digest,
                                "bytes": len(data), "bundle_bound": not auxiliary,
                                "equal_remote_sources": [row["source"] for row in peers]}
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = ROOT / "output/arcade_payment_link_20261027" / ("cloud_sources_" + stamp)
    directory.mkdir(parents=True, exist_ok=False)
    (directory / "bundle.json").write_bytes(bundle_raw)
    for name, data in files.items():
        path = directory / "reference_csv" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    value["missing_sources"] = sorted(expected - set(files))
    (directory / "provenance.json").write_bytes(canonical(value))
    return directory, value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="Read fixed remote public configuration only")
    args = parser.parse_args(argv)
    if not args.fetch:
        print(json.dumps({"network": False, "fixed_sources": len(source_names()), "bundle": BUNDLE_HASH}))
        return
    directory, value = save(fetch())
    print(json.dumps({"snapshot": str(directory), "bundle": BUNDLE_HASH, "restored_sources": len(value["files"]),
                      "missing_sources": value["missing_sources"], "remote_writes": 0, "player_rows_read": 0}, ensure_ascii=False))


if __name__ == "__main__":
    main()
