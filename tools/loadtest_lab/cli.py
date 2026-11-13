"""Prepare a portable isolated lab; never creates cloud resources or starts load."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import secrets
import subprocess
import time

from .guard import (PORTS, ACCOUNT_START, canonical, sha, need, relative, read_json,
                    write_new, load, dsn, marker_guard, DEFAULT_POSTGRES_IMAGE, validate_postgres_image,
                    resolve_database_pool)

ROOT = Path(__file__).resolve().parents[2]
CSVS = ('star_blessing_reward_definitions', 'fishing_system_rules', 'player_gameplay_stats')
POOL_OVERLAYS = ('db_pool_patch.py', 'db_pool_http_patch.py', 'bounded_pool.py')


def apply_db_pool_overlay(root, cfg, revision):
    """Apply only the committed, exact-parent reviewed transport overlay once.

    Preparation is O(source bytes), with a fixed three/four operator Git reads
    and guarded patches. No Git access or source scan runs per request.
    """
    import runpy
    targets = {'postgres.py': 'runtime/fishing_api/postgres.py',
               'server.py': 'runtime/fishing_api/server.py',
               'http_request_timing.py': 'runtime/archive_backend/http_request_timing.py'}
    parent = {name: cfg['sources'][target] for name, target in targets.items()}
    mode = cfg['backend_db_pool']
    names = POOL_OVERLAYS + (('db_pool_patch_v2.py',) if mode == 'bounded-v2' else ())
    overlay_sources = {}
    for name in names:
        source = 'server/fishing_api_overrides/' + name
        raw = subprocess.run(['git', '-C', str(ROOT), 'show', revision + ':' + source],
                             capture_output=True, check=True).stdout
        need(raw.replace(b'\r\n', b'\n') == (ROOT / source).read_bytes().replace(b'\r\n', b'\n'),
             'database_pool_overlay_must_match_committed_source')
        target = ('runtime/fishing_api/_bounded_pool.py' if name == 'bounded_pool.py'
                  else 'operator/db_pool_overlays/' + name)
        path = root / target
        need(not path.exists(), 'database_pool_overlay_target_already_exists')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        cfg['sources'][target] = sha(raw)
        overlay_sources[source] = sha(raw)
    outputs = {}
    namespaces = {}
    def patch_namespace(name):
        if name not in namespaces:
            namespaces[name] = runpy.run_path(str(root / 'operator/db_pool_overlays' / name),
                                            run_name='loadtest_reviewed_pool_overlay')
        return namespaces[name]
    for filename, patch_name, function_name in (
            ('postgres.py', 'db_pool_patch_v2.py' if mode == 'bounded-v2' else 'db_pool_patch.py', 'patch_postgres'),
            ('server.py', 'db_pool_http_patch.py', 'patch_server'),
            ('http_request_timing.py', 'db_pool_http_patch.py', 'patch_timing')):
        target = targets[filename]
        path = root / target
        namespace = patch_namespace(patch_name)
        patched = namespace[function_name](path.read_text(encoding='utf-8-sig'))
        if mode == 'bounded-v2' and filename == 'server.py':
            patched = patch_namespace('db_pool_patch_v2.py')['patch_server'](patched)
        need(type(patched) is str, 'database_pool_overlay_output_invalid')
        compile(patched, target, 'exec')
        raw = patched.encode('utf8')
        path.write_bytes(raw)
        cfg['sources'][target] = outputs[filename] = sha(raw)
    cfg['backend_overlay'] = {'id': mode, 'source_revision': revision,
        'overlay_sources': overlay_sources, 'parent_runtime_sha256': parent,
        'runtime_sha256': outputs,
        'helper_sha256': cfg['sources']['runtime/fishing_api/_bounded_pool.py']}


def prepare(args):
    receipt_path = Path(args.source_receipt).resolve()
    receipt = read_json(receipt_path)
    need(receipt.get('kind') == 'READ_ONLY_LOADTEST_BACKEND_SOURCE_SNAPSHOT'
         and receipt.get('production_rows_copied') == 0, 'reviewed_source_only_snapshot_required')
    original = Path(receipt['source_root']).resolve()
    hashes = receipt['source_hashes']
    need(1 <= len(hashes) <= 200, 'source_file_budget_exceeded')
    root = Path(args.directory).resolve()
    need(not root.is_relative_to(ROOT) and root != original and not root.exists(), 'new_external_lab_directory_required')
    purpose = args.purpose
    active = args.active if args.active is not None else (2 if purpose == 'functional-smoke' else 4000)
    accounts = args.accounts if args.accounts is not None else (2 if purpose == 'functional-smoke' else 100000)
    duration = args.duration if args.duration is not None else (120 if purpose == 'functional-smoke' else 7200)
    memory_option = getattr(args, 'database_memory_mib', None)
    cpu_option = getattr(args, 'database_cpu_limit', None)
    database_memory_mib = memory_option if memory_option is not None else (256 if purpose == 'functional-smoke' else 2048)
    database_cpu_limit = cpu_option if cpu_option is not None else (.5 if purpose == 'functional-smoke' else 1)
    image_option = getattr(args, 'postgres_image', None)
    postgres_image = DEFAULT_POSTGRES_IMAGE if image_option is None else validate_postgres_image(image_option)
    backend_db_pool = getattr(args, 'backend_db_pool', 'baseline')
    pool_parameters, pool_limits = resolve_database_pool(backend_db_pool,
        http_concurrency=getattr(args, 'http_concurrency', None),
        db_concurrency=args.db_concurrency, web_concurrency=args.web_concurrency,
        pool_max_waiters=getattr(args, 'db_pool_max_waiters', None),
        pool_wait_seconds=getattr(args, 'db_pool_wait_seconds', None))
    http_concurrency = pool_parameters['effective']['http_concurrency']
    run = secrets.token_hex(16)
    cfg = {'schema': 1, 'kind': 'SURVIVAL_ISOLATED_LOADTEST', 'run_id': run,
           'purpose': purpose, 'database': 'survival_loadtest_' + run, 'ports': PORTS,
           'account_start': ACCOUNT_START, 'accounts': accounts, 'active': active,
           'duration_seconds': duration, 'http_concurrency': http_concurrency,
           'db_concurrency': args.db_concurrency, 'web_concurrency': args.web_concurrency,
           'global_http_per_minute': args.global_http_per_minute, 'sources': {},
           'wire_mode': getattr(args, 'wire_mode', 'business-wire-v1'),
           'backend_db_pool': backend_db_pool,
           'database_pool_parameters': pool_parameters,
           'topology': 'same_host_database_diagnostic',
           'database_memory_mib': database_memory_mib, 'database_cpu_limit': database_cpu_limit,
           'postgres_image': postgres_image,
           'lottery_catalog_md5': getattr(args, 'lottery_catalog_md5', None),
           'source_snapshot_sha256': sha(receipt_path.read_bytes()),
           'profile': ('baseline_limits' if (http_concurrency, args.db_concurrency,
                       args.web_concurrency, args.global_http_per_minute) == (8, 4, 24, 2400)
                       else 'parameter_experiment_not_production')}
    if pool_limits is not None:
        cfg['database_pool_limits'] = pool_limits
    private = {key: secrets.token_hex(32) for key in
               ('controller', 'backend', 'auth_secret', 'pepper', 'database_admin', 'database_app', 'marker')}
    root.mkdir(parents=True, mode=0o700)
    write_new(root / 'private.json', private)
    for name, digest in hashes.items():
        source = original.joinpath(*relative(name).parts)
        need(source.resolve().is_relative_to(original) and not source.is_symlink(), 'snapshot_path_escape')
        raw = source.read_bytes(); need(sha(raw) == digest, 'snapshot_source_changed')
        if name.startswith('bundles/'):
            target = 'addon/server/' + name
        elif name == 'database/schema.sql':
            target = 'database/10_schema.sql'
        else:
            need(name.startswith(('fishing_api/', 'archive_backend/')) and Path(name).suffix in ('.py', '.lua', '.json', '.csv'),
                 'unreviewed_snapshot_source')
            target = 'runtime/' + name
        path = root.joinpath(*relative(target).parts)
        path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        cfg['sources'][target] = sha(raw)
    need('runtime/archive_backend/worker_fast.lua' in cfg['sources'], 'actual_lua_settlement_source_required')
    revision = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], capture_output=True, check=True).stdout.decode().strip()
    for name in CSVS:
        source = 'data/csv/玩家档案系统/' + name + '.csv'
        raw = subprocess.run(['git', '-C', str(ROOT), 'show', revision + ':' + source], capture_output=True, check=True).stdout
        target = 'addon/' + source; path = root / target
        path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw); cfg['sources'][target] = sha(raw)
    names = subprocess.run(['git', '-C', str(ROOT), 'ls-tree', '-r', '--name-only', revision,
                            'server/player_web_auth'], capture_output=True, check=True).stdout.decode().splitlines()
    for name in names:
        if not (name.endswith('.py') or name == 'server/player_web_auth/business_wire_schema.json'):
            continue
        raw = subprocess.run(['git', '-C', str(ROOT), 'show', revision + ':' + name], capture_output=True, check=True).stdout
        target = 'runtime/' + name.removeprefix('server/')
        path = root / target; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        cfg['sources'][target] = sha(raw)
    # A prepared lab is portable; running it does not need the addon/Git tree.
    operator_names = subprocess.run(['git', '-C', str(ROOT), 'ls-tree', '-r', '--name-only', revision,
                                     'tools/loadtest_lab'], capture_output=True, check=True).stdout.decode().splitlines()
    need(any(name.endswith('/runtime.py') for name in operator_names), 'commit_loadtest_operator_before_preparing_lab')
    for name in operator_names:
        if not name.endswith('.py'):
            continue
        raw = subprocess.run(['git', '-C', str(ROOT), 'show', revision + ':' + name], capture_output=True, check=True).stdout
        need(raw.replace(b'\r\n', b'\n') == (ROOT / name).read_bytes().replace(b'\r\n', b'\n'),
             'loadtest_operator_must_match_committed_source')
        target = 'operator/loadtest_lab/' + Path(name).name
        path = root / target; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        cfg['sources'][target] = sha(raw)
    if backend_db_pool in ('bounded-v1', 'bounded-v2'):
        apply_db_pool_overlay(root, cfg, revision)
    runner = b"import sys\nfrom pathlib import Path\nsys.path[:0]=[str(Path(__file__).parent/'operator'),str(Path(__file__).parent/'runtime')]\nfrom loadtest_lab.cli import entry\nraise SystemExit(entry())\n"
    (root / 'run_lab.py').write_bytes(runner); cfg['sources']['run_lab.py'] = sha(runner)
    cfg['csv_source_revision'] = revision
    write_new(root / 'lab.json', cfg)
    write_new(root / 'client.json', {'config': cfg, 'controller': private['controller'],
                                   'manifest_sha256': sha(canonical(cfg))})
    load(root)  # Validate all budgets before producing executable bootstrap files.
    password = private['database_app']
    roles = ('CREATE ROLE anon NOLOGIN;\nCREATE ROLE authenticated NOLOGIN;\nCREATE ROLE service_role NOLOGIN;\n'
             'CREATE ROLE goufayu_payment NOLOGIN;\n'
             'CREATE ROLE goufayu_migrator NOLOGIN;\n'
             "CREATE ROLE goufayu_app LOGIN PASSWORD '" + password + "';\n")
    # Image entrypoint reads init SQL as its postgres UID. The enclosing lab
    # remains 0700 on Linux; mounted init files must be readable by that UID.
    (root / 'database').chmod(0o755)
    (root / 'database/00_roles.sql').write_text(roles, encoding='utf8'); (root / 'database/00_roles.sql').chmod(0o644)
    marker = ('REVOKE CREATE,TEMPORARY ON DATABASE "' + cfg['database'] + '" FROM PUBLIC;\n'
        'CREATE SCHEMA loadtest_lab; REVOKE ALL ON SCHEMA loadtest_lab FROM PUBLIC;\n'
        'CREATE TABLE loadtest_lab.marker(singleton boolean PRIMARY KEY CHECK(singleton),run_id text NOT NULL,'
        'proof text NOT NULL,manifest_sha256 text NOT NULL,seeded boolean NOT NULL DEFAULT false);\n'
        "INSERT INTO loadtest_lab.marker VALUES(true,'" + run + "','" + private['marker'] + "','" + sha(canonical(cfg)) + "',false);\n")
    (root / 'database/90_marker.sql').write_text(marker, encoding='utf8'); (root / 'database/90_marker.sql').chmod(0o644)
    # Linux host networking keeps PostgreSQL's own observed address/port equal
    # to the explicitly guarded loopback endpoint. No public DB listener.
    compose = ('services:\n  database:\n    image: ' + postgres_image + '\n    container_name: survival-loadtest-' + run[:12]
        + '\n    network_mode: host\n    restart: "no"\n    mem_limit: ' + str(database_memory_mib) + 'm'
        + '\n    cpus: ' + str(database_cpu_limit)
        + '\n    environment:\n      PGPORT: "25432"\n      POSTGRES_DB: ' + cfg['database']
        + '\n      POSTGRES_PASSWORD: ' + private['database_admin']
        + '\n    command: ["postgres", "-p", "25432", "-c", "listen_addresses=127.0.0.1"]'
        + '\n    volumes:\n      - ./pgdata:/var/lib/postgresql/data\n      - ./database:/docker-entrypoint-initdb.d:ro\n')
    (root / 'compose.yaml').write_text(compose, encoding='utf8'); (root / 'compose.yaml').chmod(0o600)
    write_new(root / 'prepare_receipt.json', {'kind': 'ISOLATED_LOADTEST_PREPARATION_RECEIPT',
        'artifact_root': str(root), 'source_root': str(original), 'run_id': run,
        'manifest_sha256': sha(canonical(cfg)), 'sources': cfg['sources'],
        'backend_db_pool': backend_db_pool, 'backend_overlay': cfg.get('backend_overlay'),
        'database_pool_parameters': pool_parameters,
        'cloud_resources_created': 0, 'requests_sent': 0, 'production_rows_copied': 0})
    return {'status': 'LAB_PREPARED_NOT_STARTED', 'directory': str(root), 'run_id': run,
            'accounts': accounts, 'active': active, 'purpose': purpose,
            'receipt': str(root / 'prepare_receipt.json')}


def connect_admin(cfg, private):
    import psycopg
    return psycopg.connect(dsn(cfg, private, admin=True), connect_timeout=3)


def seed(directory, *, analyze_after_seed=False):
    """O(N) initial COPY in chunks of 1000; O(chunk) memory, no real accounts.

    Registration and archive fixtures only. Active account defaults are still
    initialized by the real application on authenticate/login.
    """
    need(type(analyze_after_seed) is bool, 'lab_seed_analyze_flag_invalid')
    root, cfg, private = load(directory)
    from .guard import account, database_account, production_host_guard
    production_host_guard(cfg)
    with connect_admin(cfg, private) as conn:
        marker_guard(conn, cfg, private)
        lock = conn.execute('SELECT pg_try_advisory_lock(124710,1)').fetchone()[0]
        need(lock, 'lab_seed_already_running')
        for begin in range(0, cfg['accounts'], 1000):
            end = min(begin + 1000, cfg['accounts'])
            with conn.transaction():
                conn.execute('CREATE TEMP TABLE loadtest_seed(account_id text,inventory jsonb) ON COMMIT DROP')
                with conn.cursor().copy('COPY loadtest_seed(account_id,inventory) FROM STDIN') as copy:
                    for index in range(begin, end):
                        identity = database_account(private, account(cfg, index))
                        inventory = {'lottery_ticket': 100000} if index < cfg['active'] else {}
                        copy.write_row((identity, json.dumps(inventory)))
                conn.execute('INSERT INTO public.survival_players(account_id) SELECT account_id FROM loadtest_seed WHERE true ON CONFLICT DO NOTHING')
                conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) "
                    "SELECT account_id,'{}'::jsonb,inventory FROM loadtest_seed WHERE true ON CONFLICT DO NOTHING")
                # Synthetic monthly-card fixture makes the zero-minute welfare
                # claim executable; no payment/order/provider is involved.
                conn.execute("INSERT INTO public.archive_entitlements(account_id,entitlement_id,active,expires_at) "
                    "SELECT account_id,'archive_pass',true,now()+interval '1 day' FROM loadtest_seed "
                    "WHERE inventory ? 'lottery_ticket' ON CONFLICT DO NOTHING")
            conn.commit()
        count = conn.execute('SELECT count(*) FROM public.survival_players').fetchone()[0]
        need(count == cfg['accounts'], 'lab_contains_unexpected_accounts')
        analyze = {'requested': analyze_after_seed, 'completed': False, 'elapsed_ms': None}
        if analyze_after_seed:
            started = time.monotonic()
            # The marker and endpoint guard above prove this is only the new
            # synthetic database. One explicit bulk-load statistics pass, not
            # a timer or a request hot-path sweep. Both A/B arms must opt in.
            conn.execute('ANALYZE')
            conn.commit()
            analyze.update(completed=True, elapsed_ms=round((time.monotonic() - started) * 1000, 3))
        conn.execute('UPDATE loadtest_lab.marker SET seeded=true WHERE singleton'); conn.commit()
    receipt = root / ('seed_' + secrets.token_hex(8) + '_receipt.json')
    write_new(receipt, {'kind': 'SYNTHETIC_LOADTEST_DATASET_RECEIPT', 'artifact_root': str(root),
        'run_id': cfg['run_id'], 'registered_accounts': count, 'active_ticket_fixtures': cfg['active'],
        'real_accounts_modified': 0, 'chunk_rows': 1000, 'synthetic_monthly_card_fixtures': cfg['active'],
        'statistics_after_bulk_load': analyze})
    return {'status': 'SYNTHETIC_DATASET_READY', 'registered_accounts': count, 'receipt': str(receipt)}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    subs = p.add_subparsers(dest='action', required=True)
    export = subs.add_parser('snapshot'); export.add_argument('--directory', required=True)
    init = subs.add_parser('prepare')
    init.add_argument('--directory', required=True)
    init.add_argument('--source-receipt', required=True)
    init.add_argument('--purpose', choices=('capacity', 'functional-smoke'), default='capacity')
    init.add_argument('--accounts', type=int); init.add_argument('--active', type=int)
    init.add_argument('--duration', type=int)
    init.add_argument('--http-concurrency', type=int,
                      help='HTTP workers; omitted: baseline/v1 8, bounded-v2 24')
    init.add_argument('--db-concurrency', type=int, default=4)
    init.add_argument('--web-concurrency', type=int, default=24)
    init.add_argument('--global-http-per-minute', type=int, default=2400)
    init.add_argument('--wire-mode', choices=('business-wire-v1', 'legacy-json'), default='business-wire-v1')
    init.add_argument('--backend-db-pool', choices=('baseline', 'bounded-v1', 'bounded-v2'), default='baseline',
                      help='Explicit reviewed DB pool overlay experiment; baseline keeps production transport bytes')
    init.add_argument('--db-pool-max-waiters', type=int,
                      help='bounded-v2 only: bounded DB waiting queue, default 20; maximum 32')
    init.add_argument('--db-pool-wait-seconds', type=float,
                      help='bounded-v2 only: queue wait cap, default 2; maximum 5 and request remaining deadline')
    init.add_argument('--database-memory-mib', type=int,
                      help='Isolated local database memory cap; default 2048 MiB (smoke: 256)')
    init.add_argument('--database-cpu-limit', type=float,
                      help='Isolated local database CPU cap; default 1 CPU (smoke: 0.5)')
    init.add_argument('--postgres-image',
                      help='Official PostgreSQL image pinned by sha256 digest; omitted: postgres:17')
    init.add_argument('--lottery-catalog-md5', help='Verified public client-local catalog seed MD5; otherwise startup is cold')
    data = subs.add_parser('seed'); data.add_argument('--directory', required=True)
    data.add_argument('--analyze-after-seed', action='store_true',
                      help='Run one guarded ANALYZE after synthetic bulk load; use for both A/B arms')
    serve = subs.add_parser('serve'); serve.add_argument('--directory', required=True)
    serve.add_argument('--lua-executable', help='Explicit Lua executable; otherwise detect lua5.1/lua')
    test = subs.add_parser('smoke'); test.add_argument('--directory', required=True)
    test.add_argument('--stop-lab', action='store_true')
    stop = subs.add_parser('stop'); stop.add_argument('--client', required=True)
    mon = subs.add_parser('monitor'); mon.add_argument('--directory', required=True)
    mon.add_argument('--duration', type=int)
    mon.add_argument('--interval', type=int, default=5)
    args = p.parse_args(argv)
    if args.action == 'snapshot':
        from .snapshot import snapshot
        result = snapshot(args.directory)
    elif args.action == 'prepare':
        result = prepare(args)
    elif args.action == 'seed':
        result = seed(args.directory, analyze_after_seed=args.analyze_after_seed)
    elif args.action == 'smoke':
        from .smoke import smoke
        result = smoke(args.directory, stop=args.stop_lab)
    elif args.action == 'stop':
        from .smoke import stop_lab
        result = stop_lab(args.client)
    elif args.action == 'monitor':
        from .monitor import monitor
        result = monitor(args.directory, duration_seconds=args.duration, interval_seconds=args.interval)
        result['ok'] = result['status'] == 'MONITOR_COMPLETE'
    else:
        from .runtime import serve
        return serve(args.directory, lua_executable=args.lua_executable)
    if result.get('receipt'):
        from .guard import register_storage
        result['storage_registration'] = register_storage(result['receipt'])
    print(json.dumps(result, ensure_ascii=False)); return 0 if result.get('ok', True) else 2


def entry():
    try:
        return main()
    except Exception as error:
        import re
        message = str(error)
        public = message if isinstance(error, ValueError) else getattr(error, 'code', '')
        code = public if isinstance(public, str) and re.fullmatch('[a-z0-9_:]{1,100}', public) else 'loadtest_operation_not_completed'
        print(json.dumps({'ok': False, 'error': code, 'error_type': type(error).__name__, 'automatic_retry': False}))
        return 2


if __name__ == '__main__':
    raise SystemExit(entry())
