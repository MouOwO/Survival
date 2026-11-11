"""Prepare, prove and register one exact WS4 gold-pool configuration.

The default action is read-only local planning. The inherited operator uses
the existing WS4 database lock, exact function/config guards and rollback-only
temporary probe. No player rows or real draw commands are used.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOL = 'tools/ws4_lottery_config_20261111/deploy.py'
RECIPE_FILE = 'tools/ws4_lottery_config_20261111/recipe.py'
PRIOR_DEPLOY = 'tools/public_beta_config_20261106/deploy.py'
PRIOR_DEPLOY_SHA = 'b9e6dde535d2945443b0378a6556ccef89a86b7ac6dbcbc56d755ed215e5fb9f'
SOURCE_VALIDATOR = 'tools/ws4_lottery_rates_20261111/deploy.py'
OUT = Path('D:/Survival_本地工具/runs/20261111_gold_pool_3pct01/db_config')


def sha(raw): return hashlib.sha256(raw).hexdigest()
def need(ok, code):
    if not ok: raise RuntimeError(code)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


def git_blob(revision, name):
    need(isinstance(revision, str) and len(revision) == 40
         and all(ch in '0123456789abcdef' for ch in revision), 'immutable_revision_required')
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(ROOT),
                                    'show', revision + ':' + name]).replace(b'\r\n', b'\n')


need(sha((ROOT / PRIOR_DEPLOY).read_bytes().replace(b'\r\n', b'\n')) == PRIOR_DEPLOY_SHA,
     'audited_config_operator_changed')
prior = load('lottery_frozen_config_operator', ROOT / PRIOR_DEPLOY)
recipe = load('lottery_exact_config_recipe', ROOT / RECIPE_FILE)
source_validator = load('lottery_candidate_source_validator', ROOT / SOURCE_VALIDATOR)


def compose_remote():
    text = prior.REMOTE
    changes = {
        '20261106-public-beta-config-[a-f0-9]{12}': '20261111-lottery-rates-config-[a-f0-9]{12}',
        'public-beta-exact-config-v1': recipe.RECIPE,
        recipe.PARENT_BUNDLE: recipe.NEW_BUNDLE,
        'PUBLIC_BETA_CONFIG_PREPARED_NOT_REGISTERED': 'LOTTERY_RATES_CONFIG_PREPARED_NOT_REGISTERED',
        'PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS': 'LOTTERY_RATES_CONFIG_PG_PROBE_PASS',
        'PUBLIC_BETA_EXACT_CONFIG_REGISTERED': 'LOTTERY_RATES_CONFIG_REGISTERED',
        'PUBLIC_BETA_CONFIG_ACTIVE_VERIFIED': 'LOTTERY_RATES_CONFIG_ACTIVE_VERIFIED',
    }
    for before, after in changes.items():
        need(before in text, 'frozen_config_operator_anchor_changed')
        text = text.replace(before, after)
    compile(text, '<lottery-rates-config-remote>', 'exec')
    return text


REMOTE = compose_remote()
OPERATOR_FILES = (TOOL, RECIPE_FILE, PRIOR_DEPLOY, recipe.PRIOR, SOURCE_VALIDATOR)


def inputs(source_revision, operator_revision):
    need(Path(__file__).resolve() == (ROOT / TOOL).resolve(), 'reviewed_operator_worktree_required')
    operator_pins = {}
    for name in OPERATOR_FILES:
        raw = git_blob(operator_revision, name)
        need(raw == (ROOT / name).read_bytes().replace(b'\r\n', b'\n'),
             'operator_worktree_drift')
        operator_pins[name] = sha(raw)
    _, source_binding, source_pins, _ = source_validator.source_inputs(
        source_revision, operator_revision)
    bundle_raw = (source_validator.ARTIFACT / 'bundle.json').read_bytes()
    need(sha(bundle_raw) == recipe.NEW_BUNDLE
         and source_binding['candidate_receipt_sha256'] == source_validator.RECEIPT_SHA,
         'candidate_bundle_binding_changed')
    values, binding = recipe.artifacts(bundle_raw, source_revision,
                                       source_pins, source_validator.RECEIPT_SHA)
    binding['operator_revision'] = operator_revision
    binding['operator_files'] = operator_pins
    binding['record_name'] = '20261111-lottery-rates-config-' + sha(
        recipe.prior.canonical(binding))[:12]
    return values, binding, operator_pins


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='plan',
                        choices=('plan', 'prepare', 'probe', 'activate', 'verify'))
    parser.add_argument('--source-revision'); parser.add_argument('--operator-revision')
    args = parser.parse_args(argv)
    if args.mode == 'plan':
        print(json.dumps(recipe.plan())); return 0
    report = OUT / (args.mode + '.json')
    need(not report.exists(), 'preserve_existing_local_receipt')
    values, binding, pins = inputs(args.source_revision, args.operator_revision)
    if args.mode != 'prepare':
        prepared = json.loads((OUT / 'prepare.json').read_bytes())
        need(prepared.get('binding') == binding, 'prepared_config_binding_changed')
    if args.mode in ('activate', 'verify'):
        probe = json.loads((OUT / 'probe.json').read_bytes())
        need(probe.get('binding') == binding and
             probe.get('status') == 'LOTTERY_RATES_CONFIG_PG_PROBE_PASS' and
             probe.get('transaction_rollback_verified') is True,
             'reviewed_config_probe_required')
    context = dict(MODE=args.mode, BINDING=binding,
                   ARTIFACTS={name: base64.b64encode(raw).decode('ascii')
                              for name, raw in values.items()},
                   PARENT_GUARD=recipe.prior.guard_sql(recipe.PARENT_FUNCTION, False))
    remote = '\n'.join(key + '=' + repr(value) for key, value in context.items()) + '\n' + REMOTE
    need(sha(prior.TRANSPORT.read_bytes()) == prior.TRANSPORT_SHA,
         'pinned_transport_changed')
    transport = load('lottery_pinned_config_transport', prior.TRANSPORT)
    result = transport.remote(remote, timeout=180)
    result['operator_file_sha256'] = pins
    OUT.mkdir(parents=True, exist_ok=True)
    with report.open('x', encoding='utf8') as stream:
        json.dump(result, stream, sort_keys=True, indent=2); stream.write('\n')
    print(json.dumps(result)); return 0 if result.get('ok') is True else 2


if __name__ == '__main__': raise SystemExit(main())
