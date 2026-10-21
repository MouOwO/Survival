"""Release preparation guard tests; no SSH, database or active file writes."""
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('benefits_prepare',Path(__file__).with_name('prepare.py'))
prepare=importlib.util.module_from_spec(spec);spec.loader.exec_module(prepare)


class PrepareTests(unittest.TestCase):
    def test_table_delta_preserves_online_only_policy(self):
        parent={'key':'id','rows':[{'id':'one','cap':60,'hour':0},{'id':'online','cap':20}]}
        before={'key':'id','rows':[{'id':'one','cap':30,'hour':0}]}
        after={'key':'id','rows':[{'id':'one','cap':30,'hour':5}]}
        result=prepare.table_delta(parent,before,after,'limits')
        self.assertEqual(result,{'key':'id','rows':[{'id':'one','cap':60,'hour':5},{'id':'online','cap':20}]})
        self.assertEqual(parent['rows'][0]['hour'],0)

    def test_table_conflicting_field_is_rejected(self):
        table=lambda value:{'key':'id','rows':[{'id':'one','hour':value}]}
        with self.assertRaisesRegex(AssertionError,'table_field_conflict'):
            prepare.table_delta(table(4),table(0),table(5),'rules')

    def test_three_way_preserves_unrelated_online_endpoint(self):
        before='def welfare():\n    return 0\n\n\ndef lottery():\n    return "local-pending"\n'
        parent=before.replace('local-pending','online-stable')
        after=before.replace('return 0','return 5')
        result=prepare.merge(parent,before,after,'test_scope.py')
        self.assertIn('return 5',result)
        self.assertIn('online-stable',result)
        self.assertNotIn('local-pending',result)

    def test_existing_row_cannot_be_deleted_after_online_change(self):
        table=lambda value:{'key':'id','rows':[{'id':'one','cap':value}]}
        with self.assertRaisesRegex(AssertionError,'table_delete_conflict'):
            prepare.table_delta(table(60),table(30),{'key':'id','rows':[]},'limits')


if __name__=='__main__':unittest.main()
