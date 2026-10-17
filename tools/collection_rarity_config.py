"""Keep collection imports on the reviewed five-tier rarity configuration."""
from __future__ import annotations

import csv
import io
from pathlib import Path

POOLS = {"ex", "friend", "wife", "beast"}
QUALITY_WEIGHTS = {"N": 6000, "R": 2500, "SR": 1000, "SSR": 450, "UR": 50}


def quality_for_index(index: int) -> str:
    if not 1 <= index <= 40:
        raise ValueError("collection_character_index_out_of_range")
    return "N" if index <= 5 else "R" if index <= 15 else "SR" if index <= 27 else "SSR" if index <= 37 else "UR"


def _replace_row(line: str, values: list[str]) -> str:
    stream = io.StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL if line.startswith('"') else csv.QUOTE_MINIMAL,
               lineterminator="\r\n" if line.endswith("\r\n") else "\n").writerow(values)
    return stream.getvalue()


def ensure_collection_rarity(directory: Path) -> None:
    """Change only quality and five weight fields; preserve all reward values."""
    path = directory / "archive_social_items.csv"
    original = path.read_bytes()
    lines = original.decode("utf-8-sig").splitlines(keepends=True)
    for index in range(2, len(lines)):
        values = next(csv.reader([lines[index]]))
        if not values or values[1] not in POOLS:
            continue
        quality = quality_for_index(int(values[0].rsplit("_", 1)[1]))
        if values[4] != quality:
            values[4] = quality
            lines[index] = _replace_row(lines[index], values)
    updated = (b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b"") + "".join(lines).encode("utf-8")
    if updated != original:
        path.write_bytes(updated)

    path = directory / "archive_social_rules.csv"
    original = path.read_bytes()
    lines = original.decode("utf-8-sig").splitlines(keepends=True)
    fields = next(csv.reader([lines[0]]))
    columns = ["quality_weight_" + quality.lower() for quality in QUALITY_WEIGHTS]
    missing = [column for column in columns if column not in fields]
    if missing:
        fields.extend(missing)
        values = next(csv.reader([lines[1]]))
        values.extend("number" for _ in missing)
        lines[0], lines[1] = _replace_row(lines[0], fields), _replace_row(lines[1], values)
    for index in range(2, len(lines)):
        values = next(csv.reader([lines[index]]))
        if not values or values[0] not in POOLS:
            continue
        values.extend("" for _ in range(len(fields) - len(values)))
        for quality, weight in QUALITY_WEIGHTS.items():
            values[fields.index("quality_weight_" + quality.lower())] = str(weight)
        candidate = _replace_row(lines[index], values)
        if missing or next(csv.reader([lines[index]])) != values:
            lines[index] = candidate
    updated = (b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b"") + "".join(lines).encode("utf-8")
    if updated != original:
        path.write_bytes(updated)
