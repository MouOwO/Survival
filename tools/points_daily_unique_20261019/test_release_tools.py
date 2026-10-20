"""Offline activation-failure checks; never connects to SSH, SQL or systemd."""
import ast
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
import uuid

SOURCE = (Path(__file__).with_name('remote_operator.py')).read_text('utf-8')
ACTIVATE = next(node for node in ast.parse(SOURCE).body if isinstance(node, ast.FunctionDef) and node.name == 'activate')
COMMIT_OUTCOME = next(node for node in ast.parse(SOURCE).body if isinstance(node, ast.FunctionDef) and node.name == 'committed_repair_outcome')


class Release(str):
    @property
    def name(self):
        return str(self)


class ActivationTests(unittest.TestCase):
    def environment(self, health_failure=False, undo_failure=False, admit_failure=False, commit_ack_lost=False, outcome='NOT_ATTEMPTED'):
        directory = tempfile.TemporaryDirectory(prefix='daily-release-test-')
        self.addCleanup(directory.cleanup)
        stage = Path(directory.name)
        (stage / 'validated.json').write_text(json.dumps({'bundle': 'candidate'}), encoding='utf-8')
        events, state = [], {'pointer': 'old'}

        def switch(target):
            events.append(('switch', target))
            state['pointer'] = target

        def health():
            events.append(('health',))
            if health_failure:
                raise RuntimeError('service_unhealthy_after_startup_poll')

        def undo(run):
            events.append(('undo', run))
            if undo_failure:
                raise ValueError('daily_unique_rollback_refused_account_changed')
            return {'rolled_back_accounts': 3}

        def admit(publish):
            self.assertTrue(publish)
            events.append(('admit',))
            if admit_failure:
                raise ValueError('daily_unique_plan_changed_preview_again')
            if commit_ack_lost:
                events.append(('commit_intent', 'reviewed-run'))
                raise OSError('commit_acknowledgement_lost')
            return {'repair': {'run_id': 'reviewed-run', 'changed_accounts': 3}}

        def probe():
            events.append(('probe_commit', outcome))
            return {'state': outcome, 'run_id': 'reviewed-run'}

        def save(name, value):
            events.append(('save', name, value['status']))
            return value

        def need(value, reason):
            if not value:
                raise RuntimeError(reason)

        namespace = dict(STAGE=stage, P={'bundle': 'candidate'}, OLD=Release('old'), NEW=Release('new'), json=json, need=need,
            baseline=lambda: None, backup_verified=lambda: None, payload_verified=lambda: None,
            candidate_scope=lambda: None, systemctl=lambda action: events.append(('systemctl', action)),
            pointers=lambda *args: None, admit=admit, switch=switch, health=health,
            undo_committed_repair=undo, save=save, committed_repair_outcome=probe,
            Path=lambda _: SimpleNamespace(resolve=lambda: state['pointer']))
        exec(compile(ast.Module(body=[ACTIVATE], type_ignores=[]), 'isolated_daily_activation', 'exec'), namespace)
        return namespace['activate'], events, state

    def test_success_records_the_three_repaired_players(self):
        run, events, state = self.environment()
        result = run()
        self.assertEqual((result['status'], result['player_updates']), ('ACTIVATED', 3))
        self.assertEqual(state['pointer'], 'new')
        self.assertNotIn(('undo', 'reviewed-run'), events)

    def test_failed_new_start_restores_reviewed_database_before_old_service_starts(self):
        run, events, state = self.environment(health_failure=True)
        with self.assertRaisesRegex(RuntimeError, 'service_unhealthy'):
            run()
        self.assertEqual(state['pointer'], 'old')
        undo = events.index(('undo', 'reviewed-run'))
        starts = [index for index, event in enumerate(events) if event == ('systemctl', 'start')]
        self.assertEqual(len(starts), 2)
        self.assertLess(undo, starts[-1])
        self.assertIn(('save', 'rollback', 'OLD_ARCHIVE_RESTORED'), events)

    def test_newer_player_changes_refuse_overwrite_and_keep_archive_stopped(self):
        run, events, state = self.environment(health_failure=True, undo_failure=True)
        with self.assertRaisesRegex(RuntimeError, 'daily_repair_rollback_refused_archive_stopped'):
            run()
        self.assertEqual(state['pointer'], 'old')
        self.assertEqual([event for event in events if event[0] == 'systemctl'],
            [('systemctl', 'stop'), ('systemctl', 'start'), ('systemctl', 'stop')])
        self.assertIn(('save', 'rollback', 'GUARDED_RECOVERY_REQUIRED_ARCHIVE_STOPPED'), events)
        self.assertNotIn(('save', 'rollback', 'OLD_ARCHIVE_RESTORED'), events)

    def test_rejected_preview_does_not_run_undo_and_restarts_unchanged_old_release(self):
        run, events, state = self.environment(admit_failure=True)
        with self.assertRaisesRegex(ValueError, 'daily_unique_plan_changed_preview_again'):
            run()
        self.assertEqual(state['pointer'], 'old')
        self.assertFalse(any(event[0] == 'undo' for event in events))
        self.assertEqual([event for event in events if event[0] == 'systemctl'][-1], ('systemctl', 'start'))

    def test_commit_ack_lost_probes_sql_and_undoes_committed_run_before_starting_old(self):
        run, events, state = self.environment(commit_ack_lost=True, outcome='COMMITTED')
        with self.assertRaisesRegex(OSError, 'commit_acknowledgement_lost'):
            run()
        self.assertEqual(state['pointer'], 'old')
        self.assertIn(('probe_commit', 'COMMITTED'), events)
        self.assertIn(('undo', 'reviewed-run'), events)
        self.assertLess(events.index(('undo', 'reviewed-run')), events.index(('systemctl', 'start')))
        self.assertEqual(sum(event == ('systemctl', 'start') for event in events), 1)

    def test_commit_ack_lost_with_unknown_sql_outcome_never_starts_old(self):
        run, events, _ = self.environment(commit_ack_lost=True, outcome='UNKNOWN')
        with self.assertRaisesRegex(RuntimeError, 'daily_repair_commit_outcome_unknown_archive_stopped'):
            run()
        self.assertFalse(any(event == ('systemctl', 'start') for event in events))
        self.assertFalse(any(event[0] == 'undo' for event in events))
        self.assertIn(('save', 'rollback', 'COMMIT_OUTCOME_UNKNOWN_ARCHIVE_STOPPED'), events)


class CommitOutcomeTests(unittest.TestCase):
    def probe(self, sync='new', constraint=(True,), config=True, backups=(3, 3, 0), baseline_config=False):
        directory = tempfile.TemporaryDirectory(prefix='daily-outcome-test-')
        self.addCleanup(directory.cleanup)
        stage = Path(directory.name)
        (stage / 'database_commit_intent.json').write_text(json.dumps(dict(bundle='new-bundle',
            plan_digest='reviewed-plan', run_id='15d8d467-19dd-46ad-a5b9-43fa1ed2d25a', changed_accounts=3)), encoding='utf-8')
        queries = []

        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def rollback(self):
                queries.append('ROLLBACK')

            def execute(self, sql, params=None):
                queries.append(sql)
                if sql.startswith('SET '):
                    row = None
                elif 'current_database()' in sql:
                    row = ('goufayu_test',)
                elif 'pg_get_functiondef' in sql:
                    row = (sync + ' sql',)
                elif 'FROM pg_constraint' in sql:
                    row = constraint
                elif 'to_regclass' in sql:
                    row = ('archive_daily_unique_backups',)
                elif 'count(*) FILTER' in sql:
                    row = backups
                else:
                    raise AssertionError(sql)
                return SimpleNamespace(fetchone=lambda: row)

        def need(value, reason):
            if not value:
                raise RuntimeError(reason)

        namespace = dict(STAGE=stage, P=dict(bundle='new-bundle', migration_plan_digest='reviewed-plan',
            migration_summary={'changed_accounts': 3}, new_sync_sha256=hashlib.sha256(b'new sql').hexdigest(),
            old_sync_sha256=hashlib.sha256(b'old sql').hexdigest(), configuration_sha256='reviewed-config'),
            json=json, uuid=uuid, need=need, hashlib=hashlib, SYNC='public.archive_sync_config(text,jsonb)',
            payment_deploy=lambda: SimpleNamespace(connection=Connection),
            config_rows=lambda _: {'new-bundle': 'reviewed-config'} if config else {})
        namespace['P']['old_config_rows'] = {'new-bundle': 'reviewed-config'} if baseline_config else {}
        exec(compile(ast.Module(body=[COMMIT_OUTCOME], type_ignores=[]), 'isolated_commit_outcome', 'exec'), namespace)
        result = namespace['committed_repair_outcome']()
        self.assertTrue(all(query.startswith(('SELECT ', 'SET ', 'ROLLBACK')) for query in queries))
        return result

    def test_commit_requires_constraint_config_function_and_exact_backup_cohort(self):
        self.assertEqual(self.probe()['state'], 'COMMITTED')
        self.assertEqual(self.probe(backups=(3, 2, 1))['state'], 'UNKNOWN')
        self.assertEqual(self.probe(constraint=None)['state'], 'UNKNOWN')
        self.assertEqual(self.probe(config=False)['state'], 'UNKNOWN')

    def test_old_schema_without_run_backup_is_confirmed_not_committed(self):
        self.assertEqual(self.probe(sync='old', constraint=None, config=False, backups=(0, 0, 0))['state'], 'NOT_COMMITTED')

    def test_reviewed_additive_config_from_an_older_rolled_back_release_is_not_a_commit(self):
        self.assertEqual(self.probe(sync='old', constraint=None, config=True, backups=(0, 0, 0), baseline_config=True)['state'], 'NOT_COMMITTED')
        self.assertEqual(self.probe(sync='old', constraint=None, config=True, backups=(0, 0, 0), baseline_config=False)['state'], 'UNKNOWN')

    def test_audited_rollback_is_distinct_from_never_committed(self):
        self.assertEqual(self.probe(sync='old', constraint=None, config=True, backups=(3, 0, 3))['state'], 'ROLLED_BACK')


if __name__ == '__main__':
    unittest.main(verbosity=2)
