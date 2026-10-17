"""Add one authenticated read route without replacing a deployed handler.

The existing command branch carries its own session gate, so cloning it keeps
that security context. Only the path and invoked method are changed.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re

ROUTE = '/v1/archive/endless-leaderboard'


def patch_handler(source):
    if ROUTE in source:
        if source.count(ROUTE) != 1 or source.count('.endless_leaderboard(payload)') != 1:
            raise ValueError('leaderboard_route_layout_unexpected')
        return source
    anchor = '                elif self.path == "/v1/archive/command":'
    if source.count(anchor) != 1:
        raise ValueError('archive_command_route_anchor_invalid')
    start = source.index(anchor)
    endings = [source.find(marker, start + len(anchor)) for marker in
               ('\n                elif self.path', '\n                else:')]
    endings = [position for position in endings if position >= 0]
    if not endings:
        raise ValueError('archive_command_route_end_invalid')
    end = min(endings)
    original = source[start:end]
    if original.count('.command(payload)') != 1:
        raise ValueError('archive_command_call_anchor_invalid')
    branch = original.replace('/v1/archive/command', ROUTE, 1).replace(
        '.command(payload)', '.endless_leaderboard(payload)', 1)
    # A read-method validation error uses the same ArchiveError translation as
    # command; no unvalidated payload can reach a profile or mutation route.
    branch, replacements = re.subn(r'except ArchiveError as ([a-zA-Z_][a-zA-Z0-9_]*):',
        r'except (ArchiveError, ValueError) as \1:', branch)
    if replacements != 1:
        raise ValueError('archive_command_error_translation_anchor_invalid')
    updated = source[:start] + branch + '\n' + source[start:]
    compile(updated, '<leaderboard-handler>', 'exec')
    return updated


def patch_archive_install(source):
    marker = '    service.sync()\n    return service'
    replacement = ('    service.sync()\n'
        '    from .endless_leaderboard import install as install_endless_leaderboard\n'
        '    install_endless_leaderboard(service)\n    return service')
    if replacement in source:
        return source
    if source.count(marker) != 1:
        raise ValueError('archive_install_anchor_invalid')
    return source.replace(marker, replacement, 1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--archive-service', action='store_true')
    args = parser.parse_args()
    source = args.source.read_text(encoding='utf-8-sig')
    updated = patch_archive_install(source) if args.archive_service else patch_handler(source)
    compile(updated, str(args.output), 'exec')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(updated, encoding='utf-8', newline='\n')
