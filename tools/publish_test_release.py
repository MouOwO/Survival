"""Verify a signed candidate and prepare a NEW, isolated four-account test addon.

Default operation is read-only. This tool never uploads to Workshop, changes
Steam settings, rewrites a signed candidate, or overwrites an existing addon.
The trusted public key and rollback floor come from this checkout, not input.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT.parents[2]
SECURITY = ROOT / "tools/release_security"
for folder in (ROOT / "tools", SECURITY):
    if str(folder) not in sys.path:
        sys.path.insert(0, str(folder))

import build_runtime_release as runtime
import protect_data
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

POLICY = SECURITY / "protection_policy.json"
MANIFEST = "_release_manifest.json"
SIGNATURE = "_release_signature.json"
ACCESS_FILE = "scripts/vscripts/config/test_access.lua"
GATE_FILES = (
    "scripts/vscripts/core/test_access_policy.lua",
    "scripts/vscripts/addon_game_mode.lua",
    "scripts/vscripts/systems/multiplayer_player_service.lua",
    "scripts/vscripts/systems/startup_loading_service.lua",
    "scripts/vscripts/systems/player_profile_service.lua",
    "scripts/vscripts/ui/ui_request_router.lua",
    "scripts/vscripts/core/event_bus.lua",
)
STEAM_BASE = 76561197960265728
WINDOWS_PUBLISH_PATH_MAX = 259  # MAX_PATH includes its terminating NUL.


def decode_json(raw: bytes):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON field: " + key)
            result[key] = value
        return result
    return json.loads(raw.decode("utf-8-sig"), object_pairs_hook=unique)


def load_json(path: Path):
    return decode_json(path.read_bytes())


def regular_path(path: Path, *, must_exist: bool = True) -> Path:
    """Reject even an in-root junction; resolve only after inspecting ancestors."""
    if not path.is_absolute():
        raise ValueError("An explicit absolute path is required")
    if must_exist and not path.exists():
        raise ValueError("Required path does not exist: " + str(path))
    for entry in (path, *path.parents):
        if entry.exists() and protect_data.linked(entry):
            raise ValueError("Links and junctions are forbidden: " + str(entry))
    return path.resolve(strict=must_exist)


def steamids(value) -> list[str]:
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError("Exactly four tester SteamID64 values are required")
    if any(not isinstance(sid, str) or not re.fullmatch(r"[0-9]{17}", sid)
           or not STEAM_BASE < int(sid) <= STEAM_BASE + 0xFFFFFFFF for sid in value):
        raise ValueError("Testers must be valid individual SteamID64 strings")
    if len(set(value)) != 4:
        raise ValueError("The four tester SteamID64 values must be distinct")
    return sorted(value)


def kv(text: str) -> dict:
    """Parse the small quoted-string KeyValues grammar used by addoninfo.txt."""
    pattern = re.compile(r'\s+|//[^\r\n]*|"(?:[^"\\]|\\.)*"|[{}]')
    tokens, position = [], 0
    while position < len(text):
        match = pattern.match(text, position)
        if match is None:
            raise ValueError("Unsupported addoninfo syntax")
        position = match.end()
        token = match.group()
        if not token.isspace() and not token.startswith("//"):
            tokens.append(token)

    def object_at(index, nested=False):
        result = {}
        while index < len(tokens):
            if tokens[index] == "}":
                if not nested:
                    raise ValueError("Unexpected addoninfo closing brace")
                return result, index + 1
            key = tokens[index]
            if not key.startswith('"') or index + 1 >= len(tokens):
                raise ValueError("Invalid addoninfo key")
            key = json.loads(key).casefold()
            if key in result:
                raise ValueError("Duplicate addoninfo key: " + key)
            token = tokens[index + 1]
            if token == "{":
                value, index = object_at(index + 2, True)
            elif token.startswith('"'):
                value, index = json.loads(token), index + 2
            else:
                raise ValueError("Invalid addoninfo value")
            result[key] = value
        if nested:
            raise ValueError("Missing addoninfo closing brace")
        return result, index
    result, _ = object_at(0)
    return result


def require_single_map(candidate: Path) -> None:
    data = kv(protect_data.source_path(candidate, "addoninfo.txt").read_text(encoding="utf-8-sig"))
    info = data.get("addoninfo")
    if not isinstance(info, dict) or info.get("maps") != "template_map" or info.get("isplayable") != "1":
        raise ValueError("Only template_map may be exposed as a playable map")
    if not isinstance(info.get("template_map"), dict) or info["template_map"].get("maxplayers") != "4":
        raise ValueError("template_map must declare MaxPlayers 4")


def configured_ids(candidate: Path) -> list[str]:
    """Accept only the agreed literal Lua whitelist, never execute supplied Lua."""
    raw = protect_data.source_path(candidate, ACCESS_FILE).read_text(encoding="utf-8-sig")
    # Keep configuration auditable: comments, strings, booleans and a literal
    # table only; arbitrary statements or a dynamically computed list fail.
    token_re = re.compile(r'\s+|--[^\r\n]*|"[^"\\\r\n]*"|[A-Za-z_][A-Za-z_0-9]*|[{}=,;]')
    values, offset = [], 0
    while offset < len(raw):
        match = token_re.match(raw, offset)
        if not match:
            raise ValueError("Test access configuration must be a literal Lua table")
        offset = match.end()
        token = match.group()
        if token.startswith("--"):
            if token.startswith("--["):
                raise ValueError("Block comments are unsupported in test access configuration")
        elif not token.isspace():
            values.append(token)
    # Field order is immaterial; duplicate/unknown fields are not accepted.
    if len(values) < 5 or values[:2] != ["return", "{"]:
        raise ValueError("Missing literal test access table")
    if values[-1:] == [";"]:
        values.pop()
    if values[-1:] != ["}"]:
        raise ValueError("Invalid test access table ending")
    fields, index, end = {}, 2, len(values) - 1
    while index < end:
        name = values[index]
        if name in fields or name not in {"enabled", "allowed_steamids"} or values[index + 1:index + 2] != ["="]:
            raise ValueError("Unknown or duplicate test access field")
        index += 2
        if name == "enabled":
            fields[name] = values[index]
            index += 1
        else:
            if values[index] != "{":
                raise ValueError("Tester list must be literal")
            index += 1
            members = []
            while index < end and values[index] != "}":
                token = values[index]
                if not (token.startswith('"') and token.endswith('"')):
                    raise ValueError("Tester IDs must be double-quoted SteamID64 strings")
                members.append(token[1:-1]); index += 1
                if values[index] == ",":
                    index += 1
                elif values[index] != "}":
                    raise ValueError("Invalid tester list separator")
            if index >= end:
                raise ValueError("Unterminated tester list")
            fields[name] = members
            index += 1
        if index < end and values[index] in {",", ";"}:
            index += 1
        elif index != end:
            raise ValueError("Invalid test access field separator")
    if fields.get("enabled") != "true":
        raise ValueError("Restricted test access must be enabled in the signed candidate")
    return steamids(fields.get("allowed_steamids"))


def require_reviewed_gate(candidate: Path, manifest: dict) -> None:
    """Bind admission and all late-request guards to this reviewed checkout.

    Merely finding a require string or enabled whitelist would not prove the
    server actually calls a gate. These modules currently ship unchanged;
    if protected later, bind the audited protection report's output instead.
    """
    entries = {row["path"]: row for row in manifest["files"]}
    for relative in (*GATE_FILES, ACCESS_FILE):
        if relative not in entries:
            raise ValueError("Signed candidate is missing an admission guard: " + relative)
    for relative in GATE_FILES:
        trusted = protect_data.source_path(ROOT, relative)
        current = protect_data.source_path(candidate, relative)
        if runtime.digest(current) != runtime.digest(trusted):
            raise ValueError("Candidate admission/late-request guard differs from reviewed source: " + relative)


def destination_paths(addon_name: str, install: Path) -> tuple[Path, Path]:
    if not re.fullmatch(r"(?:survival_test_[a-z0-9_]{1,60}|svt_[a-z0-9]{1,8})", addon_name):
        raise ValueError("Use a new isolated addon name: survival_test_ plus lowercase letters/digits/underscores, or svt_ plus 1-8 lowercase letters/digits")
    install = regular_path(install)
    destinations = []
    for tree in ("game", "content"):
        parent = regular_path(install / tree / "dota_addons")
        target = regular_path(parent / addon_name, must_exist=False)
        if target.parent != parent or target.exists():
            raise ValueError("Refusing to replace an existing game/content addon")
        destinations.append(target)
    return tuple(destinations)


def require_publish_paths(game_target: Path, content_target: Path, manifest: dict) -> int:
    """Preflight final GUI/packer paths before creating or copying anything.

    Python can copy a longer Windows path that the native Workshop packer may
    not accept. Count UTF-16 characters, including supplementary characters as
    two, while keeping every byte in the signed runtime unchanged.
    """
    maximum = 0
    for target in (game_target, content_target,
                   *(game_target / row["path"] for row in manifest["files"])):
        length = len(str(target).encode("utf-16-le")) // 2
        if length > WINDOWS_PUBLISH_PATH_MAX:
            raise ValueError(
                f"Windows publish path exceeds {WINDOWS_PUBLISH_PATH_MAX} characters "
                f"(MAX_PATH compatibility): {length}: {target}. "
                "Use a safe short addon name such as svt_1022; do not alter signed resources.")
        maximum = max(maximum, length)
    return maximum


def trusted_policy(policy_path=POLICY) -> tuple[dict, Path]:
    policy = load_json(policy_path)
    integrity = policy.get("integrity", {})
    if (policy.get("schema") != 1 or policy.get("channel") != "production"
            or integrity.get("manifest_schema") != 2 or integrity.get("signature") != "Ed25519"
            or integrity.get("change_index") != "md5" or integrity.get("integrity_hash") != "sha256"
            or integrity.get("activation_requires_full_file_verification") is not True
            or type(integrity.get("minimum_release_sequence")) is not int
            or not 1 <= integrity["minimum_release_sequence"] < 2**64):
        raise ValueError("Invalid trusted production integrity policy")
    key_name = integrity.get("trusted_public_key")
    public_path = protect_data.source_path(ROOT, key_name)
    public = serialization.load_pem_public_key(public_path.read_bytes())
    if not isinstance(public, Ed25519PublicKey) or protect_data.public_id(public) != integrity.get("trusted_key_id"):
        raise ValueError("Pinned trusted public key identity mismatch")
    return policy, public_path


def prepare(candidate: Path, addon_name: str, testers: list[str], publish_mode: str,
            workshop_id: str | None, *, apply=False, install=INSTALL,
            policy_path=POLICY) -> dict:
    testers = steamids(testers)
    if publish_mode not in {"create", "update"}:
        raise ValueError("Explicitly select create or update; this tool never guesses the Workshop item")
    if ((publish_mode == "create" and workshop_id is not None)
            or (publish_mode == "update" and (not isinstance(workshop_id, str)
                                             or not re.fullmatch(r"[1-9][0-9]{0,19}", workshop_id)))):
        raise ValueError("Update requires the confirmed existing Workshop ID; create must have no ID")
    candidate = regular_path(candidate)
    if runtime.within(candidate, INSTALL) or runtime.within(ROOT, candidate):
        raise ValueError("Candidate must be external to the Dota installation and development addon")
    game_target, content_target = destination_paths(addon_name, install)
    if runtime.within(game_target, candidate) or runtime.within(content_target, candidate):
        raise ValueError("Candidate and destinations may not overlap")
    manifest_path = protect_data.source_path(candidate, MANIFEST)
    signature_path = protect_data.source_path(candidate, SIGNATURE)
    manifest_bytes = manifest_path.read_bytes()
    signature_bytes = signature_path.read_bytes()
    original_manifest = hashlib.sha256(manifest_bytes).hexdigest()
    original_signature = hashlib.sha256(signature_bytes).hexdigest()
    manifest = decode_json(manifest_bytes)
    decode_json(signature_bytes)  # Reject ambiguous duplicate fields before verification.
    runtime.validate_manifest(manifest)
    for row in manifest["files"]:
        protect_data.source_path(candidate, row["path"])
    max_publish_path = require_publish_paths(game_target, content_target, manifest)
    policy, public_path = trusted_policy(policy_path)
    if runtime.digest(manifest_path) != original_manifest or runtime.digest(signature_path) != original_signature:
        raise ValueError("Signed inventory changed before signature verification")
    signature = protect_data.verify_signature(manifest_path, signature_path, public_path,
                                              policy["integrity"]["minimum_release_sequence"])
    if (signature["content_sha256"] != manifest["content_sha256"]
            or runtime.digest(manifest_path) != original_manifest
            or runtime.digest(signature_path) != original_signature):
        raise ValueError("Signed inventory changed during signature verification")
    require_single_map(candidate)
    require_reviewed_gate(candidate, manifest)
    if configured_ids(candidate) != testers:
        raise ValueError("Signed candidate tester whitelist does not match the four supplied testers")
    verification = runtime.verify(candidate, manifest)
    if not verification["ok"]:
        raise ValueError("Candidate runtime failed full inventory/hash verification")
    if runtime.digest(manifest_path) != original_manifest or runtime.digest(signature_path) != original_signature:
        raise ValueError("Signed inventory changed during runtime verification")
    result = {"schema": 1, "kind": "isolated_workshop_test_handoff",
              "status": "VERIFIED_DRY_RUN", "dry_run": not apply,
              "source": str(candidate), "game_addon": str(game_target),
              "content_addon": str(content_target), "addon_name": addon_name,
              "publish_mode": publish_mode, "workshop_id": workshop_id,
              "content_sha256": manifest["content_sha256"],
              "release_sequence": signature["release_sequence"],
              "runtime_files": manifest["file_count"], "runtime_bytes": manifest["bytes"],
              "tester_count": 4, "testers_sha256": hashlib.sha256(runtime.canonical_bytes({"steamids": testers})).hexdigest(),
              "published_maps": ["template_map"], "max_players": 4,
              "windows_publish_paths_checked": True,
              "max_publish_path_length": max_publish_path,
              "publish_path_limit": WINDOWS_PUBLISH_PATH_MAX,
              "signature_valid": True, "full_hash_verification": True,
              "runtime_metadata_copied": False, "candidate_changed": False,
              "native_smoke_test": "NOT_RUN", "ready_for_upload": False,
              "workshop_upload_performed": False,
              "limitations": ["Four Steam accounts are restricted, not four physical computers.",
                              "Workshop visibility does not replace the server account whitelist.",
                              "Workshop Manager must explicitly target this isolated addon and the confirmed item.",
                              "Native smoke and downloaded Workshop package checks remain separate."]}
    if not apply:
        return result

    receipt_dir = ROOT / "output/release_test_handoff" / addon_name
    if receipt_dir.exists():
        raise ValueError("Handoff receipt already exists; use a new test addon name")
    stage = game_target.parent / ("." + addon_name + ".staging-" + uuid.uuid4().hex)
    stage.mkdir(exist_ok=False)
    # No bulk directory copy: only the authenticated, runtime-policy-checked
    # manifest entries cross into the uploadable game addon directory.
    for row in manifest["files"]:
        source = protect_data.source_path(candidate, row["path"])
        target = stage / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as read, target.open("xb") as write:
            shutil.copyfileobj(read, write, 1024 * 1024)
        if runtime.checksums(target) != {key: row[key] for key in ("bytes", "md5", "sha256")}:
            raise ValueError("Copied runtime file failed verification: " + row["path"])
    if (runtime.digest(manifest_path) != original_manifest or runtime.digest(signature_path) != original_signature
            or not runtime.verify(candidate, manifest)["ok"] or not runtime.verify(stage, manifest)["ok"]):
        raise ValueError("Source or staged runtime changed during handoff; hidden staging retained for investigation")
    require_single_map(stage)
    require_reviewed_gate(stage, manifest)
    if configured_ids(stage) != testers:
        raise ValueError("Staged account whitelist changed")
    # Atomic rename exposes only a completely verified runtime. Do not create
    # editable content that Tools could recompile over protected runtime Lua.
    if game_target.exists() or content_target.exists():
        raise ValueError("A target appeared during staging; refusing to replace it")
    os.rename(stage, game_target)
    content_target.mkdir(exist_ok=False)
    if not runtime.verify(game_target, manifest)["ok"]:
        raise ValueError("Final installed addon failed verification; do not upload it")
    result.update(status="INSTALLED_FOR_NATIVE_TEST_ONLY", dry_run=False)
    receipt_dir.mkdir(parents=True, exist_ok=False)
    (receipt_dir / MANIFEST).write_bytes(manifest_bytes)
    (receipt_dir / SIGNATURE).write_bytes(signature_bytes)
    result["receipt_directory"] = str(receipt_dir)
    runtime.atomic_write_json(receipt_dir / "handoff.json", result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--addon-name", required=True)
    parser.add_argument("--testers-json", type=Path, required=True,
                        help='External JSON object {"steamids": [four actual SteamID64 strings]}')
    parser.add_argument("--publish-mode", choices=("create", "update"), required=True)
    parser.add_argument("--workshop-id", help="Confirmed existing item ID; required only for update")
    parser.add_argument("--apply", action="store_true", help="Install NEW isolated game/content addon; never upload")
    args = parser.parse_args()
    try:
        config = load_json(regular_path(args.testers_json))
        if not isinstance(config, dict) or set(config) != {"steamids"}:
            raise ValueError("Tester JSON must contain only steamids")
        result = prepare(args.candidate, args.addon_name, config["steamids"], args.publish_mode,
                         args.workshop_id, apply=args.apply)
    except Exception as error:
        print(json.dumps({"status": "BLOCKED_DO_NOT_UPLOAD", "error": type(error).__name__ + ": " + str(error),
                          "workshop_upload_performed": False, "ready_for_upload": False}, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
