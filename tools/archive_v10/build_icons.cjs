'use strict';
// Explicit V10 display bindings. Never writes gameplay CSV, inventory or rewards.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),{csv}=require('../shop_ui_12h/catalog.cjs'),{open}=require('../vpk_inspect.cjs');
const sources={fragment:'data/csv/存档系统/archive_fragment_definitions.csv',building:'data/csv/存档系统/archive_building_items.csv',points:'data/csv/抽奖系统/lottery_item_definitions.csv'};
const buildings=['octarine_core','rapier','crimson_guard','claymore','abyssal_blade','platemail','arcane_boots','bfury','mjollnir'];
const nativeCorrections={fragment_10:{definition:'5810',from:'econ/items/legion_commander/demon_sword.png',to:'econ/items/legion_commander/blades_voth_domosh/blades_voth_domosh.png',reason:'同一Blades of Voth Domosh饰品的旧image_inventory路径在本机已失效；采用本机实际存在的该饰品目录原图'}};
const points=[
 ['lottery_gale_bow','grove_bow','疾风弓：原生长弓轮廓，保留弓的装备辨识度'],
 ['lottery_swift_emblem','medallion_of_courage','快速纹盘：原生金属勋章／纹盘外观'],
 ['lottery_soul_devouring_blade','diffusal_blade','噬魂灵剑：原生净魂之刃的灵能刀刃外观'],
 ['lottery_gathering_grimoire','tome_of_knowledge','采集秘典：原生书本图，采集属性仍沿用正式配置'],
 ['lottery_gathering_divine_codex','necronomicon_3','采集神典：原生高级魔法典籍外观'],
 ['lottery_aaron_cannon','greater_crit','亚伦巨炮：Dota原生大炮武器图，仅作为装备外观'],
 ['lottery_titan_shield','vanguard','泰坦巨盾：原生厚重盾牌外观'],
 ['lottery_reincarnation_orb','refresher','轮回宝珠：原生刷新球的循环／宝珠外观'],
 ['lottery_crystalline_armor','shivas_guard','晶态护甲：原生冰晶护甲图，与防护类别相符'],
 ['lottery_muramasa','yasha','妖刀村正：原生夜叉的东方长刀外观，不宣称是同名饰品'],
 ['lottery_sword_of_promise','rapier','誓约之剑：原生金色圣剑轮廓，不宣称是同名饰品'],
 ['lottery_spear_of_longinus','dragon_lance','朗基努斯枪：原生赤红长枪轮廓，不宣称是同名饰品'],
 ['lottery_magic_book','book_of_shadows','魔法书：原生魔法书装备图'],
 ['lottery_raven_eye','eye_of_the_vizier','渡鸦之眼：原生眼状秘宝图，不改变采集属性']
];
function sha(b){return crypto.createHash('sha256').update(b).digest('hex');}
function textureDimensions(text,resource){
 function value(field){const match=text.match(new RegExp('^'+field+'\\s*=\\s*(\\d+)','m'));return match?Number(match[1]):0;}
 const storage=[value('Width'),value('Height')],display=[value('DisplayRectW'),value('DisplayRectH')];
 const size=storage.map((n,i)=>display[i]>0?display[i]:n);
 if(!size.every(n=>Number.isInteger(n)&&n>0))throw Error('No real texture dimensions: '+resource);
 return {size,storageSize:storage,displayRect:display};
}
function kv(text){
 const tokens=(text.match(/\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+/g)||[]).filter(t=>!t.startsWith('//')&&!t.startsWith('/*'));let i=0;
 function scalar(t){return t&&t[0]==='"'?t.slice(1,-1).replace(/\\(["\\])/g,'$1'):t;}
 function object(){const out={};while(i<tokens.length&&tokens[i]!=='}'){let key=scalar(tokens[i++]);if(/^\[.*\]$/.test(key))continue;let value=tokens[i++];if(value==='{'){value=object();if(tokens[i++]!=='}')throw Error('Malformed KV block');}else value=scalar(value);out[key]=value;}return out;}return object();
}
function generate(){
 const native=JSON.parse(fs.readFileSync(path.join(root,'data/ui/archive_native_icons.json'),'utf8'));
 const formal=Object.fromEntries(Object.entries(sources).map(([category,file])=>[category,csv(path.join(root,file)).filter(r=>r.enabled==='1')]));
 const vpk=open(path.resolve(root,'../../dota/pak01_dir.vpk')),resourceIndex=new Map(vpk.entries.map(e=>[e.path,e]));
 const schema=kv(vpk.read(resourceIndex.get('scripts/items/items_game.txt')).toString('utf8')).items_game.items;
 const viewer=path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),work=path.join(root,'design_refs/archive_v10/work/icon_binding_verification');fs.mkdirSync(work,{recursive:true});
 const sizeCache=new Map(),bindings=[];
 function record(category,id,iconPath,reason,definition,correction){
  const key=category==='fragment'?'fragment_id':'item_id',row=formal[category].find(r=>r[key]===id);if(!row)throw Error('No enabled formal item: '+category+':'+id);
  const resource='panorama/images/'+iconPath.replace(/\.png$/,'_png.vtex_c'),entry=resourceIndex.get(resource);if(!entry)throw Error('Native resource missing: '+resource);
  const bytes=vpk.read(entry);let dimensions=sizeCache.get(resource);if(!dimensions){const temp=path.join(work,resource.replace(/[\\/]/g,'__'));if(!fs.existsSync(temp)||sha(fs.readFileSync(temp))!==sha(bytes))fs.writeFileSync(temp,bytes);const text=cp.execFileSync(viewer,['-i',temp,'-b','DATA'],{encoding:'utf8',windowsHide:true});dimensions=textureDimensions(text,resource);sizeCache.set(resource,dimensions);}const size=dimensions.size;
  const evidence={formal_file:sources[category],formal_id_field:key,formal_id:id,formal_name:row.display_name,resource,vpk:'../../dota/pak01_dir.vpk',resource_sha256:sha(bytes),match_reason:reason,texture_storage_size:dimensions.storageSize,texture_display_rect:dimensions.displayRect};
  if(definition){const original=schema[definition];if(!original)throw Error('No official item definition: '+definition);const hero='npc_dota_hero_'+row.source_boss;if(!original.used_by_heroes||!Object.hasOwn(original.used_by_heroes,hero))throw Error('Fragment hero binding mismatch: '+id+' '+hero);const inventory=original.image_inventory;if(inventory&&inventory+'.png'!==iconPath&&!(correction&&definition===correction.definition&&inventory+'.png'===correction.from&&iconPath===correction.to))throw Error('Official inventory image mismatch: '+id+' '+inventory);evidence.item_definition=definition;evidence.source_boss=row.source_boss;evidence.official_item_name=original.name;evidence.official_inventory_image=inventory;if(correction)evidence.native_path_correction=correction;}
  bindings.push({category,id,name:row.display_name,uri:'file://{images}/'+iconPath,fit:'contain',source_size:size,icon_key:category+':'+id+':'+resource,evidence});
 }
 for(const row of formal.fragment){const info=native[row.fragment_id];if(!info)throw Error('Unmapped formal fragment: '+row.fragment_id);const candidate=nativeCorrections[row.fragment_id],correction=candidate&&info.item_definition===candidate.definition&&info.icon_path===candidate.from?candidate:null;record('fragment',row.fragment_id,correction?correction.to:info.icon_path,'保留与正式来源英雄、Valve饰品定义精确对应的原生饰品图',info.item_definition,correction);}
 for(let i=0;i<buildings.length;i++)record('building','building_'+String(i+1).padStart(2,'0'),'items/'+buildings[i]+'.png','按正式存档神器名称匹配Dota同名物品图');
 for(const [id,name,reason]of points)record('points',id,'items/'+name+'.png',reason);
 const nativeIds=new Set(bindings.map(b=>b.category+':'+b.id));
 const retained=formal.points.filter(r=>!nativeIds.has('points:'+r.item_id)).map(r=>({category:'points',id:r.item_id,name:r.display_name,formal_file:sources.points,decision:'retain_existing_project_art',reason:/弦|罗盘|工具|之眼|之翼|炮|剑阵|剑仙|神典|秘典/.test(r.display_name)?'无足够准确的同名原生装备；保留项目已有独立图，不以其他武器凑方形':'结晶、材料、角色或专属神话／科幻主题：保留项目已有图，不套用正式CSV中的通用临时物品图'}));
 const sourceHashes=Object.fromEntries(Object.values(sources).map(file=>[file,sha(fs.readFileSync(path.join(root,file)))]));
 return {version:1,scope:'archive_v10_display_only',preserved_categories:['shadow','friend','ex','beast','pet','fishing','titles'],sources:sourceHashes,bindings,retained};
}
function moduleSource(data){return '// Generated by tools/archive_v10/build_icons.cjs. Display only; no gameplay or storage changes.\n(function(){"use strict";var rows='+JSON.stringify(data.bindings)+';var index={};rows.forEach(function(row){index[row.category+":"+row.id]=row;});GameUI.CustomUIConfig().ArchiveV10Icons={Resolve:function(item,category){if(!item||category==="shadow")return null;var row=index[String(category)+":"+String(item.id||"")];if(!row)return null;return {uri:row.uri,fit:row.fit,sourceSize:row.source_size.slice(),iconKey:row.icon_key,name:row.name};}};})();\n';}
function main(){const data=generate(),outputs={'data/ui/archive_v10_icon_bindings.json':JSON.stringify(data,null,2)+'\n','panorama/src/scripts/custom_game/archive_v10_icons.js':moduleSource(data)};for(const[file,value]of Object.entries(outputs)){const target=path.join(root,file);if(process.argv.includes('--check')){if(!fs.existsSync(target)||fs.readFileSync(target,'utf8').replace(/\r\n/g,'\n')!==value)throw Error('Generated icon binding out of date: '+file);}else{fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,value);}}console.log('ARCHIVE_V10_ICONS '+(process.argv.includes('--check')?'CHECK':'GENERATED')+' bindings='+data.bindings.length+' fragment='+data.bindings.filter(b=>b.category==='fragment').length+' building='+data.bindings.filter(b=>b.category==='building').length+' points='+data.bindings.filter(b=>b.category==='points').length+' retained_points='+data.retained.length);}
if(require.main===module)main();module.exports={generate,moduleSource,points,textureDimensions};
