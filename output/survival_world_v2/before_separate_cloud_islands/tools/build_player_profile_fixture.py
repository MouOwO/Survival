"""Validate the local player-profile JSON fixture and wrap it as generated Lua."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "mock" / "player_profiles.json"
TARGET = ROOT / "scripts" / "vscripts" / "config" / "fixtures" / "player_profiles.lua"


def lua_escape(value: str) -> str:
    return (value.replace("\\", "\\\\")
                 .replace('"', '\\"')
                 .replace("\r", "\\r")
                 .replace("\n", "\\n"))


def build(source: Path = SOURCE, target: Path = TARGET) -> str:
    raw = source.read_text(encoding="utf-8")
    parsed = json.loads(raw)
    if parsed.get("schema_version") != 1:
        raise ValueError("player profile fixture schema_version must be 1")
    profiles = parsed.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise ValueError("player profile fixture requires non-empty profiles")
    for account_id, profile in profiles.items():
        if not isinstance(account_id, str) or not account_id:
            raise ValueError("fixture account_id must be non-empty string")
        if not isinstance(profile, dict) or not isinstance(profile.get("revision"), int):
            raise ValueError(f"fixture profile revision invalid: {account_id}")
    canonical = json.dumps(parsed, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    output = "\n".join([
        "-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.",
        "-- Source: data/mock/player_profiles.json",
        "local M = {}",
        f'M.json = "{lua_escape(canonical)}"',
        "return M",
        "",
    ])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(output, encoding="utf-8", newline="\n")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--target", type=Path, default=TARGET)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    target = args.target.resolve()
    if args.check:
        before = target.read_text(encoding="utf-8") if target.exists() else None
        expected_target = target.with_suffix(target.suffix + ".check")
        try:
            expected = build(source, expected_target)
        finally:
            if expected_target.exists():
                expected_target.unlink()
        if before != expected:
            raise SystemExit("PLAYER_PROFILE_FIXTURE_GENERATED_MISMATCH")
        print("PLAYER_PROFILE_FIXTURE_GENERATED_MATCH_PASS")
        return
    build(source, target)
    print(f"PLAYER_PROFILE_FIXTURE_GENERATED path={target}")


if __name__ == "__main__":
    main()
