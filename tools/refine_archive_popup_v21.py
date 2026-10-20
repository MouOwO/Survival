"""V21: separate architectural background, blue card bases, localized violet light.
No added texture, noise or diagonal material overlays; V20 remains recoverable.
"""
from pathlib import Path
import hashlib,json,zipfile,difflib,re,shutil
ROOT=Path(__file__).resolve().parents[1];REC=ROOT/'output/popup_iterations_20261009';OUT=ROOT/'output/popup_visual_v21_20261010';OUT.mkdir(exist_ok=True)
CONTENT=ROOT.parents[2]/'content/dota_addons/survival'
if not (OUT/'before_v21.zip').exists():
 with zipfile.ZipFile(OUT/'before_v21.zip','w',zipfile.ZIP_DEFLATED) as z:
  manifest={};paths=[REC/'v20.js',REC/'v20.css',REC/'active_version.json',ROOT/'tools/switch_archive_popup_ui.py']
  for base,pre in [(ROOT,'panorama/src'),(CONTENT,'panorama')]:
   for name in ['layout/custom_game/archive.xml','scripts/custom_game/archive_popup_study.js','styles/custom_game/archive_popup_study.css']:paths.append(base/pre/name)
  for i,p in enumerate(paths):
   key=f'{i:02d}_{p.name}';data=p.read_bytes();z.writestr(key,data);manifest[key]={'path':str(p),'sha256':hashlib.sha256(data).hexdigest()}
  z.writestr('manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2))
original=(REC/'v20.js').read_text(encoding='utf8');js=original;css=(REC/'v20.css').read_text(encoding='utf8');changes=[]
def replace(old,new,reason):
 global js
 assert js.count(old)==1,(reason,js.count(old));js=js.replace(old,new);changes.append(reason)
replace('version=20;','version=21;','Independent V21 record')
replace("backgroundColor:'#171B2Cfc',backgroundImage:'none',border:'1px solid #73698188'", "backgroundColor:'#131b2ffc',backgroundImage:'none',border:'1px solid #6c779055'",'Cool blue window base with quiet perimeter')
replace("backgroundColor:grad('#1d2034','#171B2C'),borderBottom:'1px solid #74629288'", "backgroundColor:grad('#19233a','#131b2f'),borderBottom:'1px solid #7184a04d'",'Header belongs to blue interior instead of a grey purple slab')
replace("backgroundColor:grad('#1b2136','#20283d'),borderRight:'1px solid #625c7566'", "backgroundColor:grad('#152037','#111b2f'),borderRight:'1px solid #65768e55'",'Cool sidebar foundation')
replace("backgroundColor:'#202840',padding:","backgroundColor:'#141f35',padding:",'Cool blue sidebar footer')
replace("backgroundColor:'#1b2136',backgroundImage:'none'", "backgroundColor:'#131b2f',backgroundImage:'none'",'Opaque continuous content base')
replace('from(#151c2c58),color-stop(.28,#18203c68),color-stop(.52,#1b21368c),color-stop(.76,#1b2136b0),to(#1b2136c0)', 'from(#101a2a60),color-stop(.28,#121c3068),color-stop(.52,#1420398c),color-stop(.76,#152039b8),to(#131c30d0)', 'Separate cool veil blends the art without uniform purple fill')
replace("var material=trace(p('ArchiveContent'),'PopupStudyContinuousField','arena_field_material_v20_r2.svg',0,0,CW,BH);s(material,{zIndex:'3',opacity:'.42',visibility:'visible'});", "var material=deco(p('ArchiveContent'),'PopupStudyContinuousField',0,0,CW,BH,'gradient(radial,74% 68%,0% 0%,44% 65%,from(#37365b38),color-stop(.40,#24335318),to(#15203500))');s(material,{zIndex:'3',opacity:'1',visibility:'visible'});", 'Continuous faint diffuse light; remove all added floor seams and material texture')
replace("backgroundColor:n.checked?grad('#25213b','#1b2032'):grad('#232238b8','#191d30dd')", "backgroundColor:n.checked?grad('#1d2540','#141b2e'):grad('#172137e0','#141b2fe8')",'Blue navigation base separated from selection light')
replace('from(#9869e7b8),color-stop(.24,#754bb18c),color-stop(.60,#4f32684a),to(#211f3200)', 'from(#8452c6a0),color-stop(.24,#68459a82),color-stop(.60,#40305238),to(#17213700)', 'Compact violet navigation glow with dark margins')
replace("backgroundColor:n.checked?'gradient(radial,50% 48%,0% 0%,66% 145%,from(#624b8090),color-stop(.5,#392e50b0),to(#20243add))':grad('#202238c0','#171B2Cdd'),border:'1px solid #6b607b66',borderBottom:n.checked?'1px solid #bc8edfaa':'1px solid #6b607b66'", "backgroundColor:grad('#162036cd','#11182bdf'),border:'1px solid #69728b4a',borderBottom:n.checked?'1px solid #bd85ddaa':'1px solid #69728b4a'",'Filters get independent blue bases, no whole-button purple wash')
replace("borderBottom:n.checked?'1px solid #bd85ddaa':'1px solid #69728b4a',borderRadius:'0px'});walk(n,function(c){", "borderBottom:n.checked?'1px solid #bd85ddaa':'1px solid #69728b4a',borderRadius:'0px'});var filterLight=deco(n,'PopupStudyFilterGlow',0,0,340,55,'gradient(radial,50% 100%,0% 0%,68% 115%,from(#75529c90),color-stop(.40,#47355d3b),to(#18203900))');s(filterLight,{visibility:n.checked?'visible':'collapse',zIndex:'1'});walk(n,function(c){",'Selected filter has localized lower reflection above its dark base')
replace("color:n.checked?'#ffffff':'#c7b5e3',width:'fit-children'", "color:n.checked?'#ffffff':'#c7b5e3',zIndex:'5',width:'fit-children'",'Filter glyphs remain opaque above passive light')
replace("backgroundColor:'gradient(linear,0% 0%,0% 100%,from(#141c2db0),color-stop(.38,#1a2239bd),color-stop(.72,#302644c8),to(#48305ecb))',border:'1px solid #756b875c',borderBottom:'1px solid #9876b3aa'", "backgroundColor:'transparent',border:'1px solid #7179905c',borderBottom:'1px solid #8661b377'", 'Card owns quiet thin edges; material lives in separate passive layers')
replace("deco(card,'PopupStudyBottomEdge',1,h-21,cardW-2,20,'gradient(linear,0% 0%,0% 100%,from(#684b8600),to(#9162bd36))');\n var cardMaterial=trace(card,'PopupStudyCardMaterial','arena_card_material_v20.svg',0,0,cardW,h);s(cardMaterial,{zIndex:'1',opacity:'1',visibility:'visible'});", "var cardBase=deco(card,'PopupStudyCardBase',0,0,cardW-2,h-2,'gradient(linear,0% 0%,0% 100%,from(#10192edb),color-stop(.55,#141c30e3),to(#182038e8))');s(cardBase,{zIndex:'0'});\n deco(card,'PopupStudyBottomEdge',1,h-9,cardW-2,8,'gradient(linear,0% 0%,0% 100%,from(#684b8600),to(#965cdf22))');\n var cardMaterial=deco(card,'PopupStudyCardMaterial',Math.round(cardW*.12),h-85,Math.round(cardW*.76),82,'gradient(radial,50% 88%,0% 0%,70% 105%,from(#7147a880),color-stop(.40,#49376138),to(#1b213600))');s(cardMaterial,{zIndex:'1',opacity:'1',visibility:'visible'});\n var topReflection=deco(card,'PopupStudyCardTopReflection',1,1,cardW-4,1,'gradient(linear,0% 0%,100% 0%,from(#b8caeb00),color-stop(.24,#b8caeb50),to(#b8caeb00))');s(topReflection,{zIndex:'2'});", 'Blue card base, compact amethyst reflection, one-pixel top light; remove diagonal sheen and broad purple')
replace("backgroundColor:'transparent',border:'0px'});}", "backgroundColor:'transparent',border:'0px',zIndex:'4'});}", 'Badge above all material layers; preserve original badge pixels')
replace("backgroundColor:card.__archiveUnlocked===true?'gradient(linear,0% 0%,0% 100%,from(#65547c66),color-stop(.10,#382d4bcc),color-stop(.42,#242238ee),to(#29243de8))':grad('#242438','#1b1e30'),border:'1px solid #73608370',boxShadow:'none'", "backgroundColor:grad('#1b2540','#11182b'),border:'1px solid #73608370',boxShadow:'none',zIndex:'5'",'State button dark base independent of its narrow top reflection')
replace("boxShadow:'none',zIndex:'5'});\n }", "boxShadow:'none',zIndex:'5'});var buttonLight=deco(card,'PopupStudyButtonReflection',Math.round((cardW-138)/2)+1,197,136,4,card.__archiveUnlocked===true?'gradient(linear,0% 0%,0% 100%,from(#9773b970),to(#9773b900))':'gradient(linear,0% 0%,0% 100%,from(#8192af30),to(#8192af00))');s(buttonLight,{zIndex:'6'});\n }", 'Narrow button reflection separated from base and text')
replace("cardMaterial:cards[0]?{visible:", "cardBase:cards[0]?{gradient:cards[0].FindChildTraverse('PopupStudyCardBase').style.backgroundColor,hit:cards[0].FindChildTraverse('PopupStudyCardBase').hittest}:null,cardTopReflection:cards[0]?{h:cards[0].FindChildTraverse('PopupStudyCardTopReflection').actuallayoutheight,hit:cards[0].FindChildTraverse('PopupStudyCardTopReflection').hittest}:null,cardMaterial:cards[0]?{type:cards[0].FindChildTraverse('PopupStudyCardMaterial').paneltype,gradient:cards[0].FindChildTraverse('PopupStudyCardMaterial').style.backgroundColor,visible:", 'Audit actual loaded native base and reflection layers')
css=re.sub(r'\n\.PopupArenaV20[^\n]+\n','\n',css)
for ext,text in [('js',js),('css',css)]:
 (REC/f'v21.{ext}').write_text(text,encoding='utf8');(OUT/f'v21.{ext}').write_text(text,encoding='utf8');(OUT/f'v20_to_v21.{ext}.diff').write_text(''.join(difflib.unified_diff((REC/f'v20.{ext}').read_text(encoding='utf8').splitlines(True),text.splitlines(True),fromfile='v20.'+ext,tofile='v21.'+ext)),encoding='utf8')
(OUT/'changes.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf8')
p=ROOT/'tools/switch_archive_popup_ui.py';t=p.read_text(encoding='utf8').replace('1..20','1..21').replace('range(21)','range(22)');p.write_text(t,encoding='utf8')
for src,dst in [('after_v20.png','before_v20.png'),('after_v20.audit.json','before_v20.audit.json')]:shutil.copyfile(ROOT/'output/popup_visual_v20_20261010'/src,OUT/dst)
print('V21 built:',len(changes),'localized changes, native separate gradient layers; V20 retained.')
