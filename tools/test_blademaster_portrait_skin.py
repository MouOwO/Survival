"""Check the Bladeform body skin, complete outfit, and raised portrait camera.

The head model is unchanged; the camera reveals its existing white rear mane.
"""
from pathlib import Path
import csv
import json
import math
import os
import re
import shutil
import subprocess
import unittest

from build_monster_portraits import balanced


ROOT = Path(__file__).resolve().parents[1]
ASSET = "hero_permanent_hero_blademaster"


def csv_rows(name):
    with (ROOT / "data/csv/资源系统" / name).open(encoding="utf-8-sig", newline="") as source:
        return [row for row in csv.DictReader(source)
                if row[next(iter(row))] and not row[next(iter(row))].startswith("#")]


def scene_properties(text):
    entities = {}
    for match in re.finditer(r'"CMapEntity"\s*\{', text):
        block = text[match.start():balanced(text, text.index("{", match.start())) + 1]
        props = dict(re.findall(r'"([^"]+)"\s+"(?:string|vector3|qangle)"\s+"([^"]*)"', block))
        if props.get("targetname"):
            entities[props["targetname"]] = props
    return entities


class BladeformSkinTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.asset = next(row for row in csv_rows("asset_catalog.csv") if row["asset_id"] == ASSET)
        cls.manifest = json.loads((ROOT / "art/portraits/monsters/manifest.json").read_text(encoding="utf-8"))
        cls.scene = cls.manifest["assets"][ASSET]
        cls.properties = scene_properties((ROOT / "art/portraits/monsters" /
                                          (cls.scene["map"].split("/")[-1] + ".vmap")).read_text(encoding="utf-8"))

    def test_world_lua_catalog_and_scene_skin_agree(self):
        lua = (os.environ.get("LUA_BIN") or shutil.which("lua5.1") or shutil.which("lua")
               or r"C:\Program Files\lua\bin\lua5.1.exe")
        code = '''package.path = "scripts/vscripts/?.lua;" .. package.path
local world = require("config/hero_cosmetics_config").hero_blademaster
local asset = require("config/generated/asset_catalog").by_id.hero_permanent_hero_blademaster
assert(world.body_skin ~= nil and asset.model_skin ~= nil)
io.write(tostring(world.body_skin), "\\t", tostring(asset.model_skin), "\\t", world.body_model)
'''
        result = subprocess.run([lua, "-e", code], cwd=ROOT, capture_output=True, text=True, check=True)
        world_skin, generated_skin, world_model = result.stdout.split("\t")
        self.assertEqual(self.asset["model_skin"], "0", "canonical Bladeform body uses material style zero")
        self.assertEqual(world_skin, self.asset["model_skin"])
        self.assertEqual(generated_skin, world_skin)
        self.assertEqual(self.properties["monster_portrait_body"]["skin"], world_skin)
        self.assertEqual(self.properties["monster_portrait_body"]["model"], world_model)
        self.assertEqual(self.asset["primary_model"], world_model)
        self.assertFalse(self.asset["material_group"], "an extra material group would override the matched skin")

    def test_complete_world_component_structure_is_preserved(self):
        parts = [row for row in csv_rows("asset_components.csv")
                 if row["asset_id"] == ASSET and row["enabled"] == "1"]
        self.assertEqual({part["component_id"] for part in parts}, {"arms", "back", "head", "legs", "weapon"})
        self.assertEqual(self.scene["components"], len(parts))
        for part in parts:
            props = self.properties["monster_part_" + part["component_id"]]
            self.assertEqual(props["model"], part["model_path"])
            self.assertEqual(props["skin"], part["material_group"] or part["model_skin"] or "0")
            self.assertEqual(props["parentname"], "monster_part_" + part["parent_component_id"]
                             if part["parent_component_id"] else "monster_portrait_body")
            self.assertEqual(props["parentAttachmentName"], "!bonemerge" if part["attach_mode"] == "bone_merge"
                             else part["attachment_point"])
        self.assertEqual(self.properties["monster_portrait_body"]["StartingAnim"], "portrait_red")
        self.assertEqual(self.properties["monster_part_head"].get("bodygroups", ""), "")

    def test_raised_camera_changes_viewpoint_without_changing_pose(self):
        camera = self.properties["monster_portrait_camera"]
        origin = tuple(map(float, camera["origin"].split()))
        self.assertEqual(origin, (321.856619, 12.880622, 257.916392))
        self.assertEqual(tuple(map(float, camera["angles"].split())), (25.0, 185.0, 0.0))
        self.assertEqual(float(camera["FOV"]), 14.0)
        pitch, yaw = map(math.radians, (25, 185))
        forward = (math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch))
        for position, direction, focus in zip(origin, forward, (5.855965, -14.765853, 110)):
            self.assertAlmostEqual(position + direction * 350, focus, places=5)
        self.assertEqual(self.properties["monster_portrait_body"]["origin"], "0 0 0")
        self.assertEqual(self.properties["monster_portrait_body"]["angles"], "0 0 0")


if __name__ == "__main__":
    unittest.main()
