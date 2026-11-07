"""Actual immutable Git readsets bridge original producers to later targets.

No compiler/protection/generator output is recreated or relabelled. Real Git
commands are used; spies only count calls and never replace their output.
"""
from collections import Counter
from copy import deepcopy
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import package as m, pipeline_recipe as r

ORIGINAL="a717903f6219086da17f72d872f63ef8de153160"
BEFORE_CATALOG="27ea3dc0c0b2607f9baad89887a005db6a512093"
CONTENT="3700b2328007c157325cdf204dbe47dcf7c42a9e"


class ActualProducerTargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.head=m.pending._git(m.ROOT,"rev-parse","HEAD",counts=Counter()).decode().strip()
        cls.name="data/ui/item_resources.json";cls.key="game:"+cls.name
        cls.original={"game":ORIGINAL,"content":CONTENT,"operator":BEFORE_CATALOG}
        cls.target={"game":cls.head,"content":CONTENT,"operator":"e4c4341f8bd29cf0f0f70139dcf79cf5bbe079f9"}
        cls.raw=m.pending._git(m.ROOT,"show",ORIGINAL+":"+cls.name,counts=Counter())
        cls.current=m.pending._git(m.ROOT,"show",cls.head+":"+cls.name,counts=Counter())

    def test_real_two_commit_git_objects_match_and_original_labels_are_unchanged(self):
        self.assertEqual(self.raw,self.current);self.assertNotEqual(ORIGINAL,self.head)
        kwargs={"source_revisions":self.original,"source_bytes":{self.key:self.raw},"proof_sha256":"1"*64}
        before=deepcopy(kwargs)
        with patch.object(m.subprocess,"run",wraps=subprocess.run) as observed:
            value=m._producer_target_readset_binding("compiler[0]",kwargs,self.target,{self.key:self.current})
        requests=[call.kwargs.get("input",b"") for call in observed.call_args_list]
        self.assertTrue(any((ORIGINAL+":"+self.name).encode() in q for q in requests))
        self.assertTrue(any((self.head+":"+self.name).encode() in q for q in requests))
        self.assertEqual(kwargs,before)
        self.assertEqual(value["producer_source_revisions"],self.original)
        self.assertEqual(value["target_source_revisions"],{"game":self.head,"content":CONTENT})
        self.assertFalse(value["git_revisions_relabelled"]);self.assertFalse(value["producer_outputs_recreated"])

    def test_real_target_git_change_cannot_be_hidden_by_forged_equal_readset(self):
        name="panorama/src/scripts/custom_game/common/ui_static_catalog.js";key="game:"+name
        old=m.pending._git(m.ROOT,"show",BEFORE_CATALOG+":"+name,counts=Counter())
        new=m.pending._git(m.ROOT,"show",self.head+":"+name,counts=Counter())
        self.assertNotEqual(old,new)
        kwargs={"source_revisions":{**self.original,"game":BEFORE_CATALOG},"source_bytes":{key:old},"proof_sha256":"2"*64}
        with self.assertRaisesRegex(ValueError,"current_readset_bytes_differ"):
            m._producer_target_readset_binding("compiler[0]",kwargs,self.target,{key:new})
        # Even lying that the target contains old bytes cannot pass the second
        # real revision:path Git lookup.
        with self.assertRaisesRegex(ValueError,"actual_immutable_git_object_mismatch"):
            m._producer_target_readset_binding("compiler[0]",kwargs,self.target,{key:old})

    def test_protection_and_generator_readsets_use_the_same_real_git_boundary(self):
        protection={"source_revisions":self.original,"source_bytes":{self.name:self.raw},"production_sha256":"3"*64}
        item={"source_revisions":self.original,"input_bytes":{self.key:self.raw},"output_bytes":{},
              "content_mirrors":{},"proof_sha256":"4"*64}
        first=m._producer_target_readset_binding("protection",protection,self.target,{self.key:self.current})
        second=m._producer_target_readset_binding("item_generator",item,self.target,{self.key:self.current})
        self.assertEqual(first["inputs"],second["inputs"])
        self.assertEqual(first["original_receipt_sha256"],"3"*64)
        self.assertEqual(second["original_receipt_sha256"],"4"*64)

    def test_current_bytes_and_lfs_payload_require_real_equality(self):
        kwargs={"source_revisions":self.original,"source_bytes":{self.key:self.raw},"proof_sha256":"5"*64}
        with self.assertRaisesRegex(ValueError,"current_readset_bytes_differ"):
            m._producer_target_readset_binding("compiler[0]",kwargs,self.target,{self.key:self.current+b"changed"})
        pointer=b"version https://git-lfs.github.com/spec/v1\noid sha256:"+b"0"*64+b"\nsize 3\n"
        bad={**kwargs,"source_bytes":{self.key:{"git_blob":pointer,"content":b"bad"}}}
        with self.assertRaisesRegex(ValueError,"resolved_lfs_pointer_identity_mismatch"):
            m._producer_target_readset_binding("compiler[0]",bad,self.target,{self.key:b"bad"})

    def test_new_controls_directory_is_distinct_from_original_signed_controls(self):
        self.assertEqual(r.REPORT,r.ROOT/"output/complete_delivery_release_20261107_v01")
        for previous in ("complete_delivery_release_20261103", "complete_delivery_release_20261103_v02",
                         "complete_delivery_release_20261103_v03", "complete_delivery_release_20261105_v01",
                         "complete_delivery_release_20261105_v02", "complete_delivery_release_20261105_v03",
                         "complete_delivery_release_20261106_v01", "complete_delivery_release_20261106_v02",
                         "complete_delivery_release_20261106_v03", "complete_delivery_release_20261106_v04"):
            self.assertNotEqual(r.REPORT,r.ROOT/"output"/previous)
        self.assertEqual(r.INPUT_FILE,r.REPORT/"pipeline_inputs.json")


if __name__=="__main__":unittest.main()
