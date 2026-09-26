"""Package an explicit public-tools allowlist, never local credentials or environments."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

import aliyun_game_test_auth as auth
import aliyun_test_connection as tunnel

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "setup_aliyun_test_host.cmd", "launch_aliyun_test_game.cmd", "launch_aliyun_lan_host.cmd",
    "setup_hammer_backend.cmd",
    "tools/aliyun_local_config.py", "tools/aliyun_test_host.py", "tools/aliyun_lan_probe.py",
    "tools/aliyun_game_test_auth.py", "tools/aliyun_test_connection.py", "tools/hammer_backend_bridge.py",
    "tools/setup_aliyun_test_host.ps1", "tools/launch_aliyun_test_game.ps1",
    "tools/launch_aliyun_lan_host.ps1", "tools/setup_hammer_backend.ps1", "tools/run_hammer_backend.ps1",
    "tools/map_c6/console.cjs", "tools/map_c6/console-relay.cjs", "tools/deploy/goufayu_test_known_hosts",
    "tools/test_aliyun_local_config.py", "tools/test_aliyun_test_host.py", "tools/test_aliyun_lan_probe.py",
    "tools/test_aliyun_game_test_auth.py", "tools/test_aliyun_test_connection.py",
    "tools/test_hammer_backend_bridge.py", "tools/test_setup_aliyun_test_host.py",
    "tools/test_launch_aliyun_test_game.py", "tools/build_test_host_bundle.py",
    "docs/NEW_PC_LAN_TEST_GUIDE.md", "docs/ALIYUN_TEST_MIGRATION.md",
)


def build() -> dict:
    target = ROOT / "output/test_host_bundle/goufayu_test_host_tools.zip"
    auth.no_reparse(target)
    tunnel.verify_known_hosts(ROOT / "tools/deploy/goufayu_test_known_hosts")
    payload = {}
    for name in FILES:
        source = ROOT / name
        auth.no_reparse(source)
        data = source.read_bytes()
        if re.search(rb"(?m)^[ \t]*-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----[ \t\r]*$", data):
            raise RuntimeError("private_key_material_refused")
        payload[name] = data
    revision = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                              capture_output=True, check=True, timeout=10)
    manifest = {"format": 1, "kind": "public_tools_overlay_not_complete_game",
                "base_git_commit": revision.stdout.decode("ascii").strip(),
                "includes_current_working_files": True,
                "files": {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}}
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in payload.items():
            archive.writestr(name, data)
        archive.writestr("TEST_HOST_TOOLS_MANIFEST.json", json.dumps(manifest, indent=2) + "\n")
    with zipfile.ZipFile(target) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(FILES) | {"TEST_HOST_TOOLS_MANIFEST.json"}:
            raise RuntimeError("bundle_verification_failed")
        for name, expected in manifest["files"].items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise RuntimeError("bundle_checksum_failed")
    return {"ok": True, "path": str(target), "public_files": len(FILES),
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bytes": target.stat().st_size}


if __name__ == "__main__":
    print(json.dumps(build(), ensure_ascii=False, indent=2))
