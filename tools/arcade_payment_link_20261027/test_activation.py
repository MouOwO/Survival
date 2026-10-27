"""Activation boundary tests: mocks/pure CSV only, never host or payment APIs."""
import copy
from contextlib import redirect_stderr
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import activate
import activation_remote as operator
import deploy_plan
import schema_contract


class ActivationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan,cls.files=deploy_plan.build()

    def test_default_cli_never_connects_or_writes_and_mutations_require_exact_review(self):
        with patch.object(activate,'remote') as remote,patch.object(activate,'build_activation') as build,patch('builtins.print'):
            activate.main([])
        remote.assert_not_called();build.assert_not_called()
        with redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):activate.arguments(['activate'])
        with redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):activate.arguments(['enable','--audit','a','--cloud-snapshot','s','--review-hash','h'])
        capsule={'activation_sha256':'a'*64}
        with patch.object(activate,'build_activation',return_value=(capsule,{})),patch.object(activate,'remote') as remote:
            with self.assertRaisesRegex(ValueError,'reviewed_activation_candidate_changed'):
                activate.main(['activate','--audit','a','--cloud-snapshot','s','--review-hash','b'*64])
        remote.assert_not_called()

    def test_public_routes_cannot_expose_game_mutations_and_strip_only_fixed_namespace(self):
        rules=operator.nginx_rules().decode()
        self.assertEqual(rules.count('location = /ws4-payments'),10)
        self.assertIn('location = /ws4-payments/v1/payments/wechat/notify',rules)
        self.assertIn('proxy_pass http://127.0.0.1:18769/v1/payments/wechat/notify;',rules)
        for name in ('catalog','create','status','cancel','reset'):
            self.assertNotIn('/v1/payments/'+name,rules)
        self.assertIn('location ^~ /ws4-payments/ { return 404; }',rules)
        old=b'legacy bytes\n    include /etc/nginx/goufayu-ws4-web.locations;\nold callback bytes'
        new=operator.nginx_candidate(old)
        self.assertEqual(new.replace(b'\n    include /etc/nginx/goufayu-ws4-payment.locations;',b''),old)
        with self.assertRaisesRegex(RuntimeError,'nginx_ws4_insertion_target_changed'):
            operator.nginx_candidate(new)

    def test_payment_environment_preserves_browser_state_and_unrelated_flags(self):
        before=b'PLAYER_WEB_AUTH_SECRET="browser-secret"\nPLAYER_WEB_AUTH_DATABASE="/existing.sqlite3"\nPLAYER_WEB_AUTH_STEAM_TLS_RELAY="1"\n'
        off=operator.payment_env(before,'a'*64,False)
        self.assertTrue(off.startswith(before))
        self.assertIn(b'PLAYER_WEB_AUTH_PAYMENTS_ENABLED="0"',off)
        self.assertEqual(operator.payment_env(off,'a'*64,False),off)
        on=operator.payment_env(off,'a'*64,True)
        self.assertEqual(on.replace(b'PLAYER_WEB_AUTH_PAYMENTS_ENABLED="1"',b'PLAYER_WEB_AUTH_PAYMENTS_ENABLED="0"'),off)
        with self.assertRaisesRegex(RuntimeError,'payment_environment_duplicate'):
            operator.payment_env(off+b'PLAYER_WEB_AUTH_PAYMENTS_ENABLED="0"\n','a'*64,False)

    def test_isolated_role_cannot_have_tables_membership_helpers_or_wrong_phase(self):
        valid={'unprivileged':True,'memberships':[],'direct_tables':[],'login':False,'connect':False,
               'execute_functions':['catalog','create_order_quantity','get_order','pending','update_gateway','deliver']}
        operator.validate_privileges(valid)
        for edit in ({'memberships':['goufayu_owner']},{'direct_tables':['public.survival_players']},
                     {'unprivileged':False},{'execute_functions':valid['execute_functions']+['apply_effects']},
                     {'login':True}):
            with self.assertRaises(RuntimeError):operator.validate_privileges({**valid,**edit})

    def test_sql_transport_is_fixed_isolated_and_never_puts_password_on_command_line(self):
        source="ALTER ROLE goufayu_payment LOGIN PASSWORD 'private-test-value';"
        with patch.object(operator,'command',return_value=b'') as command:
            operator.fixed_psql(source,commit=False)
        args=command.call_args.args[0];stdin=command.call_args.args[1]
        self.assertIn('goufayu-ws4-db',args);self.assertEqual(args[-1],'goufayu_ws4')
        self.assertNotIn('private-test-value',str(args))
        self.assertIn(b'private-test-value',stdin);self.assertTrue(stdin.endswith(b'ROLLBACK;\n'))
        self.assertIn(b'ISOLATION LEVEL SERIALIZABLE',stdin)

    def test_seed_contains_only_reviewed_configuration_and_keeps_reset_disabled(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage=Path(temporary)
            for name,raw in self.files.items():
                if name.startswith('reference_csv/') or name=='catalog-package.json':
                    path=stage/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            source=operator.seed_source(stage,{'alipay_enabled':True,'alipay_seller_id':'2088000000000000'})
        for forbidden in ('INSERT INTO public.','UPDATE public.','DELETE FROM','TRUNCATE','CREATE TABLE','CREATE FUNCTION',
                          'INSERT INTO payments.orders','INSERT INTO payments.test_accounts','payments.create_order('):
            self.assertNotIn(forbidden,source)
        self.assertEqual(source.count('INSERT INTO payments.products('),50)
        self.assertEqual(source.count('INSERT INTO payments.vip_recharge_levels('),12)
        self.assertIn('INSERT INTO payments.test_settings(singleton,enabled) VALUES(true,false)',source)
        self.assertEqual(source.count("RAISE EXCEPTION 'ws4_payments_not_empty'"),11)

    def test_paid_ledger_blocks_rollback_before_any_service_or_configuration_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage=Path(temporary);(stage/'private-backup').mkdir()
            counts={name:0 for name in operator.TABLES};counts['orders']=1
            with patch.object(operator,'checked_stage',return_value=stage),patch.object(operator,'database_counts',return_value=counts), \
                 patch.object(operator,'command') as command,patch.object(operator,'private_file') as write:
                with self.assertRaisesRegex(RuntimeError,'payment_ledger_exists_retain_and_repair_forward'):
                    operator.rollback_no_orders({})
            command.assert_not_called();write.assert_not_called()

    def test_exact_function_contract_covers_renames_and_quantity_delivery_patch(self):
        result=schema_contract.compile_contract(deploy_plan.ROOT/'server/payment_backend')
        self.assertEqual(len(result),35)
        self.assertEqual(result['deliver_pre_recharge']['source'],'upgrade_commerce_bundles.sql')
        self.assertEqual(result['validate_order_quantity_snapshot']['source'],'upgrade_ucoin_rate_100.sql')
        self.assertNotEqual(result['deliver_pre_recharge']['body_sha256'],result['deliver']['body_sha256'])
        for row in result.values():
            self.assertTrue(row['security_definer']);self.assertEqual(row['owner'],'goufayu_owner')

    def test_pwa_unit_changes_only_release_while_reusing_existing_sqlite_and_identity(self):
        old=b'[Service]\nUser=goufayu-ws4-web\nWorkingDirectory=/opt/goufayu-ws4-web/releases/old\nEnvironmentFile=/etc/goufayu-ws4-web/auth.env\nExecStart=/usr/bin/python3.11 -B -m player_web_auth.run\nProtectSystem=strict\n'
        release=Path('/opt/goufayu-ws4-web/releases/20261027-payment-test')
        after=operator.pwa_unit(old,release)
        self.assertEqual(after.replace(str(release).encode(),b'/opt/goufayu-ws4-web/releases/old'),old)
        with self.assertRaisesRegex(RuntimeError,'old_pwa_executable_unexpected'):
            operator.pwa_unit(old.replace(b'/usr/bin/python3.11',b'/unknown/python'),release)

    def test_key_fingerprints_execute_without_reading_key_contents_into_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary)
            for provider,names in operator.KEY_NAMES.items():
                (base/provider).mkdir()
                for name in names:(base/provider/name).write_bytes(b'private-key-test-only')
            with patch.object(operator,'Path',return_value=base):
                result=operator.key_fingerprints()
        self.assertEqual(len(result),5)
        self.assertNotIn('private-key-test-only',json.dumps(result))
        for row in result.values():
            self.assertEqual(row['sha256'],hashlib.sha256(b'private-key-test-only').hexdigest())
            self.assertEqual(set(row),{'sha256','mode','uid','gid'})


if __name__=='__main__':unittest.main()
