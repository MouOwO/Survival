"""Preflight, or explicitly update, the original restricted Workshop item.

The prior pending failure must be reconciled through the original recovery
tool first. This wrapper does not clear or bypass the publication journal.
"""
from pathlib import Path
import argparse,json,sys
sys.dont_write_bytecode=True
import build_release as build
sys.path.insert(0,str(build.ROOT/'tools'))
import steam_workshop_upload as publisher
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--apply',action='store_true');a=p.parse_args()
 report=build.REPORT/build.PACKAGE_REPORT;package=build.base.load(report)
 build.need(package['release_sequence']==build.SEQUENCE and package['full_runtime_validator_passed'],'Completed signed portrait build required')
 original=build.ROOT/'publishing/workshop/test_listing.json';listing=build.base.load(original)
 build.need(listing['workshop_id']==build.ITEM and listing['visibility_requested']=='unlisted','Original restricted listing required')
 listing.update(runtime_content_sha256=package['content_sha256'],release_sequence=build.SEQUENCE,release_revision=build.REVISION,vpk_sha256=package['vpk_sha256'],package_bytes=sum(x['bytes'] for x in package['package_files']),runtime_files=package['files'],package_files=package['package_files'])
 listing['cover']=str((original.parent/listing['cover']).resolve())
 target=build.REPORT/'listing.json';raw=json.dumps(listing,ensure_ascii=False,indent=2)+'\n'
 if target.exists():build.need(target.read_text('utf8')==raw,'Reviewed listing changed')
 else:target.write_text(raw,encoding='utf8')
 args=['--candidate',str(build.VIEW),'--vpk',str(build.OUTPUT/(build.ITEM+'.vpk')),'--listing',str(target),'--build-report',str(report),'--state-file',str(build.base.JOURNAL)]
 if a.apply:args+=['--apply','--update-existing']
 previous=sys.argv
 try:
  sys.argv=[str(Path(__file__)),*args]
  with build.inc.trusted_source(build.TRUSTED),build.portrait_scene_maps(package['target_pins']):return publisher.main()
 finally:sys.argv=previous
if __name__=='__main__':raise SystemExit(main())
