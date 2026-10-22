"""Exercise both source documents and reject mismatched versions before generation."""
import json
import tempfile
import unittest
from pathlib import Path

import openpyxl
import import_human_monster_spec as importer


class HumanMonsterImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.json_path = importer.SOURCE / 'human_spec.json'
        cls.xlsx_path = importer.SOURCE / '接入规格_人话版_v3.xlsx'
        cls.data = importer.load(cls.json_path, cls.xlsx_path)

    def test_complete_mode_ranges_and_workbook_only_bases(self):
        self.assertEqual(sum(map(len, self.data['modes'].values())), 235)
        self.assertEqual({key:len(rows) for key,rows in self.data['modes'].items()},
                         dict(standard=10, pure=10, rich=30, cold=50, scourge=50, ruins=50, celestial=35))
        self.assertEqual(set(self.data['waves']), set(range(1,31)))
        self.assertEqual(self.data['waves'][8]['health'], 4000)
        self.assertEqual(self.data['special_rotation'][8][0]['health'], 1105)
        self.assertGreater(self.data['sources']['cross_checked_cells'], 2800)

    def test_workbook_changes_drive_wave_base_even_when_json_is_unchanged(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'workbook.xlsx'
            book = openpyxl.load_workbook(self.xlsx_path)
            book['波次小怪基础值'].cell(9, 3).value = 4123.5
            book.save(destination)
            book.close()
            result = importer.load(self.json_path, destination)
        self.assertEqual(result['waves'][8]['health'], 4123.5)
        self.assertEqual(result['special_rotation'][8][0]['health'], 1105)

    def test_different_json_version_is_rejected(self):
        raw = json.loads(self.json_path.read_text(encoding='utf-8-sig'))
        raw['modes'][0]['HP倍率'] = 999
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'human.json'
            destination.write_text(json.dumps(raw), encoding='utf-8')
            with self.assertRaisesRegex(AssertionError, 'Conflicting sources'):
                importer.load(destination, self.xlsx_path)

    def test_workbook_requires_every_wave(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'workbook.xlsx'
            book = openpyxl.load_workbook(self.xlsx_path)
            book['波次小怪基础值'].delete_rows(31)
            book.save(destination)
            book.close()
            with self.assertRaisesRegex(AssertionError, 'thirty wave bases'):
                importer.load(self.json_path, destination)

    def test_corrections_are_already_in_the_imported_values(self):
        bosses = self.data['attack_bosses']
        self.assertEqual((bosses[5]['health'], bosses[5]['war3_armor']), (10005, 98))
        self.assertEqual(bosses[20]['attack'], 60600)
        self.assertEqual(bosses[30]['health'], 40000015)
        archive = {row['name']:row for row in self.data['save_challenges']}
        self.assertEqual(archive['虚空之影1']['attack'], 189002)
        self.assertEqual(archive['神兽狩猎-古尔丹']['attack'], 5500002)
        self.assertEqual(archive['神兽狩猎-黑龙王子']['health'], 10080000000)
        self.assertEqual(archive['神兽狩猎-黑龙王子']['attack'], 168000002)


if __name__ == '__main__':
    unittest.main()
