"""Verify challenge-monster bundle resources against the local Dota VPK."""
from __future__ import annotations

import csv
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VPK = ROOT.parent.parent / "dota" / "pak01_dir.vpk"
CHALLENGE_ASSET_IDS = {
    "challenge_monster_beastmaster_legacy",
    "challenge_monster_morphling",
    "challenge_monster_ember_searing_path",
    "challenge_monster_primal_beast_svarog",
    "challenge_monster_spectre_phantom_advent",
    "challenge_monster_terrorblade_fractal_horns",
}


def csv_rows(relative_path: str) -> list[dict[str, str]]:
    raw = (ROOT / relative_path).read_bytes()
    text = None
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        raise AssertionError(f"unsupported CSV encoding: {relative_path}")
    lines = [line for line in text.splitlines() if not line.startswith("#")]
    return list(csv.DictReader(lines))


def read_cstring(handle) -> str:
    data = bytearray()
    while True:
        value = handle.read(1)
        if not value:
            raise EOFError("unexpected end of VPK tree")
        if value == b"\0":
            return data.decode("utf-8", errors="replace")
        data.extend(value)


def vpk_paths() -> set[str]:
    with VPK.open("rb") as handle:
        signature, version, tree_size = struct.unpack("<III", handle.read(12))
        assert signature == 0x55AA1234, "invalid VPK signature"
        if version == 2:
            handle.read(16)
        else:
            assert version == 1, f"unsupported VPK version: {version}"
        tree_end = handle.tell() + tree_size
        result = set()
        while handle.tell() < tree_end:
            extension = read_cstring(handle)
            if not extension:
                break
            while True:
                directory = read_cstring(handle)
                if not directory:
                    break
                while True:
                    filename = read_cstring(handle)
                    if not filename:
                        break
                    entry = struct.unpack("<IHHIIH", handle.read(18))
                    preload_bytes, terminator = entry[1], entry[5]
                    assert terminator == 0xFFFF, "invalid VPK entry terminator"
                    if preload_bytes:
                        handle.read(preload_bytes)
                    prefix = "" if directory == " " else directory + "/"
                    result.add(f"{prefix}{filename}.{extension}")
        return result


def configured_resources() -> set[str]:
    resources = set()
    sources = (
        ("data/csv/资源系统/asset_catalog.csv", "primary_model"),
        ("data/csv/资源系统/asset_components.csv", "model_path"),
        ("data/csv/资源系统/asset_effects.csv", "particle_path"),
    )
    for relative_path, field in sources:
        for row in csv_rows(relative_path):
            path = row.get(field, "")
            if row.get("asset_id") in CHALLENGE_ASSET_IDS and path:
                resources.add(path + "_c")
    return resources


resources = configured_resources()
assert len(resources) == 46, (
    f"expected 46 unique challenge resources, found {len(resources)}"
)
missing = sorted(resources - vpk_paths())
assert not missing, "challenge resources missing from local VPK:\n" + "\n".join(missing)
print(f"CHALLENGE_MONSTER_RESOURCE_VPK_PASS resources={len(resources)}")