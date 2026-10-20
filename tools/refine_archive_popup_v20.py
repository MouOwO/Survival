"""Build V20: continuous architectural field, localized selection light and layered card material.
All assets are native vectors. V19 badge/typography assets and gameplay handlers stay intact.
"""
from pathlib import Path
import hashlib,json,zipfile,difflib
ROOT=Path(__file__).resolve().parents[1];REC=ROOT/'output/popup_iterations_20261009';OUT=ROOT/'output/popup_visual_v20_20261010';OUT.mkdir(exist_ok=True);ASSETS=REC/'assets'
CONTENT=ROOT.parents[2]/'content/dota_addons/survival'
if not (OUT/'before_v20.zip').exists():
 with zipfile.ZipFile(OUT/'before_v20.zip','w',zipfile.ZIP_DEFLATED) as z:
  manifest={}
  paths=[REC/'v19.js',REC/'v19.css',REC/'active_version.json',ROOT/'tools/switch_archive_popup_ui.py']
  for base,pre in [(ROOT,'panorama/src'),(CONTENT,'panorama')]:
   for name in ['layout/custom_game/archive.xml','scripts/custom_game/archive_popup_study.js','styles/custom_game/archive_popup_study.css']:paths.append(base/pre/name)
  for i,p in enumerate(paths):
   key=f'{i:02d}_{p.name}';data=p.read_bytes();z.writestr(key,data);manifest[key]={'path':str(p),'sha256':hashlib.sha256(data).hexdigest()}
  z.writestr('manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2))
original=(REC/'v19.js').read_text(encoding='utf8');js=original;css=(REC/'v19.css').read_text(encoding='utf8');changes=[]
def replace(old,new,reason):
 global js
 assert js.count(old)==1,(reason,js.count(old));js=js.replace(old,new);changes.append(reason)
# The floor/haze spans the whole panel; sparse, large stone seams avoid AI-like grain.
field='''<svg xmlns="http://www.w3.org/2000/svg" width="1064" height="766" viewBox="0 0 1064 766">
<defs>
<radialGradient id="blue" cx="22%" cy="44%" r="73%"><stop stop-color="#405677" stop-opacity=".42"/><stop offset=".62" stop-color="#2b3b62" stop-opacity=".14"/><stop offset="1" stop-color="#233250" stop-opacity="0"/></radialGradient>
<radialGradient id="purple" cx="78%" cy="90%" r="66%"><stop stop-color="#60417d" stop-opacity=".44"/><stop offset=".52" stop-color="#42345f" stop-opacity=".25"/><stop offset="1" stop-color="#2a2649" stop-opacity="0"/></radialGradient>
<linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#7898b0" stop-opacity="0"/><stop offset=".40" stop-color="#7792aa" stop-opacity=".035"/><stop offset="1" stop-color="#8d91af" stop-opacity=".09"/></linearGradient>
<linearGradient id="beam" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#7698c2" stop-opacity="0"/><stop offset=".38" stop-color="#7999b9" stop-opacity=".075"/><stop offset="1" stop-color="#6883a0" stop-opacity="0"/></linearGradient>
<linearGradient id="warm" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#b08558" stop-opacity=".10"/><stop offset="1" stop-color="#806251" stop-opacity="0"/></linearGradient>
</defs>
<rect width="1064" height="766" fill="url(#blue)"/><rect width="1064" height="766" fill="url(#purple)"/>
<path d="M210 160L320 160 830 766 560 766Z" fill="url(#beam)"/>
<path d="M835 250L1064 280 1064 650 934 560Z" fill="url(#warm)"/>
<g fill="none" stroke="url(#floor)" stroke-width="1.5">
<path fill="none" stroke="url(#floor)" stroke-width="1.5" d="M412 270L-110 766M436 270L250 766M452 270L660 766M470 270L1200 766"/>
<path fill="none" stroke="url(#floor)" stroke-width="1.5" d="M0 363L1064 345M0 443L1064 405M0 561L1064 515M0 723L1064 668"/>
</g>
<g fill="#8393b0" fill-opacity=".015"><path fill="#8393b0" fill-opacity=".015" d="M0 448L250 436 140 600 0 607Z"/><path fill="#8393b0" fill-opacity=".015" d="M693 521L1043 505 1064 674 788 689Z"/><path fill="#8393b0" fill-opacity=".015" d="M213 695L622 681 660 766 180 766Z"/></g>
</svg>'''
card='''<svg xmlns="http://www.w3.org/2000/svg" width="196" height="230" viewBox="0 0 196 230">
<defs>
<radialGradient id="surface" cx="28%" cy="18%" r="92%"><stop stop-color="#7796c7" stop-opacity=".14"/><stop offset=".50" stop-color="#405879" stop-opacity=".045"/><stop offset="1" stop-color="#344567" stop-opacity="0"/></radialGradient>
<radialGradient id="amethyst" cx="50%" cy="108%" r="75%"><stop stop-color="#8653a9" stop-opacity=".27"/><stop offset=".48" stop-color="#644284" stop-opacity=".14"/><stop offset="1" stop-color="#463460" stop-opacity="0"/></radialGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#b4bfd9" stop-opacity=".025"/><stop offset=".43" stop-color="#a4b3d8" stop-opacity=".07"/><stop offset=".48" stop-color="#728bb4" stop-opacity=".018"/><stop offset="1" stop-color="#8393ba" stop-opacity="0"/></linearGradient>
<linearGradient id="edge"><stop stop-color="#adbce2" stop-opacity="0"/><stop offset=".32" stop-color="#adbce2" stop-opacity=".23"/><stop offset="1" stop-color="#7f93bd" stop-opacity="0"/></linearGradient>
</defs>
<rect width="196" height="230" fill="url(#surface)"/><rect width="196" height="230" fill="url(#amethyst)"/>
<path d="M0 0L165 0 0 150Z" fill="url(#sheen)"/>
<path d="M9 1.5H186" fill="none" stroke="url(#edge)" stroke-width="1"/>
</svg>'''
for name,svg in [('arena_field_material_v20_r2.svg',field),('arena_card_material_v20.svg',card)]:
 (ASSETS/name).write_text(svg,encoding='utf8');css+='\n.PopupArenaV20'+name.replace('.svg','').replace('_','')+' {background-image:url("file://{images}/custom_game/popup_study/'+name+'");}\n'
replace('version=19;','version=20;','Isolated V20 record')
replace("backgroundColor:grad('#171B2C','#1e2135')","backgroundColor:'#1b2136'",'Opaque interior base: game world never shows through')
replace("box(hero,0,0,CW,520);", "box(hero,0,0,CW,BH);",'Full content layer bounds without stretching the source illustration')
replace("backgroundSize:CW+'px 425px'", "backgroundSize:Math.round(BH*1983/793)+'px '+BH+'px'",'Uniform aspect-preserving cover crop across the whole interior')
replace("backgroundPosition:'left 0px top -55px'","backgroundPosition:'center top'",'Continuous architecture uses a uniform center crop, never a stretched banner')
replace("box(veil,0,0,CW,520);", "box(veil,0,0,CW,BH);",'Full height independent blending layer')
replace("from(#171B2C40),color-stop(.46,#191d30a8),color-stop(.72,#1b1f32df),to(#1b1f32ff)","from(#151c2c58),color-stop(.28,#18203c68),color-stop(.52,#1b21368c),color-stop(.76,#1b2136b0),to(#1b2136c0)",'Blend architecture into full-height stone/haze instead of a banner boundary')
replace("var headerTrace=trace(p('ArchiveContent')", "var material=trace(p('ArchiveContent'),'PopupStudyContinuousField','arena_field_material_v20_r2.svg',0,0,CW,BH);s(material,{zIndex:'3',opacity:'.42',visibility:'visible'});\n var headerTrace=trace(p('ArchiveContent')",'Continuous code-native low-noise floor texture and diffuse light')
replace("backgroundColor:n.checked?'gradient(radial,50% 48%,0% 0%,66% 145%,from(#5944748a),color-stop(.5,#342d4baa),to(#1c2033dd))':grad('#232238b8','#191d30dd'),border:'1px solid '+(n.checked?'#8d769faa':'#69607855'),borderLeft:n.checked?'2px solid #b292d0b3':'1px solid #69607855'", "backgroundColor:n.checked?grad('#25213b','#1b2032'):grad('#232238b8','#191d30dd'),border:'1px solid #69607855',borderLeft:n.checked?'2px solid #b99be088':'1px solid #69607855',borderBottom:n.checked?'1px solid #9b6ed999':'1px solid #69607855'",'Quiet border; selected emphasis comes from localized light')
replace("walk(n,function(c){if(String(c.paneltype).toLowerCase()==='label'&&!has(c,'ArchiveNavIcon'))", "var selectedLight=deco(n,'PopupStudyNavGlow',0,0,194,68,'gradient(radial,45% 55%,0% 0%,48% 100%,from(#9869e7b8),color-stop(.24,#754bb18c),color-stop(.60,#4f32684a),to(#211f3200))');s(selectedLight,{zIndex:'1',visibility:n.checked?'visible':'collapse'});\n walk(n,function(c){if(String(c.paneltype).toLowerCase()==='label'&&!has(c,'ArchiveNavIcon'))",'Selected nav: bright compact interior with natural falloff')
replace("from(#20243acc),color-stop(.60,#232238cc),color-stop(.94,#332845d0),to(#493257d0)", "from(#141c2db0),color-stop(.38,#1a2239bd),color-stop(.72,#302644c8),to(#48305ecb)",'Translucent card material over opaque continuous panel; stronger cool-to-purple depth')
replace("deco(card,'PopupStudyBottomEdge',1,h-11,cardW-2,10,'gradient(linear,0% 0%,0% 100%,from(#684b8600),to(#7e58992b))');", "deco(card,'PopupStudyBottomEdge',1,h-21,cardW-2,20,'gradient(linear,0% 0%,0% 100%,from(#684b8600),to(#9162bd36))');\n var cardMaterial=trace(card,'PopupStudyCardMaterial','arena_card_material_v20.svg',0,0,cardW,h);s(cardMaterial,{zIndex:'1',opacity:'1',visibility:'visible'});",'Soft surface reflection and lower amethyst material, no outer neon')
replace("appearance:{header:","layers:{content:p('ArchiveContent').style.backgroundColor,heroSize:p('PopupStudyHero').style.backgroundSize,veil:p('PopupStudyVeil').style.backgroundColor,field:{h:p('PopupStudyContinuousField').actuallayoutheight,w:p('PopupStudyContinuousField').actuallayoutwidth,visible:p('PopupStudyContinuousField').visible,hit:p('PopupStudyContinuousField').hittest},navGlow:p('ArchiveTabs').Children().filter(function(n){return has(n,'ArchiveTab')&&n.checked;}).map(function(n){var g=n.FindChildTraverse('PopupStudyNavGlow');return {gradient:g.style.backgroundColor,visible:g.visible,hit:g.hittest};}),cardMaterial:cards[0]?{visible:cards[0].FindChildTraverse('PopupStudyCardMaterial').visible,hit:cards[0].FindChildTraverse('PopupStudyCardMaterial').hittest}:null},appearance:{header:",'Expose actual loaded layers for screenshot acceptance')
css+='\n.ArchiveRoot #ArchiveWindow.PopupStudy.PopupArena #ArchiveTabs .ArchiveTab:selected {border:1px solid #69607855;border-left:2px solid #b99be088;border-bottom:1px solid #9b6ed999;}\n'
for ext,text in [('js',js),('css',css)]:
 (REC/f'v20.{ext}').write_text(text,encoding='utf8');(OUT/f'v20.{ext}').write_text(text,encoding='utf8');(OUT/f'v19_to_v20.{ext}.diff').write_text(''.join(difflib.unified_diff((REC/f'v19.{ext}').read_text(encoding='utf8').splitlines(True),text.splitlines(True),fromfile='v19.'+ext,tofile='v20.'+ext)),encoding='utf8')
(OUT/'changes.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'asset_manifest.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [ASSETS/'arena_field_material_v20_r2.svg',ASSETS/'arena_card_material_v20.svg']},indent=2),encoding='utf8')
p=ROOT/'tools/switch_archive_popup_ui.py';text=p.read_text(encoding='utf8').replace('1..19','1..20').replace('range(20)','range(21)');p.write_text(text,encoding='utf8')
print('V20 built:',len(changes),'localized changes; two code-native vector material assets. V19 typography and badges unchanged.')
