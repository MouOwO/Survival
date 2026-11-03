"""Offline integration boundaries, never a query/install/publication."""
from pathlib import Path
import tempfile,unittest
from unittest.mock import patch
import release_workflow_diagnostics as d

class DiagnosticsTests(unittest.TestCase):
    def test_buildable_pending_bytes_and_runtime_dirty_are_not_silently_dropped(self):
        rows=[dict(source=dict(repo='game',path='scripts/a.lua'),status='PENDING_RUNTIME_UPDATE',blocking=False),
              dict(source=dict(repo='content',path='panorama/a.js'),status='UNCOMPILED_BINDING_REQUIRED',blocking=True),
              dict(source=dict(repo='game',path='resource/matching.txt'),status='PARENT_BYTES_MATCH',blocking=False)]
        dirty=[dict(repo='game',path='panorama/a.vjs_c',runtime_related=True),
               dict(repo='game',path='docs/a.md',runtime_related=False)]
        self.assertEqual(d.pending_source_keys(dict(rows=rows,dirty=dirty)),
            ['content:panorama/a.js','dirty:game:panorama/a.vjs_c','game:scripts/a.lua'])

    def test_duplicate_control_fields_and_oversized_controls_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'control.json';path.write_text('{"uploaded":false,"uploaded":true}')
            with self.assertRaisesRegex(ValueError,'duplicate'):d.read_control(path)
            path.write_text('{}')
            with patch.object(d,'MAX_CONTROL_BYTES',1),self.assertRaises(ValueError):d.read_control(path)

    def test_summary_preserves_pending_counts_while_limiting_console_output(self):
        value=dict(status='LOCAL_ONLY',pending_source_changes=[str(i) for i in range(50)],rows=[{}]*50)
        result=d.summary(value)
        self.assertEqual(result['pending_source_changes_count'],50)
        self.assertEqual(len(result['pending_source_changes']),12)
        self.assertEqual(result['rows_count'],50)
        self.assertEqual(len(value['rows']),50)

    def test_retirement_uses_exact_task_delivery_while_preserving_project_backlog(self):
        import release_retention
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);out=root/'output';out.mkdir();path=out/'inventory.json';path.write_text('{}')
            task=dict(status='WORKSHOP_SYNCED',workshop_synchronized=True)
            state=dict(status='LOCAL_ONLY',pending_source_changes=['unrelated:old'],task_package_delivery=task)
            with patch.object(d,'ROOT',root),patch.object(d,'read_control',return_value=({'inventory':[],'protected_paths':[]},'a'*64)),patch.object(d,'delivery_status',return_value=state),patch.object(release_retention,'plan_retirement',return_value={}) as plan:
                d.retirement_plan(None,path)
            self.assertEqual(plan.call_args.args,([],[],task))
            self.assertEqual(state['pending_source_changes'],['unrelated:old'])

if __name__=='__main__':unittest.main()
