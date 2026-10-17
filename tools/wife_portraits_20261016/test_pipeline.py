"""Scoped mutation tests: only forty wife rows/objects may change."""
from __future__ import annotations

import copy
import csv
import io
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_assets import IDS, ART_STATUS, patch_catalog, patch_icon_csv, catalog_objects, new_catalog_entry, verify_unrelated


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.header = ['icon_id','category_id','item_id','display_name','icon_path','art_status','enabled']
        self.entries = [{'icon_id':'old_ex','category_id':'ex','item_id':'ex_01','display_name':'原角色','icon_path':'old.png','art_status':'generated_portrait_v3','enabled':'1','unrelated':{'keep':'空白, 标点'}}]
        self.entries += [{'icon_id':ident,'category_id':'wife','item_id':ident,'display_name':'角色'+ident,'icon_path':'borrowed.png','art_status':'reused_portrait_v3','enabled':'1'} for ident in IDS]
        self.entries += [{'icon_id':'old_friend','category_id':'friend','item_id':'friend_01','display_name':'另一个原角色','icon_path':'friend.png','art_status':'generated_portrait_v3','enabled':'1'}]
        self.catalog = 'prefix();var entries=[  ' + ',\n '.join(json.dumps(row, ensure_ascii=False, separators=(', ', ': ')) for row in self.entries) + ' ]; untouchedController();\n'
        text = io.StringIO(newline='')
        writer = csv.DictWriter(text, self.header, extrasaction='ignore', lineterminator='\r\n')
        writer.writeheader()
        writer.writerows(self.entries)
        self.csv = b'\xef\xbb\xbf' + text.getvalue().encode('utf-8')

    def test_exact_unrelated_bytes_survive_patch(self):
        replacements = {row['item_id']: dict(row, icon_path='wife/'+row['item_id']+'.png', art_status=ART_STATUS) for row in self.entries if row['category_id']=='wife'}
        updated = patch_catalog(self.catalog, replacements)
        updated_csv = patch_icon_csv(self.csv, replacements)
        verify_unrelated(self.csv, self.catalog, updated_csv, updated)
        self.assertTrue(updated.startswith('prefix();var entries=[  '))
        self.assertTrue(updated.endswith(' ]; untouchedController();\n'))
        self.assertTrue(updated_csv.startswith(b'\xef\xbb\xbf'))
        self.assertEqual(sum(row['art_status']==ART_STATUS for _,_,row in catalog_objects(updated)[2]),40)

    def test_duplicate_or_missing_identity_is_rejected(self):
        replacements = {row['item_id']:row for row in self.entries if row['category_id']=='wife'}
        missing = dict(replacements)
        missing.pop('wife_40')
        with self.assertRaises(ValueError):
            patch_catalog(self.catalog, missing)
        with self.assertRaises(ValueError):
            patch_icon_csv(self.csv, missing)

    def test_gameplay_catalog_fields_preserved_when_replacing_art(self):
        original = {'item_id':'wife_19','category_id':'wife','description':'箭塔暴击几率+3%','quality':'SR','display_width':96,'display_height':96,'reused_from':'ex_19','tone_color':''}
        asset = {'icon_path':'wife/wife_19.png','runtime_uri':'s2r://wife_19.vtex','source_width':1254,'source_height':1254,'sha256':'newhash','alpha_bounds':[4,41,1254,1222]}
        saved = copy.deepcopy(original)
        changed = new_catalog_entry(original, asset)
        self.assertEqual(original,saved)
        self.assertNotIn('reused_from',changed)
        for key in ('item_id','category_id','description','quality','display_width','display_height','tone_color'):
            self.assertEqual(changed[key],original[key])

    def test_nonwife_change_is_detected(self):
        with self.assertRaises(ValueError):
            verify_unrelated(self.csv,self.catalog,self.csv,self.catalog.replace('空白, 标点','changed'))


if __name__ == '__main__':
    unittest.main()
