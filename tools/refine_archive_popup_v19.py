"""Build isolated V19 archive visuals from existing project fonts and SVG icons.
Never overwrite an older version's glyph sheets or illustrations.
"""
from pathlib import Path
import sys,json,re,hashlib,zipfile,difflib,shutil
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'output/ui_review_python'))
from PIL import Image,ImageDraw,ImageFont,ImageFilter
REC=ROOT/'output/popup_iterations_20261009';OUT=ROOT/'output/popup_visual_v19_20261010';ASSETS=REC/'assets';OUT.mkdir(exist_ok=True)
CONTENT=ROOT.parents[2]/'content/dota_addons/survival'
REGULAR=ROOT/'panorama/fonts/Radiance-Survival-SourceHanSansSC-Regular.otf'
MEDIUM=ROOT/'panorama/fonts/Radiance-Survival-SourceHanSansSC-Medium.otf'
original=(REC/'v18.js').read_text(encoding='utf8');js=original;css=(REC/'v18.css').read_text(encoding='utf8')
files=[ROOT/'tools/switch_archive_popup_ui.py',REC/'active_version.json',REC/'v18.js',REC/'v18.css',REC/'v12.js',REC/'v12.css']
for base,pre in [(ROOT,'panorama/src'),(CONTENT,'panorama')]:
 for name in ['layout/custom_game/archive.xml','scripts/custom_game/archive_popup_study.js','styles/custom_game/archive_popup_study.css']:files.append(base/pre/name)
if not (OUT/'before_v19.zip').exists():
 with zipfile.ZipFile(OUT/'before_v19.zip','w',zipfile.ZIP_DEFLATED) as z:
  manifest={}
  for i,p in enumerate(files):
   key=f'{i:02d}_{p.name}';data=p.read_bytes();z.writestr(key,data);manifest[key]={'path':str(p),'sha256':hashlib.sha256(data).hexdigest()}
  z.writestr('manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2))
changes=[]
def replace(old,new,reason):
 global js
 assert js.count(old)==1,(reason,js.count(old));js=js.replace(old,new);changes.append({'reason':reason,'old':old,'new':new})
replace('version=18;','version=19;','Versioned archive visual refinement')
# Independent Regular glyph pages, with exactly the previous supported characters.
old_atlas=json.loads(js.split('var atlas=',1)[1].split(',missingGlyphs=',1)[0]);ordered=list(old_atlas['glyphs']);font=ImageFont.truetype(str(REGULAR),32)
metrics={};pages=[]
for start in range(0,len(ordered),1024):
 page=Image.new('RGBA',(2048,2048));draw=ImageDraw.Draw(page);num=len(pages)
 for index,ch in enumerate(ordered[start:start+1024]):
  x=index%32*64;y=index//32*64;draw.text((x+8,y+8+font.getmetrics()[0]),ch,font=font,anchor='ls',fill='white');metrics[ch]=[num,x,y,round(font.getlength(ch),3)]
 name=f'arena_font_v19_{num}.png';page.save(ASSETS/name);pages.append(name)
atlas={'size':32,'cell':64,'side':2048,'padding':8,'logical_height':sum(font.getmetrics()),'pages':pages,'glyphs':metrics}
replace(json.dumps(old_atlas,ensure_ascii=False,separators=(',',':')),json.dumps(atlas,ensure_ascii=False,separators=(',',':')),'Regular body atlas; preserve prior versions')
(OUT/'font_atlas.json').write_text(json.dumps({'font':'Source Han Sans SC Regular','font_sha256':hashlib.sha256(REGULAR.read_bytes()).hexdigest(),**atlas},ensure_ascii=False),encoding='utf8')
rows=re.findall(r'category_id = "([^"]+)", display_name = "([^"]+)"',(ROOT/'scripts/vscripts/config/generated/archive_categories.lua').read_text(encoding='utf8'))
for key,text in rows+[('archive','存档')]:
 for role,w,h,size,fontfile in [('heading',680,110,64,MEDIUM),('nav',280,64,36,REGULAR)]:
  f=ImageFont.truetype(str(fontfile),size);im=Image.new('RGBA',(w,h));d=ImageDraw.Draw(im);b=d.textbbox((0,0),text,font=f);x=(w-b[2]+b[0])/2-b[0] if role=='heading' else -b[0];y=(h-b[3]+b[1])/2-b[1]
  if role=='heading':
   glow=Image.new('RGBA',(w,h));ImageDraw.Draw(glow).text((x,y),text,font=f,fill=(175,145,210,95));im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(1.7)))
  ImageDraw.Draw(im).text((x,y),text,font=f,fill=(228,221,240,255) if role=='heading' else (221,214,234,255));im.save(ASSETS/f'arena_v19_{role}_{key}.png')
for key,text in [('unlocked','已解锁'),('locked','未解锁'),('detail','查看详情')]:
 f=ImageFont.truetype(str(REGULAR),32);im=Image.new('RGBA',(280,64));d=ImageDraw.Draw(im);b=d.textbbox((0,0),text,font=f);d.text(((280-b[2]+b[0])/2-b[0],(64-b[3]+b[1])/2-b[1]),text,font=f,fill=(221,214,234,255) if key=='unlocked' else (163,154,180,255));im.save(ASSETS/f'arena_v19_state_{key}.png')
# Reuse existing semantic vectors; fill remaining categories with small code-native outlines.
paths={
 'shadow':'M42 12 C17 7 4 38 24 51 C36 59 50 52 54 42 C34 48 26 26 42 12 Z',
 'points':'M32 8 15 24l17 32 17-32zM15 24h34M32 8v48M15 24l17 9 17-9',
 'fragment':'M15 12l35 35M12 17l10-8M44 45l8 7M47 12L12 47M42 9l10 8M20 43l-8 9',
 'pet':'M15 50V27a17 17 0 0 1 34 0v23M10 52h44M23 17v33M32 12v38M41 17v33M12 30h40',
 'friend':'M20 28a8 8 0 1 0 0-16 8 8 0 0 0 0 16M43 29a7 7 0 1 0 0-14 7 7 0 0 0 0 14M7 51v-5c0-17 27-17 27 0v5zM37 36c12-4 20 3 20 12v3H40',
 'ex':'M32 52 11 30C-1 16 19 4 32 19 45 4 65 16 53 30z',
 'beast':'M12 48c20 9 44-1 38-20-3-8-12-10-19-6M31 22l-6-9 11 1 5-8 7 13M14 34c-9 2-6 13 2 13M26 29c-5 10 5 14 11 7',
 'shop':'M12 26h40l-5 27H17zM20 26l6-14M44 26l-6-14M24 33v12M32 33v12M40 33v12',
 'titles':'M10 20l11 13L32 13l11 20 11-13-6 29H16zM17 54h30',
 'archive':'M13 12h38v40H13zM22 22h20M22 32h20M22 42h12'}
nav_source=ROOT/'panorama/src/images/custom_game/archive_polish_v1/nav'
for key,_ in rows+[('archive','存档')]:
 p=nav_source/f'{key}.svg'
 if p.exists():svg=re.sub(r'#[0-9a-fA-F]{3,8}', '#ffffff',p.read_text(encoding='utf8'))
 else:
  assert key in paths,key
  svg='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" d="'+paths[key]+'"/></svg>'
 (ASSETS/f'arena_navicon_v19_{key if key!='shadow' else 'shadow_r2'}.svg').write_text(svg,encoding='utf8')
replace("arena_'+role+'_'+key+'.png'","arena_v19_'+role+'_'+key+'.png'",'Use lighter nav typography and tighter title glow')
replace("arena_state_'+(card.__archiveUnlocked", "arena_v19_state_'+(card.__archiveUnlocked",'Regular-weight card state text')
js=js.replace("#e5dcf5","#DDD6EA").replace("#ab9abc","#A39AB4")
replace("backgroundColor:'#141a2dfc'","backgroundColor:'#171B2Cfc'",'Cold deep blue-purple window')
replace("border:'1px solid #65527d'","border:'1px solid #73698188'",'Quiet outer edge')
replace("grad('#24223b','#1b1b30')","grad('#1d2034','#171B2C')",'Header blends into deep background')
replace("grad('#1e213b','#25334d')","grad('#1b2136','#20283d')",'Independent cool navigation backing')
replace("borderRight:'1px solid #77719966'","borderRight:'1px solid #625c7566'",'Quiet navigation divider')
replace("grad('#191b30','#242139')","grad('#171B2C','#1e2135')",'Independent content backing')
replace("from(#26203955),color-stop(.46,#222037bb),color-stop(.72,#242139ee),to(#242139ff)","from(#171B2C40),color-stop(.46,#191d30a8),color-stop(.72,#1b1f32df),to(#1b1f32ff)",'Separate cool illustration veil, preserve architecture and warm lamps')
replace("from(#65458b99),color-stop(.5,#4d3868aa),to(#28243cbb)","from(#5944748a),color-stop(.5,#342d4baa),to(#1c2033dd)",'Selected nav: localized soft interior')
replace("grad('#25243b','#1a1d31')","grad('#232238b8','#191d30dd')",'Quiet inactive navigation')
replace("n.checked?'#9574b3bb':'#66547a77'","n.checked?'#8d769faa':'#69607855'",'Navigation edge hierarchy')
replace("n.checked?'2px solid #aa88cd':'1px solid #66547a77'","n.checked?'2px solid #b292d0b3':'1px solid #69607855'",'Selected local left edge')
# Hide mixed legacy icons without deleting or changing their events.
needle=" p('ArchiveTabs').Children().forEach(function(n){if(!has(n,'ArchiveTab'))return;"
replace(needle,needle+"\n var navKey=String(n.id).replace('ArchiveTab_','');var navIcon=trace(n,'PopupStudyNavIcon','arena_navicon_v19_'+(navKey==='shadow'?'shadow_r2':navKey)+'.svg',9,16,36,36);s(navIcon,{washColor:n.checked?'#d3c5e5':'#afa6c2',brightness:'1',saturation:'1',zIndex:'8'});",'Unified passive 36px category outline icons')
replace("if(has(c,'ArchiveNavIcon')){box(c,10,19,30,30);s(c,{washColor:'#c1a6f4'});}","if(has(c,'ArchiveNavIcon'))s(c,{visibility:'collapse'});",'Suppress mixed old nav rasters and crown text')
replace("from(#705198aa),color-stop(.5,#4d3868aa),to(#28243cbb)","from(#624b8090),color-stop(.5,#392e50b0),to(#20243add)",'Selected filter: restrained local purple')
replace("grad('#2a283fbb','#1b1d30dd')","grad('#202238c0','#171B2Cdd')",'Deep inactive filter')
replace("border:'1px solid #715882',borderBottom:n.checked?'2px solid #b190d4cc':'1px solid #715882'","border:'1px solid #6b607b66',borderBottom:n.checked?'1px solid #bc8edfaa':'1px solid #6b607b66'",'Thin filter borders with local selected underline')
replace("fontSize:'19px',fontFamily:font,lineHeight:'24px',color:'#bba8ce'","fontSize:'18px',fontFamily:font,lineHeight:'26px',color:'#A39AB4'",'Regular secondary explanation')
replace("fontSize:'17px',color:'#d2c6e6'","fontSize:'15px',color:'#bcb2cd'",'Secondary header metadata')
replace("backgroundColor:align==='right'?'#17172588':'transparent'","backgroundColor:align==='right'?'#12172955':'transparent'",'Subtle progress chip')
replace("from(#23283db8),color-stop(.40,#29283ed9),color-stop(.68,#342c48d9),color-stop(.86,#443054d9),to(#503563d9)","from(#20243acc),color-stop(.60,#232238cc),color-stop(.94,#332845d0),to(#493257d0)",'Dark cool cards, purple confined to lower field')
replace("border:'1px solid #7b648a99',borderBottom:'2px solid #a56bdbbb'","border:'1px solid #756b875c',borderBottom:'1px solid #9876b3aa'",'One-pixel quiet card edges, slightly brighter bottom')
replace("var titlePage=(cfg.ArchiveHandoff.snapshot||{}).category_id==='titles'","var clearPage=(cfg.ArchiveHandoff.snapshot||{}).category_id==='clear',titlePage=(cfg.ArchiveHandoff.snapshot||{}).category_id==='titles'",'Scope badge sizing and tint fix to clear achievements')
replace("if(has(n,'ArchiveArt')){box(n,Math.round((cardW-118)/2),27,118,118);s(n,{backgroundImage:'none',backgroundColor:'transparent',border:'0px'});}","if(has(n,'ArchiveArt')){var artSize=clearPage?132:118;box(n,Math.round((cardW-artSize)/2),clearPage?20:27,artSize,artSize);s(n,{backgroundImage:'none',backgroundColor:'transparent',border:'0px'});}\n if(clearPage&&has(n,'ArchiveRewardIcon'))s(n,{washColor:'none',saturation:card.__archiveUnlocked===true?'1':'.08',brightness:card.__archiveUnlocked===true?'1.04':'.64',opacity:'1',width:'100%',height:'100%'});",'Measured badge footprint: enlarge slightly and recover original silver highlights; dim only locked badges')
replace("cardW-10,28,18,'#e4d6f6'","cardW-10,28,17,'#DDD6EA'",'Regular card names subordinate to artwork')
replace("23,14,'#c4b2d8'","23,14,'#A39AB4'",'Lower weight progress text')
button="'gradient(linear,0% 0%,0% 100%,from(#65547c66),color-stop(.10,#382d4bcc),color-stop(.42,#242238ee),to(#29243de8))'"
for old in ["grad('#7951ab','#322741')","grad('#65418b','#242035')","grad('#7752a6','#372842')"]:
 replace(old,button,'Dark action surface with narrow top reflection')
replace("backgroundColor:grad(card.__archiveUnlocked===true?'#754ba6':'#3e334e','#231e31'),border:'1px solid #684788'","backgroundColor:card.__archiveUnlocked===true?"+button+":grad('#242438','#1b1e30'),border:'1px solid #73608370'",'Quiet state buttons, no broad luminous purple fill')
# Detail popup uses the same palette. Rich text remains live and retains numeric colors.
replace("backgroundColor:'#1a192bf8',border:'1px solid #846399'","backgroundColor:'#171B2Cfc',border:'1px solid #80728e99'",'Unified detail tooltip surface and thin edge')
replace("backgroundColor:'#1a192bf8'","backgroundColor:'#171B2Cfc'",'Unified tooltip body')
replace("s(p('ArchiveTooltipName'),{color:'#eee0ff',fontSize:'23px'});s(p('ArchiveTooltipDivider'),{backgroundColor:'#705083',height:'1px'});", "styleTooltip(tip);",'Use the project Regular atlas for actual tooltip text')
helper=r"""
function styleTooltip(tip){
 var textW=(parseFloat(cfg.SurvivalArchiveColors.tooltip_width)||460)-40;
 ['ArchiveTooltipName','ArchiveTooltipEffect','ArchiveTooltipCondition'].forEach(function(id){var n=p(id);s(n,{width:textW+'px',height:'fit-children',fontFamily:font,fontWeight:'normal',fontSize:id==='ArchiveTooltipName'?'23px':'18px',lineHeight:id==='ArchiveTooltipName'?'30px':'27px',color:id==='ArchiveTooltipName'?'#DDD6EA':id==='ArchiveTooltipEffect'&&p('ArchiveTooltipStateText').text==='未解锁'?'#A39AB4':'#c4bbd4',textAlign:'left',whiteSpace:'normal',textShadow:'none'});});
 ['ArchiveTooltipStateText','ArchiveTooltipProgressLabel','ArchiveTooltipProgress'].forEach(function(id){s(p(id),{fontFamily:font,fontWeight:'normal',fontSize:'17px',lineHeight:'25px',height:'28px',width:id==='ArchiveTooltipProgress'?Math.max(80,textW-120)+'px':'110px',textAlign:id==='ArchiveTooltipProgress'?'right':'left',color:id==='ArchiveTooltipProgress'?'#d9c28e':'#A39AB4',whiteSpace:'nowrap'});});
 s(p('ArchiveTooltipDivider'),{backgroundImage:'none',backgroundColor:'#70647e66',height:'1px'});
 s(p('ArchiveTooltipStateIcon'),{washColor:'#c8bbda',brightness:'1',saturation:'0'});
 walk(tip,function(n){if(String(n.paneltype).toLowerCase()==='label'&&n.html){if(n.__popupAtlasOriginalHtml===undefined)n.__popupAtlasOriginalHtml=n.html;n.html=false;}});
 renderText(tip);
}
function richInk(text,base){var colors=[],stack=[base];String(text||'').split(/(<[^>]+>)/g).forEach(function(t){if(/^<br/i.test(t)){colors.push(stack[stack.length-1]);return;}if(/^<font/i.test(t)){var m=t.match(/color=[\"']([^\"']+)/i);stack.push(m?m[1]:stack[stack.length-1]);return;}if(/^<\/font/i.test(t)){if(stack.length>1)stack.pop();return;}if(/^</.test(t))return;Array.from(plainText(t)).forEach(function(){colors.push(stack[stack.length-1]);});});return colors;}
"""
replace('function renderText(scope){',helper+'\nfunction renderText(scope){','Tooltip typography keeps native data and inline numeric emphasis')
replace("var v=n.__popupStudyValues||{},ink=v.color||'#DDD6EA',text=plainText(n.text);","var v=n.__popupStudyValues||{},ink=v.color||'#DDD6EA',text=plainText(n.text),inks=richInk(n.text,ink),ci=0;",'Track rich-text color per glyph')
replace("Array.from(text).forEach(function(c){if(truncated)return;", "Array.from(text).forEach(function(c){var charInk=inks[ci++]||ink;if(truncated)return;",'Assign semantic text colors')
replace("lines[lines.length-1].push({m:m,x:x,advance:advance});", "lines[lines.length-1].push({m:m,x:x,advance:advance,color:charInk});",'Keep inline numbers colored')
replace("var signature=text+'|'+size", "var signature=text+'|'+size",'Retain stable footer signature')
replace("if(run.__glyphSignature===signature)return;run.__glyphSignature=signature;", "if(run.__glyphSignature===signature&&run.__glyphRichSource===String(n.text))return;run.__glyphSignature=signature;run.__glyphRichSource=String(n.text);",'Refresh when rich markup changes')
replace("child.style.washColor=ink;","child.style.washColor=g.color||ink;",'Regular glyphs preserve rich-text values')
# Audit exposes only UI geometry and style, no account data.
replace("version:version,footer:","version:version,viewport:[root.actuallayoutwidth,root.actuallayoutheight,root.actualuiscale_x,root.actualuiscale_y],window:{xy:p('ArchiveWindow').GetPositionWithinWindow(),w:p('ArchiveWindow').actuallayoutwidth,h:p('ArchiveWindow').actuallayoutheight,reviewScale:p('ArchiveWindow').GetAttributeString('popup_review_scale','1'),transform:p('ArchiveWindow').style.transform},tooltip:{visible:!has(p('ArchiveTooltip'),'ArchiveHidden'),xy:p('ArchiveTooltip').GetPositionWithinWindow(),w:p('ArchiveTooltip').actuallayoutwidth,h:p('ArchiveTooltip').actuallayoutheight,name:p('ArchiveTooltipName').text,z:p('ArchiveTooltip').style.zIndex,windowZ:p('ArchiveWindow').style.zIndex,opacity:p('ArchiveTooltip').style.opacity,visibility:p('ArchiveTooltip').style.visibility,actualVisible:p('ArchiveTooltip').visible,parent:p('ArchiveTooltip').GetParent().id},footer:",'Native acceptance inspection')
replace("if(action!=='hover')cfg.ArchiveHandoff.Hide();", "if(action!=='hover'&&action!=='audit')cfg.ArchiveHandoff.Hide();",'Inspection does not dismiss hovered detail popup')
# Passive 10px bottom transition, with no outer glow.
replace("function trace(parent,id,file,x,y,w,h)","function deco(parent,id,x,y,w,h,background){var n=parent.FindChildTraverse(id);if(!n){n=$.CreatePanel('Panel',parent,id);n.hittest=false;n.hittestchildren=false;}box(n,x,y,w,h);s(n,{backgroundColor:background,zIndex:'1'});return n;}\nfunction trace(parent,id,file,x,y,w,h)",'Passive narrow inner edge')
replace("var frame=trace(card,'PopupStudyCardTrace'", "deco(card,'PopupStudyBottomEdge',1,h-11,cardW-2,10,'gradient(linear,0% 0%,0% 100%,from(#684b8600),to(#7e58992b))');\n var frame=trace(card,'PopupStudyCardTrace'",'Narrow soft purple at inside bottom edge')
# Local console size review; default remains 1 and does not alter save data.
replace("if(action==='close')cfg.SurvivalArchive.Close();", "if(action==='scale'){var scale=Math.max(.7,Math.min(1,Number(arg)||1));p('ArchiveWindow').SetAttributeString('popup_review_scale',String(scale));s(p('ArchiveWindow'),{preTransformScale2d:String(scale)});}"+"\n if(action==='close')cfg.SurvivalArchive.Close();",'Local console native window scale review')
replace("var cardWidth=(parseFloat(anchor.style.width)||196)*sx*fit,", "var reviewScale=Number(p('ArchiveWindow').GetAttributeString('popup_review_scale','1'))||1;var cardWidth=(parseFloat(anchor.style.width)||196)*sx*fit*reviewScale,",'Tooltip follows review scaling')
replace("win.x+1280*sx*fit-12*sx", "win.x+1280*sx*fit*reviewScale-12*sx",'Keep tooltip bounds inside scaled window')
# CSS hover remains distinguishable from the selected state without a halo.
css=css.replace('brightness:1.12','brightness:1.045').replace('brightness:1.10','brightness:1.06').replace('brightness:1.4','brightness:1.12').replace('background-color:#69508466','background-color:#4e3a6566')
for file in ASSETS.glob('*v19*'):
 if file.suffix in ['.png','.svg']:css+='\n.PopupArenaV19Asset'+hashlib.sha256(file.name.encode()).hexdigest()[:10]+' {background-image:url("file://{images}/custom_game/popup_study/'+file.name+'");}\n'
for ext,data in [('js',js),('css',css)]:
 (REC/f'v19.{ext}').write_text(data,encoding='utf8');(OUT/f'v19.{ext}').write_text(data,encoding='utf8');base=(REC/f'v18.{ext}').read_text(encoding='utf8');(OUT/f'v18_to_v19.{ext}.diff').write_text(''.join(difflib.unified_diff(base.splitlines(True),data.splitlines(True),fromfile=f'v18.{ext}',tofile=f'v19.{ext}')),encoding='utf8')
(OUT/'changes.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'asset_manifest.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in ASSETS.glob('*v19*') if p.is_file()},indent=2),encoding='utf8')
switcher=ROOT/'tools/switch_archive_popup_ui.py';t=switcher.read_text(encoding='utf8');assert 'choices=range(19)' in t or 'choices=range(20)' in t;switcher.write_text(t.replace('choices=range(19)','choices=range(20)').replace('1..18','1..19'),encoding='utf8')
shutil.copyfile(ROOT/'output/popup_card_balance_v18_20261010/after_clear.png',OUT/'before_v18.png')
print('V19 built with separate Regular glyph pages, tighter Medium title, semantic outline icons and scoped original-badge treatment.')
