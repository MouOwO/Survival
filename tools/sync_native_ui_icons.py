"""Apply native-icon changes to Content while preserving its unrelated UI edits."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'panorama/src'
CONTENT = ROOT.parents[2] / 'content/dota_addons/survival/panorama'


def update(relative, replacements):
    path = CONTENT / relative
    text = path.read_text(encoding='utf-8-sig')
    for old, new in replacements:
        if new in text:
            continue
        if text.count(old) != 1:
            raise RuntimeError(f'Unexpected Content source: {relative}: {old[:70]}')
        text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8', newline='')


def script(name):
    return 'scripts/custom_game/' + name + '.js'


def main():
    module = script('native_ui_icons')
    target = CONTENT / module
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes((GAME / module).read_bytes())
    include = '<include src="file://{resources}/scripts/custom_game/native_ui_icons.js"/>'
    for name, anchor in [('survival_hud', 'item_art_remaining_5d5c1152eb'),
                         ('archive', 'item_art_remaining_5d5c1152eb'),
                         ('rogue_reward_ui', 'rogue_art_remaining_5d5c1152eb')]:
        path = CONTENT / ('layout/custom_game/' + name + '.xml')
        text = path.read_text(encoding='utf-8-sig')
        if 'native_ui_icons.js' not in text:
            pattern = r'<include src="file://\{resources\}/scripts/custom_game/' + anchor + r'\.js"\s*/>'
            text, count = re.subn(pattern, lambda m: include + m[0], text)
            if count != 1:
                raise RuntimeError('Unexpected script include: ' + name)
            path.write_text(text, encoding='utf-8', newline='')
    update(script('item_art_remaining_5d5c1152eb'), [(
        '    function create(parent,item,className){',
        '    function create(parent,item,className){\n'
        '        var native=cfg.SurvivalNativeIcons;\n'
        '        if(native){var icon=native.Create(parent,item,className);if(icon)return icon;}')])
    update(script('inventory_tooltip'), [(
        '        var art=GameUI.CustomUIConfig().SurvivalItemArt;\n'
        '        var resolved=art&&art.ResolveOriginal&&(art.ResolveOriginal(contentId)||art.ResolveOriginal(itemName));',
        '        var art=GameUI.CustomUIConfig().SurvivalNativeIcons;\n'
        '        var resolved=art&&(art.Resolve(contentId)||art.Resolve(itemName));'), (
        'if(resolved)fitted.SetImage("file://{images}/items/survival_shop_v2/"+resolved[0]+"_"+("0"+resolved[1]).slice(-2)+".png");',
        'if(resolved)fitted.SetImage(resolved.uri);')])
    update(script('topnav_remaining_5d5c1152eb'), [(
        '                var art=cfg.SurvivalItemArt;\n'
        '                var resolved=art&&art.ResolveOriginal&&(\n'
        '                    identity&&identity.removed!==1&&art.ResolveOriginal(identity.content_id)\n'
        '                    ||art.ResolveOriginal(name));',
        '                var art=cfg.SurvivalNativeIcons;\n'
        '                var resolved=art&&(\n'
        '                    identity&&identity.removed!==1&&art.Resolve(identity.content_id)\n'
        '                    ||art.Resolve(name));'), (
        'var uri="file://{images}/items/survival_shop_v2/"+resolved[0]+"_"+("0"+resolved[1]).slice(-2)+".png";',
        'var uri=resolved.uri;')])
    update(script('minimap_shortcuts'), [(
        'file://{images}/spellicons/survival/native/skill_return.png',
        'file://{images}/spellicons/furion_teleportation.png')])
    update(script('shop_ui'), [(
        '    function createEntryIcon(parent, entry, className) {',
        '    function createEntryIcon(parent, entry, className) {\n'
        '        var native = GameUI.CustomUIConfig().SurvivalNativeIcons;\n'
        '        if (native && native.Create(parent, entry, className)) return;')])
    for name in ['vitality_booster', 'platemail', 'broadsword', 'gloves', 'hand_of_midas']:
        update(script('ability_tooltip'), [(
            'spellicons/survival/native/' + name + '.png', 'items/' + name + '.png')])
    relative = script('production_progress')
    pattern = r'    function workerIcon\(job\) \{[\s\S]*?\n    \}'
    source = (GAME / relative).read_text(encoding='utf-8')
    replacement = re.search(pattern, source)[0]
    path = CONTENT / relative
    original = re.search(pattern, path.read_text(encoding='utf-8-sig'))[0]
    update(relative, [(original, replacement)])
    update(script('rogue_art_remaining_5d5c1152eb'), [(
        '        var entry=entries[String(data.card_id)];if(!entry)return false;',
        '        var native=cfg.SurvivalNativeIcons&&cfg.SurvivalNativeIcons.Resolve(data.card_id);\n'
        '        var entry=native||entries[String(data.card_id)];if(!entry)return false;'), (
        "rect(art,29,50,232,348);art.style.zIndex='1';",
        "rect(art,29,native?108:50,232,native?232:348);art.style.zIndex='1';")])
    print('NATIVE_UI_CONTENT_SYNC_PASS: icon changes applied; unrelated Content edits preserved')


if __name__ == '__main__':
    main()
