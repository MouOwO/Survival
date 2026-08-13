from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv"
TARGETS = (
    (ROOT / "resource/addon_schinese.txt", "schinese"),
    (ROOT / "resource/localization/addon_schinese.txt", "schinese"),
    (ROOT / "panorama/localization/addon_schinese.txt", "schinese"),
    (ROOT / "resource/addon_english.txt", "english"),
    (ROOT / "resource/localization/addon_english.txt", "english"),
    (ROOT / "panorama/localization/addon_english.txt", "english"),
)

ENGLISH = {
    **{
        f"lightning_strike_lv{level:02d}": (
            f"Chains through up to {targets} enemies. The first target takes 100% "
            "physical attack damage; every 0.1 seconds it jumps to the closest unhit "
            "enemy within 400 of the previous target, losing 10% damage per jump."
        )
        for level, targets in enumerate((4, 5, 6, 7, 7), 1)
    },
    **{
        f"lightning_storm_lv{level:02d}": (
            "When Lightning Strike kills an enemy, it immediately deals physical damage "
            f"equal to {multiplier}% of the tower's attack snapshot to all enemies within "
            f"500 of the death point. Then {strikes} visual-only lightning pillars strike "
            "at random over 1 second."
        )
        for level, (multiplier, strikes) in enumerate(
            ((110, 5), (120, 6), (130, 7), (140, 8), (150, 9)), 1
        )
    },
    **{
        f"laser_lv{level:02d}": (
            f"Deals {multiplier}% attack damage every 1 second. Damage to the same "
            "target rises by 5% each second, up to 500%."
        )
        for level, multiplier in enumerate((100, 120, 140, 160, 180), 1)
    },
    "lightning_diffusion_lv01": (
        "Lightning Storm hits have a 30% chance to release an electric ring, dealing "
        "200% of that hit as physical damage in a 200 radius. The ring cannot recurse."
    ),
    **{
        f"frost_attack_lv{level:02d}": (
            f"Attacks deal physical damage in a {radius} radius and slow enemies by 25% "
            "for 2 seconds."
        )
        for level, radius in enumerate((100, 150, 200, 250, 250), 1)
    },
    **{
        f"ice_blizzard_lv{level:02d}": (
            f"Attacks have a {chance}% chance to trigger a 5-second blizzard that deals "
            f"50% of the triggering attack as physical damage each second in a {radius} "
            "radius and slows enemies by 25%."
        )
        for level, (chance, radius) in enumerate(
            ((10, 300), (12, 400), (14, 500), (16, 600), (16, 700)), 1
        )
    },
}


def selected_skill_ids() -> set[str]:
    prefixes = tuple(arg.split("=", 1)[1] for arg in sys.argv[1:] if arg.startswith("--only-prefix="))
    if not prefixes:
        return set(ENGLISH)
    return {skill_id for skill_id in ENGLISH if skill_id.startswith(prefixes)}


def descriptions(skill_ids: set[str]) -> dict[str, str]:
    with SKILLS.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = {row["skill_id"].strip(): row for row in csv.DictReader(handle)}
    return {skill_id: rows[skill_id]["description"] for skill_id in skill_ids}


def update(path: Path, language: str, chinese: dict[str, str], skill_ids: set[str]) -> None:
    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    values = chinese if language == "schinese" else {
        skill_id: ENGLISH[skill_id] for skill_id in skill_ids
    }
    for skill_id, value in values.items():
        token = f"DOTA_Tooltip_ability_{skill_id}_Description"
        pattern = re.compile(rf'(^\s*"{re.escape(token)}"\s+")[^"]*("\s*$)', re.MULTILINE)
        text, count = pattern.subn(lambda match: match.group(1) + value + match.group(2), text)
        if count != 1:
            raise RuntimeError(f"{path}: expected one {token}, found {count}")
    encoded = text.replace("\r\n", "\n").replace("\n", newline).encode("utf-8")
    path.write_bytes((b"\xef\xbb\xbf" if has_bom else b"") + encoded)


def main() -> int:
    skill_ids = selected_skill_ids()
    chinese = descriptions(skill_ids)
    for path, language in TARGETS:
        update(path, language, chinese, skill_ids)
    print(f"LIGHTNING_FROST_LOCALIZATION_SYNC_PASS files={len(TARGETS)} skills={len(skill_ids)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())