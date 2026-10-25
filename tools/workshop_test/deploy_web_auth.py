"""Deploy the isolated four-account web login sidecar with pinned SSH.

Each invocation performs exactly one explicit step. ``audit`` and ``verify``
are read-only; ``prepare`` never starts a service or exposes an HTTP route.
Credentials are generated on the host and never returned to this machine.
"""
import argparse
import base64
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODES = ("audit", "prepare", "configure-transport", "activate", "verify", "rollback")
RUNTIME_SOURCES = frozenset((
    "player_web_auth/__init__.py", "player_web_auth/http_api.py",
    "player_web_auth/run.py", "player_web_auth/service.py",
    "lobby_backend/__init__.py", "lobby_backend/http_api.py", "lobby_backend/service.py",
))


def collect_sources():
    server = ROOT / "server"
    result = {}
    for name in sorted(RUNTIME_SOURCES):
        path = server / name
        if any(parent.is_symlink() or getattr(parent, "is_junction", lambda: False)()
               for parent in (server, path.parent, path)):
            raise RuntimeError("web_auth_source_path_invalid")
        if not path.is_file():
            raise RuntimeError("web_auth_source_incomplete")
        if not path.resolve().is_relative_to(server.resolve()):
            raise RuntimeError("web_auth_source_path_invalid")
        raw = path.read_bytes()
        if len(raw) > 512 * 1024:
            raise RuntimeError("web_auth_source_too_large")
        compile(raw, name, "exec")
        result[name] = base64.b64encode(raw).decode("ascii")
    return result


def overlay():
    return collect_sources()


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=MODES)
    parser.add_argument("--steam-tls-relay", choices=("0", "1"),
                        help="Explicit transport setting; accepted only by configure-transport after rollback")
    args = parser.parse_args(argv)
    if args.mode == "configure-transport" and args.steam_tls_relay is None:
        parser.error("configure-transport requires --steam-tls-relay 0 or 1")
    if args.mode != "configure-transport" and args.steam_tls_relay is not None:
        parser.error("--steam-tls-relay is accepted only by configure-transport")
    return args


def main():
    args = arguments()
    spec = importlib.util.spec_from_file_location(
        "ws4_web_pinned_transport", ROOT / "tools/archive_caps_20261020/remote_driver.py")
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    source = "MODE=" + repr(args.mode) + "\nOVERLAY=" + repr(overlay() if args.mode == "prepare" else {}) + "\n"
    source += "STEAM_TLS_RELAY=" + repr(args.steam_tls_relay) + "\n"
    source += Path(__file__).with_name("remote_web_auth.py").read_text(encoding="utf-8")
    output = transport.remote(source, timeout=180)
    # The operator emits a fixed public summary, never HTTP bodies or env files.
    record = json.loads(output)
    directory = ROOT / "output/workshop_web_auth_20261024"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / (args.mode + ".json")).write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(record, ensure_ascii=False))


if __name__ == "__main__":
    main()
