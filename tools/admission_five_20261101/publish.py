"""Preflight by default; explicit --apply updates original item with five accounts."""
from pathlib import Path
import argparse,hashlib,json,re,sys
sys.dont_write_bytecode=True
from release_checks import build as b,validated_package
import steam_workshop_upload as publisher

def reference(path,digest,snapshots):
 path=b.pack.handoff.regular_path(path)
 raw=b.pack.read_metadata(path,b.pack.MAX_MANIFEST)
 b.need(re.fullmatch(r'[0-9a-f]{64}',digest or '') and b.sha(raw)==digest,'Explicit evidence path/SHA required')
 snapshots[path]=raw
 return b.pack.handoff.decode_json(raw)

def check_native(package,native):
 b.need(native.get('status')=='PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY'
  and native.get('release_sequence')==b.SEQUENCE and native.get('content_sha256')==package['content_sha256']
  and native.get('signed_resources_verified')==6917 and native.get('protected_modules_verified')==184
  and native.get('cheats') is False and native.get('normal_default_verified') is True
  and native.get('tester_count')==5 and native.get('max_players')==4
  and native.get('real_account_grants_verified') is False and native.get('multiplayer_verified') is False
  and set(native.get('markers',{}))=={'signed_addon','server_activated','initialized','layout_ready','no_script_error'}
  and all(native['markers'].values()),'Same signed candidate startup and real readonly cheats0 proof required')

def check_server(server):
 b.need(server.get('status')=='PASS_FIVE_ACCOUNT_ADMISSION_ACTIVE' and server.get('added_steamid64')==b.ADDED
  and b.exact_ids(server.get('approved_steamids64'))==sorted(b.APPROVED)
  and server.get('max_players')==4 and server.get('web_policy_active') is True and server.get('archive_policy_active') is True
  and server.get('original_accounts_preserved') is True and server.get('payments_unchanged') is True
  and server.get('bundle_preserved')==b.EXPECTED_BUNDLE and server.get('no_real_player_auth_claimed') is True
  and server.get('unlisted_unchanged') is True,'Active exact-five backend policies and preservation receipt required')

def acceptance(package,native_path,native_sha,server_path,server_sha):
 snapshots={}
 native=reference(native_path,native_sha,snapshots);check_native(package,native)
 for key in ('engine_log','native_query'):
  ref=native.get(key,{})
  b.need(isinstance(ref.get('path'),str),'Native raw reference missing')
  p=Path(ref['path']);p=p if p.is_absolute() else native_path.parent/p
  raw=b.pack.read_metadata(b.pack.handoff.regular_path(p),b.pack.MAX_MANIFEST)
  b.need(b.sha(raw)==ref.get('sha256'),'Native raw proof drift');snapshots[p]=raw
 server=reference(server_path,server_sha,snapshots);check_server(server)
 for key in ('backup','activate','verify'):
  ref=server.get(key,{})
  b.need(isinstance(ref.get('path'),str),'Backend raw receipt reference missing')
  p=Path(ref['path']);p=p if p.is_absolute() else server_path.parent/p
  reference(p,ref.get('sha256'),snapshots)
 for path,raw in snapshots.items():b.need(path.read_bytes()==raw,'Acceptance inputs changed during validation')
 return {str(p):b.sha(raw) for p,raw in snapshots.items()}

def listing(package):
 source=b.legacy.parent.REPORT/'listing.json';value=b.load(source)
 b.need(value['workshop_id']==b.ITEM and value['visibility_requested']=='unlisted' and value['max_players']==4
  and value['map']=='ws4_entry' and value['real_money_payments'] is True,'Original listing/visibility/payment declarations required')
 value.update(tester_steamids64=sorted(b.APPROVED),description=value['description'].replace('仅供四个获准账号','仅供获准账号'),
  runtime_content_sha256=package['content_sha256'],release_sequence=b.SEQUENCE,release_revision=b.REVISION,
  vpk_sha256=package['vpk_sha256'],runtime_files=6917,package_bytes=sum(r['bytes'] for r in package['package_files']),package_files=package['package_files'])
 value['cover']=str((source.parent/value['cover']).resolve())
 return value

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--report-sha256',required=True);p.add_argument('--native-proof',type=Path,required=True);p.add_argument('--native-proof-sha256',required=True)
 p.add_argument('--server-proof',type=Path,required=True);p.add_argument('--server-proof-sha256',required=True);p.add_argument('--apply',action='store_true');a=p.parse_args()
 package,_,_=validated_package(a.report_sha256,full=True)
 proof=acceptance(package,a.native_proof.resolve(),a.native_proof_sha256,a.server_proof.resolve(),a.server_proof_sha256)
 value=listing(package);target=b.REPORT/'listing.json';raw=(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
 if target.exists():b.need(target.read_bytes()==raw,'Reviewed listing changed')
 else:b.inc.write_new(target,raw)
 argv=['--candidate',str(b.VIEW),'--vpk',str(b.OUTPUT/(b.ITEM+'.vpk')),'--listing',str(target),
  '--build-report',str(b.REPORT/'package.json'),'--state-file',str(b.JOURNAL)]
 if a.apply:argv+=['--apply','--update-existing']
 values,_,_=b.payloads(package['source_revision'])
 previous=sys.argv
 try:
  sys.argv=[str(Path(__file__)),*argv]
  with b.scene_maps(),b.admission_context(values),b.inc.trusted_source(b.TRUSTED):return publisher.main()
 finally:sys.argv=previous

if __name__=='__main__':
 try:raise SystemExit(main())
 except Exception as error:print(json.dumps({'status':'PUBLISH_REFUSED_PRESERVE_JOURNAL','error':str(error)}));raise SystemExit(1)
