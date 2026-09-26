"""Local developer-machine paths only; this file never reads a credential value.

The ignored JSON file is deliberately limited to three file paths. Credentials,
server addresses, and SSH security options cannot be supplied through it.
"""
from __future__ import annotations

import json
import os
from pathlib import Path, PureWindowsPath
import stat
import tempfile


ROOT = Path(__file__).resolve().parents[1]
LEGACY_ENVIRONMENT = Path("D:/survival_database/.env")
MAX_BYTES = 8192
PATH_KEYS = frozenset(("ssh_key", "environment", "known_hosts"))


class ConfigError(RuntimeError):
    """Fixed public error codes only; never include source JSON or file contents."""


def config_path(root: Path = ROOT) -> Path:
    return root / "output/ecs_backend_work/local_config.json"


def _no_reparse(path: Path) -> None:
    for candidate in (path, *path.parents):
        try:
            metadata = candidate.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, "st_file_attributes", 0) & 0x400:
            raise ConfigError("local_config_reparse_not_allowed")


def _defaults(root: Path) -> dict[str, Path]:
    old_hosts = root / "output/ecs_backend_work/ecs_hostkey_candidate.pub"
    return {
        "ssh_key": Path.home() / ".ssh/goufayu_ecs_ed25519_v2",
        "environment": LEGACY_ENVIRONMENT if LEGACY_ENVIRONMENT.is_file()
        else root / "output/ecs_backend_work/game-test.env",
        "known_hosts": old_hosts if old_hosts.is_file()
        else root / "tools/deploy/goufayu_test_known_hosts",
    }


def _path(value: object, root: Path) -> Path:
    if isinstance(value, Path):
        value = str(value)
    if (not isinstance(value, str) or not value or len(value) > 4096
            or value != value.strip() or any(ord(c) < 32 for c in value)
            or any(c in value for c in ('"', '<', '>', '|', '?', '*'))):
        raise ConfigError("local_config_path_invalid")
    windows = PureWindowsPath(value)
    # Reject device/UNC paths, alternate data streams and drive-relative paths.
    # Explicit local drive paths are portable between the PCs running this tool.
    if (windows.drive.startswith("\\\\") or (windows.drive and not windows.root)
            or ":" in value[2:] or (":" in value and not windows.drive)):
        raise ConfigError("local_config_path_invalid")
    path = Path(value)
    if not path.is_absolute():
        if windows.root or windows.drive or ".." in windows.parts or ".." in path.parts:
            raise ConfigError("local_config_path_invalid")
        path = root / path
    if path == config_path(root):
        raise ConfigError("local_config_path_invalid")
    return path


def _validate(value: object, root: Path, *, require_version: bool) -> dict[str, Path]:
    if not isinstance(value, dict) or set(value) - (PATH_KEYS | {"version"}):
        raise ConfigError("local_config_schema_invalid")
    if ((require_version or "version" in value)
            and (type(value.get("version")) is not int or value["version"] != 1)):
        raise ConfigError("local_config_version_invalid")
    return {name: _path(item, root) for name, item in value.items() if name in PATH_KEYS}


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ConfigError("local_config_schema_invalid")
        result[key] = value
    return result


def load(root: Path = ROOT) -> dict[str, Path]:
    """Resolve defaults and optional ignored configuration without reading secrets."""
    root = root.absolute()
    path = config_path(root)
    try:
        _no_reparse(path)
        result = _defaults(root)
        try:
            with path.open("rb") as handle:
                data = handle.read(MAX_BYTES + 1)
        except FileNotFoundError:
            return result
        if len(data) > MAX_BYTES:
            raise ConfigError("local_config_too_large")
        parsed = json.loads(data.decode("utf-8-sig"), object_pairs_hook=_unique_object)
        result.update(_validate(parsed, root, require_version=True))
        return result
    except ConfigError:
        raise
    except (OSError, ValueError, UnicodeError):
        raise ConfigError("local_config_read_failed") from None


def save(values: dict, root: Path = ROOT) -> dict[str, Path]:
    """Merge path settings and atomically save them; no server or process actions."""
    root = root.absolute()
    temporary = None
    try:
        update = _validate(values, root, require_version=False)
        result = load(root)
        result.update(update)
        data = (json.dumps({"version": 1, **{key: str(value) for key, value in result.items()}},
                           ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        if len(data) > MAX_BYTES:
            raise ConfigError("local_config_too_large")
        path = config_path(root)
        _no_reparse(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="wb", prefix="local_config.", suffix=".tmp",
                                         dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        _no_reparse(path)
        temporary.replace(path)
        temporary = None
        return result
    except ConfigError:
        raise
    except (OSError, ValueError, UnicodeError):
        raise ConfigError("local_config_write_failed") from None
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
