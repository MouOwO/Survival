"""Preflight, or explicitly update, the existing unlisted map test listing."""
from pathlib import Path
import argparse, json, sys
sys.dont_write_bytecode = True
import build_release as build
sys.path.insert(0, str(build.ROOT / 'tools'))
import steam_workshop_upload as publisher


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    report = build.REPORT_DIR / 'package.json'
    package = build.load(report)
    build.need(package['release_sequence'] == build.SEQUENCE and package['full_runtime_validator_passed'],
               'Completed signed map build required')
    original = build.ROOT / 'publishing/workshop/test_listing.json'
    listing = build.load(original)
    build.need(listing['workshop_id'] == build.ITEM and listing['visibility_requested'] == 'unlisted',
               'Only the original restricted listing may be updated')
    listing['runtime_content_sha256'] = package['content_sha256']
    listing['release_sequence'] = build.SEQUENCE
    listing['cover'] = str((original.parent / listing['cover']).resolve())
    target = build.REPORT_DIR / 'listing.json'
    raw = json.dumps(listing, ensure_ascii=False, indent=2) + '\n'
    if target.exists():
        build.need(target.read_text('utf8') == raw, 'Reviewed listing changed')
    else:
        target.write_text(raw, encoding='utf8')
    argv = ['--candidate', str(build.VIEW), '--vpk', str(build.OUTPUT / (build.ITEM + '.vpk')),
            '--listing', str(target), '--build-report', str(report), '--state-file', str(build.JOURNAL)]
    if args.apply:
        argv += ['--apply', '--update-existing']
    previous = sys.argv
    try:
        sys.argv = [str(Path(__file__)), *argv]
        with build.inc.trusted_source(build.TRUSTED):
            return publisher.main()
    finally:
        sys.argv = previous


if __name__ == '__main__':
    raise SystemExit(main())
