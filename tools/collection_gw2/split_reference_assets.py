"""Package the original flat inventory material without changing v1 consumers."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / 'design_refs/collection_gw2_v2'
OUT = ROOT / 'art/ui/sources/custom_game/collection_gw2_v2'
MIRROR = ROOT / 'panorama/src/images/custom_game/collection_gw2_v2'
OLD = ROOT / 'art/ui/sources/custom_game/collection_gw2_v1'
for directory in (OUT, MIRROR, REF / 'work'):
    directory.mkdir(parents=True, exist_ok=True)
resample = Image.Resampling.LANCZOS
plate_source = Image.open(REF / 'blank_plate.png').convert('RGBA')
# Material sampling removes only the generated cutout margin; native code owns
# the single rectangular window boundary and draws each structural band once.
plate_box = (218, 120, 1400, 886)
plate = plate_source.crop(plate_box).resize((1200, 778), resample)
reference = Image.open(REF / 'reference_inventory.png').convert('RGBA')
assets = {}

def save(key, image, source, crop, usage):
    file = OUT / (key + '.png')
    image.convert('RGBA').save(file, optimize=True)
    data = file.read_bytes()
    (MIRROR / file.name).write_bytes(data)
    assets[key] = dict(file=file.relative_to(ROOT).as_posix(), size=list(image.size),
                      sha256=hashlib.sha256(data).hexdigest(), source=source,
                      crop=crop, usage=usage)

def material(key, box, size, usage):
    save(key, plate.crop(box).resize(size, resample), 'blank_plate.png / 1200x778', list(box), usage)

save('window_background', plate, 'blank_plate.png / continuous interior material', list(plate_box),
     'Continuous translucent wash without baked title/avatar/rail/footer blocks or seams.')
material('header_strip', (0, 0, 1200, 60), (1200, 60), 'Full-width flat title material; boundary belongs to live layout.')
material('sidebar_background', (0, 60, 70, 718), (70, 658), 'Continuous flat icon rail, joined to header and footer.')
material('footer_strip', (0, 718, 1200, 778), (1200, 60), 'Full-width flat footer; no separate framed end piece.')
material('tab_background', (6, 99, 57, 141), (62, 70), 'Matte flat category material; no embossed tab border.')
material('tab_selected', (6, 99, 57, 141), (62, 70), 'Same flat material; selection drawn as a thin live highlight.')

slot_box = (112, 328, 155, 371)
slot = reference.crop(slot_box).resize((74, 74), resample)
save('slot_background', slot, 'reference_inventory.png', list(slot_box),
     'Original empty-cell interior only; excludes the baked frame so live CSS draws one boundary.')
# Isolate the four existing boundary strips mechanically; the center stays clear.
boundary_box = (108, 323, 159, 376)
boundary = reference.crop(boundary_box).resize((74, 74), resample)
frame = Image.new('RGBA', (74, 74), (0, 0, 0, 0))
for edge in [(0, 0, 74, 1), (0, 73, 74, 74), (0, 0, 1, 74), (73, 0, 74, 74)]:
    frame.paste(boundary.crop(edge), (edge[0], edge[1]))
for key in ('slot_frame', 'slot_hover', 'slot_selected'):
    save(key, frame, 'reference_inventory.png / empty cell boundary strips', list(boundary_box),
         'One-pixel original boundary strips with transparent center; live CSS supplies flat selection.')
for key in ('tab_ex', 'tab_friend', 'tab_wife'):
    icon = Image.open(OLD / (key + '.png')).convert('RGBA')
    icon.thumbnail((40, 40), resample)
    save(key, icon, 'collection_gw2_v1/' + key + '.png', None,
         'Existing category glyph for an icon-only rail; names remain in content and hover text.')
material('draw_button', (380, 17, 645, 51), (162, 30), 'Plain original title-band material for a small flat action.')
material('draw_button_hover', (380, 17, 645, 51), (162, 30), 'Same flat material; live brightness supplies hover.')
save('close', reference.crop((787, 16, 804, 33)).resize((20, 20), resample),
     'reference_inventory.png', [787, 16, 804, 33], 'Original small close control, no added bezel.')
for key in ('collection_icon', 'scroll_track', 'scroll_thumb'):
    save(key, Image.open(OLD / (key + '.png')).convert('RGBA'),
         'collection_gw2_v1/' + key + '.png', None,
         'Existing navigation/scroll bitmap retained; native controls remain thin.')
material('tooltip_background', (330, 260, 820, 610), (360, 260), 'Flat translucent original wash for readable tooltip.')
tooltip_frame = Image.new('RGBA', (360, 260), (0, 0, 0, 0))
tooltip_draw = ImageDraw.Draw(tooltip_frame)
tooltip_draw.rectangle((0, 0, 359, 259), outline=(99, 101, 101, 115), width=1)
save('tooltip_frame', tooltip_frame, 'Code-native single-line frame', None,
     'One-pixel flat neutral outline; no bevel or shadow.')
material('search_background', (83, 82, 1187, 119), (1090, 35), 'Original long flat search surface.')
assert len(assets) == 22
manifest = dict(version=2, canvas=[1200, 778], reference='Original annotated Guild Wars 2 Inventory, 815x528',
                reference_source='design_refs/collection_gw2_v2/reference_inventory.png',
                material_source='design_refs/collection_gw2_v2/blank_plate.png',
                source_policy='Built-in imagegen removes contents/annotations from the original plate; exact original empty-cell and close-control crops; flat live borders; existing portraits/business values remain untouched.',
                assets=assets)
(Path(__file__).parent / 'asset_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
runtime = {key: dict(file='file://{images}/custom_game/collection_gw2_v2/' + key + '.png', size=value['size'])
           for key, value in assets.items()}
(ROOT / 'panorama/src/scripts/custom_game/collection_gw2_data.js').write_text(
    '// Generated by tools/collection_gw2/split_reference_assets.py; art only.\n'
    + '(function(){GameUI.CustomUIConfig().CollectionGW2Data='
    + json.dumps(dict(version=2, canvas=[1200, 778], assets=runtime), separators=(',', ':'))
    + ';})();\n', encoding='utf-8')
xml = '<root>\n  <Panel hittest="false" hittestchildren="false">\n'
for key, value in runtime.items():
    xml += '    <Image id="CollectionGW2Preload_' + key + '" src="' + value['file'] + '" visible="false" hittest="false" style="visibility:collapse; width:0px; height:0px;" />\n'
xml += '  </Panel>\n</root>\n'
(ROOT / 'panorama/src/layout/custom_game/collection_gw2_assets.xml').write_text(xml, encoding='utf-8')
sheet = Image.new('RGB', (1200, 1200), '#242a2c')
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 17)
except OSError:
    font = ImageFont.load_default()
for index, (key, value) in enumerate(assets.items()):
    image = Image.open(ROOT / value['file']).convert('RGBA')
    image.thumbnail((280, 145), resample)
    x, y = index % 4 * 300, index // 4 * 200
    sheet.paste(image, (x + (300 - image.width) // 2, y + 40), image)
    draw.text((x + 10, y + 10), key, fill='#e1d9ca', font=font)
sheet.save(REF / 'work/components.png')
print('COLLECTION_GW2_REFERENCE_COMPONENTS_READY', len(assets))
