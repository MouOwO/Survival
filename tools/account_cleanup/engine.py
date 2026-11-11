"""WS4 account reset primitives. Importing performs no I/O.

Only the root SSH operator calls apply_locked; no HTTP or game entry point.
All SQL mutations belong to the caller's transaction and use one exact HMAC ID.
"""
import hashlib
import json
import re


def need(value, reason):
    if not value:
        raise ValueError(reason)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def sha(value):
    return hashlib.sha256(value).hexdigest()


def ident(value):
    need(bool(re.fullmatch('[a-z_][a-z0-9_]*', value)), 'invalid_sql_identifier')
    return '"' + value + '"'


def table(value):
    return '.'.join(ident(part) for part in value.split('.'))


def schema(conn):
    columns = conn.execute("SELECT table_schema,table_name,column_name,data_type "
        "FROM information_schema.columns WHERE table_schema NOT IN "
        "('pg_catalog','information_schema') ORDER BY 1,2,ordinal_position").fetchall()
    foreign = conn.execute("SELECT ns.nspname,t.relname,con.conname,pg_get_constraintdef(con.oid),"
        "con.confrelid::regclass::text FROM pg_constraint con JOIN pg_class t ON t.oid=con.conrelid "
        "JOIN pg_namespace ns ON ns.oid=t.relnamespace WHERE con.contype='f' AND ns.nspname "
        "NOT IN ('pg_catalog','information_schema') ORDER BY 1,2,3").fetchall()
    triggers = conn.execute("SELECT ns.nspname,t.relname,tg.tgname,pg_get_triggerdef(tg.oid) "
        "FROM pg_trigger tg JOIN pg_class t ON t.oid=tg.tgrelid JOIN pg_namespace ns "
        "ON ns.oid=t.relnamespace WHERE NOT tg.tgisinternal AND ns.nspname NOT IN "
        "('pg_catalog','information_schema') ORDER BY 1,2,3").fetchall()
    return {'columns': columns, 'foreign_keys': foreign, 'triggers': triggers}


def scope(contract):
    owned = {}
    for ns, name, column, kind in contract['columns']:
        if column == 'account_id' or (ns, name, column) == ('public', 'player_gameplay_stats', 'player_id'):
            need(kind == 'text' and ns in ('public', 'payments'), 'unreviewed_identity_column')
            owned[ns + '.' + name] = column
    need({'public.survival_players', 'public.redemption_claims', 'public.redemption_attempts',
          'payments.orders', 'payments.test_accounts'} <= owned.keys(), 'account_schema_incomplete')
    return owned


def validate_schema(conn, contract):
    need(canonical(schema(conn)) == canonical(contract), 'schema_changed_review_required')


def predicate(name, owned):
    if name == 'payments.cleared_reward_grants':
        return 'grant_id IN (SELECT grant_id FROM public.reward_grants WHERE account_id=%s)'
    return ident(owned[name]) + '=%s'


def targets(contract):
    return sorted([*scope(contract), 'payments.cleared_reward_grants'])


def snapshot(conn, account, contract, *, keep_rows=False):
    need(bool(re.fullmatch('[a-f0-9]{64}', account)), 'exact_database_identity_required')
    conn.execute("SET LOCAL timezone='UTC'")
    validate_schema(conn, contract)
    owned, summaries, snapshots = scope(contract), {}, {}
    total_rows = total_bytes = 0
    for name in targets(contract):
        query = 'SELECT to_jsonb(t)::text FROM ' + table(name) + ' t WHERE ' + predicate(name, owned)
        budget = conn.execute('SELECT count(*),coalesce(sum(octet_length(to_jsonb(t)::text)),0) FROM '
            + table(name) + ' t WHERE ' + predicate(name, owned), (account,)).fetchone()
        total_rows += budget[0]; total_bytes += int(budget[1])
        need(total_rows <= 100000 and total_bytes <= 100*1024*1024, 'account_snapshot_budget_exceeded')
        # Manual operation, bounded by statement_timeout. Deterministic content
        # ordering makes a stale plan detectable without exposing account rows.
        result = conn.execute(query + ' ORDER BY to_jsonb(t)::text', (account,))
        digest, count, size, rows = hashlib.sha256(), 0, 0, []
        for (raw,) in result:
            encoded = raw.encode(); size += len(encoded); count += 1
            need(count <= 100000 and size <= 100 * 1024 * 1024, 'account_snapshot_budget_exceeded')
            digest.update(encoded + b'\n')
            if keep_rows:
                rows.append(raw)
        summaries[name] = {'rows': count, 'sha256': digest.hexdigest(), 'bytes': size}
        if keep_rows:
            snapshots[name] = rows
    need(summaries['public.survival_players']['rows'] == 1, 'account_not_found')
    pending = conn.execute("SELECT count(*) FROM payments.orders WHERE account_id=%s "
                           "AND state NOT IN ('delivered','closed')", (account,)).fetchone()[0]
    counters = conn.execute("SELECT c.code_id,c.reserved_count,count(*) FILTER(WHERE r.account_id=%s),"
        "count(*) FROM public.redemption_codes c JOIN public.redemption_claims r USING(code_id) "
        "GROUP BY c.code_id,c.reserved_count HAVING count(*) FILTER(WHERE r.account_id=%s)>0 "
        "ORDER BY c.code_id", (account, account)).fetchall()
    for _, reserved, mine, total in counters:
        need(reserved == total and 0 < mine <= reserved, 'redemption_counter_inconsistent')
    definitions = conn.execute("SELECT coalesce(jsonb_agg(to_jsonb(c)-'reserved_count' ORDER BY code_id),"
        "'[]'::jsonb)::text FROM public.redemption_codes c").fetchone()[0]
    state = {'tables': summaries, 'code_counters': counters, 'code_definitions_sha256': sha(definitions.encode()),
             'schema_sha256': sha(canonical(contract)), 'open_payment_orders': pending}
    return {'fingerprint': sha(canonical(state)), **state}, snapshots


def lock_tables(conn, contract):
    conn.execute("SET LOCAL lock_timeout='5s'")
    conn.execute("SET LOCAL statement_timeout='30s'")
    names = sorted([*targets(contract), 'public.redemption_codes'])
    conn.execute('LOCK TABLE ' + ','.join(table(name) for name in names) + ' IN ACCESS EXCLUSIVE MODE')


def delete_order(contract):
    remaining = set(targets(contract)) - {'public.survival_players', 'payments.test_accounts'}
    edges = []
    for ns, child, _, _, parent in contract['foreign_keys']:
        child = ns + '.' + child
        parent = parent if '.' in parent else 'public.' + parent
        if child in remaining and parent in remaining:
            edges.append((child, parent))
    result = []
    while remaining:
        ready = sorted(name for name in remaining if not any(p == name and c in remaining for c, p in edges))
        need(ready, 'foreign_key_cycle_review_required')
        result.extend(ready); remaining.difference_update(ready)
    return result


def apply_locked(conn, account, contract, expected_fingerprint):
    """Requires maintenance, a verified backup and locks supplied by operator.

    No commit here. An exception rolls back deletes, counter changes and the
    temporary reward-grant trigger change together in the caller transaction.
    """
    before, _ = snapshot(conn, account, contract)
    need(before['fingerprint'] == expected_fingerprint, 'account_changed_preview_again')
    need(before['open_payment_orders'] == 0, 'pending_payment_orders_must_be_resolved')
    enabled = conn.execute("SELECT tgenabled FROM pg_trigger WHERE tgrelid='public.reward_grants'::regclass "
                           "AND tgname='reward_grants_immutable' AND NOT tgisinternal").fetchone()
    need(enabled == ('O',), 'reward_grant_immutability_not_enabled')
    owned = scope(contract)
    for code, reserved, mine, _ in before['code_counters']:
        row = conn.execute('UPDATE public.redemption_codes SET reserved_count=reserved_count-%s '
            'WHERE code_id=%s AND reserved_count=%s RETURNING reserved_count', (mine, code, reserved)).fetchone()
        need(row == (reserved - mine,), 'redemption_counter_changed')
    # This is the sole mutable account table with an immutable-delete trigger.
    # ACCESS EXCLUSIVE is held and DDL is transactional; never disable globally.
    conn.execute('ALTER TABLE public.reward_grants DISABLE TRIGGER reward_grants_immutable')
    removed = {}
    for name in delete_order(contract):
        count = conn.execute('DELETE FROM ' + table(name) + ' WHERE ' + predicate(name, owned), (account,)).rowcount
        need(count == before['tables'][name]['rows'], 'delete_count_mismatch')
        removed[name] = count
    conn.execute('ALTER TABLE public.reward_grants ENABLE TRIGGER reward_grants_immutable')
    conn.execute('UPDATE public.survival_players SET profile_revision=profile_revision+1, '
                 'created_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=%s', (account,))
    # Keep administrator admission, but discard test-reset state/generations.
    conn.execute('UPDATE payments.test_accounts SET generation=generation+1, '
                 'reset_request=NULL,reset_kind=NULL WHERE account_id=%s', (account,))
    conn.execute('INSERT INTO public.player_onboarding_state(account_id) VALUES(%s)', (account,))
    after, _ = snapshot(conn, account, contract)
    for name, record in after['tables'].items():
        expected = 1 if name in ('public.survival_players', 'public.player_onboarding_state') else (
            before['tables'][name]['rows'] if name == 'payments.test_accounts' else 0)
        need(record['rows'] == expected, 'account_not_fresh_after_reset')
    need(before['code_definitions_sha256'] == after['code_definitions_sha256'], 'code_definition_changed')
    return {'removed_rows': removed, 'released_code_claims': sum(row[2] for row in before['code_counters']),
            'after_fingerprint': after['fingerprint'], 'admission_preserved': True}
