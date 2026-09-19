"""Local consistent export, then a mandatory independently configured restic copy.

No retention pruning or database cleanup is performed. A missing/failed offsite
repository returns failure while retaining the successful local export.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import ipaddress
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
from urllib.parse import urlparse

RELEASE = Path(__file__).resolve().parents[1]
STATE = Path("/var/lib/goufayu/backup-status.json")
LOCK = Path("/var/lib/goufayu/backup.lock")


def write_status(state):
    temporary = STATE.with_suffix(".new")
    temporary.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    os.replace(temporary, STATE)


def offsite_host(repository):
    if repository.startswith("sftp:"):
        value = repository[len("sftp:"):]
        if value.startswith("//"):
            parsed = urlparse("sftp:" + value)
            if parsed.password or not parsed.path.startswith("/"):
                raise ValueError("offsite_repository_credentials_or_path_invalid")
            return parsed.hostname
        import re
        match = re.fullmatch(r"(?:[A-Za-z0-9_.-]+@)?(\[[0-9a-fA-F:]+\]|[A-Za-z0-9_.-]+):/[^\r\n]+", value)
        if match:
            return match[1].strip("[]")
    if repository.startswith("s3:"):
        parsed = urlparse(repository[len("s3:"):])
        if parsed.scheme == "https" and not parsed.username and not parsed.password and parsed.path.strip("/"):
            return parsed.hostname
    raise ValueError("offsite_requires_remote_sftp_or_https_s3_repository")


def resolved_addresses(host):
    try:
        return {ipaddress.ip_address(item[4][0].split("%")[0]) for item in socket.getaddrinfo(host, None)}
    except (OSError, ValueError):
        raise ValueError("offsite_hostname_cannot_resolve") from None


def interface_addresses():
    if not shutil.which("ip"):
        raise ValueError("iproute_required_to_verify_independent_offsite_host")
    try:
        result = subprocess.run(["ip", "-j", "address", "show"], check=True, capture_output=True, text=True)
        return {ipaddress.ip_address(address["local"].split("%")[0])
                for device in json.loads(result.stdout) for address in device.get("addr_info", [])}
    except Exception:
        raise ValueError("cannot_verify_local_interface_addresses") from None


def validate_offsite(repository):
    host = offsite_host(repository)
    if not host:
        raise ValueError("offsite_hostname_missing")
    local_names = {"localhost", socket.gethostname().lower().rstrip("."), socket.getfqdn().lower().rstrip(".")}
    local_names.update(value.strip().lower().rstrip(".") for value in os.environ.get("OFFSITE_EXCLUDED_HOSTS", "47.110.238.248").split(",") if value.strip())
    if host.lower().rstrip(".") in local_names:
        raise ValueError("repository_is_local_not_offsite")
    local_addresses = {ipaddress.ip_address("127.0.0.1"), ipaddress.ip_address("::1"), ipaddress.ip_address("47.110.238.248")}
    for name in local_names:
        try:
            local_addresses.update(resolved_addresses(name))
        except ValueError:
            continue
    # Capture interface addresses even when hostname resolves to only one NIC.
    local_addresses.update(interface_addresses())
    remote_addresses = resolved_addresses(host)
    if (not remote_addresses or remote_addresses & local_addresses or any(
            address.is_loopback or address.is_unspecified or address.is_link_local or address.is_multicast
            for address in remote_addresses)):
        raise ValueError("repository_is_local_not_offsite")


def main():
    if sys.platform != "linux" or os.geteuid() != 0:
        print("BACKUP_ERROR linux_root_required", file=sys.stderr); return 2
    import fcntl
    os.umask(0o077)
    with LOCK.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("BACKUP_ALREADY_RUNNING", file=sys.stderr); return 2
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        root = Path(os.environ.get("BACKUP_ROOT", "/var/backups/goufayu")).resolve()
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        destination = root / ("backup_" + stamp)
        state = {"time_utc": stamp, "local_export_ok": False, "offsite_ok": False, "backup": str(destination)}
        try:
            command = [sys.executable, str(RELEASE / "database/dbtool.py"), "--pg-bin",
                       os.environ.get("PG_BIN", str(RELEASE / "deploy/pg-bin")), "export",
                       "--source-service", os.environ.get("BACKUP_SERVICE", "goufayu_migrator"),
                       "--source-role", "goufayu_owner", "--output", str(destination)]
            subprocess.run(command, check=True)
            state["local_export_ok"] = True
            write_status(state)
            if os.environ.get("OFFSITE_REQUIRED", "1") != "1":
                raise ValueError("offsite_required_must_equal_1")
            repository = os.environ.get("RESTIC_REPOSITORY", "")
            password_file = os.environ.get("RESTIC_PASSWORD_FILE", "")
            if not repository or not password_file or not Path(password_file).is_file() or not shutil.which("restic"):
                state["error"] = "offsite_not_configured"
                write_status(state)
                print("LOCAL_BACKUP_OK; OFFSITE_NOT_CONFIGURED", file=sys.stderr)
                return 1
            validate_offsite(repository)
            info = Path(password_file).stat()
            if info.st_uid != 0 or info.st_mode & 0o077:
                raise ValueError("restic_password_requires_root_0600")
            # Do not initialize an unknown repository or silently change backup ownership.
            subprocess.run(["restic", "snapshots", "--json"], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["restic", "backup", str(destination), "--tag", "goufayu-postgresql17", "--quiet"], check=True)
            # Ensure repository metadata can be read after uploading; full restore is separate.
            subprocess.run(["restic", "check"], check=True)
            state["offsite_ok"] = True
            write_status(state)
            print("LOCAL_EXPORT_AND_ENCRYPTED_OFFSITE_COPY_OK (restore drill is separate)")
            return 0
        except Exception as error:
            state["error"] = str(error) if type(error) is ValueError else type(error).__name__
            write_status(state)
            print("BACKUP_FAILED; inspect /var/lib/goufayu/backup-status.json; local files retained", file=sys.stderr)
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
