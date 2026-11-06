"""Isolated complete-package ordinary-client rehearsal, never publication.

Explicit actions authenticate the whole signed candidate and actual0104 parent.
All staging/retained originals stay outside addon trees. A complete directory is
switched only with no Dota client; the original directory remains in the external
transaction. Restore physically stages/validates a complete copy before switching
and retains both backup and exercised candidate. No ACF/journal edits or kill.

Costs: stage/restore O(package bytes + file count), inspect O(volumes) native RM
queries plus a whole installed hash pass. Launch retains immutable file handles;
its wait observes a process HANDLE and makes no game/network request.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import importlib.machinery
import json
import os
from pathlib import Path
import re
import shutil
import sys
from types import ModuleType

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STORE = Path("D:/Survival_本地排演/complete_delivery_20261103")
LOG_ROOT = ROOT / "output/complete_delivery_rehearsal_20261103"
PORT = 29072
KIND = "COMPLETE_SIGNED_PACKAGE_ORDINARY_REHEARSAL"
BASE_MANIFEST = "7025356658517360342"
PARENT = ROOT / "tools/arcade_portrait_release_v03_20261101/rehearsal_v04.py"
PARENT_SHA = "2adecf06ca42cd67d40cef29cd91f7f8935db5f1e428e9d01fb300e2081b4c13"
LAUNCH_ROUTES = ("direct", "lobby")
_ENV = None
_CONTEXT = None
_ROUTE = None
_EXECUTED_OPERATOR_PINS = {}

def need(ok, why):
    if not ok: raise ValueError(why)

def recipe():
    from complete_delivery_release_20261103 import pipeline_recipe
    return pipeline_recipe

def names(rows, item="3824360109"):
    need(isinstance(rows, list) and 2 <= len(rows) <= 1001, "complete_bounded_index_and_volumes_required")
    expected = [item + ".vpk", *(item + "_%03d.vpk" % n for n in range(len(rows)-1))]
    need([row.get("name") for row in rows] == expected
        and all(type(row.get("bytes")) is int and row["bytes"] > 0
            and re.fullmatch("[a-f0-9]{64}", row.get("sha256", "")) for row in rows),
        "complete_exact_consecutive_package_rows_required")
    return expected

def source_binding(package, report_sha):
    global _CONTEXT
    sources = package.get("source_revisions")
    need(isinstance(sources, dict) and set(sources) == {"game", "content"}
        and all(re.fullmatch("[a-f0-9]{40}", v or "") for v in sources.values())
        and package.get("source_revision") == sources["game"],
        "complete_rehearsal_immutable_source_pair_required")
    value = dict(package_report_sha256=report_sha, source_revisions=sources,
        source_revision=sources["game"], operator_revision=package["operator_revision"],
        collection_source_revisions=package["collection_source_revisions"],
        content_sha256=package["content_sha256"], signed_manifest_sha256=package["signed_manifest_sha256"])
    need(_CONTEXT is None or _CONTEXT == value, "complete_rehearsal_one_authenticated_candidate_per_process")
    _CONTEXT = value
    return value

@contextmanager
def capture_operator_imports():
    """Compile the exact freshly read tool bytes, bypassing stale .pyc caches."""
    original=importlib.machinery.SourceFileLoader.get_code
    def get_code(loader,fullname):
        lexical=Path(loader.path).absolute()
        if lexical.is_relative_to(ROOT/"tools"):
            path=lexical.resolve()
            need(path.is_relative_to((ROOT/"tools").resolve()) and path.is_file()
                and path.stat().st_size<=4*1024*1024,"complete_bounded_project_operator_source_required")
            raw=path.read_bytes();relative=path.relative_to(ROOT).as_posix()
            pin=hashlib.sha256(raw.replace(b"\r\n",b"\n")).hexdigest()
            need(relative not in _EXECUTED_OPERATOR_PINS or _EXECUTED_OPERATOR_PINS[relative]==pin,
                "complete_operator_changed_during_import")
            _EXECUTED_OPERATOR_PINS[relative]=pin
            return compile(raw,str(path),"exec",dont_inherit=True)
        return original(loader,fullname)
    importlib.machinery.SourceFileLoader.get_code=get_code
    try:yield
    finally:importlib.machinery.SourceFileLoader.get_code=original

def environment():
    global _ENV
    if _ENV is None:
        b = recipe(); raw = PARENT.read_bytes()
        need(hashlib.sha256(raw).hexdigest() == PARENT_SHA, "complete_frozen_owned_process_primitives_changed")
        spec = importlib.util.spec_from_file_location("complete_private_owned_v04", PARENT)
        v4 = importlib.util.module_from_spec(spec)
        with capture_operator_imports():spec.loader.exec_module(v4)
        p = v4.p; original_write = p.write_new
        v4.STORE = STORE; v4.LOG_ROOT = LOG_ROOT
        p.b = b; p.need = need; p.STORE = STORE; p.PORT = PORT; p.KIND = KIND
        # All CIM failures must terminate, including a denied Get-CimInstance.
        p.SNAPSHOT_PS = p.SNAPSHOT_PS.replace("29048", str(PORT)).replace(
            "Get-CimInstance Win32_Process", "Get-CimInstance -ErrorAction Stop Win32_Process")
        def process_details(pid):
            need(type(pid) is int and 0 < pid < 2**31, "complete_pid_required")
            return p.powershell("$p=Get-CimInstance -ErrorAction Stop Win32_Process -Filter 'ProcessId="+str(pid)+"';"
                "if(-not $p){'null';exit};[ordered]@{pid=[int]$p.ProcessId;created_utc=$p.CreationDate.ToUniversalTime().ToString('o');"
                "executable=$p.ExecutablePath;command_line=$p.CommandLine}|ConvertTo-Json -Compress")
        p.process_details = process_details
        def write_new(path, value):
            if isinstance(value, dict) and _CONTEXT is not None:
                value = dict(value)
                for key, expected in _CONTEXT.items():
                    need(key not in value or value[key] == expected, "complete_operation_receipt_binding_changed:"+key)
                    value[key] = expected
                target = Path(path)
                if value.get("pid") and "native_created_filetime" not in value and (target.parent/"process.json").is_file():
                    live = p.json_read(target.parent/"process.json")
                    if value["pid"] == live.get("pid") and value.get("created_utc") == live.get("created_utc"):
                        value["native_created_filetime"] = live["native_created_filetime"]
                if target.name in ("launch_intent.json", "process.json"):
                    value.update(launch_route=_ROUTE, owned_launch=True,
                        direct_entry_requested=_ROUTE == "direct", lobby_creation_by_tool=False)
            return original_write(path, value)
        p.write_new = write_new
        p.require_rows = require_rows; p.package_auth = package_auth; p.fixed_paths = fixed_paths
        p.load_transaction = load_transaction; p.acf_item = acf_item; p.own_code_pins = own_code_pins
        p.arguments = arguments; p.live_record = live_record
        p.full_vpk = full_vpk
        v4.own_code_pins = own_code_pins; v4.expected_log_path = expected_log_path
        v4.r.own_code_pins = own_code_pins
        _ENV = (b, p, v4)
    return _ENV

def own_code_pins():
    b, p, v4 = environment()
    values = [Path(__file__), PARENT, v4.PARENT, v4.r.PARENT,
        HERE/"pipeline_recipe.py", HERE/"package.py", HERE/"native_admission.py", HERE/"verify_download.py"]
    if _CONTEXT is not None:
        b.verify_operator_paths(dict(_EXECUTED_OPERATOR_PINS), _CONTEXT["operator_revision"])
    return {str(path.resolve()):p.digest(p.regular(path)) for path in values}

def expected_log_path(folder):
    folder = Path(folder).absolute()
    need(folder.parent == STORE and folder.name == environment()[1].safe_id(folder.name),
        "complete_exact_transaction_log_route")
    return LOG_ROOT/folder.name/"engine.log"

def arguments(log, route=None):
    route = _ROUTE if route is None else route
    need(route in LAUNCH_ROUTES, "complete_explicit_launch_route_required")
    # Explicitly enable the native loopback console. A port alone does not
    # establish command access when a modal Panorama layer captures the GUI.
    # This adds one launch token only; diagnostics still verify process/port
    # ownership and never imply native acceptance or transaction permission.
    return ["-steam","-novid","-console","-vconsole","-vconport",str(PORT),"-condebug","-con_logfile",str(log),
        "+sv_cheats","0","+survival_archive_http_enabled","1",
        "+net_showmsg","CUserMsg_CustomGameEvent","+net_restrict_showmsg_socket","client"] + (
        ["+dota_launch_custom_game","3824360109","ws4_entry"] if route == "direct" else [])

def fixed_paths():
    b, p, _ = environment()
    need(p.INSTALLED == ROOT.parents[4]/"workshop/content/570/3824360109"
        and p.STORE == STORE and p.PORT == PORT, "complete_fixed_install_store_port_changed")
    for path in (p.INSTALLED, STORE, LOG_ROOT): p.regular(path, exists=False)
    need(p.INSTALLED.anchor.casefold() == STORE.anchor.casefold(), "complete_same_volume_switch_required")
    b.inc.disjoint([p.INSTALLED, STORE, LOG_ROOT, b.VIEW, b.OUTPUT, b.BASE])

def require_rows(folder, expected):
    _, p, _ = environment(); wanted = names(expected)
    folder = p.regular(folder)
    need(folder.is_dir() and {v.name for v in folder.iterdir()} == set(wanted),
        "complete_exact_package_folder_required")
    need([p.row(folder/name) for name in wanted] == expected, "complete_package_byte_mismatch")

def full_vpk(folder, manifest):
    b, _, _ = environment()
    with b.scene_maps(): return b.pack.verify_vpk(Path(folder)/(b.ITEM+".vpk"), manifest)

def package_auth(expected_sha, *, full=True):
    b, p, _ = environment()
    report, manifest, signed = b.load_package(expected_sha, full=full)
    need(signed.get("signature_valid") is True and signed.get("release_sequence") == report["release_sequence"]
        and report["content_sha256"] == manifest["content_sha256"], "complete_signed_candidate_required")
    p.NAMES = tuple(names(report["package_files"])); p.ORDER = (*p.NAMES[1:], p.NAMES[0])
    source_binding(report, expected_sha)
    return report, manifest

def acf_item():
    b, p, _ = environment(); path = p.regular(p.ACF)
    need(path.stat().st_size <= 4*1024*1024, "complete_bounded_acf_required")
    raw = path.read_bytes(); value = b.pack.handoff.kv(raw.decode("utf-8-sig"))["appworkshop"]
    item = value["workshopitemsinstalled"][b.ITEM]
    need(value.get("appid") == "570" and item.get("manifest") == BASE_MANIFEST,
        "complete_original_official_acf_required_never_rewrite")
    return dict(item=item, raw_sha256=hashlib.sha256(raw).hexdigest())

def load_transaction(identifier, report_sha, *, full=False):
    report, manifest = package_auth(report_sha, full=full)
    b, p, _ = environment(); fixed_paths(); folder = p.directory(identifier)
    value = p.json_read(folder/"transaction.json")
    need(value.get("schema") == 1 and value.get("kind") == KIND and value.get("transaction_id") == identifier
        and value.get("candidate_files") == report["package_files"] and value.get("code_pins") == own_code_pins()
        and all(value.get(k) == v for k,v in _CONTEXT.items())
        and value.get("installed") == str(p.INSTALLED), "complete_rehearsal_transaction_changed")
    parent, _ = b.baseline(full=False, require_current_journal=False)
    need(value.get("original_files") == parent["package_files"], "complete_rehearsal_original_binding_changed")
    return folder, value, report, manifest

def live_record(folder, transaction):
    global _ROUTE
    _, p, _ = environment(); live = p.json_read(Path(folder)/"process.json")
    need(live.get("kind") == KIND and live.get("owned_launch") is True
        and live.get("launch_route") in LAUNCH_ROUTES
        and live.get("argv") == arguments(Path(live["log_file"]),live["launch_route"])
        and live.get("log_file") == str(expected_log_path(folder))
        and live.get("log_origin") == "DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT"
        and live.get("code_pins") == own_code_pins() == transaction["code_pins"]
        and all(live.get(k) == v for k,v in _CONTEXT.items())
        and type(live.get("native_created_filetime")) is int
        and type(live.get("keeper",{}).get("native_created_filetime")) is int,
        "complete_owned_ordinary_process_binding_changed")
    need(_ROUTE is None or _ROUTE == live["launch_route"], "complete_live_route_changed")
    _ROUTE = live["launch_route"]
    return live

def copy_set(source, destination, rows):
    _, p, _ = environment()
    destination = p.regular(destination, exists=False)
    need(not destination.exists(), "complete_new_staging_folder_required")
    destination.mkdir()
    for row in rows: p.copy_new(Path(source)/row["name"],destination/row["name"],row)
    require_rows(destination, rows)

def switch_directory(installed, ready, retained, old_rows, new_rows):
    """Two exact directory renames; preserve both sides on every failure."""
    _, p, _ = environment()
    installed,ready,retained = [p.regular(path,exists=False) for path in (installed,ready,retained)]
    need(installed.anchor.casefold() == ready.anchor.casefold() == retained.anchor.casefold(),
        "complete_same_volume_directory_switch_required")
    need(len({str(path.resolve()).casefold() for path in (installed,ready,retained)}) == 3
        and not retained.exists(), "complete_distinct_new_retained_folder_required")
    require_rows(installed,old_rows); require_rows(ready,new_rows)
    p.no_clients()
    os.rename(installed,retained)
    require_rows(retained,old_rows)
    # Failure leaves the original fully retained outside the mount and the new
    # complete ready set intact. Never merge, delete, overwrite or auto-retry.
    p.no_clients()
    os.rename(ready,installed)
    require_rows(installed,new_rows)

def stage(identifier, report_sha):
    report, manifest = package_auth(report_sha,full=True)
    b,p,_ = environment(); fixed_paths(); p.safe_id(identifier)
    STORE.mkdir(parents=True,exist_ok=True)
    with p.operation_lock():
        p.no_clients()
        parent, old_manifest = b.baseline(full=True,require_current_journal=True)
        require_rows(p.INSTALLED,parent["package_files"]); full_vpk(p.INSTALLED,old_manifest)
        before = acf_item(); folder = p.directory(identifier)
        need(not folder.exists(),"complete_exclusive_new_transaction_required")
        required = sum(row["bytes"] for row in report["package_files"]) + p.RESERVE
        need(shutil.disk_usage(STORE.anchor).free >= required,"complete_candidate_stage_space_required")
        folder.mkdir()
        for child in ("events","inspections"): (folder/child).mkdir()
        p.write_new(folder/"transaction.json",dict(schema=1,kind=KIND,transaction_id=identifier,
            installed=str(p.INSTALLED),release_sequence=report["release_sequence"],
            candidate_files=report["package_files"],original_files=parent["package_files"],
            original_content_sha256=parent["content_sha256"],original_release_sequence=parent["release_sequence"],
            acf=before,code_pins=own_code_pins(),publication_performed=False))
        copy_set(b.OUTPUT,folder/"candidate_ready",report["package_files"])
        full_vpk(folder/"candidate_ready",manifest)
        p.no_clients(); need(acf_item()==before,"complete_acf_changed_before_install")
        p.event(folder,"COMPLETE_DIRECTORY_SWITCH_INTENT")
        switch_directory(p.INSTALLED,folder/"candidate_ready",folder/"backup",
            parent["package_files"],report["package_files"])
        full_vpk(p.INSTALLED,manifest)
        need(acf_item()==before,"complete_acf_changed_during_install")
        p.write_new(folder/"installed.json",dict(status="COMPLETE_SIGNED_CANDIDATE_INSTALLED",
            observed_utc=p.stamp(),original_backup_preserved=True,acf_written=False,journal_written=False))
        return dict(status="COMPLETE_SIGNED_CANDIDATE_INSTALLED",transaction_id=identifier,
            report_sha256=report_sha,publication_performed=False)

def launch(identifier, report_sha, *, route):
    global _ROUTE
    need(route in LAUNCH_ROUTES and (_ROUTE is None or _ROUTE==route),"complete_single_explicit_launch_route_required")
    _ROUTE=route
    return environment()[2].launch(identifier,report_sha)

def inspect(identifier, report_sha, label):
    folder, tx, report, manifest = load_transaction(identifier,report_sha)
    b,p,_=environment();p.safe_id(label)
    with p.operation_lock():
        path=folder/"inspections"/(label+".json")
        need(not path.exists(),"complete_exclusive_new_inspection_required")
        live=live_record(folder,tx);p.owned(p.snapshot(),live)
        need(p.same_identity(p.process_details(live["keeper"]["pid"]),live["keeper"])
            and not (folder/"hold_end.json").exists() and not (folder/"hold_failed.json").exists(),
            "complete_continuous_keeper_required")
        with p.FiveHolds(p.INSTALLED) as held:
            require_rows(p.INSTALLED,report["package_files"])
            need(held.identities==live["held_files"],"complete_held_file_identity_changed")
            rows=[dict(name=name,**p.file_use_result(p.restart_manager_users(p.INSTALLED/name),live,live["keeper"]))
                for name in p.NAMES]
            p.owned(p.snapshot(),live)
            need(acf_item()["item"]==tx["acf"]["item"],"complete_acf_changed")
        raw=p.regular(Path(live["log_file"])).read_bytes()
        need(len(raw)<=64*1024*1024,"complete_bounded_engine_log_required")
        value=dict(schema=1,kind=KIND,status="NATIVE_FILE_USE_OBSERVATION_NOT_GAMEPLAY_ACCEPTANCE",
            observed_utc=p.stamp(),release_sequence=report["release_sequence"],
            process={k:live[k] for k in ("pid","created_utc","command_line_sha256","native_created_filetime")},
            keeper=live["keeper"],candidate_files=report["package_files"],held_files=live["held_files"],file_use=rows,
            external_signed_manifest_binding=True,external_signed_resources_verified=manifest["file_count"],
            external_protected_modules_verified=report["protected_modules_verified"],
            index_owned_dota_use_observed=rows[0]["owned_dota_uses_file"],
            data_volumes_used=all(row["owned_dota_uses_file"] and row["owned_keeper_uses_file"] for row in rows[1:]),
            engine_log_sha256=hashlib.sha256(raw).hexdigest(),official_download=False,production_gameplay_verified=False)
        p.write_new(path,value)
        return dict(status=value["status"],receipt=str(path),data_volumes_used=value["data_volumes_used"])

def close(identifier, report_sha):
    # Frozen v03 closes the exact native HWND via one WM_CLOSE, retains process
    # creation identity, never VCon quit, kill or repeated fallback.
    return environment()[2].r.close(identifier,report_sha)

def restore(identifier, report_sha):
    folder,tx,report,manifest=load_transaction(identifier,report_sha,full=True)
    b,p,_=environment()
    with p.operation_lock():
        p.no_clients();need(not (folder/"restored.json").exists(),"complete_restore_is_not_replayed")
        need(acf_item()["item"]==tx["acf"]["item"],"complete_acf_changed_before_restore")
        if (folder/"process.json").exists():
            live=live_record(folder,tx)
            need((folder/"hold_end.json").is_file() and not (folder/"hold_failed.json").exists()
                and not p.same_identity(p.process_details(live["keeper"]["pid"]),live["keeper"]),
                "complete_retained_process_exit_and_keeper_release_required")
        parent,old=b.baseline(full=True,require_current_journal=False)
        backup=folder/"backup"
        if not backup.exists():
            # A failed stage before the original-directory rename made no
            # install switch. Verify the actual parent and preserve its partial
            # ready folder; this is recovery, never native acceptance.
            need(not (folder/"process.json").exists(),"complete_launched_transaction_missing_backup")
            require_rows(p.INSTALLED,parent["package_files"]);full_vpk(p.INSTALLED,old)
            p.write_new(folder/"restored.json",dict(status="COMPLETE_STAGE_NO_INSTALL_SWITCH_RECOVERED",
                observed_utc=p.stamp(),original_files=parent["package_files"],
                original_content_sha256=parent["content_sha256"],acf_written=False,
                canonical_journal_written=False,backups_preserved=True,
                partial_candidate_preserved=True,publication_performed=False))
            return dict(status="COMPLETE_STAGE_NO_INSTALL_SWITCH_RECOVERED",publication_performed=False)
        require_rows(backup,parent["package_files"]);full_vpk(backup,old)
        ready=folder/"restore_ready";retained=folder/"retained_candidate"
        if p.INSTALLED.exists():
            # A successfully switched restore whose final receipt write failed
            # may be explicitly resumed, but unknown/mixed bytes never qualify.
            try:require_rows(p.INSTALLED,parent["package_files"]);already_original=True
            except ValueError:already_original=False
        else:already_original=False
        if not already_original:
            if ready.exists():require_rows(ready,parent["package_files"])
            else:
                need(shutil.disk_usage(STORE.anchor).free>=sum(v["bytes"] for v in parent["package_files"])+p.RESERVE,
                    "complete_restore_staging_space_required")
                copy_set(backup,ready,parent["package_files"])
            full_vpk(ready,old);p.no_clients()
            if p.INSTALLED.exists():
                require_rows(p.INSTALLED,report["package_files"])
                switch_directory(p.INSTALLED,ready,retained,report["package_files"],parent["package_files"])
            else:
                # Explicit recovery of a two-rename gap. The old directory is
                # intact in backup and the exercised/new candidate is retained.
                if retained.exists():require_rows(retained,report["package_files"])
                else:
                    candidate=folder/"candidate_ready"
                    require_rows(candidate,report["package_files"])
                    os.rename(candidate,retained)
                p.no_clients();os.rename(ready,p.INSTALLED)
        require_rows(retained,report["package_files"])
        p.no_clients();require_rows(p.INSTALLED,parent["package_files"]);full_vpk(p.INSTALLED,old)
        need(acf_item()["item"]==tx["acf"]["item"],"complete_acf_changed_after_restore")
        p.write_new(folder/"restored.json",dict(status="ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED",
            observed_utc=p.stamp(),original_files=parent["package_files"],
            original_content_sha256=parent["content_sha256"],original_release_sequence=parent["release_sequence"],
            original_steam_manifest=BASE_MANIFEST,backups_preserved=True,candidate_preserved=True,
            canonical_journal_written=False,acf_written=False,publication_performed=False))
        return dict(status="ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED",publication_performed=False)

def static_plan():
    return dict(status="STATIC_COMPLETE_ORDINARY_REHEARSAL_PLAN_NO_EFFECTS",workshop_id="3824360109",
        external_store=str(STORE),port=PORT,actions=["stage","launch","inspect","close","restore"],
        full_package_set="DYNAMIC_FROM_AUTHENTICATED_SIGNED_REPORT",sdk_initialized=False,files_written=0)

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",nargs="?",default="plan",choices=["plan","stage","launch","inspect","close","restore"])
    parser.add_argument("--transaction");parser.add_argument("--report-sha256");parser.add_argument("--label")
    parser.add_argument("--route",choices=LAUNCH_ROUTES);args=parser.parse_args(argv)
    if args.action=="plan":
        need(not any((args.transaction,args.report_sha256,args.label,args.route)),"complete_plan_has_no_mutation_inputs")
        print(json.dumps(static_plan()));return 0
    need(args.transaction and args.report_sha256,"complete_explicit_transaction_and_report_required")
    if args.action=="launch":value=launch(args.transaction,args.report_sha256,route=args.route)
    elif args.action=="inspect":value=inspect(args.transaction,args.report_sha256,args.label)
    else:
        need(args.route is None and args.label is None,"complete_unrelated_action_inputs_rejected")
        value=globals()[args.action](args.transaction,args.report_sha256)
    print(json.dumps(value));return 0

if __name__=="__main__":raise SystemExit(main())
