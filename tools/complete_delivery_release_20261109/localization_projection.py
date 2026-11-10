"""Exact historical localization projection with bounded Chinese-name additions.

The content/game historical trees already diverged before the two W changes.
Never overwrite game text with the whole content file. These fixed historical
full-byte mask hashes retain every other byte (including order/comments/newlines).
Both current Git sources, approved values and the complete game output are bound.
The original proof shape/kind remains compatible with older receipts. A new
optional, identical two-alias block is accepted only at the Tokens opening;
removing that exact approved block must restore the original full-byte masks.
No filesystem reads except this module's import identity; no producer relabeling.
"""
from __future__ import annotations
from copy import deepcopy
import hashlib
from pathlib import Path
import re

EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
KIND = "EXACT_REVIEWED_LOCALIZATION_TWO_TOKEN_PROJECTION"
MAX_BYTES = 256 * 1024
TOKENS = (
    "DOTA_Tooltip_ability_ability_survival_blademaster_agility_Description",
    "DOTA_Tooltip_ability_ability_survival_monkey_king_fury_Description",
)
# Independently reproduced from the two immutable pre-patch commits. This is
# deliberate exact-path review, not a filename/prefix-wide localization rule.
BASELINES = {
    "panorama/localization/addon_english.txt": {
        "game": {
            "revision": "58d1a6dcc6078cc90af354b275026070e853e1d7",
            "sha256": "0ce7c6a0d2358e31d8fb889f239f3835db17b0bd2c0a69cc1fe2a49725467870",
            "masked_sha256": "4439bc21514a4d9cf623e1afc07a98b197745dff9f3c2261814b83943e4fc1f6"
        },
        "content": {
            "revision": "7aa4bc71752df2b0085a893a85ad181f1144d22b",
            "sha256": "0fe395fc8328443882976622806183ea7afceac5886fa8e428f4a6587e057743",
            "masked_sha256": "6e10a3379d43fefa978f0a8d474088508cf9d333b4321e80dce772533d676a29"
        }
    },
    "panorama/localization/addon_schinese.txt": {
        "game": {
            "revision": "58d1a6dcc6078cc90af354b275026070e853e1d7",
            "sha256": "7abcfb2486caf5dbe383d6a04d2ea06e94316865983e001323de5645015e0c02",
            "masked_sha256": "2e28daa63c0cb52198ad5510e7768fa5ed62b26b729a856c10e96cd6bb5aba04"
        },
        "content": {
            "revision": "7aa4bc71752df2b0085a893a85ad181f1144d22b",
            "sha256": "a571719b47d5f1059189895978922cbe5b5026e98f6bc60edde1ed0a89f456f2",
            "masked_sha256": "45615dc25f21f5d4d586fb1a33a9946df59298ad9774a6b94c8b6f6c8b92b2ee"
        }
    },
    "resource/addon_english.txt": {
        "game": {
            "revision": "58d1a6dcc6078cc90af354b275026070e853e1d7",
            "sha256": "96192761c4e7650146b22ba04a17ae75954d1b7d60a8e8053629acfd7425d24d",
            "masked_sha256": "4012dd9086144592ed8b4a5417638feb77926c64f9afd0b9d16c6872108eab35"
        },
        "content": {
            "revision": "7aa4bc71752df2b0085a893a85ad181f1144d22b",
            "sha256": "96192761c4e7650146b22ba04a17ae75954d1b7d60a8e8053629acfd7425d24d",
            "masked_sha256": "4012dd9086144592ed8b4a5417638feb77926c64f9afd0b9d16c6872108eab35"
        }
    },
    "resource/addon_schinese.txt": {
        "game": {
            "revision": "58d1a6dcc6078cc90af354b275026070e853e1d7",
            "sha256": "e40d0dc982ac55801b70bbc5065d004b181e15bda7d855c0a317bcd5f0b5ee71",
            "masked_sha256": "8f7d7f1088f7170c1cfa37b6bf4b56191b457b8331faf033230a66e97ffb8250"
        },
        "content": {
            "revision": "7aa4bc71752df2b0085a893a85ad181f1144d22b",
            "sha256": "74815f6c8a46d6c6086c1a1b4bc138b2934b6376244724956e1ae6e492fa5f81",
            "masked_sha256": "d093528e9185d66c68191ccb9dd4100326ef38405e80a7d42a79c05a5dfb7573"
        }
    },
    "resource/localization/addon_english.txt": {
        "game": {
            "revision": "58d1a6dcc6078cc90af354b275026070e853e1d7",
            "sha256": "f8a0ed46b2eb08cc9f6a3a86de8ea5330b4cd008d702f6efb3525e718bae216c",
            "masked_sha256": "078a8d8df4bf4ab2cccc491228d950703abf305b46c9835a1a6be22b96302efb"
        },
        "content": {
            "revision": "7aa4bc71752df2b0085a893a85ad181f1144d22b",
            "sha256": "f8a0ed46b2eb08cc9f6a3a86de8ea5330b4cd008d702f6efb3525e718bae216c",
            "masked_sha256": "078a8d8df4bf4ab2cccc491228d950703abf305b46c9835a1a6be22b96302efb"
        }
    },
    "resource/localization/addon_schinese.txt": {
        "game": {
            "revision": "58d1a6dcc6078cc90af354b275026070e853e1d7",
            "sha256": "06509fca7d111ed3ffee54863c0d898744042777f9844436b490ff2c925de628",
            "masked_sha256": "c17b6eaf7f5b79373c9760bebdda1496d180dcc003add26405edb39213147cab"
        },
        "content": {
            "revision": "7aa4bc71752df2b0085a893a85ad181f1144d22b",
            "sha256": "75fd4d0c754ba46fb4c4d49ce938f1200b10ac1833401eaa6c8550120d8e7cc1",
            "masked_sha256": "e4ad4613a65ea84964db310832b124e268f338164357f8714d172dcf5399a307"
        }
    }
}
APPROVED_VALUE_SHA256 = {
    "english": {
        "DOTA_Tooltip_ability_ability_survival_blademaster_agility_Description": "d5a6cb70f9e4dc9c2125b303561c7a4773993d310c31989ac3205d4a8443b67c",
        "DOTA_Tooltip_ability_ability_survival_monkey_king_fury_Description": "b4cc64f21eac2cd6ce8a54e7f9209dc52a6a0de5cc020edd3a02933d2afeae04"
    },
    "schinese": {
        "DOTA_Tooltip_ability_ability_survival_blademaster_agility_Description": "8d77616b63380d54b72dca7d0971b91997a73d4e73f90af2dc7659a8277635fd",
        "DOTA_Tooltip_ability_ability_survival_monkey_king_fury_Description": "e0f0a965fbe273bc7686181bf8df7c28b0a9263a51d6324b79225fc16f93c89c"
    }
}
PATHS = frozenset(BASELINES)


def need(value, code):
    if not value:
        raise ValueError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def fingerprint(raw):
    return {"sha256": sha(raw), "bytes": len(raw), "md5": hashlib.md5(raw).hexdigest()}


TRAINING_NAME_BLOCK = (
    '        "building_endless_training_target" "长青轮纹"\n'
    '        "npc_dota_unit_building_endless_training_target" "长青轮纹"\n'
).encode("utf-8")
TRAINING_NAME_KEYS = (
    b'"building_endless_training_target"',
    b'"npc_dota_unit_building_endless_training_target"',
)


def _without_training_name(raw):
    counts = tuple(raw.count(key) for key in TRAINING_NAME_KEYS)
    if counts == (0, 0):
        return raw
    need(counts == (1, 1), "localization_training_name_alias_pair_required")
    opening = re.search(rb'(?m)^[ \t]*"Tokens"[ \t]*\n[ \t]*\{\n', raw)
    need(opening is not None, "localization_training_name_tokens_opening_required")
    start = opening.end()
    need(raw[start:start + len(TRAINING_NAME_BLOCK)] == TRAINING_NAME_BLOCK,
         "localization_training_name_value_or_layout_changed")
    return raw[:start] + raw[start + len(TRAINING_NAME_BLOCK):]


def _mask(raw):
    need(type(raw) is bytes and 0 < len(raw) <= MAX_BYTES, "localization_bounded_bytes_required")
    need(b"\r" not in raw and b"\x00" not in raw, "localization_exact_git_lf_required")
    raw.decode("utf-8-sig")  # reject malformed text; retain BOM and all raw bytes
    raw = _without_training_name(raw)
    values = {}
    masked = raw
    for token in TOKENS:
        expression = rb'(?m)^([ \t]*"' + token.encode("ascii") + rb'"[ \t]+")((?:\\.|[^"\\\r\n])*)("[ \t]*$)'
        matches = list(re.finditer(expression, masked))
        need(len(matches) == 1, "localization_exact_single_reviewed_token_required")
        found = matches[0]
        value = found.group(2)
        need(0 < len(value) <= 4096, "localization_bounded_value_required")
        values[token] = sha(value)
        masked = masked[:found.start(2)] + b"__REVIEWED_HERO_W_DESCRIPTION__" + masked[found.end(2):]
    return sha(masked), values


def verify_projection(path, content_raw, game_raw):
    """Pure full-byte proof, repeated by collector and independently by signer."""
    need(path in PATHS, "unreviewed_localization_projection_path")
    content_mask, content_values = _mask(content_raw)
    game_mask, game_values = _mask(game_raw)
    need((TRAINING_NAME_KEYS[0] in content_raw) == (TRAINING_NAME_KEYS[0] in game_raw),
         "localization_training_name_dual_source_required")
    language = path.rsplit("_", 1)[1][:-4]
    expected = APPROVED_VALUE_SHA256[language]
    need(content_values == game_values == expected, "localization_reviewed_values_or_projection_changed")
    need(content_mask == BASELINES[path]["content"]["masked_sha256"]
         and game_mask == BASELINES[path]["game"]["masked_sha256"],
         "localization_unreviewed_bytes_outside_two_tokens")
    return {"schema": 1, "kind": KIND, "resource": path, "baselines": deepcopy(BASELINES[path]),
            "masked_sha256": {"game": game_mask, "content": content_mask},
            "value_sha256": dict(content_values),
            "sources": {"game": fingerprint(game_raw), "content": fingerprint(content_raw)},
            "output": fingerprint(game_raw)}


def validate_metadata(path, proof, inputs, output, source_fingerprints):
    """Ledger shape checks; only verify_projection(actual bytes) proves content."""
    need(path in PATHS and isinstance(proof, dict), "localization_projection_proof_required")
    need(set(proof) == {"schema", "kind", "resource", "baselines", "masked_sha256", "value_sha256", "sources", "output"}
         and type(proof["schema"]) is int and proof["schema"] == 1
         and proof["kind"] == KIND and proof["resource"] == path, "localization_projection_schema_changed")
    expected_inputs = {"game:" + path, "content:" + path}
    need(set(inputs) == expected_inputs and set(source_fingerprints) == expected_inputs,
         "localization_exact_dual_source_binding_required")
    need(proof["baselines"] == BASELINES[path]
         and proof["masked_sha256"] == {role: BASELINES[path][role]["masked_sha256"] for role in ("game", "content")}
         and proof["value_sha256"] == APPROVED_VALUE_SHA256[path.rsplit("_", 1)[1][:-4]],
         "localization_reviewed_baseline_or_values_changed")
    expected_sources = {role: source_fingerprints[role + ":" + path] for role in ("game", "content")}
    need(proof["sources"] == expected_sources
         and all(inputs[role + ":" + path] == expected_sources[role]["sha256"] for role in expected_sources)
         and proof["output"] == output == expected_sources["game"], "localization_source_or_output_fingerprint_changed")
