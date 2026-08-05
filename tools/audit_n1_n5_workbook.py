"""Read-only audit for the N1-N5 monster balance workbook.

The project deliberately uses only the Python standard library here so the
audit works with the repository's pinned local Python without extra packages.
"""
from __future__ import annotations

import argparse
import json
import posixpath
import re
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree as ET


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
CELL_REF = re.compile(r"^([A-Z]+)([1-9][0-9]*)$")
EXPECTED_SHEETS = (
    "总览",
    "小怪属性对照",
    "首怪Boss对照",
    "进攻Boss对照",
    "特殊目标对照",
    "转生Boss对照",
    "十戒Boss对照",
    "本次修正记录",
    "首怪Boss倍率明细",
    "进攻Boss倍率明细",
)
MODERN_SHEET_SUFFIXES = (
    "说明与总览",
    "{difficulty}波次总表",
    "小怪属性明细",
    "进攻Boss波",
    "出怪期挑战Boss",
    "每波Boss倍率对比",
    "四个练功房",
    "转生Boss",
    "十戒Boss",
    "特殊Boss与材料怪",
    "存档挑战独立表",
    "属性关联分析",
    "待确认索引",
)


def valid_sheet_order(actual_names: tuple[str, ...]) -> bool:
    if actual_names == EXPECTED_SHEETS:
        return True
    if len(actual_names) != len(MODERN_SHEET_SUFFIXES):
        return False
    match = re.fullmatch(r"(N[1-5])波次总表", actual_names[1])
    if not match:
        return False
    difficulty_id = match.group(1)
    expected = tuple(
        name.format(difficulty=difficulty_id) for name in MODERN_SHEET_SUFFIXES
    )
    return actual_names == expected


@dataclass(frozen=True)
class Cell:
    value: str
    formula: str | None = None


def qname(namespace: str, name: str) -> str:
    return f"{{{namespace}}}{name}"


def normalize_target(target: str) -> str:
    if target.startswith("/"):
        target = target[1:]
    elif not target.startswith("xl/"):
        target = "xl/" + target
    return posixpath.normpath(target)


def inline_text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return "".join(node.text or "" for node in element.iter(qname(MAIN_NS, "t")))


def load_shared_strings(archive: zipfile.ZipFile) -> list[str]:
    path = "xl/sharedStrings.xml"
    if path not in archive.namelist():
        return []
    root = ET.fromstring(archive.read(path))
    return [inline_text(item) for item in root.findall(qname(MAIN_NS, "si"))]


def read_cell(element: ET.Element, shared_strings: list[str]) -> Cell:
    kind = element.attrib.get("t")
    value_element = element.find(qname(MAIN_NS, "v"))
    formula_element = element.find(qname(MAIN_NS, "f"))
    raw = value_element.text or "" if value_element is not None else ""
    if kind == "s" and raw:
        value = shared_strings[int(raw)]
    elif kind == "inlineStr":
        value = inline_text(element.find(qname(MAIN_NS, "is")))
    elif kind == "b":
        value = "1" if raw == "1" else "0"
    else:
        value = raw
    return Cell(value=value, formula=formula_element.text if formula_element is not None else None)


def workbook_sheets(archive: zipfile.ZipFile) -> list[tuple[str, str]]:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    targets = {item.attrib["Id"]: item.attrib["Target"] for item in relationships}
    result = []
    sheets = workbook.find(qname(MAIN_NS, "sheets"))
    if sheets is None:
        return result
    for sheet in sheets:
        relation_id = sheet.attrib[qname(REL_NS, "id")]
        result.append((sheet.attrib["name"], normalize_target(targets[relation_id])))
    return result


def read_sheet(
    archive: zipfile.ZipFile,
    target: str,
    shared_strings: list[str],
) -> list[dict[str, object]]:
    root = ET.fromstring(archive.read(target))
    rows = []
    for row in root.iter(qname(MAIN_NS, "row")):
        values: dict[str, str] = {}
        formulas: dict[str, str] = {}
        for element in row.findall(qname(MAIN_NS, "c")):
            reference = element.attrib.get("r", "")
            match = CELL_REF.fullmatch(reference)
            if not match:
                continue
            column = match.group(1)
            cell = read_cell(element, shared_strings)
            if cell.value != "":
                values[column] = cell.value
            if cell.formula is not None:
                formulas[column] = cell.formula
        if values or formulas:
            rows.append({
                "row": int(row.attrib.get("r", "0")),
                "values": values,
                "formulas": formulas,
            })
    return rows


def audit(path: Path) -> tuple[dict[str, object], list[str]]:
    errors: list[str] = []
    with zipfile.ZipFile(path) as archive:
        shared_strings = load_shared_strings(archive)
        definitions = workbook_sheets(archive)
        actual_names = tuple(name for name, _ in definitions)
        if not valid_sheet_order(actual_names):
            errors.append("unexpected_sheet_order")
        sheets = []
        for name, target in definitions:
            rows = read_sheet(archive, target, shared_strings)
            sheets.append({
                "name": name,
                "target": target,
                "nonempty_row_count": len(rows),
                "rows": rows,
            })
    return {
        "workbook": str(path.resolve()),
        "sheet_names": list(actual_names),
        "sheets": sheets,
    }, errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--sheet", action="append", default=[])
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.workbook.is_file():
        print(f"ERROR: workbook not found: {args.workbook}", file=sys.stderr)
        return 2
    try:
        report, errors = audit(args.workbook)
    except (OSError, KeyError, ValueError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f"ERROR: workbook audit failed: {error}", file=sys.stderr)
        return 3
    selected = set(args.sheet)
    if selected:
        unknown = selected.difference(report["sheet_names"])
        if unknown:
            print("ERROR: unknown sheets: " + ", ".join(sorted(unknown)), file=sys.stderr)
            return 4
        report["sheets"] = [item for item in report["sheets"] if item["name"] in selected]
    report["errors"] = errors
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8", newline="\n")
    else:
        sys.stdout.buffer.write(text.encode("utf-8"))
    if errors:
        print("N1_N5_WORKBOOK_AUDIT_FAIL " + ",".join(errors), file=sys.stderr)
        return 5
    print("N1_N5_WORKBOOK_AUDIT_PASS", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())