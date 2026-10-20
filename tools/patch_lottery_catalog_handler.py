"""Add the public lottery catalog route without replacing a deployed handler."""
from __future__ import annotations
from pathlib import Path
import argparse


def patch_handler(source: str) -> str:
    if 'self.path == "/v1/lottery/catalog"' in source:
        return source
    anchor = '                elif self.path == "/v1/lottery/snapshot":'
    if source.count(anchor) != 1:
        raise ValueError("lottery_catalog_route_anchor_invalid")
    start = source.index(anchor)
    endings = [source.find(value, start + len(anchor)) for value in
               ('\n                elif self.path', '\n                else:')]
    end = min(value for value in endings if value >= 0)
    branch = source[start:end]
    if branch.count('.lottery_snapshot(payload)') != 1:
        raise ValueError("lottery_catalog_call_anchor_invalid")
    # Preserve the existing archive-availability and session/authentication
    # boundary, including deployments that use a local archive variable.
    route = branch.replace('/v1/lottery/snapshot', '/v1/lottery/catalog', 1).replace(
        '.lottery_snapshot(payload)', '.lottery_catalog(payload)', 1)
    return source[:start] + route + '\n' + source[start:]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    updated = patch_handler(args.source.read_text(encoding='utf-8-sig'))
    compile(updated, str(args.output), 'exec')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(updated, encoding='utf-8', newline='\n')
    print('LOTTERY_CATALOG_HANDLER_STAGED', args.output)
