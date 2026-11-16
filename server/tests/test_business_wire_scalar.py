"""Wire scalar canonicalization must retain the standard JSON byte contract."""
from pathlib import Path
import unittest,json,math,random,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server')]
from player_web_auth import business_wire as codec

class ScalarJsonContractTests(unittest.TestCase):
 def test_scalar_bytes_match_standard_JSON_across_float_and_escape_boundaries(self):
  rng=random.Random(161126)
  values=[None,False,True,0,1,-1,0.0,-0.0,1e20,1e-20,'','quote"\\\n\t\x00','\u5408\u6210\U0001f98a',''.join(chr(i)for i in range(1024)),2**128,-2**128]
  values.extend(math.ldexp(rng.uniform(-1,1),rng.randrange(-1000,1000))for _ in range(2000))
  for value in values:
   expected=json.dumps(value,ensure_ascii=False,allow_nan=False,sort_keys=True,separators=(',',':')).encode('utf8')
   self.assertEqual(codec._scalar_json_bytes(value),expected)
 def test_complex_discriminator_retains_canonical_fallback(self):
  for value in [[],{},[1,True],{'x':None,'n':0,'b':False},[1,2]]:self.assertEqual(codec._scalar_json_bytes(value),codec.canonical(value))
 def test_nonfinite_and_surrogate_errors_keep_full_original_reply(self):
  for value in [float('nan'),float('inf'),-float('inf')]:
   with self.assertRaises(ValueError):codec._scalar_json_bytes(value)
  for raw in [b'{"value":NaN}',b'{"value":Infinity}',b'{"value":"\\ud800"}',b'{"x":1,"x":2}']:
   self.assertIs(codec.pack_bytes(raw,codec.SCHEMA_HASH),raw)
 def test_schema_types_and_signed_zero_survive_roundtrip(self):
  value={'integer':0,'float':0.0,'negative_zero':-0.0,'flag':False,'nil':None,'items':[0,False,None,0.0,-0.0],'vip':{'active':False},'label':'\u5408\u6210\U0001f98a'}
  before=codec.canonical(value);self.assertEqual(codec.canonical(codec.decode(codec.encode(value))),before);self.assertEqual(codec.canonical(value),before)

if __name__=='__main__':unittest.main()
