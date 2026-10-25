"""Read factual Warcraft III unit data; never execute a map or change game data.

Only standard named MPQ members are read, through the shared bounded reader.
An optimized map can put its custom units directly in SLK: the .w3u object
count is therefore not the unit count. Sparse SLK cells stay missing; they do
not inherit values from the preceding unit. Custom .w3u objects inherit only
from their explicitly recorded parent, before applying their own patches.
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import importlib.util
import json
import math
import re
import struct
from collections import Counter
from pathlib import Path

SCHEMA = "war3_units_base_v1"
MAX_BYTES = 32 * 1024 * 1024
SLK_MEMBERS = {
    "data": r"Units\UnitData.slk",
    "balance": r"Units\UnitBalance.slk",
    "weapons": r"Units\UnitWeapons.slk",
    "ui": r"Units\UnitUI.slk",
    "abilities": r"Units\UnitAbilities.slk",
}
PROFILE_MEMBERS = [r"Units\UnitStrings.txt", r"Units\UnitSkin.txt"] + [
    f"Units\\{race}UnitStrings.txt"
    for race in ("Human", "Orc", "Undead", "NightElf", "Neutral", "Campaign")
]
MEMBERS = list(SLK_MEMBERS.values()) + PROFILE_MEMBERS + [
    r"Units\UnitMetaData.slk", "war3map.w3u", "war3map.wts", "war3map.j",
    r"scripts\war3map.j", "war3mapUnits.doo",
]
PROFILE_FIELDS = {"Name", "EditorName", "EditorSuffix", "Propernames", "Art"}
FIELDS = {
    "name": ("profile", "Name"), "editor_name": ("profile", "EditorName"),
    "editor_suffix": ("profile", "EditorSuffix"), "proper_names": ("profile", "Propernames"),
    "icon": ("profile", "Art"), "race": ("data", "race"),
    "movement_type": ("data", "movetp"), "hp": ("balance", "HP"),
    "hp_regen": ("balance", "regenHP"), "armor": ("balance", "def"),
    "armor_per_upgrade": ("balance", "defUp"), "armor_type": ("balance", "defType"),
    "movement_speed": ("balance", "spd"), "collision_size": ("balance", "collision"),
    "level": ("balance", "level"), "is_building": ("balance", "isbldg"),
    "unit_type": ("balance", "type"), "upgrade_ids": ("balance", "upgrades"),
    "strength": ("balance", "STR"), "agility": ("balance", "AGI"),
    "intelligence": ("balance", "INT"), "strength_growth": ("balance", "STRplus"),
    "agility_growth": ("balance", "AGIplus"), "intelligence_growth": ("balance", "INTplus"),
    "primary_attribute": ("balance", "Primary"), "model": ("ui", "file"),
    "model_scale": ("ui", "modelScale"), "ability_ids": ("abilities", "abilList"),
    "hero_ability_ids": ("abilities", "heroAbilList"),
    "attack_enabled_mask": ("weapons", "weapsOn"),
    "acquisition_range": ("weapons", "acquire"),
}
for _attack in (1, 2):
    for _name, _field in {
        "base": "dmgplus", "dice": "dice", "sides": "sides",
        "interval": "cool", "range": "rangeN", "type": "atkType",
        "weapon_type": "weapTp", "damage_point": "dmgpt", "backswing": "backSw",
        "upgrade_bonus": "dmgUp", "declared_min": "mindmg", "declared_max": "maxdmg",
    }.items():
        FIELDS[f"attack{_attack}_{_name}"] = ("weapons", f"{_field}{_attack}")

# These standard object fields cover the requested unit properties. Other
# fields are reported, never guessed. Metadata inside a map can extend this.
OBJECT_FIELDS = {
    "unam": ("profile", "Name"), "unsf": ("profile", "EditorSuffix"),
    "upro": ("profile", "Propernames"), "uico": ("profile", "Art"),
    "umdl": ("ui", "file"), "usca": ("ui", "modelScale"),
    "uhpm": ("balance", "HP"), "uhpr": ("balance", "regenHP"),
    "udef": ("balance", "def"), "udup": ("balance", "defUp"),
    "udty": ("balance", "defType"), "umvs": ("balance", "spd"),
    "umvt": ("data", "movetp"), "ucol": ("balance", "collision"),
    "ulev": ("balance", "level"), "ubdg": ("balance", "isbldg"),
    "utyp": ("balance", "type"), "upgr": ("balance", "upgrades"),
    "uabi": ("abilities", "abilList"), "uhab": ("abilities", "heroAbilList"),
    "uaen": ("weapons", "weapsOn"), "uacq": ("weapons", "acquire"),
}
for _attack in (1, 2):
    for _suffix, _field in {"b": "dmgplus", "d": "dice", "s": "sides",
                           "c": "cool", "r": "rangeN", "t": "atkType", "w": "weapTp"}.items():
        OBJECT_FIELDS[f"ua{_attack}{_suffix}"] = ("weapons", f"{_field}{_attack}")


class ParseError(ValueError):
    pass


def digest(blob):
    return hashlib.sha256(blob).hexdigest()


def decode_text(blob):
    for encoding in ("utf-8-sig", "gb18030", "cp1252"):
        try:
            return blob.decode(encoding), encoding
        except UnicodeError:
            pass
    raise ParseError("text does not decode with the supported encodings")


def split_sylk(line):
    """Split record fields without splitting a quoted semicolon."""
    fields, token, quoted, index = [], [], False, 0
    while index < len(line):
        char = line[index]
        if char == '"':
            token.append(char)
            if quoted and index + 1 < len(line) and line[index + 1] == '"':
                token.append('"'); index += 1
            else:
                quoted = not quoted
        elif char == ";" and not quoted:
            fields.append("".join(token)); token = []
        else:
            token.append(char)
        index += 1
    if quoted:
        raise ParseError("unterminated quoted SYLK cell")
    return fields + ["".join(token)]


def cell_value(token):
    if token.startswith('"'):
        if not token.endswith('"'):
            raise ParseError("unterminated string cell")
        return token[1:-1].replace('""', '"')
    try:
        value = int(token, 10)
    except ValueError:
        try:
            value = float(token)
        except ValueError:
            return token
    if isinstance(value, float) and not math.isfinite(value):
        raise ParseError("non-finite numeric cell")
    return value


def parse_slk(blob, member):
    text, encoding = decode_text(blob)
    lines = text.splitlines()
    if not lines or not lines[0].startswith("ID;"):
        raise ParseError(f"{member}: missing SYLK signature")
    cells, locations, x, y = {}, {}, 1, 1
    for line_number, line in enumerate(lines, 1):
        parts = split_sylk(line)
        if parts[0] != "C":
            continue
        value, has_value = None, False
        for part in parts[1:]:
            if part.startswith("X") and part[1:].isdigit():
                x = int(part[1:])
            elif part.startswith("Y") and part[1:].isdigit():
                y = int(part[1:])
            elif part.startswith("K"):
                value, has_value = cell_value(part[1:]), True
        if x < 1 or y < 1 or x > 4096 or y > 200_000:
            raise ParseError(f"{member}:{line_number}: cell coordinate out of bounds")
        if has_value:
            if (y, x) in locations:
                raise ParseError(f"{member}:{line_number}: duplicate cell {x},{y}")
            cells.setdefault(y, {})[x] = value
            locations[y, x] = line_number
    headers = cells.pop(1, {})
    if not headers or 1 not in headers:
        raise ParseError(f"{member}: no first-row unit-ID header")
    if len(set(headers.values())) != len(headers):
        raise ParseError(f"{member}: duplicate headers")
    rows = {}
    for row_number, values in sorted(cells.items()):
        raw_id = values.get(1)
        if not isinstance(raw_id, str) or len(raw_id) != 4:
            raise ParseError(f"{member}: row {row_number} lacks a four-character ID")
        if raw_id in rows:
            raise ParseError(f"{member}: duplicate unit {raw_id}")
        row = {}
        for column, value in values.items():
            field = headers.get(column)
            if field is None:
                raise ParseError(f"{member}: row {row_number} has an unnamed column {column}")
            row[field] = {"value": value, "source": {"file": member, "row": row_number,
                "line": locations[row_number, column], "column": column, "field": field}}
        rows[raw_id] = row
    return rows, {"encoding": encoding, "rows": len(rows), "headers": list(headers.values())}


def parse_profiles(blob, member):
    text, encoding = decode_text(blob)
    rows, raw_id = {}, None
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            raw_id = stripped[1:-1]
            if len(raw_id) != 4:
                raw_id = None
            elif raw_id in rows:
                raise ParseError(f"{member}:{line_number}: duplicate section {raw_id}")
            else:
                rows[raw_id] = {}
        elif raw_id and "=" in line and not stripped.startswith("//"):
            key, value = line.split("=", 1)
            key = key.strip()
            if key not in PROFILE_FIELDS:
                continue  # Deliberately do not export descriptions or tooltips.
            if key in rows[raw_id]:
                raise ParseError(f"{member}:{line_number}: duplicate {raw_id}.{key}")
            value = value.strip()
            if len(value) > 4096:
                raise ParseError(f"{member}:{line_number}: name/model field exceeds the text limit")
            rows[raw_id][key] = {"value": value, "source": {
                "file": member, "line": line_number, "field": key}}
    return rows, {"encoding": encoding, "sections": len(rows)}


def parse_wts(blob):
    text, _ = decode_text(blob)
    return {int(match[1]): match[2].strip() for match in re.finditer(
        r"(?m)^STRING\s+(\d+)\s*\r?\n\{\s*\r?\n(.*?)\r?\n\}", text, re.S)}


class BinaryReader:
    def __init__(self, blob):
        self.blob, self.position = blob, 0

    def take(self, count):
        if count < 0 or self.position + count > len(self.blob):
            raise ParseError(f"truncated .w3u at byte {self.position}")
        offset = self.position
        self.position += count
        return self.blob[offset:self.position]

    def integer(self):
        return struct.unpack("<i", self.take(4))[0]

    def fourcc(self):
        value = self.take(4)
        return None if value == b"\0\0\0\0" else value.decode("latin1")

    def string(self):
        end = self.blob.find(b"\0", self.position)
        if end < 0 or end - self.position > 1024 * 1024:
            raise ParseError(f"unterminated or oversized .w3u string at byte {self.position}")
        blob = self.take(end - self.position)
        self.take(1)
        return decode_text(blob)[0]


def parse_w3u(blob):
    reader = BinaryReader(blob)
    version = reader.integer()
    if version not in (1, 2):
        raise ParseError(f"unsupported .w3u version {version}; no layout guessing")
    objects = []
    for table in ("original", "custom"):
        count = reader.integer()
        if not 0 <= count <= 100_000:
            raise ParseError(".w3u object count is out of bounds")
        for object_index in range(count):
            offset = reader.position
            old_id, new_id = reader.fourcc(), reader.fourcc()
            if old_id is None or (table == "custom" and new_id is None):
                raise ParseError(".w3u object lacks a parent or custom ID")
            modification_count = reader.integer()
            if not 0 <= modification_count <= 10_000:
                raise ParseError(".w3u modification count is out of bounds")
            modifications = []
            for modification_index in range(modification_count):
                mod_offset = reader.position
                field, kind = reader.fourcc(), reader.integer()
                if kind == 0:
                    value = reader.integer()
                elif kind in (1, 2):
                    value = struct.unpack("<f", reader.take(4))[0]
                    if not math.isfinite(value):
                        raise ParseError("non-finite .w3u numeric value")
                elif kind == 3:
                    value = reader.string()
                else:
                    raise ParseError(f"unknown .w3u value type {kind}")
                end_id = reader.fourcc()
                if end_id not in (None, old_id, new_id):
                    raise ParseError(f"unexpected .w3u modification end ID {end_id!r}")
                modifications.append({"field_id": field, "type": kind, "value": value,
                    "offset": mod_offset, "modification_index": modification_index})
            objects.append({"table": table, "object_index": object_index, "offset": offset,
                "old_id": old_id, "new_id": new_id, "modifications": modifications})
    if reader.position != len(blob):
        raise ParseError(f".w3u leaves {len(blob)-reader.position} unparsed bytes")
    return objects, {"version": version, "bytes_parsed": reader.position,
        "original_objects": sum(obj["table"] == "original" for obj in objects),
        "custom_objects": sum(obj["table"] == "custom" for obj in objects)}


def strip_jass_comments(text):
    """Retain line numbers and strings while removing JASS line comments."""
    result, quoted, escaped, index = [], False, False, 0
    while index < len(text):
        char = text[index]
        if not quoted and text[index:index + 2] == "//":
            end = text.find("\n", index)
            if end < 0:
                result.extend(" " * (len(text) - index)); break
            result.extend(" " * (end - index)); index = end; continue
        result.append(char)
        if char == '"' and not escaped:
            quoted = not quoted
        escaped = char == "\\" and not escaped if quoted else False
        index += 1
    return "".join(result)


def call_arguments(text, open_paren):
    depth, quoted, escaped, start = 1, False, False, open_paren + 1
    result = []
    for index in range(start, min(len(text), start + 32_768)):
        char = text[index]
        if char == '"' and not escaped:
            quoted = not quoted
        if not quoted:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return result + [text[start:index].strip()]
            elif char == "," and depth == 1:
                result.append(text[start:index].strip()); start = index + 1
        escaped = char == "\\" and not escaped if quoted else False
    raise ParseError("unterminated or oversized JASS call")


def mask_jass_strings(text):
    result, quoted, escaped = [], False, False
    for char in text:
        was_quoted = quoted
        if char == '"' and not escaped:
            quoted = not quoted
        result.append(" " if (was_quoted or quoted) and char != "\n" else char)
        escaped = char == "\\" and not escaped if quoted else False
    return "".join(result)


def literal_raw_id(expression):
    expression = expression.strip()
    if re.fullmatch(r"'(?:[^'\\]|\\.){4}'", expression):
        return expression[1:-1]
    match = re.fullmatch(r'(?:FourCC|UnitId)\s*\(\s*"([^"\r\n]{4})"\s*\)', expression)
    if match:
        return match[1]
    if re.fullmatch(r"(?:0[xX][0-9a-fA-F]{1,8}|\d{1,10})", expression):
        value = int(expression, 16 if expression.lower().startswith("0x") else 10)
        if 0 <= value <= 0xFFFFFFFF:
            raw = value.to_bytes(4, "big")
            if all(32 <= char <= 126 for char in raw):
                return raw.decode("ascii")
    return None


def extract_creation_evidence(blob, member="war3map.j"):
    text, encoding = decode_text(blob)
    text = strip_jass_comments(text)
    searchable = mask_jass_strings(text)
    functions = list(re.finditer(r"(?m)^\s*function\s+(\w+)\s+takes\b", searchable))
    function_index, function_name = 0, None
    evidence, unresolved = {}, []
    calls = list(re.finditer(r"\b(CreateUnit|CreateUnitAtLoc|BlzCreateUnitWithSkin)\s*\(", searchable))
    line, previous_offset = 1, 0
    for match in calls:
        while function_index < len(functions) and functions[function_index].start() < match.start():
            function_name = functions[function_index][1]; function_index += 1
        line += text.count("\n", previous_offset, match.start()); previous_offset = match.start()
        args = call_arguments(text, match.end() - 1)
        if len(args) < 2:
            raise ParseError(f"{member}:{line}: unit creation call has fewer than two arguments")
        record = {"file": member, "line": line, "function": function_name,
            "call": match[1], "owner_expression": args[0][:256], "type_expression": args[1][:256]}
        raw_id = literal_raw_id(args[1])
        if raw_id is None:
            unresolved.append(record)
        else:
            evidence.setdefault(raw_id, []).append(record)
    return evidence, unresolved, {"encoding": encoding, "creation_calls": len(calls),
        "literal_calls": sum(map(len, evidence.values())), "dynamic_type_calls": len(unresolved)}


def metadata_field_map(rows):
    result = dict(OBJECT_FIELDS)
    table_names = {"unitdata": "data", "unitbalance": "balance", "unitweapons": "weapons",
                   "unitui": "ui", "unitabilities": "abilities"}
    for field_id, row in rows.items():
        slk = str(row.get("slk", {}).get("value", "")).lower().removesuffix(".slk")
        field = row.get("field", {}).get("value")
        if slk in table_names and isinstance(field, str):
            result[field_id] = table_names[slk], field
    return result


def apply_objects(units, objects, field_map):
    unknowns, patches = [], []
    for obj in objects:
        raw_id = obj["new_id"] if obj["table"] == "custom" else obj["old_id"]
        parent = obj["old_id"]
        if obj["table"] == "custom":
            if parent not in units:
                raise ParseError(f"custom unit {raw_id} has an unavailable parent {parent}")
            if raw_id in units:
                # Optimized SLKs can already contain the child. Their explicit
                # cells take precedence over the parent's inherited cells.
                explicit = units[raw_id]
            else:
                explicit = {"tables": {}, "object_parent_id": None, "source_rows": {}}
            inherited = copy.deepcopy(units[parent])
            for row in inherited["tables"].values():
                for cell in row.values():
                    cell["source"]["inherited_from"] = parent
            for table, row in explicit["tables"].items():
                inherited["tables"].setdefault(table, {}).update(row)
            inherited["source_rows"].update(explicit["source_rows"])
            inherited["object_parent_id"] = parent
            units[raw_id] = inherited
        elif raw_id not in units:
            units[raw_id] = {"tables": {}, "object_parent_id": None, "source_rows": {}}
            unknowns.append({"kind": "original_patch_without_slk_row", "raw_id": raw_id})
        for mod in obj["modifications"]:
            source = {"file": "war3map.w3u", "offset": mod["offset"], "field_id": mod["field_id"],
                "table": obj["table"], "object_index": obj["object_index"],
                "modification_index": mod["modification_index"]}
            mapped = field_map.get(mod["field_id"])
            patch = {"raw_id": raw_id, "field_id": mod["field_id"], "type": mod["type"], "source": source}
            if mapped and (not isinstance(mod["value"], str) or len(mod["value"]) <= 4096):
                table, field = mapped
                units[raw_id]["tables"].setdefault(table, {})[field] = {"value": mod["value"], "source": source}
                patch.update(value=mod["value"], mapped_table=table, mapped_field=field)
            else:
                if isinstance(mod["value"], str):
                    patch.update(value_omitted=True, value_characters=len(mod["value"]),
                        value_sha256=digest(mod["value"].encode("utf-8")))
                else:
                    patch["value"] = mod["value"]
                unknowns.append({"kind": "unmapped_object_field", **patch})
            patches.append(patch)
    return patches, unknowns


def list_value(value):
    if value in (None, "", "_", "-"):
        return []
    return [item.strip() for item in str(value).split(",") if item.strip() and item.strip() not in ("_", "-")]


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def canonical_unit(raw_id, unit, creation_evidence, wts):
    row = {"raw_id": raw_id, "raw_id_hex": f"0x{int.from_bytes(raw_id.encode('latin1'), 'big'):08X}",
        "object_parent_id": unit["object_parent_id"], "source_rows": unit["source_rows"],
        "provenance": {}, "missing_fields": []}
    for canonical, (table, field) in FIELDS.items():
        cell = unit["tables"].get(table, {}).get(field)
        if cell is None:
            row[canonical] = None
            row["missing_fields"].append(canonical)
        else:
            row[canonical] = cell["value"]
            row["provenance"][canonical] = copy.deepcopy(cell["source"])
    if row["name"] is None:
        cell = unit["tables"].get("ui", {}).get("name")
        if cell is not None:
            row["name"] = cell["value"]
            row["provenance"]["name"] = {**cell["source"], "fallback": "editor_name_not_localized_name"}
            row["missing_fields"].remove("name")
    if isinstance(row["name"], str):
        match = re.fullmatch(r"TRIGSTR_(\d+)", row["name"])
        if match and int(match[1]) in wts:
            resolved = wts[int(match[1])]
            if len(resolved) > 4096:
                raise ParseError(f"unit {raw_id} has an oversized localized name")
            row["name"] = resolved
            row["provenance"]["name"]["resolved_through"] = "war3map.wts"
    row["name_plain"] = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(row["name"] or "")).replace("|n", " ")
    for field in ("ability_ids", "hero_ability_ids", "upgrade_ids"):
        if row[field] is not None:
            row[field] = list_value(row[field])
    for attack in (1, 2):
        base, dice, sides = (row[f"attack{attack}_{field}"] for field in ("base", "dice", "sides"))
        for boundary in ("min", "max"):
            field = f"attack{attack}_{boundary}"
            if all(is_number(value) for value in (base, dice, sides)):
                row[field] = base + dice * (1 if boundary == "min" else sides)
                row["provenance"][field] = {"calculation": "base+dice" if boundary == "min" else "base+dice*sides",
                    "component_fields": [f"attack{attack}_{name}" for name in ("base", "dice", "sides")],
                    "scope": "base weapon only; excludes hero attributes, upgrades, abilities, and runtime setters"}
            else:
                row[field] = None
                row["missing_fields"].append(field)
    row["creation_evidence"] = creation_evidence.get(raw_id, [])
    neutral = [record for record in row["creation_evidence"] if re.fullmatch(
        r"Player\s*\(\s*(?:12|PLAYER_NEUTRAL_AGGRESSIVE)\s*\)", record["owner_expression"])]
    name_token = re.search(r"BOSS|boss|首领|怪物|精英|练功|练级", row["name_plain"])
    row["possible_monster"] = bool(neutral or name_token)
    row["classification_evidence"] = (["literal_CreateUnit_owner_Player12"] if neutral else []) + (
        [f"name_token:{name_token[0]}"] if name_token else [])
    row["classification_note"] = "candidate only; ownership, wave/category membership and runtime strength need JASS analysis"
    row["computed_note"] = ("attack1/2_base are dmgplus damage-base components, not complete displayed attacks; "
        "min=base+dice and max=base+dice*sides. These are weapon-object values before JASS setters "
        "(including damage-base writes through ConvertUnitState(0x12)), hero attributes, abilities and upgrades.")
    return row


def build_units(blobs):
    units, parsing, unknowns = {}, {}, []
    for table, member in SLK_MEMBERS.items():
        if member not in blobs:
            raise ParseError(f"required member missing: {member}")
        rows, parsing[member] = parse_slk(blobs[member], member)
        for raw_id, row in rows.items():
            unit = units.setdefault(raw_id, {"tables": {}, "object_parent_id": None, "source_rows": {}})
            unit["tables"][table] = row
            first = next(iter(row.values()))["source"]
            unit["source_rows"][table] = {"file": member, "row": first["row"]}
    for member in PROFILE_MEMBERS:
        if not blobs.get(member):
            continue
        rows, parsing[member] = parse_profiles(blobs[member], member)
        for raw_id, row in rows.items():
            if raw_id not in units:
                unknowns.append({"kind": "name_section_without_unit_row", "raw_id": raw_id, "file": member})
                continue
            target = units[raw_id]["tables"].setdefault("profile", {})
            for field, cell in row.items():
                if field in target and target[field]["value"] != cell["value"]:
                    unknowns.append({"kind": "profile_override", "raw_id": raw_id, "field": field,
                        "previous_source": target[field]["source"], "selected_source": cell["source"]})
                target[field] = cell
    field_map = dict(OBJECT_FIELDS)
    metadata = r"Units\UnitMetaData.slk"
    if blobs.get(metadata):
        rows, parsing[metadata] = parse_slk(blobs[metadata], metadata)
        field_map = metadata_field_map(rows)
    patches = []
    if blobs.get("war3map.w3u"):
        objects, parsing["war3map.w3u"] = parse_w3u(blobs["war3map.w3u"])
        patches, object_unknowns = apply_objects(units, objects, field_map)
        unknowns.extend(object_unknowns)
    creation_evidence, unresolved = {}, []
    script = next((member for member in ("war3map.j", r"scripts\war3map.j") if blobs.get(member)), None)
    if script:
        creation_evidence, unresolved, parsing[script] = extract_creation_evidence(blobs[script], script)
        for raw_id, records in creation_evidence.items():
            if raw_id not in units:
                unknowns.append({"kind": "literal_creation_without_unit_row", "raw_id": raw_id, "references": records})
    wts = parse_wts(blobs["war3map.wts"]) if blobs.get("war3map.wts") else {}
    rows = [canonical_unit(raw_id, unit, creation_evidence, wts) for raw_id, unit in sorted(units.items())]
    manifest = {"schema": SCHEMA, "unit_count": len(rows), "possible_monster_count": sum(row["possible_monster"] for row in rows),
        "parsing": parsing, "w3u_patch_count": len(patches), "dynamic_creation_calls": len(unresolved),
        "missing_field_counts": dict(sorted(Counter(field for row in rows for field in row["missing_fields"]).items())),
        "placed_units_member_present": bool(blobs.get("war3mapUnits.doo")),
        "notes": ["Sparse cells are not filled from preceding rows or silently replaced by zero.",
            "Only an explicit .w3u custom object supplies a parent; optimized SLK IDs are not guessed to inherit.",
            "Weapon boundaries are base+dice and base+dice*sides, before hero stats/upgrades/runtime setters.",
            "possible_monster is a candidate label, not a proven wave/challenge assignment.",
            "No map script, DLL, model or native binary is executed; game configs are never written."]}
    unknown_report = {"schema": SCHEMA, "issues": unknowns, "dynamic_creation_calls": unresolved,
        "placed_units": "not parsed; use the separate placed-unit extractor" if blobs.get("war3mapUnits.doo")
            else "war3mapUnits.doo absent; explicit placed creations may still occur in war3map.j"}
    return {"schema": SCHEMA, "units": rows}, manifest, unknown_report, patches


def load_reader(path):
    if path is None:
        from war3_extract import mpq
        return mpq
    spec = importlib.util.spec_from_file_location("war3_unit_mpq_reader", path)
    if spec is None or spec.loader is None:
        raise ParseError("cannot load the explicitly selected MPQ reader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_members(source, extracted_roots, reader_path=None, limit=MAX_BYTES):
    if not 0 < limit <= MAX_BYTES:
        raise ParseError("extraction budget must be between one byte and 32 MiB")
    blobs, manifest, consumed = {}, [], 0
    source = Path(source) if source else None
    stream = source.open("rb") if source else None
    try:
        archive = load_reader(reader_path).MPQ(stream, source.stat().st_size) if stream else None
        for member in MEMBERS:
            relative = Path(*member.split("\\"))
            candidates = [Path(root) / relative for root in extracted_roots]
            existing = [path for path in candidates if path.is_file()]
            row = {"member": member}
            if existing:
                sizes = [path.stat().st_size for path in existing]
                if any(size > limit - consumed for size in sizes):
                    raise ParseError(f"input member exceeds remaining extraction budget: {member}")
                copies = [path.read_bytes() for path in existing]
                if any(blob != copies[0] for blob in copies[1:]):
                    raise ParseError(f"conflicting extracted copies of {member}")
                blob = copies[0]
                row["input"] = str(existing[0].resolve())
            elif archive:
                matches = archive.lookup(member)
                if not matches:
                    manifest.append({**row, "present": False}); continue
                selected = matches[0]
                block = archive.blocks[selected["block_index"]]
                try:
                    blob = archive.extract(member, block, limit - consumed)
                except Exception as error:
                    manifest.append({**row, "present": True, "extraction_error": str(error)}); continue
                row["mpq_record"] = selected
            else:
                manifest.append({**row, "present": False}); continue
            consumed += len(blob)
            if consumed > limit:
                raise ParseError("aggregate member data exceeds the extraction budget")
            blobs[member] = blob
            manifest.append({**row, "present": True, "bytes": len(blob), "sha256": digest(blob)})
    finally:
        if stream:
            stream.close()
    return blobs, {"source": str(source.resolve()) if source else None,
        "source_sha256": load_reader(reader_path).sha256_file(source) if source else None,
        "members": manifest, "consumed_bytes": consumed, "limit_bytes": limit}


def write_outputs(output, data, manifest, unknowns, patches):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    for filename, document in (("units_base.json", data), ("manifest.json", manifest),
                               ("unknowns.json", unknowns), ("object_patches.json", patches)):
        (output / filename).write_text(json.dumps(document, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    rows = data["units"]
    columns = ["raw_id", "raw_id_hex", "name", "name_plain", "object_parent_id"] + list(FIELDS)
    columns = list(dict.fromkeys(columns)) + ["attack1_min", "attack1_max", "attack2_min", "attack2_max",
        "possible_monster", "classification_evidence", "source_rows", "computed_note"]
    with (output / "units_base.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: json.dumps(value, ensure_ascii=False, separators=(",", ":"))
                if isinstance(value, (dict, list)) else value for key, value in row.items() if key in columns})
    return {name: digest((output / name).read_bytes()) for name in (
        "units_base.json", "units_base.csv", "manifest.json", "unknowns.json", "object_patches.json")}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="read-only original .w3x/.w3m archive")
    parser.add_argument("--mpq-reader", type=Path, help="optional compatible standard MPQ reader")
    parser.add_argument("--extracted-root", type=Path, action="append", default=[],
        help="reuse an extracted member tree; repeat for additional non-conflicting trees")
    parser.add_argument("--output", type=Path, required=True, help="analysis output directory, never a game config directory")
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    args = parser.parse_args(argv)
    if args.source is None and not args.extracted_root:
        parser.error("provide --source and/or --extracted-root")
    blobs, extraction = read_members(args.source, args.extracted_root, args.mpq_reader, args.max_bytes)
    data, manifest, unknowns, patches = build_units(blobs)
    manifest["extraction"] = extraction
    hashes = write_outputs(args.output, data, manifest, unknowns, patches)
    print(json.dumps({"schema": SCHEMA, "units": manifest["unit_count"],
        "possible_monsters": manifest["possible_monster_count"], "object_patches": len(patches),
        "unknown_issues": len(unknowns["issues"]), "dynamic_creations": len(unknowns["dynamic_creation_calls"]),
        "output": str(args.output.resolve()), "sha256": hashes}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
