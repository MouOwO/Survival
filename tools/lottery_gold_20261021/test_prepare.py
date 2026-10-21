import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('gold_ticket_prepare', Path(__file__).with_name('prepare.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TicketOverlayTests(unittest.TestCase):
    def setUp(self):
        self.old = dict(key='id', rows=[dict(id='cultivation', ticket='normal', cost=1), dict(id='map', ticket='normal', cost=1)])

    def test_only_cultivation_currency_may_change(self):
        new = dict(key='id', rows=[dict(id='cultivation', ticket='special', cost=1), dict(id='map', ticket='normal', cost=1)])
        result = module.overlay_table(self.old, new, 'cultivation', {'ticket'})
        result['rows'][0]['cost'] = 9
        self.assertEqual(new['rows'][0]['cost'], 1)
        self.assertEqual(self.old['rows'][0]['ticket'], 'normal')

    def test_price_mutation_is_rejected(self):
        new = dict(key='id', rows=[dict(id='cultivation', ticket='special', cost=10), self.old['rows'][1]])
        with self.assertRaisesRegex(AssertionError, 'unrelated_table_field_changed'):
            module.overlay_table(self.old, new, 'cultivation', {'ticket'})

    def test_other_pool_currency_mutation_is_rejected(self):
        new = dict(key='id', rows=[self.old['rows'][0], dict(id='map', ticket='special', cost=1)])
        with self.assertRaisesRegex(AssertionError, 'unrelated_table_field_changed'):
            module.overlay_table(self.old, new, 'cultivation', {'ticket'})

    def test_added_or_deleted_rows_are_rejected(self):
        for rows in (self.old['rows'][:1], self.old['rows'] + [dict(id='new', ticket='special', cost=1)]):
            with self.assertRaisesRegex(AssertionError, 'table_rows_changed'):
                module.overlay_table(self.old, dict(key='id', rows=rows), 'cultivation', {'ticket'})


if __name__ == '__main__':
    unittest.main()
