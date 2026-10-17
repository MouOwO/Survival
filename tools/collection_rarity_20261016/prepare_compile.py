"""Build a three-resource compile wrapper from the established scoped compiler.

No compile runs here; the emitted PowerShell retains the backup/hash checks.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    source = (ROOT / "tools/wife_video_20261016/compile_ui.ps1").read_text(encoding="utf-8-sig")
    source = source.replace("wife_video_20261016", "collection_rarity_20261016")
    start = source.index("$wifeScope = @(")
    end = source.index("\n)", start) + 2
    source = source[:start] + """$wifeScope = @(
    'scripts/custom_game/collection_gw2.js',
    'scripts/custom_game/common/archive_tooltip.js',
    'styles/custom_game/collection_gw2.css'
)""" + source[end:]
    source = source.replace("//scripts/include", "//scripts/include | //styles/include")
    source = source.replace("$relative -replace '\\.js$', '.vjs_c'", "($relative -replace '\\.js$', '.vjs_c') -replace '\\.css$', '.vcss_c'")
    source = source.replace("exact five JS sources", "exact two JS and one CSS sources")
    source = source.replace("imagesCompiled = 0; cssCompiled = 0; xmlCompiled = 0", "imagesCompiled = 0; jsCompiled = 2; cssCompiled = 1; xmlCompiled = 0")
    source = source.replace("Confirm every selected script is already loaded", "Confirm every selected script/style is already loaded")
    source = source.replace("No layout or HUD changes are required", "No layout or HUD changes are required")
    source = source.replace("WIFE_UI_COMPILE_PASS", "COLLECTION_RARITY_COMPILE_PASS")
    source = source.replace("$wife", "$rarity").replace("Get-Wife", "Get-Rarity")
    target = Path(__file__).with_name("compile_ui.ps1")
    target.write_text(source, encoding="utf-8-sig", newline="\r\n")
    print("COLLECTION_RARITY_COMPILE_WRAPPER_READY", target.relative_to(ROOT))


if __name__ == "__main__":
    main()
