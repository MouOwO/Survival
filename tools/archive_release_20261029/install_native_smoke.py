"""Verify, or explicitly install, the signed 2901 package as a NEW test addon.

Uses the existing authenticated handoff unchanged. Only its reviewed-source
lookup is scoped to the frozen 2901 source; no developer addon is overwritten.
This command never launches a game or uploads a Workshop item.
"""
from pathlib import Path
import argparse,json,sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
import build_workshop as build

ADDON='svt_a2901'

def run(apply=False):
    report=build.load(ROOT/'output/release_archive_20261029/workshop_build/package.json')
    build.need(report['release_sequence']==build.SEQUENCE and report['full_runtime_validator_passed'],
               'Completed 2901 build required')
    handoff=build.pack.handoff
    original=handoff.require_reviewed_gate
    def reviewed(candidate,manifest):
        with build.reviewed_source(build.TRUSTED):
            return original(candidate,manifest)
    handoff.require_reviewed_gate=reviewed
    try:
        listing=build.load(ROOT/'publishing/workshop/test_listing.json')
        result=handoff.prepare(build.CANDIDATE,ADDON,listing['tester_steamids64'],'update',build.ITEM,apply=apply)
    finally:
        handoff.require_reviewed_gate=original
    if apply:
        build.runtime.atomic_write_json(ROOT/'output/release_archive_20261029/native_handoff.json',result)
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install',action='store_true')
    args=parser.parse_args()
    try:
        result=run(args.install)
        print(json.dumps(result,ensure_ascii=False))
    except Exception as error:
        print(json.dumps({'status':'NATIVE_HANDOFF_REFUSED','error':str(error)},ensure_ascii=False))
        raise SystemExit(1)
