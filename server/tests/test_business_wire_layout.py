"""Compatibility with unchanged BW1 bytes, including all immutable templates."""
from pathlib import Path
import unittest,json,hashlib,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'server'))
from player_web_auth import business_wire as codec
def fixture(defaults, variant):
    from copy import deepcopy
    value=deepcopy(defaults)
    if variant=="reverse":value=dict(reversed(list(value.items())))
    if variant=="patch" and value:
        key=sorted(value)[0];old=value[key]
        value[key]=(not old)if type(old)is bool else old+1 if type(old)is int else old+0.125 if type(old)is float else old+"合成" if type(old)is str else 7
    if variant=="references":return {"save":value,"copy":[deepcopy(value),deepcopy(value)],"typed":[False,0,0.0,-0.0,None,2**53-1]}
    return {"save":value,"ok":True}

class LayoutCompatibility(unittest.TestCase):
 def test_all_existing_templates_match_frozen_original_packet_bytes(self):
  golden=json.loads((ROOT/'server/tests/fixtures/business_wire_layout_golden.json').read_bytes())
  self.assertEqual(codec.SCHEMA_HASH,golden['schema_hash'])
  self.assertEqual(len(golden['rows']),4*len(codec._TEMPLATES))
  for row in golden['rows']:
   with self.subTest(template=row['template'],variant=row['variant']):
    value=fixture(codec._TEMPLATES[row['template']]['defaults'],row['variant']);before=codec.canonical(value);packed=codec.pack_bytes(before,codec.SCHEMA_HASH)
    self.assertEqual(len(packed),row['bytes']);self.assertEqual(hashlib.sha256(packed).hexdigest(),row['packed_sha256'])
    decoded=json.loads(packed);decoded=codec.decode(decoded)if codec.MARKER in decoded else decoded
    self.assertEqual(codec.canonical(decoded),before);self.assertEqual(codec.canonical(value),before)
 def test_public_decode_cannot_reuse_private_writer_bytes(self):
  envelope=codec._encode({'value':'x'*200},_retain=True)
  envelope.raw=b'{}';envelope.decoded_raw=b'corrupt'
  self.assertEqual(codec.decode(envelope.value),{'value':'x'*200})
 def test_large_decoded_reply_retains_original_memory_bound(self):
  value={'value':'x'*70000};writer=codec._encode(value,_retain=True)
  self.assertEqual(codec._decode(writer.value,_writer=writer),value)
  self.assertIsNone(writer.decoded_raw)
if __name__=='__main__':unittest.main()
