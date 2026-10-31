"""On-demand repair of the existing fixed Steam TLS relay; no auth/data changes."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "output/steam_login_repair"
PROBE = r'''
import json,pathlib,socket,subprocess,sys,time,urllib.request
pid=subprocess.check_output(['systemctl','show','goufayu-ws4-web.service','--property=MainPID','--value'],text=True,timeout=5).strip()
assert pid.isdigit() and int(pid)>0,'web_service_not_running'
cwd=pathlib.Path('/proc/'+pid+'/cwd').resolve()
assert cwd.is_relative_to(pathlib.Path('/opt/goufayu-ws4-web/releases'))
env=dict(value.split(b'=',1) for value in pathlib.Path('/proc/'+pid+'/environ').read_bytes().split(b'\0') if b'=' in value)
enabled=env.get(b'PLAYER_WEB_AUTH_STEAM_TLS_RELAY',b'0')==b'1'
listener=subprocess.check_output(['ss','-ltnH','sport = :18768'],text=True,timeout=5)
result={'relay_enabled':enabled,'listener_present':any('127.0.0.1:18768' in line for line in listener.splitlines()),'web_health_ok':False,'steam_transport_ok':False,'invalid_assertion_rejected':False}
try:
 with urllib.request.urlopen('http://127.0.0.1:18767/health',timeout=3) as response:
  result['web_health_ok']=response.status==200 and json.load(response).get('ok') is True
except Exception:pass
if enabled and result['web_health_ok']:
 sys.path.insert(0,str(cwd))
 from player_web_auth.service import steam_check,AuthError
 started=time.monotonic()
 try:
  valid=steam_check({'openid.ns':'http://specs.openid.net/auth/2.0','openid.mode':'id_res'},tls_relay=True)
  result['steam_transport_ok']=True
  result['invalid_assertion_rejected']=valid is False
 except AuthError:pass
 result['probe_seconds']=round(time.monotonic()-started,2)
print(json.dumps(result))
'''


def load_relay():
    spec = importlib.util.spec_from_file_location("manual_steam_relay", Path(__file__).with_name("steam_tls_relay.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def remote_probe(relay):
    result = json.loads(relay.transport().remote(PROBE, timeout=35))
    keys = {"relay_enabled", "listener_present", "web_health_ok", "steam_transport_ok",
            "invalid_assertion_rejected"}
    if (not isinstance(result, dict) or not keys.issubset(result)
            or set(result) - keys - {"probe_seconds"}
            or any(type(result[key]) is not bool for key in keys)):
        raise RuntimeError("remote_check_invalid")
    return {key: result[key] for key in keys}  # No arbitrary remote output in the user receipt.


def local_state(relay):
    if not relay.RECEIPT.exists():
        return "missing"
    info = relay.RECEIPT.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_size > 4096 or relay.RECEIPT.is_symlink()
            or getattr(info, "st_file_attributes", 0) & 0x400):
        raise RuntimeError("relay_receipt_invalid")
    record = json.loads(relay.RECEIPT.read_text("utf8"))
    if not isinstance(record, dict) or type(record.get("pid")) is not int:
        raise RuntimeError("relay_receipt_invalid")
    try:
        observed = relay.process_identity(record["pid"])
    except RuntimeError as error:
        if str(error) == "relay_process_not_found":
            return "stale"
        raise
    if observed != record:
        raise RuntimeError("relay_process_identity_changed")
    return "running"


def recover(relay, probe, *, repair=False):
    state = local_state(relay)  # Identity failure must never be treated as a dead process.
    before = probe()
    def result(code, ok=False, changed=False, after=None):
        return {"ok": ok, "status": code, "local_state": state,
                "relay_restarted": changed, "before": before, "after": after}
    def ready(value):
        return (value["web_health_ok"] and value["relay_enabled"]
                and value["steam_transport_ok"] and value["invalid_assertion_rejected"])
    if ready(before):
        return result("READY", True)
    if not before["relay_enabled"]:
        return result("CLOUD_RELAY_DISABLED")
    if not before["web_health_ok"]:
        return result("CLOUD_AUTH_UNHEALTHY")
    if not repair:
        return result("RELAY_REPAIR_REQUIRED")
    if state != "running" and before["listener_present"]:
        return result("REMOTE_LISTENER_NOT_OWNED")
    if state != "missing":
        relay.stop()  # Existing helper rechecks creation time, image and exact fixed command.
    relay.start()  # Existing helper refuses a second receipt and pins SSH/TLS destinations.
    after = probe()
    return result("RELAY_RESTORED" if ready(after) else "STEAM_TRANSPORT_UNAVAILABLE",
                  ready(after), True, after)


@contextmanager
def exclusive_repair(path):
    import msvcrt
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as stream:
        if stream.seek(0, 2) == 0:
            stream.write(b"0"); stream.flush()
        stream.seek(0)
        try:
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise RuntimeError("repair_already_running") from None
        try:
            yield
        finally:
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)


MESSAGES = {
    "READY": "验签通路正常，无需重启。请从游戏重新打开授权页，重新点击 Steam 登录。",
    "RELAY_RESTORED": "Steam 验签通路已恢复。请从游戏重新打开授权页，重新点击 Steam 登录；不要刷新旧错误页。",
    "RELAY_REPAIR_REQUIRED": "验签通路不可用。请运行项目根目录的“修复Steam登录.cmd”。",
    "STEAM_TRANSPORT_UNAVAILABLE": "中转已启动，但仍无法连接 Steam。请检查或切换可用网络／加速节点，再运行一次。",
    "CLOUD_RELAY_DISABLED": "云端未启用该中转。工具不会修改开关，请保留此结果交给维护者。",
    "CLOUD_AUTH_UNHEALTHY": "云端登录服务不可用。工具不会重启后台服务，请保留此结果交给维护者。",
    "REMOTE_LISTENER_NOT_OWNED": "云端已有无法对应本机回执的中转。为避免影响其他进程，本次停止操作。",
    "REPAIR_BUSY": "另一个修复程序正在运行，请等待它完成。",
    "CHECK_FAILED": "检查未完成。请先确认网络／加速节点可用；若仍失败，请保留下方错误码。",
}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--repair", action="store_true")
    args = parser.parse_args(argv)
    print("正在检查 Steam 验签通路，请稍候（通常约 10～40 秒）……", flush=True)
    try:
        if os.name != "nt":
            raise RuntimeError("windows_required")
        with exclusive_repair(RUNTIME / "repair.lock"):
            relay = load_relay()
            result = recover(relay, lambda: remote_probe(relay), repair=args.repair)
            (RUNTIME / "last_result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), "utf8")
    except Exception as error:
        safe = {"repair_already_running", "relay_process_identity_changed", "relay_process_is_not_owned_forward",
                "relay_process_access_failed", "relay_receipt_invalid", "relay_ssh_start_failed",
                "relay_receipt_exists_review_before_start", "reviewed_remote_action_failed", "remote_check_invalid"}
        code = str(error) if isinstance(error, RuntimeError) and str(error) in safe else "manual_login_check_failed"
        result = {"ok": False, "status": "REPAIR_BUSY" if code == "repair_already_running" else "CHECK_FAILED", "error": code}
    print(MESSAGES[result["status"]])
    print("测试期间请保持这台电脑和可用网络在线。此工具不修改账号、存档、订单或云端配置。")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
