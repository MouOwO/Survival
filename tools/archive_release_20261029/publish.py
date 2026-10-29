"""Update only the existing restricted 2901 listing after live server verification.

Default performs the canonical publisher's complete read-only preflight. An
explicit --apply submits one update using the existing recovery journal.
"""
from pathlib import Path
import argparse,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
sys.path.insert(0,str(ROOT/'tools'))
import build_workshop as build
import steam_workshop_upload as publisher

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--apply',action='store_true')
 args=parser.parse_args()
 out=ROOT/'output/release_archive_20261029'
 package=build.load(out/'workshop_build/package.json')
 native=build.load(out/'native_smoke.json')
 live=build.load(out/'server_plan/candidate_v3/remote_verify.json')
 build.need(package['release_sequence']==build.SEQUENCE and package['full_runtime_validator_passed'],'Completed immutable build required')
 build.need(native['status']=='PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY' and native['content_sha256']==package['content_sha256'],'Actual native startup evidence required')
 build.need(live['phase']=='LIVE_VERIFIED' and live['bundle']==build.EXPECTED_ARCHIVE_BUNDLE,'Live coordinated backend required')
 argv=['--candidate',str(build.CANDIDATE),'--vpk',str(build.OUTPUT/(build.ITEM+'.vpk')),
       '--listing',str(ROOT/'publishing/workshop/test_listing.json'),'--build-report',str(out/'workshop_build/package.json'),
       '--state-file',str(build.JOURNAL)]
 if args.apply:argv+=['--apply','--update-existing']
 previous=sys.argv
 try:
  sys.argv=[str(Path(__file__)),*argv]
  with build.reviewed_source(build.TRUSTED):
   return publisher.main()
 finally:sys.argv=previous

if __name__=='__main__':
 try:raise SystemExit(main())
 except Exception as error:
  print(json.dumps({'status':'PUBLISH_REFUSED_PRESERVE_JOURNAL','error':str(error)}))
  raise SystemExit(1)
