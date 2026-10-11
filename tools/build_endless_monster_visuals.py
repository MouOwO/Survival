"""Import the approved endless appearances once, then build from authoritative CSVs.

Run --import-plan to materialize the design as editable runtime CSVs. Ordinary
runs and --check use only those CSVs, never the design document or audit output.
All exported values are visual; combat and navigation configuration is untouched.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
import re
import struct
import subprocess
import tempfile
from pathlib import Path

import build_configs
from build_wave_monster_cosmetics import Vpk

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/csv/存档系统"
GENERATED = ROOT / "scripts/vscripts/config/generated"
OUTPUT = ROOT / "output/endless_monster_runtime_20261011"
DEFAULT_PLAN = ROOT / "docs/design/endless_monster_visual_plan_20261009.json"
SCHEMAS = {
    "archive_endless_visuals": [
        ("visual_id", "string"), ("cycle_slot", "number"),
        ("outfit_round", "number"), ("display_name", "string"),
        ("outfit_name", "string"), ("model_path", "string"),
        ("base_scale", "number"), ("model_skin", "number"),
        ("activity_modifiers", "list"),
        ("bounds_min_x", "number"), ("bounds_min_y", "number"),
        ("bounds_min_z", "number"), ("bounds_max_x", "number"),
        ("bounds_max_y", "number"), ("bounds_max_z", "number"),
        ("enabled", "boolean"),
    ],
    "archive_endless_visual_components": [
        ("component_id", "string"), ("visual_id", "string"),
        ("model_path", "string"), ("model_skin", "number"),
        ("material_group", "string"), ("attach_mode", "string"),
        ("enabled", "boolean"),
    ],
    "archive_endless_visual_ornaments": [
        ("ornament_id", "string"), ("visual_id", "string"),
        ("model_path", "string"), ("attachment", "string"),
        ("local_x", "number"), ("local_y", "number"),
        ("local_z", "number"), ("root_x", "number"),
        ("root_y", "number"), ("root_z", "number"),
        ("angle_pitch", "number"), ("angle_yaw", "number"),
        ("angle_roll", "number"), ("model_scale", "number"),
        ("enabled", "boolean"),
    ],
}
NUMBERS = r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"


def numbers(text: str) -> list[float]:
    return [float(n) for n in re.findall(NUMBERS, text)]


def bracket(text: str, start: int, opening: str = "[", closing: str = "]") -> str:
    """Extract a nested resourceinfo table, ignoring brackets in quoted names."""
    depth, quoted, escaped = 0, False, False
    for index in range(start, len(text)):
        char = text[index]
        if quoted:
            if char == '"' and not escaped:
                quoted = False
            escaped = char == "\\" and not escaped
            continue
        if char == '"':
            quoted = True
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError("Unclosed resourceinfo table")


def table_blocks(text: str) -> list[str]:
    result, index = [], 0
    while (index := text.find("{", index)) >= 0:
        block = bracket(text, index, "{", "}")
        result.append(block)
        index += len(block)
    return result


def array_field(text: str, name: str) -> str:
    match = re.search(r"\b" + re.escape(name) + r"\s*=\s*\[", text)
    return bracket(text, text.index("[", match.start())) if match else ""


def transpose(matrix):
    return [list(column) for column in zip(*matrix)]


def mat_vec(matrix, vector):
    return [sum(a * b for a, b in zip(row, vector)) for row in matrix]


def mat_mul(left, right):
    return [[sum(left[i][k] * right[k][j] for k in range(3))
             for j in range(3)] for i in range(3)]


def quaternion_matrix(q):
    x, y, z, w = q
    return [[1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
            [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
            [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)]]


def matrix_angles(matrix):
    pitch = math.asin(max(-1.0, min(1.0, -matrix[2][0])))
    if abs(math.cos(pitch)) > 0.00001:
        yaw = math.atan2(matrix[1][0], matrix[0][0])
        roll = math.atan2(matrix[2][1], matrix[2][2])
    else:
        yaw = math.atan2(-matrix[0][1], matrix[1][1])
        roll = 0.0
    return [math.degrees(a) for a in (pitch, yaw, roll)]


class NativeResources:
    """Read installed resources; native files extracted only beneath OUTPUT."""
    def __init__(self):
        self.packs = [Vpk(ROOT / "../../dota/pak01_dir.vpk"),
                      Vpk(ROOT / "../../core/pak01_dir.vpk")]
        self.records = {}
        self.geometry = {}
        self.resourceinfo = ROOT / "../../bin/win64/resourceinfo.exe"

    def locate(self, name):
        compiled = name if name.endswith("_c") else name + "_c"
        for pack in self.packs:
            if compiled in pack.entries:
                return pack, compiled
        raise ValueError("Missing installed native resource: " + name)

    def verify(self, name):
        if name in self.records:
            return
        pack, compiled = self.locate(name)
        self.records[name] = {"path": name, "pack": str(pack.path),
                              "compiled": compiled}
        if not re.search(r"\.(vmdl|vmesh|vmat|vagrp|vanim|vseq|vphys|vsnap|vpcf)$", name):
            return
        raw = pack.read(compiled)
        table = 8 + struct.unpack_from("<I", raw, 8)[0]
        for index in range(struct.unpack_from("<I", raw, 12)[0]):
            entry = table + index * 12
            if raw[entry:entry+4] != b"RERL":
                continue
            data = entry + 4 + struct.unpack_from("<I", raw, entry+4)[0]
            offset, count = struct.unpack_from("<II", raw, data)
            for row in range(count):
                pointer = data + offset + row * 16 + 8
                start = pointer + struct.unpack_from("<q", raw, pointer)[0]
                end = raw.index(b"\0", start)
                self.verify(raw[start:end].decode("utf8"))

    def model_geometry(self, name):
        if name in self.geometry:
            return self.geometry[name]
        self.verify(name)
        pack, compiled = self.locate(name)
        raw = pack.read(compiled)
        native = OUTPUT / "native" / compiled
        native.parent.mkdir(parents=True, exist_ok=True)
        native.write_bytes(raw)
        dump = subprocess.run([str(self.resourceinfo.resolve()), "-i", str(native),
                               "-b", "MDAT"], check=True, capture_output=True,
                              encoding="utf8").stdout
        native.with_suffix(native.suffix + ".MDAT.txt").write_text(dump, encoding="utf8")
        mins, maxs, attachments = [], [], {}
        for scene in re.finditer(r"m_sceneObjects\s*=([\s\S]*?)m_constraints", dump):
            mins += [numbers(m) for m in re.findall(r"m_vMinBounds\s*=\s*\[([^\]]+)\]", scene[1])]
            maxs += [numbers(m) for m in re.findall(r"m_vMaxBounds\s*=\s*\[([^\]]+)\]", scene[1])]
        bones = {}
        for skeleton in re.finditer(r"m_bones\s*=\s*\[", dump):
            part = bracket(dump, dump.index("[", skeleton.start()))
            for block in table_blocks(part):
                bone = re.search(r'm_boneName\s*=\s*"([^"]+)"', block)
                inverse = numbers(array_field(block, "m_invBindPose"))
                if bone and len(inverse) == 12:
                    rot_inv = [inverse[i:i+3] for i in (0, 4, 8)]
                    rotation = transpose(rot_inv)
                    position = mat_vec(rotation, [-inverse[i] for i in (3, 7, 11)])
                    bones[bone[1]] = (rotation, position)
        for match in re.finditer(r"m_attachments\s*=\s*\[", dump):
            part = bracket(dump, dump.index("[", match.start()))
            for block in table_blocks(part):
                label = re.search(r'm_name\s*=\s*"([^"]+)"', block)
                bone_names = re.findall(r'"([^"]*)"', array_field(block, "m_influenceNames"))
                offsets = numbers(array_field(block, "m_vInfluenceOffsets"))
                rotations = numbers(array_field(block, "m_vInfluenceRotations"))
                if not label or not bone_names:
                    continue
                attachments.setdefault(label[1], None)
                # Use a verified single-bone bind pose. Blended/root-transform
                # anchors retain root mounting until their transform is known.
                count = re.search(r"m_nInfluences\s*=\s*(\d+)", block)
                if not count or int(count[1]) != 1 or bone_names[0] not in bones:
                    continue
                if len(offsets) < 3 or len(rotations) < 4:
                    continue
                rotation, position = bones[bone_names[0]]
                offset = mat_vec(rotation, offsets[:3])
                anchor_rotation = mat_mul(rotation, quaternion_matrix(rotations[:4]))
                attachments[label[1]] = {
                    "position": [a+b for a, b in zip(position, offset)],
                    "rotation": anchor_rotation,
                }
        if not mins or len(mins) != len(maxs):
            raise ValueError("No scene geometry bounds for " + name)
        result = {"min": [min(b[i] for b in mins) for i in range(3)],
                  "max": [max(b[i] for b in maxs) for i in range(3)],
                  "attachments": attachments}
        self.geometry[name] = result
        return result


def number(value):
    # The existing CSV compiler accepts decimal literals, not exponent syntax.
    result = f"{float(value):.6f}".rstrip("0").rstrip(".")
    return "0" if result in ("", "-0") else result


def write_rows(name, rows):
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    schema = SCHEMAS[name]
    writer.writerow([field for field, _ in schema])
    writer.writerow(["#types:" + schema[0][1]] + [kind for _, kind in schema[1:]])
    for row in rows:
        writer.writerow([row.get(field, "") for field, _ in schema])
    SOURCE.mkdir(parents=True, exist_ok=True)
    (SOURCE / (name + ".csv")).write_text(buffer.getvalue(), encoding="utf8", newline="\n")


def ornaments_for(monster, variant, visual_id, catalog, native):
    if not variant.get("components"):
        return []
    body = native.model_geometry(monster["base_model"])
    low, high = body["min"], body["max"]
    height = high[2] - low[2]
    width = high[1] - low[1]
    center_x = (low[0] + high[0]) / 2
    center_y = (low[1] + high[1]) / 2
    fraction = float((variant.get("geometry_target") or {}).get(
        "maximum_ornament_height_fraction_of_body", 0.16))
    result = []
    for declaration in variant["components"]:
        resource_id = declaration["resource_id"]
        model = catalog[resource_id]["model_path"]
        geometry = native.model_geometry(model)
        size = [geometry["max"][i] - geometry["min"][i] for i in range(3)]
        scale = min(height * fraction / max(size[2], 0.001),
                    max(width * 0.34, height * 0.12) / max(size[0], size[1], 0.001))
        count = int(declaration.get("count", 1))
        for repeat in range(count):
            side = (-1 if repeat == 0 else 1) if count == 2 else 0
            # The bone/crystal base sits on the bounding surface, rather than
            # centering an environmental prop inside the monster's torso.
            x = center_x + ((high[0]-low[0]) * 0.23 if resource_id in
                            ("bone_point", "centered_gem") else 0)
            y = center_y + side * width * 0.18
            z = high[2] - (height * 0.08 if resource_id == "centered_gem" else 0)
            target = [x - (geometry["min"][0]+geometry["max"][0])*scale/2,
                      y - (geometry["min"][1]+geometry["max"][1])*scale/2,
                      z - geometry["min"][2]*scale]
            attachments = body["attachments"]
            head = ["attach_head", "head", "attach_attack1", "attach_attack"]
            back = ["attach_hitloc", "attach_head", "head"]
            preferences = head if resource_id in ("bone_point", "centered_gem") else back
            attachment = next((name for name in preferences
                               if attachments.get(name) is not None), "")
            local, angles = target, [0, 0, 0]
            if attachment:
                anchor = attachments[attachment]
                inverse = transpose(anchor["rotation"])
                local = mat_vec(inverse, [a-b for a, b in zip(target, anchor["position"])])
                angles = matrix_angles(inverse)
            row = {"ornament_id": visual_id + ":ornament_" + str(len(result)+1),
                   "visual_id": visual_id, "model_path": model,
                   "attachment": attachment, "model_scale": number(scale), "enabled": 1}
            for label, values in (("local", local), ("root", target)):
                row.update({label + "_" + axis: number(v) for axis, v in zip("xyz", values)})
            row.update({"angle_" + label: number(v)
                        for label, v in zip(("pitch", "yaw", "roll"), angles)})
            result.append(row)
    if len(result) > 2:
        raise ValueError("At most two custom ornaments: " + visual_id)
    return result


def import_plan(plan_path):
    plan = json.loads(plan_path.read_text(encoding="utf-8-sig"))
    native = NativeResources()
    catalog = {row["id"]: row for row in plan["ornament_catalog"]}
    exports = {name: [] for name in SCHEMAS}
    for monster in plan["monster_rows"]:
        slot = int(monster["cycle_slot"])
        for variant in monster["variants"]:
            round_ = int(variant["outfit_round"])
            visual_id = f"endless_visual_{slot:03d}_{round_}"
            manifest = variant.get("variant_manifest") or {}
            model = manifest.get("body_model") or monster["base_model"]
            native.verify(model)
            activity = [mod["modifier"] for mod in manifest.get("all_asset_modifiers", [])
                        if mod.get("type") == "activity" and mod.get("asset") == "ALL"]
            bounds = monster["resource_audit"]["bounds"]
            visual = {"visual_id": visual_id, "cycle_slot": slot, "outfit_round": round_,
                      "display_name": monster["name"], "outfit_name": variant["short_text"],
                      "model_path": model, "base_scale": number(monster["base_scale_suggestion"]),
                      "model_skin": manifest.get("model_skin", 0),
                      "activity_modifiers": "|".join(dict.fromkeys(activity)), "enabled": 1}
            for limit in ("min", "max"):
                visual.update({"bounds_" + limit + "_" + axis: number(v)
                               for axis, v in zip("xyz", bounds[limit])})
            exports["archive_endless_visuals"].append(visual)
            for index, component in enumerate(manifest.get("components", []), 1):
                native.verify(component["model_path"])
                exports["archive_endless_visual_components"].append({
                    "component_id": visual_id + ":" + str(component.get("slot", index)),
                    "visual_id": visual_id, "model_path": component["model_path"],
                    "model_skin": component.get("skin", 0),
                    "material_group": component.get("material_group", ""),
                    "attach_mode": "bone_merge", "enabled": 1})
            if not monster["native_four_outfits"]:
                exports["archive_endless_visual_ornaments"].extend(
                    ornaments_for(monster, variant, visual_id, catalog, native))
    for name, rows in exports.items():
        write_rows(name, rows)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "config_resource_audit.json").write_text(json.dumps({
        "source": str(plan_path.relative_to(ROOT)), "runtime_authority": "data/csv/存档系统",
        "records": {name: len(rows) for name, rows in exports.items()},
        "verified_resource_count": len(native.records), "missing_resources": [],
        "ambient_particle_count": 0, "live_visual_verified": False,
        "ornament_transforms": "Single-bone bind-pose inverse; unknown anchors use root surface coordinates",
        "resources": list(native.records.values()), "model_geometry": native.geometry,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


def source_rows(name):
    return [row for _, row in build_configs.csv_dict_rows(SOURCE / (name + ".csv"))]


def validate_sources():
    rows = {name: source_rows(name) for name in SCHEMAS}
    visual_rows = rows["archive_endless_visuals"]
    if len(visual_rows) != 200:
        raise ValueError("Exactly 200 visual rows required")
    visuals = {row["visual_id"]: row for row in visual_rows}
    if len(visuals) != 200:
        raise ValueError("Duplicate visual_id")
    expected = {(slot, round_) for slot in range(1, 51) for round_ in range(1, 5)}
    actual = {(int(row["cycle_slot"]), int(row["outfit_round"])) for row in visual_rows}
    if actual != expected:
        raise ValueError("Incomplete or duplicate 50 x 4 visual cycle")
    for row in visual_rows:
        if float(row["base_scale"]) <= 0:
            raise ValueError("Invalid base_scale: " + row["visual_id"])
    for name in ("archive_endless_visual_components", "archive_endless_visual_ornaments"):
        ids, key = set(), SCHEMAS[name][0][0]
        counts = {}
        for row in rows[name]:
            if row[key] in ids or row["visual_id"] not in visuals:
                raise ValueError("Duplicate component or unknown visual: " + row[key])
            ids.add(row[key])
            counts[row["visual_id"]] = counts.get(row["visual_id"], 0) + 1
            if name.endswith("ornaments") and counts[row["visual_id"]] > 2:
                raise ValueError("Too many ornaments: " + row["visual_id"])
            if name.endswith("components") and row["attach_mode"] != "bone_merge":
                raise ValueError("Native components must use bone_merge")
            if name.endswith("ornaments") and float(row["model_scale"]) <= 0:
                raise ValueError("Invalid ornament model_scale")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import-plan", action="store_true",
                        help="Replace the three runtime CSVs from the approved design")
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    parser.add_argument("--check", action="store_true",
                        help="Validate CSVs and compare generated Lua without writing")
    args = parser.parse_args()
    if args.import_plan and args.check:
        parser.error("--import-plan mutates CSVs and cannot be combined with --check")
    if args.import_plan:
        import_plan(args.plan)
    rows = validate_sources()
    GENERATED.mkdir(parents=True, exist_ok=True)
    if args.check:
        with tempfile.TemporaryDirectory(prefix="survival_endless_visuals_") as tmp:
            for name in SCHEMAS:
                temporary = Path(tmp) / (name + ".lua")
                build_configs.build(SOURCE / (name + ".csv"), temporary)
                actual = GENERATED / temporary.name
                # Git may restore generated Lua with CRLF on Windows. Only
                # normalize that line ending; all other bytes remain strict.
                if (not actual.exists()
                        or temporary.read_bytes().replace(b"\r\n", b"\n")
                        != actual.read_bytes().replace(b"\r\n", b"\n")):
                    raise ValueError("Generated Lua is stale: " + name)
    else:
        for name in SCHEMAS:
            build_configs.build(SOURCE / (name + ".csv"), GENERATED / (name + ".lua"))
    print("ENDLESS_VISUAL_CONFIG_" + ("CHECK" if args.check else "BUILD") + "_PASS "
          + json.dumps({name: len(value) for name, value in rows.items()}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
