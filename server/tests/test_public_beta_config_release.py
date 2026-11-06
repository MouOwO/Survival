"""Pure configuration/SQL and controlled transport checks; no remote calls."""
from pathlib import Path
import ast
import copy
import hashlib
import importlib.util
import json
import re
import sys
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
ROOT = next(path for path in HERE.parents if (path / 'AGENTS.md').is_file())


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), value.__dict__)
    return value


DIRECTORY = HERE if (HERE / 'recipe.py').is_file() else ROOT / 'tools/public_beta_config_20261106'
recipe = module('config_recipe_test_subject', DIRECTORY / 'recipe.py')
deploy = module('config_deploy_test_subject', DIRECTORY / 'deploy.py')


class ExactConfigRecipe(unittest.TestCase):
    def setUp(self):
        self.parent = recipe.parent_function()
        self.candidate = recipe.derive_function(self.parent)
        candidates = [ROOT / recipe.SOURCE_PATH]
        # Only this ignored pre-freeze rehearsal may use its content-addressed
        # artifact. Once promoted to server/tests, require the tracked bundle.
        if DIRECTORY == HERE:
            candidates.append(ROOT / 'output/public_beta_0601_repair_20261106_v01/bundles' / recipe.NEW_BUNDLE / 'bundle.json')
        self.bundle = next(path.read_bytes() for path in candidates if path.is_file())
        self.config = recipe.configuration(self.bundle)

    def test_only_one_exact_branch_and_all_parent_bytes_remain(self):
        old = self.parent.decode()
        new = self.candidate.decode()
        begin = new.index(' -- Public-beta 20261106:')
        finish = new.index(' -- Exact published WS4 catalog contract', begin)
        self.assertEqual(new[:begin] + new[finish:], old)
        added = new[begin:finish]
        self.assertEqual(added.count(recipe.NEW_BUNDLE), 1)
        self.assertEqual(added.count(recipe.PG_CONFIG_SHA), 1)
        self.assertIn("p_config IS NULL", added)
        self.assertIn("jsonb_typeof(p_config) IS DISTINCT FROM 'object'", added)
        self.assertIn("IS DISTINCT FROM '" + recipe.PG_CONFIG_SHA, added)
        self.assertNotIn('GRANT', added)
        self.assertNotIn('UPDATE', added)
        self.assertNotIn('DELETE', added)

    def test_drift_rejected_before_generating_sql(self):
        with self.assertRaisesRegex(RuntimeError, 'audited_sync_function_changed'):
            recipe.derive_function(self.parent + b'\n')
        with self.assertRaisesRegex(RuntimeError, 'fixed_bundle_changed'):
            recipe.configuration(self.bundle + b'\n')
        with self.assertRaisesRegex(RuntimeError, 'activation_config_changed'):
            recipe.activate_sql(self.config + b'\n')

    def test_exact_archive_service_sync_representation(self):
        document = json.loads(self.bundle)
        actual = json.loads(self.config)
        self.assertEqual(actual['configs'], document['configs'])
        self.assertEqual(set(actual), {'configs', 'compatible_config_hashes'})
        self.assertEqual(recipe.sha(self.config), recipe.CONFIG_SHA)
        for key, value in document['compatible_config_hashes'].items():
            self.assertEqual(actual['compatible_config_hashes'][key]['commands'], sorted(value['commands']))
            self.assertEqual(actual['compatible_config_hashes'][key]['upgrade_commands'], sorted(value['upgrade_commands']))

    def test_real_function_clones_only_point_to_temporary_tables(self):
        for source, name in ((self.parent, 'public_beta_parent_probe'), (self.candidate, 'public_beta_candidate_probe')):
            clone = recipe.isolated_function(source, name)
            self.assertNotIn('public.archive_sync_config(', clone)
            self.assertNotIn('public.archive_config_sets', clone)
            self.assertFalse(re.search(r'(?<![\w.])archive_config_sets\b', clone))
            original = source.decode()
            expected = original.replace('public.archive_sync_config(', 'pg_temp.' + name + '(', 1)
            expected = re.sub(r'(?<![A-Za-z0-9_.])(?:public\.)?archive_config_sets\b', 'pg_temp.archive_config_sets', expected)
            self.assertEqual(clone, expected)

    def test_probe_uses_fixed_old_configs_no_real_mutating_function(self):
        sql = recipe.probe_sql(self.config)
        self.assertTrue(sql.startswith('BEGIN ISOLATION LEVEL REPEATABLE READ;'))
        self.assertNotIn('COMMIT;', sql)
        # References to public sync occur only in metadata and comparison text,
        # never as a call. Only old config content is copied into temporary data.
        self.assertNotIn('PERFORM public.archive_sync_config(', sql)
        self.assertNotIn('SELECT public.archive_sync_config(', sql)
        self.assertIn('INSERT INTO pg_temp.archive_config_sets SELECT config_hash,config FROM public.archive_config_sets WHERE config_hash IN (', sql)
        self.assertIn('transaction_failure_not_rolled_back', sql)
        self.assertIn('postgres_function_canonicalization_changed', sql)
        self.assertIn("NULL::jsonb,'null'::jsonb,'[]'::jsonb", sql)
        self.assertIn("ROLLBACK;\nSELECT json_build_object", sql)

    def test_pg_get_functiondef_output_gets_statement_separator_only_at_execution(self):
        self.assertTrue(self.parent.endswith(b'$function$\n'))
        self.assertTrue(self.candidate.endswith(b'$function$\n'))
        self.assertIn('$function$\n;\nCREATE OR REPLACE FUNCTION pg_temp.public_beta_candidate_probe', recipe.probe_sql(self.config))
        self.assertIn('$function$\n;\nDO $beta_probe$', recipe.probe_sql(self.config))
        self.assertIn('$function$\n;\nDO $register$', recipe.activate_sql(self.config))

    def test_pg_temporary_alias_is_explicit_and_full_byte_comparison_remains(self):
        sql = recipe.probe_sql(self.config)
        self.assertIn("alias_prefix:='CREATE OR REPLACE FUNCTION pg_temp.public_beta_candidate_probe(';", sql)
        self.assertIn("physical_prefix:='CREATE OR REPLACE FUNCTION '||quote_ident(namespace)||'.public_beta_candidate_probe(';", sql)
        self.assertIn('IF starts_with(normalized,physical_prefix)=starts_with(normalized,alias_prefix) THEN', sql)
        self.assertIn("RAISE EXCEPTION 'temporary_function_header_invalid'", sql)
        self.assertIn('normalized:=target_prefix||substr(normalized,length(selected_prefix)+1);', sql)
        self.assertIn('probe_function_body_changed', sql)
        self.assertIn('postgres_function_canonicalization_changed', sql)
        self.assertEqual(recipe.sha(self.candidate), 'b32ffb324573cad653c70c37e4dcb64f725d35af436d1557e5ffda5c9c92775b')

    def test_activation_is_single_transaction_guards_before_mutations(self):
        sql = recipe.activate_sql(self.config)
        self.assertEqual(sql.count('BEGIN ISOLATION LEVEL SERIALIZABLE;'), 1)
        self.assertEqual(sql.count('COMMIT;'), 1)
        self.assertLess(sql.index('LOCK TABLE'), sql.index('sync_function_drift'))
        self.assertLess(sql.index('sync_function_drift'), sql.index('CREATE OR REPLACE FUNCTION public.archive_sync_config'))
        self.assertLess(sql.rindex('config_inventory_drift'), sql.index('COMMIT;'))
        self.assertNotIn('DROP ', sql)
        self.assertNotIn('TRUNCATE ', sql)
        self.assertNotIn('DELETE FROM public.', sql)
        self.assertFalse(re.search(r'(?i)\b(?:from|into|update|join)\s+(?:public\.)?player_\w+', sql))

    def test_verify_owns_no_transaction_and_requires_exact_acl_inventory(self):
        sql = recipe.verify_sql()
        self.assertNotIn('COMMIT;', sql)
        self.assertNotIn('ROLLBACK;', sql)
        self.assertNotIn('CREATE ', sql)
        self.assertNotIn('INSERT ', sql)
        self.assertIn(recipe.sha(self.candidate), sql)
        self.assertIn(recipe.NEW_BUNDLE, sql)
        self.assertIn(recipe.PG_CONFIG_SHA, sql)
        self.assertIn('goufayu_app=X/goufayu_owner', sql)
        self.assertIn('config_inventory_drift', sql)

    def test_fixed_psql_call_never_uses_credentials_or_service_mutations(self):
        tree = ast.parse(deploy.REMOTE)
        nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in ('need','execute_sql')]
        result = Mock(returncode=0, stdout=b'{"ok":true}', stderr=b'not exposed')
        runner = Mock(return_value=result)
        namespace = dict(json=json, subprocess=Mock(run=runner))
        exec(compile(ast.Module(body=nodes,type_ignores=[]), '<fixed-sql>', 'exec'), namespace)
        self.assertTrue(namespace['execute_sql']('BEGIN READ ONLY; ROLLBACK;')['ok'])
        args = runner.call_args.args[0]
        self.assertIn('goufayu-ws4-db', args)
        self.assertEqual(args[-2:], ['-d','goufayu_ws4'])
        self.assertIn('PGPASSFILE=/dev/null', args)
        self.assertIn('PGSERVICEFILE=/dev/null', args)
        result.returncode = 1
        with self.assertRaisesRegex(RuntimeError, '^exact_config_sql_failed_no_retry$'):
            namespace['execute_sql']('BEGIN READ ONLY; ROLLBACK;')
        self.assertEqual(runner.call_count, 2, 'No automatic retry on SQL failure')

    def test_transport_modes_only_prepare_probe_activate_verify(self):
        self.assertNotIn("['systemctl','stop'", deploy.REMOTE)
        self.assertNotIn("['systemctl','start'", deploy.REMOTE)
        self.assertNotIn('admin-password', deploy.REMOTE)
        self.assertNotIn('/environ', deploy.REMOTE)
        self.assertIn("write_new('activation.intent.json'", deploy.REMOTE)
        self.assertIn('config_retained_on_api_rollback=True', deploy.REMOTE)


if __name__ == '__main__':
    unittest.main()
