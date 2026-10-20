"""Keep the complete reviewed payload/reports immutable before a narrow reseal."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'output/points_daily_unique_20261019'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(release_dir='release'):
    assert release_dir in ('release', 'release_v2', 'release_v3'), 'unreviewed_release_directory'
    out = BASE / release_dir
    spec = importlib.util.spec_from_file_location('daily_previous_checked', Path(__file__).with_name('release_operator.py'))
    operator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(operator)
    operator.OUT = out
    plan, _ = operator.checked()
    archive = out / 'previous_seal' / plan['tar_sha256']
    sources = {path.relative_to(out).as_posix(): path for path in out.rglob('*')
               if path.is_file() and 'previous_seal' not in path.relative_to(out).parts}
    sources.update({'tool_sources/' + path.name: path for path in Path(__file__).parent.glob('*.py')})
    checks = {}
    for name, source in sorted(sources.items()):
        assert not source.is_symlink(), 'previous_seal_symlink_refused'
        target = archive / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            assert digest(target) == digest(source), 'previous_seal_changed:' + name
        else:
            shutil.copyfile(source, target)
        checks[name] = digest(target)
    report = dict(status='PREVIOUS_SEAL_ARCHIVED', tar_sha256=plan['tar_sha256'], bundle=plan['bundle'], files=checks)
    record = archive / 'archive_manifest.json'
    packed = json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    if record.exists():
        assert record.read_bytes() == packed, 'previous_archive_manifest_changed'
    else:
        record.write_bytes(packed)
    print(json.dumps(dict(status=report['status'], tar_sha256=plan['tar_sha256'], files=len(checks),
        destination=str(archive.relative_to(ROOT))), ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-dir', choices=('release', 'release_v2', 'release_v3'), default='release')
    main(parser.parse_args().release_dir)
