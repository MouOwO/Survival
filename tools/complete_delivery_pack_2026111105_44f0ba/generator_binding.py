"""Exact immutable item-resource generator replay; never a release authority.

Only the reviewed generator and its four public inputs are exported to a fresh
temporary directory. Six outputs are compared with the selected game Git tree,
and five JS mirrors with the selected content tree. No worktree source, key,
runtime installation, compiler, VPK, SDK, journal or network is consulted.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT.parents[2] / 'content/dota_addons/Survival'
TOOL = 'tools/complete_delivery_pack_2026111105_44f0ba/generator_binding.py'
GENERATOR = 'tools/build_item_resources.py'
INPUTS = ('data/ui/item_resources.json', 'data/presentation/approved_names_20261030.json', 'panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js', 'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js')
LUA = 'scripts/vscripts/config/generated/item_resources.lua'
OUTPUTS = ('panorama/src/scripts/custom_game/common/item_resources.js', LUA, 'panorama/src/scripts/custom_game/native_ui_icons.js', 'panorama/src/scripts/custom_game/archive_v10_icons.js', INPUTS[2], INPUTS[3])
MAX_BLOB = 4 * 1024 * 1024
MAX_TOTAL = 16 * 1024 * 1024
EXECUTED_TOOL_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()

def need(value, reason):
    if not value:
        raise ValueError(reason)

def fingerprint(raw):
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(), 'md5': hashlib.md5(raw, usedforsecurity=False).hexdigest()}

def canonical(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n').encode('ascii')

class GitSource:

    def __init__(self, repository, revision):
        need(isinstance(revision, str) and re.fullmatch('[a-f0-9]{40}', revision), 'explicit_immutable_commit_required')
        self.repository = Path(repository).resolve()
        self.revision = revision
        self.cache = {}
        actual = self.git('rev-parse', '--verify', revision + '^{commit}').decode().strip()
        need(actual == revision, 'exact_commit_required')

    def git(self, *args):
        return subprocess.check_output(['git', '--no-replace-objects', '-c', 'safe.directory=' + self.repository.as_posix(), '-C', str(self.repository), *args], stderr=subprocess.PIPE, timeout=60)

    def read(self, path):
        need(path in (GENERATOR, TOOL, *INPUTS, *OUTPUTS) or path in tuple((content_path(p) for p in OUTPUTS if p != LUA)), 'unreviewed_generator_source_path')
        if path not in self.cache:
            identity = self.revision + ':' + path
            size = int(self.git('cat-file', '-s', identity))
            need(0 <= size <= MAX_BLOB, 'generator_source_size_limit')
            raw = self.git('show', identity)
            need(len(raw) == size and (not raw.startswith(b'version https://git-lfs.github.com/spec/v1')), 'exact_resolved_text_blob_required')
            need(sum((len(v) for v in self.cache.values())) + len(raw) <= MAX_TOTAL, 'generator_total_source_size_limit')
            self.cache[path] = raw
        return self.cache[path]

    def fact(self, path):
        raw = self.read(path)
        oid = self.git('rev-parse', self.revision + ':' + path).decode().strip()
        need(re.fullmatch('[a-f0-9]{40}', oid), 'git_blob_oid_required')
        return {'commit': self.revision, 'git_oid': oid, **fingerprint(raw)}

def content_path(game_path):
    need(game_path.startswith('panorama/src/'), 'only_js_has_content_mirror')
    return 'panorama/' + game_path[len('panorama/src/'):]

def tool_identity(operator, *, allow_diagnostic=False):
    actual = Path(__file__).read_bytes().replace(b'\r\n', b'\n')
    need(fingerprint(actual)['sha256'] == EXECUTED_TOOL_LF_SHA256, 'binding_tool_changed_after_load')
    try:
        pinned = operator.read(TOOL)
    except subprocess.CalledProcessError:
        pinned = None
    committed = pinned is not None and pinned.replace(b'\r\n', b'\n') == actual
    need(committed or allow_diagnostic, 'binding_tool_not_in_exact_operator_commit')
    return {'path': TOOL, 'operator_revision': operator.revision, 'loaded_lf_sha256': EXECUTED_TOOL_LF_SHA256, 'operator_blob': operator.fact(TOOL) if pinned is not None else None, 'exact_committed_tool': committed, 'diagnostic_only': not committed}

def replay(game, content, operator, identity, *, python=sys.executable, json_normalization='IDENTITY_EXACT_GIT_BYTES'):
    """One bounded O(source+output bytes) replay; no runtime/timer work.

    The generator's two legacy adapters are genuine input/output transforms.
    Other expected outputs are deliberately absent before execution, so a stale
    generated Lua/JS file cannot be accepted by merely running --check over it.
    """
    need(json_normalization in ('IDENTITY_EXACT_GIT_BYTES', 'LF_TO_CRLF'), 'explicit_reviewed_json_normalization_required')
    source = {path: game.read(path) for path in INPUTS}
    normalization = {}
    for path in INPUTS[:2]:
        raw = source[path]
        need(b'\r' not in raw, 'json_git_source_must_be_lf_before_explicit_normalization')
        if json_normalization == 'LF_TO_CRLF':
            source[path] = raw.replace(b'\n', b'\r\n')
        normalization[path] = {'normalization': json_normalization, 'git_sha256': fingerprint(raw)['sha256'], 'executed': fingerprint(source[path])}
    source[GENERATOR] = operator.read(GENERATOR)
    expected = {path: game.read(path) for path in OUTPUTS}
    mirrors = {content_path(path): content.read(content_path(path)) for path in OUTPUTS if path != LUA}
    need(sum(map(len, source.values())) + sum(map(len, expected.values())) <= MAX_TOTAL, 'generator_replay_size_limit')
    python = str(Path(python).resolve())
    need(Path(python).is_file(), 'explicit_python_executable_required')
    environment = {key: value for key, value in os.environ.items() if key.upper() in {'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP'}}
    environment.update(PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1')
    commands = []
    scratch = Path('D:/Survival_本地工具/scratch')
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='survival_item_generator_', dir=str(scratch)) as temporary:
        stage = Path(temporary)
        for path, raw in source.items():
            destination = stage / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(raw)
        for check in (False, True):
            args = [python, '-I', '-B', '-X', 'utf8', str(stage / GENERATOR)]
            if check:
                args.append('--check')
            run = subprocess.run(args, cwd=stage, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
            need(run.returncode == 0, 'immutable_generator_execution_failed')
            need(len(run.stdout) <= 65536 and len(run.stderr) <= 65536, 'generator_log_limit')
            result = json.loads(run.stdout)
            need(result.get('status') == ('CHECK_PASS' if check else 'GENERATED') and set(result.get('outputs', [])) == set(OUTPUTS) and (len(result.get('outputs', [])) == len(OUTPUTS)), 'generator_output_contract_changed_requires_review')
            commands.append({'mode': 'check' if check else 'generate', 'exit_code': 0, 'stdout_sha256': fingerprint(run.stdout)['sha256'], 'result': result})
            paths = set()
            for path in stage.rglob('*'):
                need(not path.is_symlink(), 'generator_created_symlink')
                if path.is_file():
                    paths.add(path.relative_to(stage).as_posix())
            need(paths == set(source) | set(OUTPUTS), 'generator_unreviewed_file_write')
            for path, raw in source.items():
                if path not in OUTPUTS:
                    need((stage / path).read_bytes() == raw, 'generator_modified_source:' + path)
            for path, raw in expected.items():
                need((stage / path).read_bytes() == raw, 'generated_output_not_exact_selected_git_bytes:' + path)
        for path, raw in mirrors.items():
            corresponding = 'panorama/src/' + path[len('panorama/'):]
            need(b'\r' not in raw.replace(b'\r\n', b'\n'), 'content_mirror_lone_cr')
            need(raw.replace(b'\r\n', b'\n') == expected[corresponding], 'generated_content_js_mirror_mismatch:' + path)
    inputs = {'game:' + path: game.fact(path) for path in INPUTS}
    generator = operator.fact(GENERATOR)
    outputs = {path: {'repo': 'game', 'path': path, **game.fact(path), 'inputs': sorted(inputs), 'generated_exact_git_bytes': True, 'kind': 'executable_resolver_not_protected' if path == LUA else 'authored_js_requires_official_compile'} for path in OUTPUTS}
    return {'schema': 1, 'kind': 'IMMUTABLE_ITEM_RESOURCE_GENERATOR_PROOF', 'source_revisions': {'game': game.revision, 'content': content.revision, 'operator': operator.revision}, 'binding_tool': identity, 'generator': {'path': GENERATOR, **generator}, 'executed_operator_inputs': {GENERATOR: {'revision': operator.revision, 'git_sha256': generator['sha256'], 'executed_sha256': generator['sha256'], 'executed_lf_sha256': fingerprint(source[GENERATOR].replace(b'\r\n', b'\n'))['sha256'], 'normalization': 'IDENTITY_EXACT_GIT_BYTES'}}, 'inputs': inputs, 'outputs': outputs, 'input_normalizations': normalization, 'content_mirrors': {path: {**content.fact(path), 'normalization': 'CRLF_TO_LF_ONLY', 'normalized_sha256': fingerprint(raw.replace(b'\r\n', b'\n'))['sha256']} for path, raw in mirrors.items()}, 'execution': {'python': fingerprint(Path(python).read_bytes()), 'python_version': sys.version, 'isolated_python': True, 'commands': commands, 'only_reviewed_inputs_exported': True, 'outputs_initially_absent_except_two_adapters': True, 'fresh_temporary_stage_removed': True}, 'checks': {'six_outputs_exact': True, 'five_content_mirrors_equal': True, 'generate_then_check': True, 'no_unreviewed_file_writes': True}, 'generator_exit_code': 0, 'immutable_rebuild_equals_target': True, 'protection_excluded_module': LUA, 'authority_blockers': (['BINDING_WRAPPER_NOT_YET_COMMITTED_TO_OPERATOR'] if not identity['exact_committed_tool'] else []) + ['COMPLETE_SCOPE_LEDGER_AND_RELEASE_AUTHORITY_NOT_VALIDATED'], 'runtime_files_modified': False, 'protected': False, 'compiled': False, 'sdk_calls': 0, 'network_calls': 0, 'publication_ready': False}

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--content-source-revision', required=True)
    parser.add_argument('--operator-source-revision', required=True)
    parser.add_argument('--allow-uncommitted-tool-diagnostic', action='store_true')
    parser.add_argument('--json-normalization', choices=('IDENTITY_EXACT_GIT_BYTES', 'LF_TO_CRLF'), default='IDENTITY_EXACT_GIT_BYTES')
    args = parser.parse_args(argv)
    game = GitSource(ROOT, args.source_revision)
    content = GitSource(CONTENT, args.content_source_revision)
    operator = GitSource(ROOT, args.operator_source_revision)
    identity = tool_identity(operator, allow_diagnostic=args.allow_uncommitted_tool_diagnostic)
    print(canonical(replay(game, content, operator, identity, json_normalization=args.json_normalization)).decode('ascii'), end='')
if __name__ == '__main__':
    main()
