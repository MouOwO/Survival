// Registry is the only source of runtime image paths. Page CSS/XML use ui-resource:// IDs.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'..'),kit=path.join(root,'art/ui/development/ui_reuse_import/ui_reuse_system_v1'),src=path.join(root,'panorama/src');
const specs=path.join(src,'ui');fs.mkdirSync(specs,{recursive:true});
for(const f of ['resource_registry.json','legacy_aliases.json','design_tokens.json','component_contracts.json','page_compositions.json'])if(!fs.existsSync(path.join(specs,f)))fs.copyFileSync(path.join(kit,'specs',f),path.join(specs,f));
const registry=JSON.parse(fs.readFileSync(path.join(specs,'resource_registry.json'))),aliases=JSON.parse(fs.readFileSync(path.join(specs,'legacy_aliases.json'))),tokens=JSON.parse(fs.readFileSync(path.join(specs,'design_tokens.json')));
const content='D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival/panorama';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const entries={},hashIds={},projectPaths={};
for(const [id,a] of Object.entries(registry.assets)){const output=path.join(src,'images/ui',a.file),input=fs.existsSync(output)?output:path.join(kit,a.file),b=fs.readFileSync(input);if(hash(b)!==a.source_sha256)throw Error('Hash mismatch '+id);fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,b);entries[id]={...a,runtime:'ui/'+a.file};hashIds[a.source_sha256]=id;}
const extraFile=path.join(src,'scripts/custom_game/common/ui_project_resources.json');
if(fs.existsSync(extraFile))Object.assign(projectPaths,JSON.parse(fs.readFileSync(extraFile)));
function legacy(relative){if(projectPaths[relative])return projectPaths[relative];const candidates=[path.join(src,'images',relative),path.join(content,'images',relative)];const file=candidates.find(f=>fs.existsSync(f));if(!file)throw Error('Missing existing image '+relative);const digest=hash(fs.readFileSync(file));const id=hashIds[digest]||'project.'+relative.replace(/\.[^.]+$/,'').replace(/[^a-zA-Z0-9_]+/g,'.');projectPaths[relative]=id;if(!entries[id])entries[id]={runtime:relative,file:null,scope:'project_variant',quality:'existing_project_resource_not_recropped',source_sha256:digest};return id;}
const pageFiles=['archive.js','lottery_ui.js','rogue_reward_ui.js','main_hud_skin.js','shop_ui.js','daily_rewards.js','treasure_history.js','reward_presentation.js','ability_tooltip.js','combat_stats.js'].map(n=>'scripts/custom_game/'+n)
 .concat(['archive.css','archive_kit.css','archive_difficulty.css','lottery_celestial.css','lottery.css','shop.css','rogue_reward_ui.css','main_hud_skin.css','main_hud_assets.css','daily_rewards.css'].map(n=>'styles/custom_game/'+n))
 .concat(['archive.xml','survival_hud.xml','lottery_window.xml','rogue_reward_ui.xml'].map(n=>'layout/custom_game/'+n));
for(const f of pageFiles){const file=path.join(src,f);if(!fs.existsSync(file))continue;let text=fs.readFileSync(file,'utf8');if(/\.(css|xml)$/.test(f))text=text.replace(/file:\/\/\{images\}\/([^"')]+\.(?:png|svg|jpg))/g,(_,url)=>'ui-resource://'+legacy(url));else text=text.replace(/(["'])file:\/\/\{images\}\/([^"']+\.(?:png|svg|jpg))\1/g,(_,q,url)=>'GameUI.CustomUIConfig().SurvivalUI.Asset('+JSON.stringify(legacy(url))+')');fs.writeFileSync(file,text);}
// Dynamic collections keep their existing files when there is no shared equivalent.
for(const dir of ['custom_game/main_hud_v1','custom_game/archive_kit/derived','custom_game/archive_kit/item_art','custom_game/lottery_handoff/v3']){const folder=path.join(src,'images',dir);if(!fs.existsSync(folder))continue;function visit(base){for(const e of fs.readdirSync(base,{withFileTypes:true})){const f=path.join(base,e.name);if(e.isDirectory())visit(f);else if(/\.(png|svg|jpg)$/.test(e.name))legacy(path.relative(path.join(src,'images'),f).replaceAll('\\','/'));}}visit(folder);}
// Rehydrate project-only IDs on repeat builds; shared IDs always keep their canonical file.
for(const [relative,id]of Object.entries(projectPaths))if(!entries[id]){const file=[path.join(src,'images',relative),path.join(content,'images',relative)].find(f=>fs.existsSync(f));if(!file)throw Error('Missing registered project image '+relative);entries[id]={runtime:relative,file:null,scope:'project_variant',quality:'existing_project_resource_not_recropped',source_sha256:hash(fs.readFileSync(file))};}
const dir=path.dirname(extraFile);fs.mkdirSync(dir,{recursive:true});fs.mkdirSync(path.join(src,'styles/custom_game/common'),{recursive:true});
fs.writeFileSync(extraFile,JSON.stringify(projectPaths,null,2));
const data={assets:entries,aliases,tokens,pending:registry.pending_assets,projectPaths};
fs.writeFileSync(path.join(dir,'ui_registry.js'),require('./ui_registry_source.cjs')(data));
fs.writeFileSync(path.join(src,'styles/custom_game/common/ui_assets.css'),Object.keys(entries).map((id,i)=>'.UIAssetDependency'+i+'{background-image:url("ui-resource://'+id+'");}').join('\n'));
fs.writeFileSync(path.join(root,'art/ui/development/ui_reuse_import/runtime_registry.json'),JSON.stringify(data,null,2));
fs.writeFileSync(path.join(root,'art/ui/development/ui_reuse_import/page_files.json'),JSON.stringify(pageFiles,null,2));
console.log('UI_REGISTRY_BUILD_PASS: '+Object.keys(registry.assets).length+' shared/page IDs, '+Object.keys(entries).length+' total registered IDs, '+Object.keys(aliases).length+' supplied aliases; old files retained');
