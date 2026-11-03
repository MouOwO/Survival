"""Extract only public grid bitmap data from a closed, hash-bound native log.

No account/scope/session values or original KV payloads are written or printed.
The atlas is a candidate UI baseline; the server must still scan live terrain
and compare every word before declaring known and sending sparse overrides.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_MANIFEST = "ac45847850e8d28abe8eb7b0cd039f8e00d5cbefd268de99356c99eaf6ca6d6c"
PUBLIC_SOURCES = (
    "scripts/vscripts/systems/grid_placement_system.lua",
    "scripts/vscripts/core/building_grid_geometry.lua",
    "scripts/vscripts/config/grid_placement_config.lua",
    "scripts/vscripts/config/map_layouts/template_map.lua",
    "scripts/vscripts/config/generated/build_forbidden_regions.lua",
    "scripts/vscripts/systems/forbidden_region_service.lua",
)
AREA = re.compile(r"3\|\d+\|-?\d+\|-?\d+\|\d+\|\d+\|-?\d+(?:\.\d+)?\|[0-9a-f]+")


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf8")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def parse_areas(raw):
    if len(raw) > 128 * 1024 * 1024:
        raise ValueError("bounded_closed_native_log_required")
    text = raw.decode("latin1")
    if "ShutdownSource2Logging" not in text:
        raise ValueError("closed_native_log_required")
    # splitlines() treats arbitrary UTF8 continuation bytes as Latin1 NEL.
    # Native protobuf dumps must be separated by the actual LF only.
    lines = text.split("\n")
    values = []
    for index, line in enumerate(lines):
        if 'event_name: "ui_grid_placement_static_area"' not in line:
            continue
        if index + 1 >= len(lines) or "data:" not in lines[index + 1]:
            raise ValueError("native_static_area_payload_missing")
        found = AREA.findall(lines[index + 1])
        if len(found) != 1:
            raise ValueError("exactly_one_public_bitmap_required")
        area = found[0]
        parts = area.split("|")
        size, x, y, width, height = map(int, parts[1:6])
        if not 1 <= size <= 65536 or not 1 <= width * height <= 65536 or len(parts[7]) != (width * height + 1) // 2:
            raise ValueError("public_bitmap_dimensions_invalid")
        if any(int(digit, 16) > 10 or int(digit, 16) % 4 > 2 for digit in parts[7]):
            raise ValueError("public_bitmap_cell_state_unknown")
        values.append(area)
    if len(values) != 2 or values[0] != values[1]:
        raise ValueError("two_identical_native_static_areas_required")
    return values[0]


def extract(log, manifest, snapshot):
    manifest_raw = Path(manifest).read_bytes()
    if len(manifest_raw) > 8 * 1024 * 1024 or sha(manifest_raw) != EXPECTED_MANIFEST:
        raise ValueError("immutable_dev04_manifest_changed")
    entries = json.loads(manifest_raw)["files"]
    if not isinstance(entries, list) or len(entries) > 20000:
        raise ValueError("snapshot_manifest_budget_exceeded")
    index = {}
    for row in entries:
        if row.get("area") == "game":
            key = row["relative"].replace("\\", "/")
            if key in index:
                raise ValueError("duplicate_snapshot_resource")
            index[key] = row
    sources, raw_sources = {}, {}
    for relative in ("maps/template_map.vpk", *PUBLIC_SOURCES):
        if relative not in index:
            raise ValueError("snapshot_public_source_missing:" + relative)
        path = Path(snapshot) / relative
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 256 * 1024 * 1024:
            raise ValueError("bounded_snapshot_public_source_required")
        with path.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != index[relative]["sha256"]:
            raise ValueError("snapshot_public_source_changed:" + relative)
        raw_sources[relative] = actual
        if relative.endswith(".lua"):
            sources[relative] = sha(path.read_bytes().replace(b"\r\n", b"\n"))
    log_raw = Path(log).read_bytes()
    area = parse_areas(log_raw)
    parts = area.split("|")
    return dict(format=1, kind="NATIVE_GRID_STATIC_CANDIDATE_REQUIRES_CURRENT_SERVER_SCAN", atlases=[dict(
        id=1, map="template_map", area=area, source_map_sha256=raw_sources["maps/template_map.vpk"],
        source_manifest_sha256=EXPECTED_MANIFEST, source_log_sha256=sha(log_raw), source_identical_events=2,
        source_public_file_sha256=raw_sources, projection_source_sha256=sources,
        projection_signature=sha(canonical(sources)), source_area_sha256=sha(area.encode("ascii")),
        excluded_modes=["rich", "cold", "scourge", "ruins"],
        size=int(parts[1]), origin_x=int(parts[2]), origin_y=int(parts[3]), width=int(parts[4]), height=int(parts[5]),
        ground_height=float(parts[6]), word_count=(int(parts[4]) * int(parts[5]) + 15) // 16,
        authority=False, requires_current_live_scan=True, missing_word_requires_validated_baseline=True,
        original_scope_session_account_included=False)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "data/ui/grid_static_atlas_candidate_20261103.json")
    args = parser.parse_args()
    dest = args.output.resolve()
    if not dest.is_relative_to(ROOT / "data/ui") and not dest.is_relative_to(ROOT / "output"):
        raise ValueError("public_candidate_output_must_stay_in_workspace")
    value = extract(args.log, args.manifest, args.snapshot)
    raw = canonical(value)
    if dest.exists() and dest.read_bytes() != raw:
        raise ValueError("refuse_to_overwrite_different_candidate")
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("xb") as stream:
            stream.write(raw)
    row = value["atlases"][0]
    print(json.dumps(dict(status="PUBLIC_NATIVE_ATLAS_CANDIDATE_EXTRACTED_NOT_AUTHORITY", sha256=sha(raw),
                         source_map_sha256=row["source_map_sha256"], source_identical_events=2,
                         width=row["width"], height=row["height"], word_count=row["word_count"],
                         raw_private_payloads_disclosed=False)))


if __name__ == "__main__":
    main()
