"""Check original files using Dota's own FreeType/Fontconfig DLLs in an isolated process.
This proves CFF parsing and family/weight selection, NOT Workshop mounting in a game client.
Only private fontconfig configuration is used. No machine-wide fonts or config are changed.
"""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT.parents[1] / 'bin/win64'
engine_config = ROOT.parents[1] / 'core/panorama/fonts/fonts.conf'
# Match the setup performed by panorama_text_pango, within this process only.
os.environ['FONTCONFIG_PATH'] = engine_config.parent.as_posix()
os.environ['LANG'] = 'zh_CN.UTF-8'
os.add_dll_directory(str(BIN))
ft = C.CDLL(str(BIN / 'libfreetype-6.dll'))
fc = C.CDLL(str(BIN / 'libfontconfig-1.dll'))

def api(lib, name, ret, args):
    fn = getattr(lib, name); fn.restype = ret; fn.argtypes = args; return fn

ptr = C.c_void_p
init = api(ft, 'FT_Init_FreeType', C.c_int, [C.POINTER(ptr)])
new = api(ft, 'FT_New_Memory_Face', C.c_int, [ptr, ptr, C.c_long, C.c_long, C.POINTER(ptr)])
glyph = api(ft, 'FT_Get_Char_Index', C.c_uint, [ptr, C.c_ulong])
load = api(ft, 'FT_Load_Char', C.c_int, [ptr, C.c_ulong, C.c_int])
size = api(ft, 'FT_Set_Pixel_Sizes', C.c_int, [ptr, C.c_uint, C.c_uint])
done = api(ft, 'FT_Done_Face', C.c_int, [ptr])
create_config = api(fc, 'FcConfigCreate', ptr, [])
add_dir = api(fc, 'FcConfigAppFontAddDir', C.c_int, [ptr, C.c_char_p])
parse = api(fc, 'FcNameParse', ptr, [C.c_char_p])
substitute = api(fc, 'FcConfigSubstitute', C.c_int, [ptr, ptr, C.c_int])
defaults = api(fc, 'FcDefaultSubstitute', None, [ptr])
match = api(fc, 'FcFontMatch', ptr, [ptr, ptr, C.POINTER(C.c_int)])
get_string = api(fc, 'FcPatternGetString', C.c_int, [ptr, C.c_char_p, C.c_int, C.POINTER(C.c_char_p)])
get_int = api(fc, 'FcPatternGetInteger', C.c_int, [ptr, C.c_char_p, C.c_int, C.POINTER(C.c_int)])
destroy_pattern = api(fc, 'FcPatternDestroy', None, [ptr])
config = create_config()
assert api(fc,'FcConfigParseAndLoad',C.c_int,[ptr,C.c_char_p,C.c_int])(config,engine_config.as_posix().encode(),1)
assert config and add_dir(config, str(ROOT / 'panorama/fonts').encode())
library = ptr(); assert init(C.byref(library)) == 0
sample = '奖池详情、抽奖记录、解锁条件、确认、取消、0/10、100%、×10'
# A conservative superset: every printable code point in UI source, localization,
# CSV configuration, and game scripts. Includes comments, thus reports are reviewed
# before treating missing characters as visible-text failures.
characters = set(sample); locations = {}; counts = {}; skipped = []; legacy_encodings = []
for folder, exts in [('panorama/src', {'.js','.xml'}), ('panorama/localization',{'.txt'}),
                     ('resource',{'.txt'}), ('data/csv',{'.csv'}), ('scripts/vscripts',{'.lua','.txt'}),
                     (str(ROOT.parents[2] / 'content/dota_addons/Survival/panorama'),{'.js','.xml','.txt'})]:
    count = 0
    for file in (ROOT / folder).rglob('*'):
        if not file.is_file() or file.suffix not in exts: continue
        raw = file.read_bytes()
        try: text = raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
        except UnicodeError:
            try:
                text = raw.decode('gb18030')
                legacy_encodings.append(str(file))
            except UnicodeError:
                skipped.append(str(file)); continue
        count += 1
        for ch in set(text):
            if not ch.isspace() and not unicodedata.category(ch).startswith('C'):
                characters.add(ch)
                if ch not in locations: locations[ch] = os.path.relpath(file,ROOT).replace('\\','/')
    counts[folder] = count
report = {'kind':'isolated_dota_font_libraries_not_game_capture','os_font_installation':False,
          'game_fonts_conf_loaded':str(engine_config),
          'native_addon_mount_verified':False,'files_scanned':counts,'encoding_review_files':skipped,
          'gb18030_sources':legacy_encodings,'presentation_fallbacks':{'💰':'金币','🌲':'木材'},
          'unique_printable_characters':len(characters),'fonts':[]}
manifest = json.loads((ROOT / 'panorama/src/ui/font_manifest.json').read_text())
for item in manifest['files']:
    file = ROOT / item['runtime']; data = file.read_bytes()
    assert hashlib.sha256(data).hexdigest() == item['sha256']
    if file.suffix != '.otf': continue
    assert data[:4] == b'OTTO'
    tables = {data[12+i*16:16+i*16].decode():struct.unpack_from('>II',data,20+i*16) for i in range(struct.unpack_from('>H',data,4)[0])}
    assert 'CFF ' in tables and 'fvar' not in tables
    assert struct.unpack_from('>H',data,tables['OS/2'][0]+4)[0] == item['weight']
    memory = C.create_string_buffer(data); face = ptr()
    assert new(library, memory, len(data), 0, C.byref(face)) == 0
    missing = [{'character':ch,'codepoint':f'U+{ord(ch):04X}','first_file':locations.get(ch)} for ch in sorted(characters) if not glyph(face,ord(ch))]
    for px in [14,16,18,20,24,30,38,44]:
        assert size(face,0,px) == 0
        for ch in sample:
            assert glyph(face,ord(ch)) > 0 and load(face,ord(ch),4) == 0, (file.name,ch,px)
    pattern = parse((item.get('typographic_family') or item['family']).encode()+f":weight={ {400:80,500:100,700:200}[item['weight']] }".encode())
    assert substitute(config,pattern,0); defaults(pattern)
    result=C.c_int(); selected=match(config,pattern,C.byref(result)); assert selected
    actual=C.c_char_p(); assert get_string(selected,b'file',0,C.byref(actual)) == 0
    matched=Path(actual.value.decode()); assert matched.name == file.name, (file.name,str(matched))
    actual_weight=C.c_int(); assert get_int(selected,b'weight',0,C.byref(actual_weight)) == 0
    report['fonts'].append({'file':file.name,'sha256':item['sha256'],'weight':item['weight'],
        'fontconfig_selected_file':str(matched),'fontconfig_weight':actual_weight.value,
        'freetype_cff_rasterization':'passed_14_16_18_20_24_30_38_44px','missing_characters':missing})
    destroy_pattern(pattern);destroy_pattern(selected);done(face)
api(fc,'FcConfigDestroy',None,[ptr])(config)
api(ft,'FT_Done_FreeType',C.c_int,[ptr])(library)
(ROOT / 'art/ui/development/font_import/verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'result':'FONT_LIBRARIES_PASS','scanned':counts,'characters':len(characters),
                  'missing':{f['file']:len(f['missing_characters']) for f in report['fonts']},
                  'native_addon_mount_verified':False},ensure_ascii=False))
