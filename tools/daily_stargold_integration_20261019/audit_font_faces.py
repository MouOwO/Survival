"""Isolated engine Fontconfig/FreeType check; does not load the running game."""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path

root=Path(__file__).resolve().parents[2]
engine=root.parents[1]
font_config=engine/'core/panorama/fonts/fonts.conf'
os.environ['FONTCONFIG_PATH']=str(font_config.parent)
os.environ['LANG']='zh_CN.UTF-8'
os.add_dll_directory(str(engine/'bin/win64'))
ft=C.CDLL(str(engine/'bin/win64/libfreetype-6.dll'))
fc=C.CDLL(str(engine/'bin/win64/libfontconfig-1.dll'))
def api(lib,name,ret,args):
    fn=getattr(lib,name);fn.restype=ret;fn.argtypes=args;return fn
p=C.c_void_p
init=api(ft,'FT_Init_FreeType',C.c_int,[C.POINTER(p)])
new=api(ft,'FT_New_Memory_Face',C.c_int,[p,p,C.c_long,C.c_long,C.POINTER(p)])
glyph=api(ft,'FT_Get_Char_Index',C.c_uint,[p,C.c_ulong])
size=api(ft,'FT_Set_Pixel_Sizes',C.c_int,[p,C.c_uint,C.c_uint])
load=api(ft,'FT_Load_Char',C.c_int,[p,C.c_ulong,C.c_int])
free=api(ft,'FT_Done_Face',C.c_int,[p])
create=api(fc,'FcConfigCreate',p,[])
read=api(fc,'FcConfigParseAndLoad',C.c_int,[p,C.c_char_p,C.c_int])
add=api(fc,'FcConfigAppFontAddDir',C.c_int,[p,C.c_char_p])
parse=api(fc,'FcNameParse',p,[C.c_char_p])
subs=api(fc,'FcConfigSubstitute',C.c_int,[p,p,C.c_int])
defaults=api(fc,'FcDefaultSubstitute',None,[p])
match=api(fc,'FcFontMatch',p,[p,p,C.POINTER(C.c_int)])
string=api(fc,'FcPatternGetString',C.c_int,[p,C.c_char_p,C.c_int,C.POINTER(C.c_char_p)])
destroy=api(fc,'FcPatternDestroy',None,[p])
config=create();assert read(config,str(font_config).encode(),1)
assert add(config,str(root/'panorama/fonts').encode())
library=p();assert init(C.byref(library))==0
sample='每日登录奖励签到累计天月卡奖励开通月卡领取奖励奖励规则聚财古符古树眷顾森罗本源第今天英雄每秒攻击生命木材金币全属性伐木效率金矿收益积分回补签零点刷新断不重置进度0123456789ⅠⅡⅢⅣⅤⅥⅦ+%/×'
manifest=json.loads((root/'panorama/src/ui/font_manifest.json').read_text())
report={'kind':'isolated_engine_font_libraries_check','nativeGameCapture':False,'osFontInstallation':False,'stockFontChanges':False,'fontConfig':str(font_config),'sample':sample,'faces':[]}
for item in manifest['files']:
    if not item['runtime'].endswith('.otf'):continue
    file=root/item['runtime'];data=file.read_bytes();assert hashlib.sha256(data).hexdigest()==item['sha256']
    buffer=C.create_string_buffer(data);face=p();assert new(library,buffer,len(data),0,C.byref(face))==0
    missing=[c for c in sample if not glyph(face,ord(c))];assert not missing,(file.name,missing)
    for pixels in [12,14,16,18,20,24,36,40]:
        assert size(face,0,pixels)==0
        for ch in sample:assert load(face,ord(ch),4)==0
    family=item.get('typographic_family') or item['family'];weight={400:80,500:100,700:200}[item['weight']]
    pattern=parse(f'{family}:weight={weight}'.encode());assert subs(config,pattern,0);defaults(pattern)
    result=C.c_int();selected=match(config,pattern,C.byref(result));assert selected
    actual=C.c_char_p();assert string(selected,b'file',0,C.byref(actual))==0
    actual_path=Path(actual.value.decode());assert actual_path.name==file.name,(file.name,actual_path)
    report['faces'].append({'family':family,'weight':item['weight'],'file':str(file),'fontconfigSelected':str(actual_path),'sha256':item['sha256'],'missingSampleCharacters':missing,'freetypeRasterizationPx':[12,14,16,18,20,24,36,40]})
    destroy(pattern);destroy(selected);free(face)
api(fc,'FcConfigDestroy',None,[p])(config)
api(ft,'FT_Done_FreeType',C.c_int,[p])(library)
out=root/'design_refs/daily_stargold_integration_20261019/font_faces_audit.json'
out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'status':'PASS','faces':len(report['faces']),'sampleCharacters':len(set(sample)),'nativeGameCapture':False,'output':str(out)},ensure_ascii=False))
