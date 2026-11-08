"""Plan reviewed standalone-test migration; no Git mutation or automatic tests.

Default action is a read-only JSON plan. Apply requires its exact SHA256, backs
up EVERY selected script before any source removal, and retains recovery data.
Run accepts one manifest member, never a directory or a batch. Runtime tests,
server code, assets, release controls and existing evidence are not migrated.

Cold planning cost: two Git trees plus one bounded text pass/index O(N+B), where
N is tracked paths and B is inspected code bytes. No watcher, frame work or IO
polling. Apply is O(selected bytes); run starts one explicitly selected process.
"""
from __future__ import annotations
import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT.parents[1].parent / "content/dota_addons/Survival"
EXTERNAL = Path("D:/Survival_本地工具")
REPORTS = ROOT / "output/local_tools_20261108"
RECOVERY = Path("D:/Survival_本地排演/complete_delivery_20261103")
SUBDIRS = ("tests/game", "tests/content", "runs/test_migrations", "logs", "screenshots", "scratch", "archives", "vpk_lab")
CODE = {".py", ".lua", ".js", ".cjs", ".mjs"}
MAX_FILE = 2 * 1024 * 1024
MAX_SCAN = 64 * 1024 * 1024
SMOKE = ("tools/test_grid_state.cjs", "tools/test_grid_zoom_visibility.cjs", "tools/test_static_grid.cjs")
# These are actual production/restore primitives even when named "test".
KEEP = {
    "tools/admission_five_20261101/test_projected_policy.lua", "tools/publish_test_release.py",
    "tools/release_pipeline.py", "tools/release_sdk_lineage_hook.py", "tools/release_lineage_20261101/guard.py",
    "tools/shared_boss_portrait_release_20261101/source_baseline_0104.json",
}


def need(value, reason):
    if not value:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def stamp():
    return datetime.now(timezone.utc).isoformat()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def safe(root, relative):
    part = PurePosixPath(relative)
    need(not part.is_absolute() and bool(part.parts) and all(p not in ("..", ".") for p in part.parts), "unsafe_relative_path")
    result = root.joinpath(*part.parts)
    need(result.resolve().is_relative_to(root.resolve()), "path_escapes_root")
    for node in (result, *result.parents):
        need(not node.is_symlink() and not node.is_junction(), "reparse_path_rejected:" + str(node))
        if node == root:
            break
    return result


def read(path, limit=MAX_FILE):
    need(path.is_file() and not path.is_symlink() and not path.is_junction() and path.stat().st_size <= limit, "bounded_regular_file_required:" + str(path))
    return path.read_bytes()


def git(repo, *args):
    result = subprocess.run(["git", "--no-optional-locks", "--no-replace-objects", "-c", "safe.directory=" + repo.as_posix(), "-C", str(repo), *args], capture_output=True, timeout=60)
    need(result.returncode == 0, "readonly_git_failed:" + args[0])
    return result.stdout


def trees():
    result, heads = {}, {}
    for role, repo in (("game", ROOT), ("content", CONTENT)):
        heads[role] = git(repo, "rev-parse", "HEAD").decode().strip()
        raw = git(repo, "ls-tree", "-r", "-l", "-z", heads[role])
        result[role] = {}
        for row in raw.split(b"\0"):
            if row:
                metadata, name = row.split(b"\t", 1)
                mode, kind, oid, size = metadata.decode().split()
                result[role][name.decode("utf-8")] = {"oid": oid, "kind": kind, "bytes": int(size) if size != "-" else 0}
    return result, heads


def test_code(path):
    name = PurePosixPath(path).name
    return path.startswith("tools/") and Path(name).suffix.lower() in CODE and (name.startswith("test_") or ".test." in name or path.startswith("tools/tests/"))


def frozen_paths():
    """Conservatively protect actual recorded controls and retained codepins."""
    selected, controls = set(KEEP), {}

    def references(value):
        if isinstance(value, dict):
            for key, item in value.items():
                references(key)
                references(item)
        elif isinstance(value, list):
            for item in value:
                references(item)
        elif isinstance(value, str):
            if value.startswith(("tools/", "publishing/")):
                selected.add(value)
            elif Path(value).is_absolute() and Path(value).is_relative_to(ROOT):
                selected.add(Path(value).relative_to(ROOT).as_posix())

    def control(path, *, all_fields=False):
        raw = read(path, 32 * 1024 * 1024)
        controls[str(path)] = sha(raw)
        data = json.loads(raw)
        if all_fields:
            references(data)
        else:
            for key in ("executed_operator_inputs", "operator_binding", "operator_hashes", "code_pins"):
                references(data.get(key, {}))
        return data

    authority = control(ROOT / "publishing/workshop/release_authority_complete_20261103.json", all_fields=True)
    report = Path(authority["report_directory"])
    need(report.resolve().is_relative_to((ROOT / "output").resolve()), "active_report_escapes_project")
    if (report / "package.json").exists():
        control(report / "package.json")
    # Production and compiler evidence already exist before final collection.
    # Protect that active producer closure too; never wait for package.json.
    for handoff_path in sorted(report.glob("*_producers_handoff.json")):
        handoff = control(handoff_path)
        for key in ("compile_plan", "compile_proof", "production_receipt", "protection_proof"):
            if isinstance(handoff.get(key), dict):
                control(Path(handoff[key]["path"]))
    for pin_path in sorted(report.glob("source_pins_catalog*.json")):
        pin = control(pin_path)
        phase = pin.get("phase", "")
        match = re.fullmatch(r"catalog([0-9]+)", phase)
        if match:
            for catalog in sorted((ROOT / "output").glob("ui_static_catalog_gen" + match[1] + "_*")):
                manifest = catalog / "data/ui/ui_static_catalog_manifest.json"
                if manifest.is_file():
                    control(manifest)
    inputs_path = report / "pipeline_inputs.json"
    if inputs_path.exists():
        inputs = control(inputs_path)
        request_path = Path(inputs["collection_request"]["path"])
        need(request_path.resolve().is_relative_to((ROOT / "output").resolve()), "collection_control_escapes_project")
        request = control(request_path)
        control(Path(request["catalog"]["manifest"]["path"]))
        control(Path(request["production"]["receipt"]["path"]))
        for item in request["compiler_receipts"]:
            control(Path(item["plan"]["path"]))
    # Old recovery code may still be needed even after its original game exited.
    if RECOVERY.is_dir():
        for folder in sorted(RECOVERY.iterdir()):
            if folder.is_dir() and not folder.is_symlink() and not folder.is_junction() and (folder / "transaction.json").is_file():
                control(folder / "transaction.json")
    return selected, controls


def exclusions(path, text):
    reasons = []
    if re.search(r"__file__|__dirname|import\.meta|fileURLToPath", text):
        reasons.append("file_location_dependency")
    if re.search(r"(?:require\s*\(\s*|from\s*|import\s*)[\"']\.", text):
        reasons.append("relative_module_import")
    if re.search(r"(?:tests[/\\]|(?:require|import)\s*\(?\s*[\"']test_)", text):
        reasons.append("test_fixture_dependency")
    if re.search(r"\b(?:subprocess|child_process|requests|urllib|socket)\b|https?://|\bos\.execute\s*\(|\bio\.popen\s*\(|\bfetch\s*\(", text):
        reasons.append("process_or_network_review_required")
    if re.search(r"writeFile|write_text|write_bytes|rmtree|\bunlink\s*\(|Remove-Item|\bos\.(?:remove|rename)\s*\(|io\.open\([^\n]*,[ \t]*[\"'][wax]", text):
        reasons.append("filesystem_write_review_required")
    if Path(path).suffix == ".py":
        try:
            tree = ast.parse(text)
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and (node.level or (node.module or "").split(".")[0] not in sys.stdlib_module_names):
                    reasons.append("project_or_external_python_import")
                if isinstance(node, ast.Import) and any(n.name.split(".")[0] not in sys.stdlib_module_names for n in node.names):
                    reasons.append("project_or_external_python_import")
        except SyntaxError:
            reasons.append("unparsed_python")
    return sorted(set(reasons))


def plan(external=EXTERNAL):
    need(external.is_absolute() and all(not external.resolve().is_relative_to(x.resolve()) for x in (ROOT, CONTENT)), "external_workspace_must_be_outside_both_addon_trees")
    safe(external, "tests/game")
    inventory, heads = trees()
    frozen, controls = frozen_paths()
    candidates = {p: row for p, row in inventory["game"].items() if test_code(p) and row["kind"] == "blob"}
    texts, reasons, seen = {}, {}, 0
    for path, row in candidates.items():
        if row["bytes"] > MAX_FILE:
            reasons[path] = ["large_file_review_required"]
            continue
        raw = read(safe(ROOT, path)); seen += len(raw)
        need(seen <= MAX_SCAN, "candidate_scan_budget_exceeded")
        # A dirty test is a user change and cannot be migrated as its Git source.
        equivalent = {raw, raw.replace(b"\r\n", b"\n")}
        oids = {hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() for data in equivalent}
        if row["oid"] not in oids:
            reasons[path] = ["working_bytes_differ_from_head"]
            continue
        try:
            texts[path] = raw.decode("utf-8")
        except UnicodeDecodeError:
            reasons[path] = ["non_utf8_review_required"]
            continue
        reasons[path] = exclusions(path, texts[path])
        if path in frozen:
            reasons[path].append("production_or_recovery_closure")
    # Index test identifiers once, then scan other tracked code once. Function
    # name collisions conservatively retain tests rather than guessing intent.
    identifiers, filenames = {}, {}
    for path in candidates:
        identifiers.setdefault(PurePosixPath(path).stem, set()).add(path)
        filenames.setdefault(PurePosixPath(path).name, set()).add(path)
    for path, row in inventory["game"].items():
        if path == "tools/local_tools_workspace.py":
            continue  # The three optional smoke labels are metadata, not imports.
        if Path(path).suffix.lower() not in CODE or row["bytes"] > MAX_FILE or not path.startswith(("tools/", "scripts/", "panorama/src/")):
            continue
        text = texts.get(path)
        if text is None:
            raw = read(safe(ROOT, path)); seen += len(raw)
            need(seen <= MAX_SCAN, "reference_scan_budget_exceeded")
            text = raw.decode("utf-8", "replace")
        for token in set(re.findall(r"\btest_[A-Za-z0-9_]+\b", text)):
            for target in identifiers.get(token, ()):
                if target != path:
                    reasons.setdefault(target, []).append("referenced_by_other_code")
        for token in set(re.findall(r"[\w.-]+\.(?:py|lua|js|cjs|mjs)\b", text)):
            for target in filenames.get(token, ()):
                if target != path:
                    reasons.setdefault(target, []).append("referenced_by_other_code")
    rows, retained = [], []
    for path in sorted(candidates):
        why = sorted(set(reasons.get(path, [])))
        if why:
            retained.append({"source": path, "reasons": why})
        else:
            raw = read(safe(ROOT, path))
            rows.append({"source": path, "destination": "tests/game/" + path, "backup": "originals/game/" + path,
                         "sha256": sha(raw), "bytes": len(raw), "source_head": heads["game"], "synthetic_smoke_reviewed": path in SMOKE})
    return {"kind": "REVIEW_REQUIRED_STANDALONE_TEST_MIGRATION_PLAN", "schema": 1, "created_utc": stamp(),
            "project_root": str(ROOT), "content_root": str(CONTENT), "external_root": str(external), "source_heads": heads,
            "tool_sha256": sha(Path(__file__).read_bytes()), "control_sha256": controls, "protected_paths": sorted(frozen),
            "rows": rows, "retained": retained, "counts": {"candidates": len(candidates), "move": len(rows), "bytes": sum(x["bytes"] for x in rows),
                "retained": len(retained), "retained_reasons": dict(Counter(reason for x in retained for reason in x["reasons"])), "inspected_code_bytes": seen},
            "smoke_candidates": [p for p in SMOKE if any(x["source"] == p for x in rows)],
            "effects": "Plan only. Apply moves reviewed files; no Git mutation, native game, test execution, server or publication."}


def new_file(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def plan_output(path, *, recovery=False):
    """New plans belong only to the external workspace; legacy is explicit."""
    base = REPORTS if recovery else EXTERNAL / "runs/test_migrations"
    need(base.is_absolute() and (recovery or all(not base.resolve().is_relative_to(x.resolve()) for x in (ROOT, CONTENT))),
         "external_plan_root_required")
    candidate = path if path.is_absolute() else base / path
    need(candidate.is_relative_to(base) and candidate.suffix.lower() == ".json", "plan_output_must_be_in_dedicated_migration_directory")
    result = safe(base, candidate.relative_to(base).as_posix())
    # Check ancestors above the dedicated directory too: a junction at runs or
    # the external workspace root must not redirect a supposedly external plan.
    for node in (result, *result.parents):
        need(not node.is_symlink() and not node.is_junction(), "plan_output_reparse_rejected:" + str(node))
    return result


def initialize(external=EXTERNAL):
    need(external.is_absolute() and all(not external.resolve().is_relative_to(x.resolve()) for x in (ROOT, CONTENT)), "external_workspace_must_be_outside_addons")
    for relative in SUBDIRS:
        safe(external, relative).mkdir(parents=True, exist_ok=True)
    help_path = safe(external, "使用说明.txt")
    if not help_path.exists():
        new_file(help_path, ("Survival 本地工具工作区\n\n"
            "tests/game 和 tests/content：经过清单核对的独立测试。\n"
            "runs、logs、screenshots、scratch：以后一次性工具、日志、截图和临时文本。\n"
            "archives：原字节备份与迁移清单；vpk_lab：树外实验包。\n"
            "当前发行控制仍保留项目已忽略的固定 output 路径，直到事务收口。\n"
            "生成计划或单条运行请使用项目 tools/local_tools_workspace.py --help。\n"
            "例如：plan --out next_plan.json；计划保存到 runs/test_migrations。\n"
            "不传 --out 时只输出到终端；旧项目 output 仅供明确恢复操作。\n"
            "迁移与运行需要独立审核的清单摘要；不会自动全量运行测试。\n"
            "项目：" + str(ROOT) + "\n").encode("utf-8"))
    return {"status": "EXTERNAL_LOCAL_TOOLS_WORKSPACE_READY", "root": str(external), "directories": list(SUBDIRS), "readme": str(help_path), "git_mutations": 0}


def apply(path, expected):
    raw = read(path, 32 * 1024 * 1024)
    need(re.fullmatch("[a-f0-9]{64}", expected or "") and sha(raw) == expected, "reviewed_plan_sha256_required")
    value = json.loads(raw)
    need(value["kind"] == "REVIEW_REQUIRED_STANDALONE_TEST_MIGRATION_PLAN" and value["schema"] == 1
         and value["project_root"] == str(ROOT) and value["content_root"] == str(CONTENT)
         and value["tool_sha256"] == sha(Path(__file__).read_bytes()), "plan_or_operator_identity_changed")
    _, heads = trees()
    need(heads == value["source_heads"], "source_heads_changed_make_a_new_plan")
    current_frozen, current_controls = frozen_paths()
    need(current_frozen == set(value["protected_paths"]) and current_controls == value["control_sha256"],
         "active_or_retained_control_set_changed_make_a_new_plan")
    for control, digest in value["control_sha256"].items():
        need(sha(read(Path(control), 32 * 1024 * 1024)) == digest, "frozen_control_changed")
    external = Path(value["external_root"])
    need(external.is_absolute() and all(not external.resolve().is_relative_to(x.resolve()) for x in (ROOT, CONTENT)), "external_root_must_be_outside_addons")
    folder = safe(external, "archives/migrations/" + expected)
    need(not folder.exists() and value["rows"] and len({x["source"] for x in value["rows"]}) == len(value["rows"]), "fresh_nonempty_unique_migration_required")
    for row in value["rows"]:
        need(test_code(row["source"]) and row["source"] not in value["protected_paths"]
             and row["destination"] == "tests/game/" + row["source"] and row["backup"] == "originals/game/" + row["source"], "row_scope_changed")
        source = safe(ROOT, row["source"]); data = read(source)
        need(sha(data) == row["sha256"] and len(data) == row["bytes"], "source_changed_before_backup:" + row["source"])
        need(not safe(external, row["destination"]).exists(), "external_destination_conflict")
    for relative in SUBDIRS:
        safe(external, relative).mkdir(parents=True, exist_ok=True)
    folder.mkdir(parents=True)
    new_file(folder / "reviewed_plan.json", raw)
    state = {"kind": "STANDALONE_TEST_MIGRATION_MANIFEST", "schema": 1, "plan_sha256": expected, "project_root": str(ROOT),
             "external_root": str(external), "source_heads": heads, "rows": value["rows"], "status": "BACKING_UP", "removed": [], "git_mutations": 0}
    journal = folder / "journal.json"
    def persist():
        journal.write_bytes(canonical(state))
    persist()
    try:
        for row in value["rows"]:
            data = read(safe(ROOT, row["source"]))
            need(sha(data) == row["sha256"], "source_changed_during_backup")
            new_file(safe(folder, row["backup"]), data)
            new_file(safe(external, row["destination"]), data)
        # This is the all-files barrier: NO original has been removed yet.
        for row in value["rows"]:
            for copy in (safe(folder, row["backup"]), safe(external, row["destination"]), safe(ROOT, row["source"])):
                need(sha(read(copy)) == row["sha256"], "all_backup_hashes_must_verify_before_removal")
        new_file(folder / "all_backups_verified.json", canonical({"plan_sha256": expected, "files": len(value["rows"]), "bytes": value["counts"]["bytes"], "utc": stamp()}))
        state["status"] = "BACKUPS_VERIFIED_MIGRATING"; persist()
        for row in value["rows"]:
            source = safe(ROOT, row["source"])
            need(all(sha(read(copy)) == row["sha256"] for copy in (source, safe(folder, row["backup"]), safe(external, row["destination"]))),
                 "source_or_backup_changed_during_migration")
            source.unlink()
            state["removed"].append(row["source"]); persist()
        state["status"] = "COMPLETE_EXTERNAL_TESTS_RETAINED_GIT_UNCHANGED"; persist()
        new_file(folder / "manifest.json", canonical(state))
    except BaseException:
        state["status"] = "FAILED_PRESERVE_BACKUPS_AND_PARTIAL_MIGRATION"; persist()
        raise
    return {"status": state["status"], "moved": len(state["removed"]), "manifest": str(folder / "manifest.json"), "manifest_sha256": sha((folder / "manifest.json").read_bytes()), "git_mutations": 0}


def run_one(manifest, expected, script, timeout=120):
    raw = read(manifest, 32 * 1024 * 1024)
    need(re.fullmatch("[a-f0-9]{64}", expected or "") and sha(raw) == expected, "explicit_manifest_sha256_required")
    value = json.loads(raw)
    need(value["kind"] == "STANDALONE_TEST_MIGRATION_MANIFEST" and value["status"] == "COMPLETE_EXTERNAL_TESTS_RETAINED_GIT_UNCHANGED"
         and value["project_root"] == str(ROOT), "completed_project_migration_manifest_required")
    selected = [x for x in value["rows"] if x["source"] == script]
    need(len(selected) == 1 and 1 <= timeout <= 1800, "one_manifest_script_and_bounded_timeout_required")
    row = selected[0]; target = safe(Path(value["external_root"]), row["destination"])
    need(test_code(script) and row["destination"] == "tests/game/" + script
         and all(not Path(value["external_root"]).resolve().is_relative_to(x.resolve()) for x in (ROOT, CONTENT)), "external_test_member_required")
    need(sha(read(target)) == row["sha256"], "external_test_changed")
    suffix = target.suffix.lower()
    command = [sys.executable, "-X", "utf8", "-B"] if suffix == ".py" else (["C:/Program Files/lua/bin/lua5.1.exe"] if suffix == ".lua" else [shutil.which("node") or "node"])
    env = os.environ.copy()
    env["SURVIVAL_PROJECT_ROOT"] = str(ROOT)
    env["PYTHONPATH"] = os.pathsep.join([str(ROOT), str(ROOT / "tools"), env.get("PYTHONPATH", "")])
    env["LUA_PATH"] = (ROOT / "scripts/vscripts/?.lua").as_posix() + ";" + env.get("LUA_PATH", ";;")
    result = subprocess.run([*command, str(target)], cwd=ROOT, env=env, timeout=timeout)
    return result.returncode


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("init")
    p = sub.add_parser("plan")
    p.add_argument("--out", type=Path, help="JSON filename under D:/Survival_本地工具/runs/test_migrations; omit for stdout only")
    p.add_argument("--recovery-output", action="store_true", help="Explicit recovery only: allow the original ignored project report directory")
    p = sub.add_parser("apply"); p.add_argument("--plan", type=Path, required=True); p.add_argument("--plan-sha256", required=True)
    p = sub.add_parser("run"); p.add_argument("script"); p.add_argument("--manifest", type=Path, required=True); p.add_argument("--manifest-sha256", required=True); p.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args(argv)
    if args.action == "init":
        print(json.dumps(initialize(), ensure_ascii=False)); return 0
    if args.action == "plan":
        need(not args.recovery_output or args.out is not None, "recovery_output_requires_an_explicit_filename")
        destination = plan_output(args.out, recovery=args.recovery_output) if args.out else None
        value = plan()
        if destination:
            new_file(destination, canonical(value))
            print(json.dumps({"status": "PLAN_WRITTEN_NO_MIGRATION", "path": str(destination), "sha256": sha(destination.read_bytes()), "counts": value["counts"], "smoke_candidates": value["smoke_candidates"]}, ensure_ascii=False))
        else:
            print(canonical(value).decode("utf-8"))
        return 0
    if args.action == "apply":
        print(json.dumps(apply(args.plan, args.plan_sha256), ensure_ascii=False)); return 0
    return run_one(args.manifest, args.manifest_sha256, args.script, args.timeout)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "LOCAL_TOOLS_REFUSED_PRESERVE_EXISTING_DATA", "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(2)
