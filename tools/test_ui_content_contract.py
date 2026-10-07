"""Regression guard for Content branch synchronization dropping shipped HUD UI."""
from pathlib import Path
import argparse
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--content-root", type=Path, default=ROOT.parents[2] / "content/dota_addons/survival")
CONTENT = parser.parse_args().content_root / "panorama"

def verify(folder):
    hud = ET.parse(folder / "layout/custom_game/survival_hud.xml").getroot()
    includes = {n.get("src", "").rsplit("/", 1)[-1] for n in hud.iter("include")}
    required = {"lottery_fullscreen_v2.css", "lottery_cinematic_v1.css", "lottery_cinematic_v1.js",
                "reference_windows.js", "reference_windows.css", "topnav_windows.css",
                "topnav_refinement_v5.css", "nav_windows_modern_20260929.css",
                "lumberjack_fusion_queue.js", "portrait_palette.js", "portrait_presentation.js",
                "world_health_bar_anchor.js", "building_construction_progress.js",
                "native_ui_icons.js", "commerce_jade.css", "commerce_components.js", "commerce_art_manifest.js"}
    assert required <= includes, (str(folder), "missing includes", sorted(required - includes))
    ids = {n.get("id") for n in hud.iter()}
    required_ids = {"LotterySceneBackground", "LotterySceneShade", "LotteryTaglineBounds",
                    "LotteryUnlockNotice", "LotteryDrawPity", "SurvivalLocalHeroPortrait",
                    "SurvivalReturnCastleAsset"}
    assert required_ids <= ids, (str(folder), "missing panels", sorted(required_ids - ids))
    root = next(n for n in hud.iter("Panel") if "SurvivalHUDRoot" in n.get("class", "").split())
    assert {"UnifiedWindowsV4", "HandoffReadableStats", "HandoffResourceTree"} <= set(root.get("class").split())
    tabs = next(n for n in hud.iter() if n.get("id") == "LotteryPoolTabs")
    canvas = next(n for n in hud.iter() if n.get("id") == "LotteryMainCanvas")
    assert tabs in list(canvas), "pool tabs must remain outside the header"

verify(ROOT / "panorama/src")
verify(CONTENT)
for rel in ("layout/custom_game/lottery_window.xml", "styles/custom_game/common/ui_assets.css"):
    assert "ui-resource://" not in (CONTENT / rel).read_text(encoding="utf-8-sig"), rel
print("PASS UI Content contract: lottery, navigation, portrait, construction and native asset URLs")
