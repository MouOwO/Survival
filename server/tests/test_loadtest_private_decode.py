"""Private generator IPC must preserve data types and never construct objects."""
import importlib.util,io,math,pickle,struct,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('private_decode_under_test',ROOT/'tools/loadtest_native/decode_service.py');ipc=importlib.util.module_from_spec(spec);spec.loader.exec_module(ipc)
class PrivateDecodeData(unittest.TestCase):
    def test_bytes_unicode_numeric_types_and_signed_zero(self):
        value={'raw':b'\x00\xff','name':'中文','flag':False,'count':0,'float':-0.0,'big':2**200,'none':None,'rows':[1,2]};frame=ipc.packet(value);self.assertEqual(struct.unpack('!I',frame[:4])[0],len(frame)-4);actual=ipc.data_only(frame[4:]);self.assertEqual(actual,value);self.assertIs(type(actual['flag']),bool);self.assertIs(type(actual['count']),int);self.assertEqual(math.copysign(1,actual['float']),-1)
    def test_shared_baseline_identity_is_preserved_in_private_data(self):
        baseline={'hash':'synthetic','snapshot':{'save':{}}};actual=ipc.data_only(pickle.dumps({'baseline':baseline,'next_state':baseline},protocol=5));self.assertIs(actual['baseline'],actual['next_state'])
    def test_global_constructors_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'globals_forbidden'):ipc.data_only(pickle.dumps(complex(1,2)))
    def test_persistent_external_handles_are_rejected(self):
        stream=io.BytesIO();writer=pickle.Pickler(stream,protocol=5);writer.persistent_id=lambda obj:'synthetic_external_handle'if obj==42 else None;writer.dump([42])
        with self.assertRaisesRegex(ValueError,'persistent_objects_forbidden'):ipc.data_only(stream.getvalue())
    def test_trailing_data_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'trailing_data'):ipc.data_only(pickle.dumps({'ok':True})+b'extra')
    def test_frame_budget_is_enforced(self):
        with patch.object(ipc,'MAX_FRAME',32):
            with self.assertRaisesRegex(ValueError,'frame_budget'):ipc.packet({'x':'a'*100})
if __name__=='__main__':unittest.main()
