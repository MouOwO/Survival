"""Full original-item official download verification for the exact0104 package."""
from pathlib import Path
import argparse,hashlib,importlib.util,sys
sys.dont_write_bytecode=True
from release_checks import build as b,validated_package
PROTOCOL=b.ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
b.need(hashlib.sha256(PROTOCOL.read_bytes().replace(b'\r\n',b'\n')).hexdigest()=='1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f','Frozen official protocol drift')
spec=importlib.util.spec_from_file_location('five_account_official_download',PROTOCOL)
protocol=importlib.util.module_from_spec(spec);spec.loader.exec_module(protocol)
api=protocol.api
REPORT_SHA=None

def local_inputs(require_success=False,*,full=False):
 snapshots={}
 read=lambda p:protocol.read_snapshot(p,api.pack.MAX_MANIFEST,snapshots)
 read(b.REPORT/'package.json');read(b.VIEW/api.pack.handoff.MANIFEST);read(b.VIEW/api.pack.handoff.SIGNATURE)
 state=api.pack.handoff.decode_json(read(b.JOURNAL))
 report,manifest,signature=validated_package(REPORT_SHA,full=full)
 success=(state.get('uploaded') is True and state.get('owner')==api.OWNER and state.get('app_id')==api.APP
  and state.get('workshop_id')==b.ITEM and state.get('visibility_requested')==3 and state.get('release_sequence')==b.SEQUENCE
  and state.get('content_sha256')==manifest['content_sha256'] and state.get('package_files')==report['package_files']
  and state.get('vpk_sha256')==report['vpk_sha256'] and state.get('legal_agreement_required') is False)
 if require_success:b.need(success,'Successful same-package original-item upload required')
 protocol.unchanged(snapshots)
 return dict(report=report,manifest=manifest,signature=signature,state=state,snapshots=snapshots,success=success,
  expected_manifest=protocol.journal_manifest(state) if success else None,total=sum(r['bytes'] for r in report['package_files']),
  report_sha256=REPORT_SHA,state_sha256=b.sha(snapshots[b.JOURNAL]),protected_modules=184)

def main():
 global REPORT_SHA
 p=argparse.ArgumentParser(add_help=False);p.add_argument('--report-sha256',required=True);a,remaining=p.parse_known_args();REPORT_SHA=a.report_sha256
 package,_,_=validated_package(REPORT_SHA)
 record=b.load(b.BASE_RECORD);old_receipt=b.load(b.ROOT/record['download_receipt']['path'])
 for n,v in dict(ITEM=b.ITEM,SEQUENCE=b.SEQUENCE,FILE_COUNT=6917,CONTENT=package['content_sha256'],CANDIDATE=b.VIEW,TRUSTED=b.TRUSTED,
  VPK=b.OUTPUT/(b.ITEM+'.vpk'),REPORT=b.REPORT/'package.json',STATE=b.JOURNAL,OUTPUT=b.REPORT/'download_evidence',
  MINIMUM_REMOTE_UPDATED=old_receipt['pre_query']['time_updated'],local_inputs=local_inputs).items():setattr(protocol,n,v)
 values,_,_=b.payloads(package['source_revision']);old=sys.argv
 try:
  sys.argv=[old[0],*remaining]
  with b.scene_maps(),b.admission_context(values),b.inc.trusted_source(b.TRUSTED):return protocol.main()
 finally:sys.argv=old

if __name__=='__main__':raise SystemExit(main())
