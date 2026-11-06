"""Pure, exact-parent public-beta contract patch; no remote/deployment actions.

Preserves live onboarding and unrelated backend behavior. Source snippets and
the new helper come from an immutable Git revision. Build-time O(source bytes),
no additional refresh loop; each fresh claim adds two authenticated session
context reads (admission and pending settlement), while a replay adds only the
admission read and never grants another reward.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('public_beta_bundle_source', HERE / 'build.py')
source = importlib.util.module_from_spec(spec)
exec(compile((HERE / 'build.py').read_bytes(), str(HERE / 'build.py'), 'exec'), source.__dict__)

PARENT_SERVICE_SHA = 'ec0748b94f3e7581b9271dc23c8ab0eb0f46a0901d796c6fcbca2b434b08c4b3'
HELPER = 'server/archive_backend/public_beta_gift.py'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def methods(raw):
    text = raw.decode('utf8')
    source.need('\r' not in text, 'service_lf_source_required')
    tree = ast.parse(text)
    classes = [item for item in tree.body if isinstance(item, ast.ClassDef)
               and item.name == 'ArchiveService']
    source.need(len(classes) == 1, 'archive_service_class_required')
    lines = text.splitlines(keepends=True)
    nodes = {item.name: item for item in classes[0].body if isinstance(item, ast.FunctionDef)}
    return lines, nodes


def fragment(lines, node):
    return ''.join(lines[node.lineno - 1:node.end_lineno])


def derive(parent_raw, source_raw):
    source.need(sha(parent_raw) == PARENT_SERVICE_SHA, 'actual_parent_service_changed')
    before_lines, before_nodes = methods(parent_raw)
    desired_lines, desired_nodes = methods(source_raw)
    replacements, records = [], {}
    for name in ('validate', '_command', 'finish_prepared'):
        source.need(name in before_nodes and name in desired_nodes, 'public_beta_method_missing')
        before = fragment(before_lines, before_nodes[name])
        desired = fragment(desired_lines, desired_nodes[name])
        after = before

        def replace(old, new):
            nonlocal after
            source.need(after.count(old) == 1, 'public_beta_parent_anchor_changed:' + name)
            source.need(desired.count(new) == 1, 'public_beta_insertion_not_source_bound:' + name)
            after = after.replace(old, new, 1)

        if name == 'validate':
            replace('            if not tier or tier.get("enabled") is not True or tier.get("track") != c.get("track"):\n',
                    '            # The public-beta switch stops new settlement in Lua, while a\n'
                    '            # completed receipt remains recoverable after a lost reply.\n'
                    '            beta_replay = tier_id == "public_beta_login"\n'
                    '            if not tier or (tier.get("enabled") is not True and not beta_replay) or tier.get("track") != c.get("track"):\n')
        elif name == '_command':
            replace('        command=scope_clear(self,payload,command)\n',
                    '        command=scope_clear(self,payload,command)\n'
                    '        from .public_beta_gift import scope as scope_public_beta_gift\n'
                    '        command=scope_public_beta_gift(self,payload,command)\n')
        else:
            replace('            profile,command=prepared["profile"],dict(prepared["command"])\n',
                    '            profile,command=prepared["profile"],dict(prepared["command"])\n'
                    '            from .public_beta_gift import validate_pending as validate_public_beta_gift\n'
                    '            validate_public_beta_gift(self,account,command)\n'
                    '            from .public_beta_gift import current_activity_error\n'
                    '            public_beta_error=current_activity_error(self,command)\n')
            replace('            if legacy_error:\n',
                    '            if public_beta_error:\n'
                    "                result={'ok':False,'error':public_beta_error}\n"
                    '            elif legacy_error:\n')
        expected = desired
        if name == '_command':
            start = '        # Account tutorial metadata has its own protocol and SQL persistence.\n'
            stop = '        if not accepts(self.bundle, requested_hash, kind):'
            source.need(before.count(start) == before.count(stop) == desired.count(stop) == 1,
                        'retained_onboarding_anchor_changed')
            retained = before[before.index(start):before.index(stop)]
            source.need('from .onboarding import KINDS as onboarding_kinds' in retained
                        and '.public_beta_gift' not in retained, 'retained_onboarding_invalid')
            expected = desired.replace(stop, retained + stop, 1)
        source.need(after == expected, 'public_beta_method_outside_patch_changed:' + name)
        node = before_nodes[name]
        replacements.append((node.lineno - 1, node.end_lineno, after))
        records[name] = dict(parent_sha256=sha(before.encode()), source_sha256=sha(desired.encode()),
                             derived_sha256=sha(after.encode()))
    result = before_lines[:]
    for start, finish, value in sorted(replacements, reverse=True):
        result[start:finish] = [value]
    raw = ''.join(result).encode('utf8')
    compile(raw, '<derived-public-beta-service>', 'exec')
    return raw, dict(recipe='public-beta-exact-service-v1',
                     parent_service_sha256=sha(parent_raw),
                     source_service_sha256=sha(source_raw),
                     derived_service_sha256=sha(raw), methods=records,
                     outside_methods_unchanged=True, retained_onboarding=True)


def payloads(parent_raw, revision):
    desired = source.git_blob(revision, source.SERVICE)
    helper = source.git_blob(revision, HELPER)
    compile(helper, HELPER, 'exec')
    service, binding = derive(parent_raw, desired)
    binding.update(source_revision=revision, public_beta_helper_sha256=sha(helper))
    return {'backend/archive_backend/service.py': service,
            'backend/archive_backend/public_beta_gift.py': helper}, binding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parent-service', required=True, type=Path)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source.need(not args.output.exists(), 'exclusive_service_patch_output_required')
    values, binding = payloads(args.parent_service.read_bytes(), args.source_revision)
    args.output.mkdir(parents=True)
    for name, raw in values.items():
        path = args.output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(raw)
    report = dict(status='EXACT_PUBLIC_BETA_SERVICE_PAYLOADS_NOT_DEPLOYED', binding=binding,
                  files={name: sha(raw) for name, raw in values.items()}, remote_actions=0)
    with (args.output / 'binding.json').open('x', encoding='utf8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
