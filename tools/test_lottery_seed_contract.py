"""Source-contract regression tests; no engine/HTTP/account/transaction writes."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import build_lottery_catalog as seed_builder
import build_ui_static_catalog as static_builder


BUNDLE = "d" * 64
OTHER = "a" * 64
MD5 = "e" * 32
DECLARATION = "scripts/vscripts/config/generated/archive_http_bundle.lua"
MANIFEST = "scripts/vscripts/config/generated/lottery_catalog_manifest.lua"


class Source:
    def __init__(self, bundle=BUNDLE, config=BUNDLE, md5=MD5, revisions=None):
        pool_map = ", ".join("["+json.dumps(k)+"] = "+json.dumps(v) for k,v in sorted((revisions or {}).items()))
        self.files = {DECLARATION: ('return { hash = "' + bundle + '" }').encode(),
            MANIFEST: ('return { config_hash = "' + config + '", catalog_md5 = "' + md5
                       + '", pool_revisions = { ' + pool_map + ' } }').encode()}
        self.reads = []
    def read(self, name):
        self.reads.append(name)
        return self.files[name]


class StaticContractTests(unittest.TestCase):
    def test_matching_public_seed_records_both_immutable_source_dependencies(self):
        source = Source()
        static_builder.validate_lottery_seed_contract(source, {"config_hash": BUNDLE, "md5": MD5,
            "catalog_json":'{"schema":1,"snapshots":[]}'})
        self.assertEqual(source.reads, [DECLARATION, MANIFEST])
    def test_s9_stale_seed_can_be_self_consistent_and_still_wrong_for_game(self):
        public = '{"schema":1,"snapshots":[]}'
        digest = hashlib.md5(public.encode("ascii"), usedforsecurity=False).hexdigest()
        stale = {"config_hash": OTHER, "md5": digest, "catalog_json": public}
        source = Source(config=OTHER, md5=digest)
        with self.assertRaisesRegex(ValueError, "seed_production_bundle_mismatch"):
            static_builder.validate_lottery_seed_contract(source, stale)
    def test_lua_manifest_md5_must_equal_the_json_seed(self):
        with self.assertRaisesRegex(ValueError, "lua_manifest_mismatch"):
            static_builder.validate_lottery_seed_contract(Source(md5="f"*32), {"config_hash": BUNDLE, "md5": MD5})
    def test_lua_manifest_must_use_the_production_config(self):
        with self.assertRaisesRegex(ValueError, "lua_manifest_mismatch"):
            static_builder.validate_lottery_seed_contract(Source(config=OTHER), {"config_hash": BUNDLE, "md5": MD5})
    def test_missing_production_hash_never_falls_back_to_seed_hash(self):
        source = Source();source.files[DECLARATION] = b"return {}"
        with self.assertRaisesRegex(ValueError, "production_bundle_hash_missing"):
            static_builder.validate_lottery_seed_contract(source, {"config_hash": BUNDLE, "md5": MD5})
    def test_revision_map_must_match_public_seed_even_when_md5_and_config_match(self):
        seed={"config_hash":BUNDLE,"md5":MD5,"catalog_json":json.dumps({"snapshots":[
            {"selected_pool":{"id":"map","revision":"production"}}]})}
        with self.assertRaisesRegex(ValueError,"pool_revisions_mismatch"):
            static_builder.validate_lottery_seed_contract(Source(revisions={"map":"unpublished-local"}),seed)


class BuilderContractTests(unittest.TestCase):
    def fixture(self, root):
        path = root / DECLARATION;path.parent.mkdir(parents=True)
        path.write_text('return { hash = "' + BUNDLE + '" }', encoding="utf8")
    def document(self):
        raw = '{"schema":1,"snapshots":[]}'
        return {"catalog_json":raw,"catalog_md5":hashlib.md5(raw.encode("ascii"),usedforsecurity=False).hexdigest(),
            "config_hash":BUNDLE,"catalog":{"snapshots":[]}}
    def test_explicit_foreign_bundle_rejects_before_lua_projection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary);self.fixture(root)
            with patch("server.archive_backend.bundle.Bundle",return_value=SimpleNamespace(hash=OTHER)), \
                 patch("server.archive_backend.lottery_catalog.catalog_document") as project:
                with self.assertRaisesRegex(ValueError,"bundle_contract_mismatch"):
                    seed_builder.generate(root,"lua-unused",root/"explicit_other")
                project.assert_not_called()
    def test_explicit_matching_bundle_builds_all_three_consistent_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary);self.fixture(root)
            with patch("server.archive_backend.bundle.Bundle",return_value=SimpleNamespace(hash=BUNDLE)), \
                 patch("server.archive_backend.lottery_catalog.catalog_document",return_value=self.document()):
                files,metadata = seed_builder.generate(root,"lua-unused",root/"explicit_current")
            self.assertEqual(len(files),3)
            self.assertEqual(metadata["config_hash"],BUNDLE)
            seed = json.loads(files["data/ui/lottery_catalog.json"])
            static_builder.validate_lottery_seed_contract(Source(md5=seed["md5"]),seed)
            self.assertIn(BUNDLE,files[MANIFEST])
    def test_default_bundle_is_resolved_from_the_game_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary);self.fixture(root)
            with patch("server.archive_backend.bundle.Bundle",return_value=SimpleNamespace(hash=BUNDLE)) as load, \
                 patch("server.archive_backend.lottery_catalog.catalog_document",return_value=self.document()):
                seed_builder.generate(root,"lua-unused")
            load.assert_called_once_with(root/"server/bundles"/BUNDLE)
    def test_lua_pool_revisions_come_from_same_canonical_document(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);self.fixture(root)
            public={"schema":1,"snapshots":[{"selected_pool":{"id":"map","revision":"123-456"}}]}
            raw=json.dumps(public,ensure_ascii=True,sort_keys=True,separators=(",",":"))
            document={"catalog_json":raw,"catalog_md5":hashlib.md5(raw.encode("ascii"),usedforsecurity=False).hexdigest(),
                "config_hash":BUNDLE,"catalog":public}
            with patch("server.archive_backend.bundle.Bundle",return_value=SimpleNamespace(hash=BUNDLE)), \
                 patch("server.archive_backend.lottery_catalog.catalog_document",return_value=document):
                files,_=seed_builder.generate(root,"lua-unused")
            source=Source(md5=document["catalog_md5"]);source.files[MANIFEST]=files[MANIFEST].encode()
            static_builder.validate_lottery_seed_contract(source,json.loads(files["data/ui/lottery_catalog.json"]))


if __name__ == "__main__":unittest.main()
