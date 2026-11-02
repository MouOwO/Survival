"""Create one private four-code workbook only after explicit --generate.

Default: static, zero writes/entropy/network. --resume never generates codes;
it recovers the same batch from its intact workbook and hash-only pending file.
No registration, old128 import, Desktop copy or external delivery is provided.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import secrets
import stat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PRIVATE = ROOT / "output/redemption_ticket_codes_20261102/private"
BATCH = "ordinary_ticket_four_tiers_20261102_v01"
WORKBOOK = "普通抽奖券四档兑换码_20261102.xlsx"
INTENT = "generation_intent.json"
PENDING = "generation_pending.json"
HASHES = "ticket_hashes.json"
REGISTRY = "server_codes.json"
MANIFEST = "generation_manifest.json"
TARGETS = (INTENT, PENDING, WORKBOOK, HASHES, REGISTRY, MANIFEST)
HEADERS = ["登记状态", "兑换码", "奖励名称", "奖励数量", "库存ID", "适用奖池",
           "每账号次数", "全服总次数(0不限)", "开始时间", "截止时间", "说明"]
DISCLAIMER = "本文件不是旧128码Excel，不用旧register.py导入"


def need(value, code):
    if not value:
        raise ValueError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8") + b"\n"


def compiler():
    spec = importlib.util.spec_from_file_location("private_ticket_code_compiler", HERE / "definitions.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_pins():
    return {name: sha((HERE / name).read_bytes())
            for name in ("generate_private.py", "definitions.py", "tiers.json")}


def private_directory():
    # Fixed paths only; ignore rules do not grant permission to follow junctions.
    expected = ROOT / "output/redemption_ticket_codes_20261102/private"
    need(PRIVATE == expected, "fixed_private_directory_required")
    current = ROOT
    for name in ("output", "redemption_ticket_codes_20261102", "private"):
        current = current / name
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        need(stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode)
             and not getattr(info, "st_file_attributes", 0) & 0x400, "private_reparse_or_non_directory_refused")
    return expected


def write_new(name, raw):
    need(name in TARGETS, "unknown_private_output_refused")
    path = private_directory() / name
    with path.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def same_or_new(name, raw):
    path = PRIVATE / name
    if path.exists():
        need(path.is_file() and not path.is_symlink() and path.read_bytes() == raw,
             "existing_private_artifact_differs_preserve_pending")
    else:
        write_new(name, raw)


def load_json(name):
    path = PRIVATE / name
    need(path.is_file() and not path.is_symlink() and path.stat().st_size < 1024 * 1024,
         "private_pending_missing_or_invalid")
    return json.loads(path.read_text(encoding="utf-8"))


def workbook_bytes(codes):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    book = Workbook()
    sheet = book.active
    sheet.title = "四档普通券兑换码"
    sheet.append(HEADERS)
    for quantity, code in codes.items():
        sheet.append(["待登记", code, "普通抽奖券", int(quantity), "lottery_ticket", "地图抽奖(map)",
                      1, 0, None, None, "仅登记成功后生效；每账号每码一次；无期限"])
    sheet.freeze_panes = "A2"
    sheet.auto_filter.ref = sheet.dimensions
    for cell in sheet[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="334E68")
    for row in sheet.iter_rows(min_row=2):
        row[1].number_format = "@"
        for cell in row:
            cell.alignment = Alignment(vertical="top", wrap_text=True)
    for column in "ABCDEFGHIJK":
        sheet.column_dimensions[column].width = 20 if column != "B" else 42
    sheet.column_dimensions["K"].width = 48
    notes = book.create_sheet("使用说明")
    for row in [("重要", DISCLAIMER), ("批次", BATCH),
                ("状态", "待登记：此文件本身不会向服务器登记"),
                ("券种", "lottery_ticket，普通地图奖池；不含金色券special_lottery_ticket"),
                ("次数", "每账号每码1次；全服总次数0表示不限；无开始或截止限制"),
                ("保密", "真实明文只在本私有Excel；不要提交Git、放进客户端或公开发送"),
                ("登记", "Root使用WS4专用insert-only工具；备份与验证通过后仅新增4行"),
                ("交付", "Root登记成功后另行更新状态和复制桌面；生成器不自动分发"),
                ("中断恢复", "保留全部文件；--resume只恢复本批，绝不重新生成；损坏时停止并人工核查")]:
        notes.append(row)
    notes.column_dimensions["A"].width = 18
    notes.column_dimensions["B"].width = 100
    result = io.BytesIO()
    book.save(result)
    book.close()
    return result.getvalue()


def hashes_from_workbook(module):
    from openpyxl import load_workbook
    path = PRIVATE / WORKBOOK
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 2 * 1024 * 1024,
         "intact_original_workbook_required_no_regeneration")
    try:
        book = load_workbook(path, read_only=True, data_only=False)
    except Exception:
        raise ValueError("intact_original_workbook_required_no_regeneration") from None
    try:
        need(set(book.sheetnames) == {"四档普通券兑换码", "使用说明"}, "private_workbook_shape_invalid")
        sheet = book["四档普通券兑换码"]
        need(sheet.max_row == 5 and sheet.max_column == len(HEADERS), "private_workbook_shape_invalid")
        rows = list(sheet.iter_rows())
        need([c.value for c in rows[0]] == HEADERS, "private_workbook_shape_invalid")
        hashes = {}
        for quantity, row in zip(module.QUANTITIES, rows[1:]):
            need(all(c.data_type != "f" for c in row), "private_workbook_formula_refused")
            values = [c.value for c in row]
            need(values[0] == "待登记" and values[2:8] == ["普通抽奖券", quantity,
                 "lottery_ticket", "地图抽奖(map)", 1, 0]
                 and values[8:10] == [None, None], "private_workbook_reward_changed")
            code = values[1]
            need(isinstance(code, str) and re.fullmatch(r"GFCJ" + str(quantity) + r"-[A-F0-9]{24}", code),
                 "private_workbook_code_shape_invalid")
            from archive_backend.redemption_codes import normalize
            hashes[str(quantity)] = sha(normalize(code).encode("ascii"))
        notes = list(book["使用说明"].values)
        need(any(row[:2] == ("重要", DISCLAIMER) for row in notes), "private_workbook_disclaimer_missing")
        need(any(row[:2] == ("批次", BATCH) for row in notes), "private_workbook_batch_changed")
        return hashes
    finally:
        book.close()


def finish_same_batch(module, *, catalog=None):
    private_directory()
    intent, pending = load_json(INTENT), load_json(PENDING)
    pins = source_pins()
    need(intent.get("batch") == pending.get("batch") == BATCH
         and intent.get("source_pins") == pending.get("source_pins") == pins,
         "generation_source_changed_preserve_pending")
    hashes = hashes_from_workbook(module)
    need(hashes == pending.get("hashes"), "workbook_hash_differs_from_pending_no_regeneration")
    registry = module.compile_definitions(hashes, catalog=catalog)
    need(sha(canonical(registry)) == pending.get("registry_sha256"),
         "reward_definition_changed_preserve_pending")
    same_or_new(HASHES, canonical(hashes))
    same_or_new(REGISTRY, canonical(registry))
    artifacts = {name: {"sha256": sha((PRIVATE / name).read_bytes()), "bytes": (PRIVATE / name).stat().st_size}
                 for name in (WORKBOOK, HASHES, REGISTRY)}
    manifest = {"schema": 1, "batch": BATCH, "status": "PRIVATE_FOUR_CODES_CREATED_NOT_REGISTERED",
                "registration_status": "待登记", "registered": False,
                "quantities": list(module.QUANTITIES), "ticket_content_id": module.TICKET,
                "source_pins": pins, "artifacts": artifacts,
                "plaintext_location": "PRIVATE_WORKBOOK_ONLY", "server_connections": 0,
                "old128_codes_read_or_changed": False, "automatic_delivery": False}
    same_or_new(MANIFEST, canonical(manifest))
    return {"ok": True, "status": manifest["status"], "codes": 4,
            "files": {name: {"path": str(PRIVATE / name), **row} for name, row in artifacts.items()},
            "manifest": {"path": str(PRIVATE / MANIFEST), "sha256": sha((PRIVATE / MANIFEST).read_bytes())}}


def generate():
    module = compiler()
    # Check the installed dependency and catalogue before reserving a batch.
    from openpyxl import Workbook  # noqa: F401
    catalog, _ = module.offers(module.ROOT)
    module.compile_definitions({str(n): str(i) * 64 for i, n in enumerate(module.QUANTITIES, 1)}, catalog=catalog)
    directory = private_directory()
    need(not any((directory / name).exists() for name in TARGETS),
         "existing_generation_target_use_resume_no_new_codes")
    directory.mkdir(parents=True, exist_ok=True)
    pins = source_pins()
    write_new(INTENT, canonical({"schema": 1, "batch": BATCH, "status": "RESERVED_NO_AUTOMATIC_REGENERATION",
                               "created_utc": datetime.now(timezone.utc).isoformat(), "source_pins": pins}))
    # Exactly four draws from the secure source. A failure never loops/retries.
    codes = {str(n): "GFCJ" + str(n) + "-" + secrets.token_hex(12).upper() for n in module.QUANTITIES}
    from archive_backend.redemption_codes import normalize
    hashes = {quantity: sha(normalize(code).encode("ascii")) for quantity, code in codes.items()}
    registry = module.compile_definitions(hashes, catalog=catalog)
    write_new(PENDING, canonical({"schema": 1, "batch": BATCH, "source_pins": pins,
                                 "hashes": hashes, "registry_sha256": sha(canonical(registry)),
                                 "status": "PRESERVE_ORIGINAL_WORKBOOK_AND_RESUME_ONLY"}))
    write_new(WORKBOOK, workbook_bytes(codes))
    # The completed workbook is the only persisted plaintext source. All
    # subsequent phases can recover from it without another entropy call.
    return finish_same_batch(module, catalog=catalog)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--generate", action="store_true")
    action.add_argument("--resume", action="store_true")
    args = parser.parse_args(argv)
    if args.generate:
        result = generate()
    elif args.resume:
        result = finish_same_batch(compiler())
    else:
        result = {"ok": True, "status": "STATIC_PRIVATE_GENERATION_PLAN", "quantities": [10, 50, 100, 200],
                  "private_directory": str(PRIVATE), "plaintext_codes_created": 0,
                  "entropy_calls": 0, "files_written": 0, "server_connections": 0}
    print(json.dumps(result, sort_keys=True, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        code = str(error)
        print(json.dumps({"ok": False, "status": "PRESERVE_PENDING_NO_AUTOMATIC_REGENERATION",
                          "error": code if re.fullmatch(r"[a-z0-9_]{1,100}", code) else type(error).__name__}))
        raise SystemExit(1)
