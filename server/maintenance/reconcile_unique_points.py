"""Owner-only, preview-by-default repair. No payment or permanent-stat writes.

Credentials use the existing libpq service/pass files. Apply requires an exact
reviewed plan digest; every changed account is backed up atomically in SQL.
Rollback refuses to overwrite any account modified after the repair.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
sys.path.insert(0, str(ROOT / 'server/aliyun/database'))
from archive_backend.bundle import Bundle
from archive_backend.unique_points import MIGRATION, catalog, preview
from dbtool import connect


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def plans(conn, bundle, accounts=None):
    items, aliases = catalog(bundle)
    rows = conn.execute('''SELECT p.account_id,p.profile_revision,s.content_inventory,s.archive
        FROM public.survival_players p JOIN public.player_archive_state s USING(account_id)
        WHERE (%s::text[] IS NULL OR p.account_id=ANY(%s::text[]))
        ORDER BY p.account_id''', (accounts, accounts)).fetchall()
    result = []
    for account, revision, inventory, archive in rows:
        candidate = preview(inventory, archive, items, aliases)
        if candidate['changed_items']:
            result.append({'account_id': account, 'revision': revision,
                           'before_inventory': inventory, 'before_archive': archive, **candidate})
    digest = hashlib.sha256(encode({'migration': MIGRATION, 'config_hash': bundle.hash,
                                   'plans': result}).encode()).hexdigest()
    return result, digest


def apply(conn, bundle, expected_digest, accounts=None):
    # Recheck the complete reviewed snapshot under a repeatable-read transaction.
    # Individual rows are then locked in the ordinary gameplay-stats/player order.
    candidates, digest = plans(conn, bundle, accounts)
    if digest != expected_digest:
        raise ValueError('unique_points_plan_changed_preview_again')
    run = str(uuid.uuid4())
    for plan in candidates:
        account = plan['account_id']
        conn.execute('SELECT 1 FROM public.player_gameplay_stats WHERE player_id=%s FOR UPDATE', (account,))
        actual = conn.execute('SELECT profile_revision FROM public.survival_players WHERE account_id=%s FOR UPDATE', (account,)).fetchone()
        state = conn.execute('SELECT content_inventory,archive FROM public.player_archive_state WHERE account_id=%s FOR UPDATE', (account,)).fetchone()
        if actual != (plan['revision'],) or state != (plan['before_inventory'], plan['before_archive']):
            raise ValueError('unique_points_state_changed_preview_again')
        conn.execute('''INSERT INTO public.archive_unique_points_backups
            (run_id,account_id,migration_id,config_hash,before_revision,after_revision,
             before_inventory,after_inventory,before_archive,after_archive,converted_points,details)
            VALUES(%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,%s::jsonb,%s,%s::jsonb)''',
            (run, account, MIGRATION, bundle.hash, plan['revision'], plan['revision']+1,
             encode(plan['before_inventory']), encode(plan['content_inventory']),
             encode(plan['before_archive']), encode(plan['archive']), plan['converted_points'], encode(plan['details'])))
        conn.execute('UPDATE public.player_archive_state SET content_inventory=%s::jsonb,archive=%s::jsonb WHERE account_id=%s',
                     (encode(plan['content_inventory']), encode(plan['archive']), account))
        conn.execute('UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=%s', (account,))
    return {'run_id': run, 'changed_accounts': len(candidates),
            'converted_points': sum(p['converted_points'] for p in candidates), 'plan_digest': digest}


def summary(candidates):
    items = {}
    for plan in candidates:
        for detail in plan['details']:
            entry = items.setdefault(detail['id'], {'id': detail['id'], 'affected_accounts': 0,
                'previous_copies': 0, 'extra_copies': 0, 'converted_points': 0})
            entry['affected_accounts'] += 1
            entry['previous_copies'] += detail['previous_count']
            entry['extra_copies'] += detail['extra_copies']
            entry['converted_points'] += detail['converted_points']
    return sorted(items.values(), key=lambda row: (-row['converted_points'], row['id']))


def rollback(conn, run):
    records = conn.execute('''SELECT account_id,after_revision,before_inventory,after_inventory,
        before_archive,after_archive FROM public.archive_unique_points_backups
        WHERE run_id=%s AND migration_id=%s AND rolled_back_at IS NULL ORDER BY account_id''', (run, MIGRATION)).fetchall()
    for account, revision, before_inventory, after_inventory, before_archive, after_archive in records:
        conn.execute('SELECT 1 FROM public.player_gameplay_stats WHERE player_id=%s FOR UPDATE', (account,))
        actual = conn.execute('SELECT profile_revision FROM public.survival_players WHERE account_id=%s FOR UPDATE', (account,)).fetchone()
        state = conn.execute('SELECT content_inventory,archive FROM public.player_archive_state WHERE account_id=%s FOR UPDATE', (account,)).fetchone()
        if actual != (revision,) or state != (after_inventory, after_archive):
            raise ValueError('unique_points_rollback_refused_account_changed')
        conn.execute('UPDATE public.player_archive_state SET content_inventory=%s::jsonb,archive=%s::jsonb WHERE account_id=%s',
                     (encode(before_inventory), encode(before_archive), account))
        conn.execute('UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=%s', (account,))
        conn.execute('UPDATE public.archive_unique_points_backups SET rolled_back_at=now() WHERE run_id=%s AND account_id=%s', (run, account))
    return {'run_id': run, 'rolled_back_accounts': len(records)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--service', required=True, help='Existing owner libpq service, never a DSN/password')
    parser.add_argument('--bundle', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply-plan', metavar='SHA256', help='Apply exactly this preview digest')
    mode.add_argument('--rollback-run', type=uuid.UUID, help='Guarded rollback of a backup run')
    args = parser.parse_args()
    bundle = None
    if not args.rollback_run:
        current = ROOT / 'server/bundles'
        bundle = Bundle(args.bundle or current / json.loads((current/'current.json').read_text('utf-8'))['hash'])
    conn = connect(args.service, role='goufayu_owner')
    try:
        conn.execute('BEGIN ISOLATION LEVEL REPEATABLE READ' + (' READ ONLY' if not args.apply_plan and not args.rollback_run else ''))
        if args.rollback_run:
            result = rollback(conn, str(args.rollback_run))
        elif args.apply_plan:
            result = apply(conn, bundle, args.apply_plan)
        else:
            candidates, digest = plans(conn, bundle)
            result = {'preview': True, 'plan_digest': digest, 'config_hash': bundle.hash,
                      'unique_item_count': len(catalog(bundle)[0]), 'changed_accounts': len(candidates),
                      'changed_items': sum(p['changed_items'] for p in candidates),
                      'converted_points': sum(p['converted_points'] for p in candidates),
                      'items': summary(candidates)}
        conn.execute('COMMIT')
        print(encode({'ok': True, **result}))
    except BaseException:
        conn.execute('ROLLBACK')
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
