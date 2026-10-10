"""Add the bounded archive transport route to an existing backend handler.

This patch keeps the supplied handler's session/security logic. It does not copy
the older staged handler over a deployed version or change settlement bundles.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re

ROUTE = '/v1/archive/endless-batch'
CAPABILITY = '"capabilities": {"endless_batch": 1, "endless_batch_limit": 32}'


def patch_handler(source: str) -> str:
    if ROUTE not in source:
        anchor = '                elif self.path == "/v1/archive/command":'
        if source.count(anchor) != 1:
            raise ValueError('archive_command_route_anchor_invalid')
        start = source.index(anchor)
        endings = [source.find(value, start + len(anchor)) for value in
            ('\n                elif self.path', '\n                else:')]
        end = min(value for value in endings if value >= 0)
        original = source[start:end]
        if original.count('.command(payload)') != 1:
            raise ValueError('archive_command_call_anchor_invalid')
        # Clone the existing branch, including its own archive variable,
        # error-code filtering and exception translation.
        route = original.replace('/v1/archive/command', ROUTE, 1).replace(
            '.command(payload)', '.endless_batch(payload)', 1)
        source = source[:start] + route + '\n' + source[start:]
    if CAPABILITY not in source:
        anchors = re.findall(r'"protocol": 1, "config_hash": (?:application\.)?archive\.bundle\.hash', source)
        if len(anchors) != 1:
            raise ValueError('archive_config_capability_anchor_invalid')
        source = source.replace(anchors[0], anchors[0] + ', ' + CAPABILITY)
    return source


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    updated = patch_handler(args.source.read_text(encoding='utf-8-sig'))
    compile(updated, str(args.output), 'exec')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(updated, encoding='utf-8', newline='\n')
    print('ENDLESS_BATCH_HANDLER_STAGED', args.output)
