"""Run only through the pinned audit transport; all SQL fixture writes roll back."""
from pathlib import Path
from copy import deepcopy
import contextlib, hashlib, importlib, io, json, secrets, sys, unittest

sys.dont_write_bytecode = True
payment = Path('/opt/goufayu/payments/current').resolve(strict=True)
archive = Path('/opt/goufayu/releases/current').resolve(strict=True)
assert payment.name == '20261016-shop-functional-v2'
assert archive.name == '20261016-shop-functional-v2'
sys.path.insert(0, str(payment))
from deploy import connection
from psycopg import sql
from psycopg.types.json import Jsonb

nonce = secrets.token_hex(16)
accounts, order_ids, checks = set(), set(), []

def need(value, name):
    assert value, name
    checks.append(name)

def identity(label):
    return hashlib.sha256(('vip_current_production_fixture:' + nonce + ':' + label).encode()).hexdigest()

def business(conn):
    result = {}
    tables = conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()
    for schema, name in tables:
        query = sql.SQL("SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'[]')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(name))
        result[schema + '.' + name] = conn.execute(query).fetchone()[0]
    return result

with connection() as c:
    try:
        c.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        c.execute("SET lock_timeout='5s'")
        c.execute('SET ROLE goufayu_owner')
        need(c.execute('SELECT current_database()').fetchone()[0] == 'goufayu_test', 'expected_database')
        before = business(c)
        fn_before = {name: hashlib.sha256(c.execute('SELECT pg_get_functiondef(%s::regprocedure)',(name,)).fetchone()[0].encode()).hexdigest()
                     for name in ['payments.credit_vip_recharge()', 'payments.deliver(text,text,integer,text,text)',
                                  'payments.apply_effects(text,jsonb,boolean)']}
        c.execute('SAVEPOINT vip_audit_all_fixtures')
        defaults = c.execute("SELECT coalesce(jsonb_object_agg(field_id,default_value),'{}'::jsonb) FROM payments.stat_rules").fetchone()[0]
        provider = c.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()
        need(provider is not None, 'configured_wechat_provider')
        thresholds = c.execute('SELECT level,required_fen FROM payments.vip_recharge_levels ORDER BY level').fetchall()
        need(len(thresholds) == 12, 'all_twelve_thresholds')
        vip_products = [row[0] for row in c.execute("SELECT to_jsonb(p) FROM payments.products p WHERE enabled AND sku LIKE 'video_bundle_vip_%%' ORDER BY sort_order,sku")]
        need(len(vip_products) == 10, 'ten_formal_cash_vip_packages')
        sku, marker = 'vip_audit_' + nonce, 'vip_audit_marker_' + nonce
        grants = {'items':{}, 'item_limits':{}, 'entitlements':[], 'lines':[]}
        c.execute("INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,'isolated VIP fixture','rollback-only fixture',1,'{}',false,0,%s,'fixture','item','fixture',0)",
                  (sku, marker, Jsonb(grants)))
        def buyer(label):
            account = identity('account:' + label)
            need(not c.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone(), label + '_fresh_nonce_account')
            c.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)',(account,Jsonb(defaults)))
            c.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',(account,Jsonb({}),Jsonb({})))
            accounts.add(account)
            return account
        account, test_account = buyer('real_payment'), buyer('test_payment')
        session = 'vip_audit_' + nonce
        need(c.execute('SELECT public.match_profile_login(%s,%s,%s,%s)',(account,session,'standard',Jsonb(defaults))).fetchone()[0]['ok'], 'synthetic_match_session')
        sequence = 0
        def stats(who=account):
            return c.execute('SELECT vip_recharge_total_fen,vip_level,shop_paid_currency FROM public.player_gameplay_stats WHERE player_id=%s',(who,)).fetchone()
        def state(who=account):
            return c.execute('SELECT to_jsonb(s),a.archive,a.content_inventory,p.profile_revision FROM public.player_gameplay_stats s JOIN public.player_archive_state a ON a.account_id=s.player_id JOIN public.survival_players p ON p.account_id=s.player_id WHERE s.player_id=%s',(who,)).fetchone()
        def receipt(amount, who=account, channel='wechat'):
            global sequence
            sequence += 1
            order = ('WX' if channel == 'wechat' else 'AL') + identity('order:' + str(sequence))[:30]
            transaction = '420000' + str(int(identity('transaction:' + str(sequence))[:30],16)).zfill(37)
            appid, mchid = c.execute('SELECT appid,mchid FROM payments.providers WHERE provider=%s',(channel,)).fetchone()
            reward = {'version':4,'item_id':marker,'purchase_limit':0,'effects':{},'grants':grants}
            c.execute("INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,state,provider,appid,mchid) VALUES(%s,%s,%s,%s,%s,'pending',%s,%s,%s)",
                      (order,who,sku,amount,Jsonb(reward),channel,appid,mchid))
            order_ids.add(order)
            return (order,transaction,amount,appid,mchid)
        def deliver(value):
            assert value[0] in order_ids
            return c.execute('SELECT payments.deliver(%s,%s,%s,%s,%s)',value).fetchone()[0]
        def denied(value, label):
            try:
                with c.transaction():
                    deliver(value)
            except Exception as exc:
                need('payment_mismatch' in str(exc),label)
            else:
                raise AssertionError(label + '_unexpectedly_accepted')
        pending = receipt(100)
        need(stats() == (0,0,0), 'pending_not_credited')
        denied((pending[0],pending[1],101,*pending[3:]), 'amount_mismatch_rejected')
        denied((*pending[:3],'invalid-app',pending[4]), 'merchant_mismatch_rejected')
        denied((pending[0],'fake',*pending[2:]), 'invalid_transaction_rejected')
        need(stats() == (0,0,0), 'invalid_callbacks_preserve_recharge')
        c.execute("UPDATE payments.orders SET state='closed' WHERE order_id=%s",(pending[0],))
        fake = receipt(100)
        c.execute("UPDATE payments.orders SET state='delivered',transaction_id=%s WHERE order_id=%s",(fake[1],fake[0]))
        need(stats() == (0,0,0), 'state_only_delivery_not_credited')
        review = receipt(100)
        c.execute("UPDATE payments.orders SET state='paid_review',transaction_id=%s,paid_at=now() WHERE order_id=%s",(review[1],review[0]))
        need(deliver(review)['state'] == 'paid_review' and stats() == (0,0,0), 'manual_review_not_credited')
        c.execute("UPDATE payments.orders SET state='closed' WHERE order_id=%s",(review[0],))
        cleared = receipt(100)
        c.execute('UPDATE payments.orders SET cleared_at=now() WHERE order_id=%s',(cleared[0],))
        need(deliver(cleared)['state'] == 'delivered' and stats() == (0,0,0), 'cleared_delivery_not_credited')
        c.execute('UPDATE payments.test_settings SET enabled=true WHERE singleton')
        c.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)',(test_account,))
        need(deliver(receipt(5000,test_account))['state'] == 'delivered' and stats(test_account) == (0,0,0), 'test_account_not_credited')
        last = None
        for level, fen in thresholds:
            remaining = fen - 1 - stats()[0]
            if remaining:
                need(deliver(receipt(remaining))['state'] == 'delivered', 'tier_' + str(level) + '_preboundary_delivered')
            need(stats()[:2] == (fen-1,level-1), 'tier_' + str(level) + '_not_early')
            if level <= 10:
                product = next(p for p in vip_products if p['grants']['required_vip_level'] == level)
                block = c.execute('SELECT payments.product_block(%s,%s,%s,%s,%s)',(account,product['item_id'],product['purchase_limit'],Jsonb(product['grants']),Jsonb(product['effects']))).fetchone()[0]
                need(block == 'vip_level_required', 'vip_package_' + str(level) + '_locked_before_threshold')
            last = receipt(1)
            need(deliver(last)['state'] == 'delivered' and stats()[:2] == (fen,level), 'tier_' + str(level) + '_exact_boundary')
            once = state()
            deliver(last)
            need(state() == once, 'tier_' + str(level) + '_callback_idempotent')
            if level <= 10:
                block = c.execute('SELECT payments.product_block(%s,%s,%s,%s,%s)',(account,product['item_id'],product['purchase_limit'],Jsonb(product['grants']),Jsonb(product['effects']))).fetchone()[0]
                need(block == '', 'vip_package_' + str(level) + '_unlocked_at_threshold')
        need(stats() == (1250000,12,0), 'max_tier_and_no_wallet_mint')
        need(c.execute("SELECT active AND expires_at IS NULL FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='vip'",(account,)).fetchone()[0], 'real_delivery_activates_membership')
        need(c.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s',(account,)).fetchone()[0] == 24, 'exactly_twentyfour_recharge_receipts')
        need(not state()[1].get('vip_claimed'), 'confirmed_old_service_no_automatic_privilege_grants')
        for product in vip_products:
            order_id = 'WX' + identity('formal-vip:' + product['sku'])[:30]
            order = c.execute('SELECT payments.create_order(%s,%s,%s,%s)',(account,session,order_id,product['sku'])).fetchone()[0]
            need(order.get('order_id') == order_id, product['sku'] + '_checkout_allowed')
            order_ids.add(order_id)
            old = state()
            transaction = '420000' + str(int(identity('formal-tx:' + product['sku'])[:30],16)).zfill(37)
            args = (order_id,transaction,order['amount'],*provider)
            need(deliver(args)['state'] == 'delivered', product['sku'] + '_formal_reward_delivered')
            new = state()
            expected_effects = deepcopy(product['effects'])
            bundle_hash = json.loads((archive/'addon/server/bundles/current.json').read_text())['hash']
            bundle = json.loads((archive/'addon/server/bundles'/bundle_hash/'bundle.json').read_text())
            for tier in bundle['configs']['archive_starjoy_levels']['rows']:
                if old[0]['starjoy_reward_level'] < tier['level'] <= new[0]['starjoy_reward_level']:
                    for field, value in zip(tier['effect_ids'],tier['effect_values']):
                        expected_effects[field] = float(expected_effects.get(field,0)) + float(value)
            for field, delta in expected_effects.items():
                need(abs(float(new[0][field])-float(old[0][field])-float(delta)) < 0.00001, product['sku'] + '_effect_' + field)
            for claim in product['grants']['vip_claims']:
                need(new[1]['vip_claimed'].get(claim) is True, product['sku'] + '_claim_' + claim)
            deliver(args)
            need(state() == new, product['sku'] + '_repeated_callback_no_grants')
            retry = c.execute('SELECT payments.create_order(%s,%s,%s,%s)',(account,session,'WX'+identity('retry:'+product['sku'])[:30],product['sku'])).fetchone()[0]
            need(retry.get('error') in ('already_owned','purchase_limit_reached'), product['sku'] + '_rebuy_blocked')
        need(stats()[1] == 12, 'vip12_ceiling_after_package_purchases')
        need(c.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s',(test_account,)).fetchone()[0] == 0, 'test_account_has_no_recharge_ledger')
        ranking_namespace={}
        exec(compile(RANK_TEST_SOURCE,'<reviewed_vip_ranking_fixture>','exec'),ranking_namespace)
        ranking_result=ranking_namespace['run_checks'](c,RANK_MIGRATION_SOURCE,defaults)
        c.execute('ROLLBACK TO SAVEPOINT vip_audit_all_fixtures')
        after = business(c)
        need(after == before, 'all_business_tables_unchanged_after_fixture_rollback')
        fn_after = {name: hashlib.sha256(c.execute('SELECT pg_get_functiondef(%s::regprocedure)',(name,)).fetchone()[0].encode()).hexdigest() for name in fn_before}
        need(fn_after == fn_before, 'production_sql_functions_unchanged')
        result = {'status':'PASS','checks':checks,'check_count':len(checks),
                  'thresholds':thresholds,'formal_vip_packages':len(vip_products),
                  'business_hashes_before':before,'business_hashes_after':after,
                  'function_hashes_before':fn_before,'function_hashes_after':fn_after,
                  'synthetic_accounts':len(accounts),'synthetic_orders':len(order_ids),
                  'schema_migrations':0,'gateway_requests':0,'individual_player_rows_read':False,
                  'synthetic_writes_committed':0,'all_fixture_writes_rolled_back':True}
        result['ranking_projection_tests']=ranking_result
    finally:
        c.rollback()

# Existing signatures, encryption and delivery tests use mocks and ephemeral keys.
sink = io.StringIO()
suite = unittest.defaultTestLoader.loadTestsFromName('payment_backend.test_payments')
with contextlib.redirect_stdout(sink),contextlib.redirect_stderr(sink):
    api_result = unittest.TextTestRunner(stream=sink,verbosity=1).run(suite)
result['payment_api_tests'] = {'tests':api_result.testsRun,'failures':len(api_result.failures),
                              'errors':len(api_result.errors),'ok':api_result.wasSuccessful(),
                              'gateway_requests':0}
if not api_result.wasSuccessful():
    result['payment_api_failure_details'] = sink.getvalue()
    result['status'] = 'FAILED'
print(json.dumps(result,ensure_ascii=False,default=str))
