"""Read-only unified delivery diagnostics; no SDK grant, install or cleanup.

Pending inventory is a one-shot O(N) indexed Git audit with bounded streamed
hashing. Control records are bounded; package volumes are not re-read here.
This does not replace signed/native/SDK/download validation at publication.
"""
from contextlib import redirect_stdout
from pathlib import Path
import hashlib, io, json, os, stat
ROOT = Path(__file__).resolve().parents[1]
MAX_CONTROL_BYTES = 16 * 1024 * 1024

def read_control(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_CONTROL_BYTES:
        raise ValueError('bounded_regular_delivery_control_required')
    raw = path.read_bytes()

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate_delivery_control_key')
            result[key] = value
        return result
    value = json.loads(raw, object_pairs_hook=unique)
    if not isinstance(value, dict):
        raise ValueError('delivery_control_object_required')
    return (value, hashlib.sha256(raw).hexdigest())

def pending_inventory():
    complete = ROOT / 'output/release_baselines/complete_active.json'
    if complete.exists():
        import importlib
        import release_pipeline as pipeline
        auth = pipeline.authority()
        family = Path(auth.policy['recipe_path']).parent.name
        if family not in ('complete_delivery_release_20261103', 'complete_delivery_release_20261109', 'complete_delivery_pack_2026110902_351f87', 'complete_delivery_pack_2026111001_4705ac', 'complete_delivery_pack_2026111002_e1fa24', 'complete_delivery_pack_2026111003_b73d5c', 'complete_delivery_pack_2026111004_bdcfcd', 'complete_delivery_pack_2026111005_53969b', 'complete_delivery_pack_2026111006_49f754', 'complete_delivery_pack_2026111007_314dcb', 'complete_delivery_pack_2026111008_c0a4f5', 'complete_delivery_pack_2026111009_4969f8', 'complete_delivery_pack_2026111101_b1ea02', 'complete_delivery_pack_2026111102_e9c5c2', 'complete_delivery_pack_2026111105_44f0ba', 'complete_delivery_pack_2026111106_d18de8', 'complete_delivery_pack_2026111201_8c2c6c', 'complete_delivery_pack_2026111202_b5573e', 'complete_delivery_pack_2026111203_89cd9c', 'complete_delivery_pack_2026111204_d07060'):
            raise ValueError('registered_complete_delivery_family_required')
        cursor, _ = read_control(complete)
        if cursor.get('authority_sha256') != auth.digest:
            if family not in ('complete_delivery_release_20261109', 'complete_delivery_pack_2026110902_351f87', 'complete_delivery_pack_2026111001_4705ac', 'complete_delivery_pack_2026111002_e1fa24', 'complete_delivery_pack_2026111003_b73d5c', 'complete_delivery_pack_2026111004_bdcfcd', 'complete_delivery_pack_2026111005_53969b', 'complete_delivery_pack_2026111006_49f754', 'complete_delivery_pack_2026111007_314dcb', 'complete_delivery_pack_2026111008_c0a4f5', 'complete_delivery_pack_2026111009_4969f8', 'complete_delivery_pack_2026111101_b1ea02', 'complete_delivery_pack_2026111102_e9c5c2', 'complete_delivery_pack_2026111105_44f0ba', 'complete_delivery_pack_2026111106_d18de8', 'complete_delivery_pack_2026111201_8c2c6c', 'complete_delivery_pack_2026111202_b5573e', 'complete_delivery_pack_2026111203_89cd9c', 'complete_delivery_pack_2026111204_d07060') or cursor.get('baseline_sha256') != auth.policy.get('reviewed_source_baseline_sha256') or cursor.get('authority_sha256') != auth.policy.get('parent_authority_sha256'):
                raise ValueError('registered_complete_parent_transition_required')
            return importlib.import_module(family + '.parent_pending').inventory()
        return importlib.import_module(family + '.complete_pending').inventory()
    import release_pending_inventory as pending
    arguments = []
    active = ROOT / 'output/release_baselines/active.json'
    if active.exists():
        cursor, _ = read_control(active)
        if set(cursor) != {'baseline', 'baseline_sha256', 'baseline_registry_sha256'}:
            raise ValueError('explicit_active_baseline_cursor_required')
        arguments = ['--baseline', cursor['baseline'], '--baseline-sha256', cursor['baseline_sha256'], '--baseline-registry-sha256', cursor['baseline_registry_sha256']]
    captured = io.StringIO()
    with redirect_stdout(captured):
        result = pending.main(arguments)
    value = json.loads(captured.getvalue())
    if result != 0 or not isinstance(value, dict) or 'rows' not in value:
        raise ValueError('complete_pending_inventory_unavailable')
    return value

def pending_source_keys(pending):
    sources = [row['source']['repo'] + ':' + row['source']['path'] for row in pending['rows'] if row.get('status') != 'PARENT_BYTES_MATCH']
    sources += ['dirty:' + row['repo'] + ':' + row['path'] for row in pending.get('dirty', []) if row.get('runtime_related')]
    return sorted(set(sources))

def report_directory(auth):
    """Use the fixed complete-family control directory without following links."""
    family = Path(auth.policy['recipe_path']).parent
    if family.parent.resolve() != (ROOT / 'tools').resolve():
        raise ValueError('registered_delivery_family_required')
    if 'report_directory' not in auth.policy:
        return ROOT / 'output' / family.name
    if family.name not in ('complete_delivery_release_20261103', 'complete_delivery_release_20261109', 'complete_delivery_pack_2026110902_351f87', 'complete_delivery_pack_2026111001_4705ac', 'complete_delivery_pack_2026111002_e1fa24', 'complete_delivery_pack_2026111003_b73d5c', 'complete_delivery_pack_2026111004_bdcfcd', 'complete_delivery_pack_2026111005_53969b', 'complete_delivery_pack_2026111006_49f754', 'complete_delivery_pack_2026111007_314dcb', 'complete_delivery_pack_2026111008_c0a4f5', 'complete_delivery_pack_2026111009_4969f8', 'complete_delivery_pack_2026111101_b1ea02', 'complete_delivery_pack_2026111102_e9c5c2', 'complete_delivery_pack_2026111105_44f0ba', 'complete_delivery_pack_2026111106_d18de8', 'complete_delivery_pack_2026111201_8c2c6c', 'complete_delivery_pack_2026111202_b5573e', 'complete_delivery_pack_2026111203_89cd9c', 'complete_delivery_pack_2026111204_d07060'):
        raise ValueError('report_directory_override_requires_complete_family')
    configured = auth.policy['report_directory']
    if not isinstance(configured, str):
        raise ValueError('absolute_real_report_directory_required')
    path = Path(configured)
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('absolute_real_report_directory_required')
    for entry in (path, *path.parents):
        if os.path.lexists(entry):
            info = entry.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 1024:
                raise ValueError('report_directory_reparse_refused')
    path = path.resolve(strict=True)
    base = (ROOT / 'output').resolve(strict=True)
    if not path.is_dir() or path == base or (not path.is_relative_to(base)):
        raise ValueError('report_directory_must_be_beneath_output')
    return path

def delivery_status(auth, *, download_receipt=None, pending=None):
    import release_delivery_state as delivery
    import release_pending_inventory as inventory
    pending = pending if pending is not None else pending_inventory()
    folder = report_directory(auth)
    local, report_sha = read_control(folder / 'package.json')
    journal, journal_sha = read_control(auth.policy['canonical_journal'])
    receipt = {}
    if download_receipt is not None:
        path = Path(download_receipt).resolve()
        if not path.is_relative_to(folder.resolve()):
            raise ValueError('download_receipt_must_belong_to_registered_release')
        receipt, _ = read_control(path)
    candidate = Path(local['candidate'])
    if not candidate.is_absolute() or not candidate.resolve().is_relative_to(Path('D:/Survival_发布候选').resolve()):
        raise ValueError('external_registered_candidate_required')
    local_manifest, _ = read_control(candidate / '_release_manifest.json')
    if journal.get('uploaded') is True and journal.get('content_sha256') == local_manifest.get('content_sha256'):
        published_manifest = local_manifest
    else:
        parent_manifest = inventory.PARENT_MANIFEST
        if Path(auth.policy['recipe_path']).parent.name == 'complete_delivery_release_20261109':
            from complete_delivery_release_20261109 import parent_pending
            parent_manifest = parent_pending.PARENT_MANIFEST
        published_manifest, _ = read_control(parent_manifest)
    sources = pending_source_keys(pending)
    inputs = dict(local_package=local, local_package_report_sha256=report_sha, expected_source_revisions=local.get('source_revisions'), journal=journal, journal_sha256=journal_sha, download_receipt=receipt, local_resources=local_manifest.get('files'), published_resources=published_manifest.get('files'), pending_source_changes=sorted(set(sources)))
    result = delivery.report(inputs)
    task = delivery.report({**inputs, 'pending_source_changes': []})
    changed_inputs = []
    for name, pin in local.get('auxiliary_input_pins', {}).items():
        path = ROOT / name
        if not path.resolve().is_relative_to(ROOT) or not path.is_file() or path.is_symlink() or (path.stat().st_size > MAX_CONTROL_BYTES) or (hashlib.sha256(path.read_bytes()).hexdigest() != pin.get('sha256')):
            changed_inputs.append(name)
    if changed_inputs:
        result.update(status=delivery.LOCAL_ONLY, workshop_synchronized=False)
        result['blockers'].append('frozen_operator_inputs_changed_new_candidate_required')
    result.update(task_package_status=task['status'] if not changed_inputs else delivery.LOCAL_ONLY, task_package_delivery=task if not changed_inputs else {**task, 'status': delivery.LOCAL_ONLY, 'workshop_synchronized': False}, task_runtime_paths=local.get('changed_runtime_paths', []), project_status=result['status'], project_backlog_is_separate_from_task=True)
    result.update(pending_counts=pending['counts'], recorded_parent_sequence=pending['recorded_parent_sequence'], recorded_parent_content_sha256=pending['recorded_parent_content_sha256'], local_package_report_sha256=report_sha, changed_operator_inputs=changed_inputs, recorded_parent_is_live_remote_query=False, filesystem_actions=0, sdk_calls=0)
    return result

def retirement_plan(auth, inventory_path, *, download_receipt=None, pending=None):
    import release_retention
    path = Path(inventory_path).resolve()
    if not path.is_relative_to((ROOT / 'output').resolve()):
        raise ValueError('retirement_inventory_must_be_local_control_record')
    value, _ = read_control(path)
    state = delivery_status(auth, download_receipt=download_receipt, pending=pending)
    return release_retention.plan_retirement(value.get('inventory'), value.get('protected_paths'), state['task_package_delivery'])

def summary(value):
    result = dict(value)
    if 'rows' in result:
        result['rows_count'] = len(result.pop('rows'))
    for key in ('pending_source_changes', 'pending_resource_changes', 'retire', 'blocked'):
        if isinstance(result.get(key), list):
            result[key + '_count'] = len(result[key])
            result[key] = result[key][:12]
    return result

def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', default='delivery-status', choices=('pending', 'delivery-status', 'retire-plan'))
    parser.add_argument('--download-receipt', type=Path)
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    if args.action == 'pending':
        if args.download_receipt or args.inventory:
            parser.error('pending takes no receipt/inventory')
        value = pending_inventory()
        passed = not (value['counts']['pending'] or value['counts']['dirty_runtime'])
    else:
        import release_sdk_lineage_hook as hook
        from release_lineage_20261101 import guard
        auth = guard.load_authority(hook.AUTHORITY_FILE, hook.AUTHORITY_SHA256)
        if args.action == 'retire-plan':
            if args.inventory is None:
                parser.error('retire-plan needs --inventory')
            value = retirement_plan(auth, args.inventory, download_receipt=args.download_receipt)
            passed = value['status'] == 'RETIREMENT_PLAN_READY'
        else:
            if args.inventory:
                parser.error('delivery-status takes no retirement inventory')
            value = delivery_status(auth, download_receipt=args.download_receipt)
            passed = value['workshop_synchronized']
    print(json.dumps(value if args.full else summary(value), ensure_ascii=False, indent=2))
    return 2 if args.check and (not passed) else 0
if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(json.dumps(dict(status='LOCAL_ONLY', workshop_synchronized=False, diagnostic_error_type=type(error).__name__, publication_performed=False, sdk_calls=0)))
        raise SystemExit(2)
