"""Bounded native peer routing and partial-start cleanup regression."""
from pathlib import Path
import ast,unittest
SOURCE=Path(__file__).resolve().parents[2]/"tools/loadtest_native/peer_forward.py"
def functions():
 tree=ast.parse(SOURCE.read_text("utf8")); selected=[n for n in tree.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in {"need","ports","argv","PeerForward"}]
 env={"ROOT":Path("/srv/survival-loadtest/peer_link_20261117_01"),"KNOWN_SHA":"known"}
 exec(compile(ast.Module(body=selected,type_ignores=[]),str(SOURCE),"exec"),env);return env
class Child:
 instances=[];fail_port=None
 def __init__(self,spec,digest,stage,port):self.port=port;self.started=False;self.closed_flag=True;self.closed_calls=0;self.instances.append(self)
 def start(self):
  self.closed_flag=False;self.started=True
  if self.port==self.fail_port:raise ValueError("injected_start_failure")
 def close(self):self.closed_flag=True;self.closed_calls+=1
 def closed(self):return self.closed_flag
 def require_alive(self):assert self.started and not self.closed_flag
 def sample(self):return {"local_port":self.port}
 def receipt(self):return {"closed":self.closed_flag,"forced_kill":False,"local_bind":"127.0.0.1:"+str(self.port),"target_bind":"127.0.0.1:29567"}
class PeerForwardGroupTests(unittest.TestCase):
 def setUp(self):Child.instances=[];Child.fail_port=None;self.e=functions();self.e.update(read_spec=lambda *_:{"peer_forward_ports":list(range(29567,29571))},_Forward=Child)
 def test_ports_reject_unbound_range_and_types(self):
  for bad in ([22],[29568],list(range(29567,29583)),[29567.0],[],"29567"):
   with self.subTest(bad=bad),self.assertRaises(ValueError):self.e["ports"]({"peer_forward_ports":bad})
  self.assertEqual(self.e["ports"]({}),(29567,))
 def test_every_listener_has_only_same_authorized_destination(self):
  for port in range(29567,29571):
   args=self.e["argv"](port);self.assertEqual(args[args.index("-L")+1],f"127.0.0.1:{port}:127.0.0.1:29567");self.assertEqual(args[-1],"root@47.111.16.128");self.assertIn("StrictHostKeyChecking=yes",args);self.assertIn("ControlMaster=no",args)
 def test_all_children_sample_and_close(self):
  group=self.e["PeerForward"]("spec","digest",Path("stage"));group.start();group.require_alive();self.assertEqual([r["local_port"] for r in group.sample()],list(range(29567,29571)));self.assertFalse(group.closed());group.close();receipt=group.receipt();self.assertTrue(receipt["closed"]);self.assertEqual(receipt["data_ssh_processes"],4);self.assertTrue(all(x["closed"]for x in receipt["forwards"]))
 def test_partial_start_failure_closes_started_and_unstarted(self):
  Child.fail_port=29569;group=self.e["PeerForward"]("spec","digest",Path("stage"))
  with self.assertRaisesRegex(ValueError,"injected_start_failure"):group.start()
  self.assertTrue(group.closed());self.assertTrue(all(x.closed_calls==1 for x in Child.instances));self.assertFalse(Child.instances[-1].started)
if __name__=="__main__":unittest.main()
