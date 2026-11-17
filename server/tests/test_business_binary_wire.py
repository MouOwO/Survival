"""Negotiated binary reply compatibility, hostile frames and bounded state."""
from pathlib import Path
import base64
import concurrent.futures
import copy
import json
import sys
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server')]
from player_web_auth import business_wire as bw,business_binary_wire as binary

class BinaryBusinessWireTests(unittest.TestCase):
    def test_small_integer_payload_bytes_exclude_the_35_byte_frame_header(self):
        for value,length in [(0,1),(1,1),(223,1),(-1,2),(224,3),(16383,3),(16384,4)]:
            raw=binary.encode(value)
            self.assertEqual(len(raw)-35,length)
            self.assertEqual(binary.decode(raw),value)

    def test_types_float_boundaries_templates_and_unknown_keys_roundtrip(self):
        values=[None,False,True,0,0.0,-0.0,2**53-1,-(2**53-1),5e-324,-5e-324,
                1.7976931348623157e308,'雪😀\0',{'1':1,'01':False,'@1':None,'~':0,'':[]},[],{}]
        values.extend(row['defaults']for row in bw.SCHEMA['templates'])
        for value in values:
            original=bw.canonical(value)
            self.assertEqual(bw.canonical(binary.decode(binary.encode(value))),original)
            self.assertEqual(bw.canonical(value),original)

    def test_unsafe_large_integer_falls_back_without_truncation(self):
        for n in [2**53,-2**53,2**80]:
            with self.assertRaises(ValueError):binary.encode({'n':n})
            value={'ok':True,'n':n,'text':'synthetic'*30};body=bw.canonical(value)
            result=bw.pack_bytes(body,binary.ADVERTISEMENT);parsed=json.loads(result)
            self.assertNotIn('_bb',parsed)
            self.assertEqual(bw.canonical(bw.decode(parsed)if'_bw'in parsed else parsed),body)

    def test_completed_object_references_are_independent_after_decode(self):
        shared={'nested':{'value':['synthetic'*20,False,0,None]}}
        result=binary.decode(binary.encode({'a':copy.deepcopy(shared),'b':copy.deepcopy(shared)}))
        result['a']['nested']['value'].append(7)
        self.assertEqual(len(result['b']['nested']['value']),4)

    def test_string_table_limit_and_new_frame_do_not_share_state(self):
        value={'items':['synthetic-long-'+str(i)for i in range(4200)]+['synthetic-long-0']*20}
        self.assertEqual(binary.decode(binary.encode(value)),value)
        a=binary.encode({'x':'same-long-string','y':'same-long-string'})
        b=binary.encode({'x':'another-long-string','y':'another-long-string'})
        self.assertEqual(binary.decode(a)['x'],'same-long-string')
        self.assertEqual(binary.decode(b)['x'],'another-long-string')
        with self.assertRaises(ValueError):binary.decode(binary._PREFIX+b'\x0d\x01')

    def test_truncated_changed_schema_trailing_bytes_and_noncanonical_varints(self):
        good=binary.encode({'ok':True,'data':[1,None,False]})
        for bad in [good[:i]for i in range(len(good))]+[good+b'x',b'XX'+good[2:],
              binary._PREFIX+b'\x03\x80\x00',binary._PREFIX+b'\x03'+b'\xff'*9,
              good[:9]+bytes([good[9]^1])+good[10:]]:
            with self.assertRaises(ValueError):binary.decode(bad)

    def test_invalid_UTF8_duplicate_fields_cycles_and_nonfinite_are_rejected(self):
        for node in [b'\x05\x01\xff',b'\x06\x02\x06a\x20\x06a\x20',
                     b'\x06\x01\x00\x20',b'\x0a\x01',b'\x0b\x01\x0a\x01',
                     b'\x04'+bytes.fromhex('000000000000f07f'),b'\x08\x00']:
            with self.assertRaises(ValueError):binary.decode(binary._PREFIX+node)

    def test_base64_strict_padding_alphabet_and_envelope_members(self):
        for value in [{'_bb':x}for x in ['AB==','AAB=','AA=A','!!!!','Zg==\n']]+[{'_bb':False},{'_bb':'','extra':1}]:
            with self.assertRaises((ValueError,TypeError)):binary.unwrap(value)

    def test_byte_node_depth_and_expansion_budgets(self):
        with mock.patch.object(bw,'MAX_BYTES',64):
            with self.assertRaises(ValueError):binary.encode({'x':'x'*100})
        with mock.patch.object(bw,'MAX_NODES',3):
            with self.assertRaises(ValueError):binary.decode(binary._PREFIX+b'\x07\x04'+b'\x20'*4)
        with self.assertRaises(ValueError):binary.decode(binary._PREFIX+b'\x07\x01'*65+b'\x20')
        raw=binary._tree_bytes([0,[4,1,[0,*([1]*12)]],*([[3,1]]*8)])
        with mock.patch.object(bw,'MAX_NODES',50):
            with self.assertRaises(ValueError):binary.decode(raw)

    def test_only_negotiated_smaller_representation_and_small_body_constant_path(self):
        value={'ok':True,'items':[{'id':'synthetic-'+str(i),'hash':'a'*64}for i in range(100)]}
        body=bw.canonical(value);legacy=bw.pack_bytes(body,bw.SCHEMA_HASH)
        new=bw.pack_bytes(body,binary.ADVERTISEMENT);self.assertLess(len(new),len(legacy))
        self.assertEqual(bw.canonical(bw.decode(binary.unwrap(json.loads(new)))),body)
        self.assertIs(bw.pack_bytes(body,'unsupported'),body)
        for body in [b'{}',b'{"ok":true}',b'{"x":NaN}',b'{"x":1,"x":2}']:
            with mock.patch.object(bw,'_encode',side_effect=AssertionError('small encode forbidden')):
                self.assertIs(bw.pack_bytes(body,binary.ADVERTISEMENT),body)

    def test_parallel_frames_have_no_account_or_cross_response_cache(self):
        def one(i):
            value={'ok':True,'account':'synthetic-'+str(i),'items':['long-'+str(i)]*20}
            self.assertEqual(binary.decode(binary.encode(value)),value)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8)as pool:list(pool.map(one,range(200)))

if __name__=='__main__':unittest.main()
