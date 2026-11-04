"""Real Ed25519/Valve DATA and exact gate-source rebinding boundaries.

Fixtures create an ephemeral in-memory test key, never read a production private
key and never claim the fixture is the actual published0104 parent. The separate
all-original semantic preflight exercises the real parent and original receipts.
"""
from base64 import b64encode
from copy import deepcopy
import hashlib
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

sys.path.insert(0,str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import package as m, ledger as l


def compiled(data):
    return struct.pack("<IHHII",28+len(data),12,0,8,1)+struct.pack("<4sII",b"DATA",8,len(data))+data


class SignedGeneratorRebindTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve()
        self.name="panorama/scripts/custom_game/generated_test.vjs_c"
        self.source="panorama/src/scripts/custom_game/generated_test.js"
        self.pins={"game":"a"*40,"content":"b"*40,"operator":"c"*40}
        self.origins={**self.pins,"operator":"d"*40}
        self.generated=b"var answer = 42;\n"
        self.artifact=compiled(self.generated.replace(b"\n",b"\r\n"))
        target=self.root/self.name;target.parent.mkdir(parents=True);target.write_bytes(self.artifact)
        row={"path":self.name,**l.byte_fingerprint(self.artifact)}
        self.manifest={"schema":2,"kind":"runtime_release_allowlist","hash_algorithms":["md5","sha256"],
            "files":[row],"file_count":1,"bytes":len(self.artifact)}
        self.manifest["content_sha256"]=l.sha(m.pack.runtime.manifest_payload(self.manifest))
        self.parent_raw=l.canonical(self.manifest);self.parent_sha=l.sha(self.parent_raw)
        (self.root/m.build_release.MANIFEST).write_bytes(self.parent_raw)
        key=Ed25519PrivateKey.generate();public=key.public_key();key_id=m.pack.protect_data.public_id(public)
        self.public=self.root/"test_public.pem"
        self.public.write_bytes(public.public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo))
        self.document={"schema":2,"algorithm":"Ed25519","key_id":key_id,"release_sequence":2026110104,
            "content_sha256":self.manifest["content_sha256"],
            "signature":b64encode(key.sign(m.pack.protect_data.DOMAIN+struct.pack(">Q",2026110104)+
                m.pack.runtime.manifest_payload(self.manifest))).decode()}
        (self.root/m.build_release.SIGNATURE).write_bytes(l.canonical(self.document))
        self.policy={"integrity":{"minimum_release_sequence":2026102101,"trusted_key_id":key_id}}
        self.baseline={"parent_sequence":2026110104,"parent_manifest_sha256":self.parent_sha,
                       "parent_content_sha256":self.manifest["content_sha256"]}
        self.proof_raw=l.canonical({"kind":"IMMUTABLE_ITEM_RESOURCE_GENERATOR_PROOF"})
        self.prepare_generation()

    def prepare_generation(self):
        mirror=self.source.replace("panorama/src/","panorama/",1)
        self.item={"source_revisions":self.origins,"proof_raw":self.proof_raw,"proof_sha256":l.sha(self.proof_raw),
            "output_bytes":{self.source:self.generated},"input_bytes":{"game:data/input.json":b"{}\n"},
            "content_mirrors":{mirror:self.generated}}
        self.verified={"outputs":{self.source:l.byte_fingerprint(self.generated)}}
        self.sources={"game:"+self.name:self.artifact,"game:"+self.source:self.generated,
            "content:"+mirror:self.generated,**self.item["input_bytes"]}
        reference={"kind":"IMMUTABLE_ITEM_RESOURCE_GENERATOR_PROOF","original_receipt_sha256":l.sha(self.proof_raw),
                   "original_source_revisions":self.origins}
        generator={"kind":reference["kind"],"sha256":reference["original_receipt_sha256"],"source_revisions":self.origins,
                   "verification_sha256":l.sha(l.canonical(self.verified))}
        inputs={key:l.sha(raw) for key,raw in self.sources.items()}
        row={"kind":"compiled","inputs":inputs,"output":l.byte_fingerprint(self.artifact),"original_receipts":[reference]}
        self.receipt={"kind":"COMPLETE_RUNTIME_BINDING_RECEIPT","source_revisions":self.pins,
            "declaration_is_not_package_authority":True,"bindings":{self.name:row},"original_receipts":[generator]}
        self.refresh_receipt()

    def refresh_receipt(self):
        raw=l.canonical(self.receipt);pin=l.sha(raw)
        self.receipts={pin:raw}
        self.binding={"resource":self.name,"kind":"compiled","inputs":self.receipt["bindings"][self.name]["inputs"],
                      "output":l.byte_fingerprint(self.artifact),"receipt_sha256":pin}

    def parent(self):
        with patch.object(m.pending,"_read_json",return_value=self.baseline), \
             patch.object(m.pack.handoff,"trusted_policy",return_value=(self.policy,self.public)):
            return m._signed_rebind_parent(self.parent_raw,self.parent_sha,self.root)

    def rebind(self):
        root,rows,_,_=self.parent()
        return m._verify_signed_rebind(self.binding,pins=self.pins,
            target_rows={self.name:l.byte_fingerprint(self.artifact)},parent_rows=rows,parent_root=root,
            parent_sha256=self.parent_sha,source_raw=self.sources,binding_receipts=self.receipts,
            item_evidence=self.item,item_verified=self.verified)

    def test_real_signature_and_exact_crlf_data_do_not_invent_fresh_compilation(self):
        value=self.rebind()
        self.assertEqual(value["normalization"],"GIT_LF_TO_COMPILER_CRLF_ONLY")
        self.assertFalse(value["fresh_compilation_claimed"])
        self.assertFalse(value["invented_historical_source_revision"])

    def test_invalid_real_ed25519_signature_is_rejected(self):
        bad={**self.document,"signature":b64encode(b"\0"*64).decode()}
        (self.root/m.build_release.SIGNATURE).write_bytes(l.canonical(bad))
        with self.assertRaises(InvalidSignature):self.rebind()

    def test_entire_artifact_must_match_even_when_data_is_unchanged(self):
        (self.root/self.name).write_bytes(self.artifact+b"old_metadata")
        with self.assertRaisesRegex(ValueError,"entire_artifact_changed"):self.rebind()

    def test_current_git_artifact_cannot_differ_from_parent(self):
        self.sources["game:"+self.name]=self.artifact+b"different_current_git"
        with self.assertRaisesRegex(ValueError,"typed_input_set_changed"):self.rebind()

    def test_changed_generated_source_requires_fresh_compilation(self):
        self.generated=b"var answer = 43;\n";self.prepare_generation()
        with self.assertRaisesRegex(ValueError,"data_not_exact_generator_output"):self.rebind()

    def test_raw_binding_receipt_is_required(self):
        self.receipts={}
        with self.assertRaisesRegex(ValueError,"raw_binding_receipt_missing"):self.rebind()

    def test_forged_fresh_compiler_reference_is_not_rebinding_evidence(self):
        self.receipt["bindings"][self.name]["original_receipts"].append({"kind":"FAKE_FRESH_COMPILER"})
        self.refresh_receipt()
        with self.assertRaisesRegex(ValueError,"serialized_binding_changed"):self.rebind()

    def test_wrong_original_generator_verification_is_rejected(self):
        self.receipt["original_receipts"][0]["verification_sha256"]="0"*64;self.refresh_receipt()
        with self.assertRaisesRegex(ValueError,"original_generator_reference_changed"):self.rebind()


class AdmissionSourceBytesTests(unittest.TestCase):
    def test_original_protection_bytes_are_used_and_both_proof_and_target_checked(self):
        source={"gate.lua":b"original source\n"};protected={"gate.lua":b"proved protected runtime\n"}
        expected={"gate.lua":l.byte_fingerprint(protected["gate.lua"])}
        result=m.admission_resource_bytes({"gate.lua"},source,{}, {"protected_outputs":protected},
            {"protected_outputs":expected},expected)
        self.assertEqual(result,protected)
        with self.assertRaisesRegex(ValueError,"not_original_receipt"):
            m.admission_resource_bytes({"gate.lua"},source,{}, {"protected_outputs":{"gate.lua":b"wrong"}},
                {"protected_outputs":expected},expected)
        with self.assertRaisesRegex(ValueError,"not_in_complete_target"):
            m.admission_resource_bytes({"gate.lua"},source,{}, {"protected_outputs":protected},
                {"protected_outputs":expected},{"gate.lua":l.byte_fingerprint(b"different target")})

    def test_signed_parent_newline_rebind_requires_exact_full_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();plain=b"line one\nline two\n";original=plain.replace(b"\n",b"\r\n")
            (root/"gate.lua").write_bytes(original);row=l.byte_fingerprint(original);notes={}
            args=({"gate.lua"},{"gate.lua":plain},{},{"protected_outputs":{}},{"protected_outputs":{}},{"gate.lua":row})
            expected=m.admission_resource_bytes(*args,parent_root=root,parent_rows={"gate.lua":row},source_bindings=notes)
            self.assertEqual(expected["gate.lua"],original)
            self.assertEqual(notes["gate.lua"]["kind"],"ORIGINAL_SIGNED_GIT_LF_TO_CRLF_REBIND")
            (root/"gate.lua").write_bytes(original+b"extra")
            with self.assertRaisesRegex(ValueError,"not_exact_git_lf_to_crlf"):
                m.admission_resource_bytes(*args,parent_root=root,parent_rows={"gate.lua":row})
            with self.assertRaisesRegex(ValueError,"signed_parent_equivalence_required"):
                m.admission_resource_bytes(*args)


if __name__=="__main__":unittest.main()
