const fs=require('fs'),p=require('path'),crypto=require('crypto');
const here=__dirname,repo=p.resolve(here,'../../../..'),engine=p.resolve(repo,'../../..'),source=p.join(here,'baseline/content');
const current=p.join(engine,'content/dota_addons/survival_ui_handoff_v1/panorama'),out=p.join(here,'candidate/panorama');
const pack=p.join(repo,'art/ui/development/ui_handoff_v1/received/ui_import_handoff_v1');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const read=f=>fs.readFileSync(f,'utf8').replace(/\r\n/g,'\n');
const write=(rel,data)=>{let dest=p.join(out,rel);fs.mkdirSync(p.dirname(dest),{recursive:true});fs.writeFileSync(dest,data);};
let assets=[],assetPaths={};
const python=process.env.SURVIVAL_PYTHON||p.join(require('os').homedir(),'AppData/Local/Programs/Python/Python314/python.exe');
const iconRead=require('child_process').spawnSync(python,[p.join(repo,'tools/read_archive_icons.py')],{encoding:'utf8'});
if(iconRead.status!==0)throw Error(iconRead.stderr||'Archive icon table validation failed');
const iconEntries=JSON.parse(iconRead.stdout);
const textureWritten=new Set();
for(const entry of iconEntries){
 const runtime='images/'+entry.icon_path,original_path='panorama/src/'+runtime;
 const bytes=fs.readFileSync(p.join(repo,original_path));write(runtime,bytes);
 assets.push({original_path,runtime,sha256:hash(bytes),kind:'generated_archive_icon'});
 // Compile a bounded, mipmapped texture from the untouched PNG master.
 // Directly sampling a 1254px PNG into a ~64px card aliases fine character art.
 for(const size of [{name:'small',limit:64},{name:'regular',limit:256}]){
 const textureId=entry.icon_path.startsWith('custom_game/archive_heads_v2/')?'head_v2_'+p.basename(entry.icon_path,'.png'):entry.icon_path.startsWith('custom_game/archive_portraits_v1/')?'portrait_'+p.basename(entry.icon_path,'.png'):entry.icon_path.startsWith('custom_game/archive_polish_v1/')?'polish_'+p.basename(entry.icon_path,'.png'):entry.item_id;
 const texture='images/custom_game/archive_gpu_'+size.name+'/'+textureId+'.vtex';
 const vtex='<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->\n"CDmeVtex"\n{\n'+
 '"m_inputTextureArray" "element_array" [ "CDmeInputTexture" { "m_name" "string" "0" "m_fileName" "string" "panorama/'+runtime+'" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" } ]\n'+
 '"m_outputTypeString" "string" "2D"\n"m_outputFormat" "string" "BGRA8888"\n"m_outputClearColor" "vector4" "0 0 0 0"\n"m_nOutputMinDimension" "int" "0"\n"m_nOutputMaxDimension" "int" "'+size.limit+'"\n"m_bNoLod" "bool" "0"\n'+
 '"m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" { "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" } "m_outputColorSpace" "string" "srgb" } ]\n}\n';
 if(!textureWritten.has(texture)){write(texture,vtex);assets.push({original_path:'art/ui/development/remaining_ui_handoff_v1/candidate/panorama/'+texture,runtime:texture,sha256:hash(vtex),kind:'compiled_icon_recipe'});textureWritten.add(texture);}
 entry[size.name==='small'?'small_runtime_uri':'runtime_uri']='s2r://panorama/'+texture;
 }
}
function asset(page,basename,key){const list=JSON.parse(read(p.join(pack,'pages',page,'asset_map.json'))),a=list.find(a=>p.basename(a.original_path)===basename);if(!a)throw Error('Missing mapped resource '+page+'/'+basename);const bytes=fs.readFileSync(p.join(pack,a.shared_asset));if(hash(bytes)!==a.sha256)throw Error('SHA mismatch '+basename);let runtime='images/custom_game/remaining_handoff_ready/'+key+p.extname(basename);write(runtime,bytes);assets.push({...a,runtime});return assetPaths[key]='file://{images}/'+runtime.slice(7);}
const navFiles={};
for(const name of ['preview_qr.png','shop.png']){const runtime='images/custom_game/shop_preview_v1/'+name,bytes=fs.readFileSync(p.join(repo,'panorama/src',runtime));write(runtime,bytes);assets.push({original_path:'panorama/src/'+runtime,runtime,sha256:hash(bytes),kind:'preview_asset'});}
for(const line of read(p.join(repo,'data/csv/存档系统/archive_navigation_icons.csv')).trim().split('\n').slice(1)){
 const [id,name,file]=line.split(',');const original_path='panorama/src/images/'+file,runtime='images/'+file;
 const bytes=fs.readFileSync(p.join(repo,original_path));write(runtime,bytes);assets.push({original_path,runtime,sha256:hash(bytes),kind:'archive_navigation_vector'});navFiles[id]='file://{images}/'+file;
}
for(let name of ['top_left','top','top_right','left','center','right','bottom_left','bottom','bottom_right','header_texture','title_ornament_left','title_ornament_right','close_normal','close_hover','close_pressed'])asset('common_window',name+'.png','window_'+name);
for(let name of ['left','middle','right'])asset('pool_details','tab_'+name+'.png','tab_'+name);
asset('pool_details','interaction_components_v2_tab_selected_overlay.png','tab_glow');
asset('pool_details','interaction_components_v2_card_normal.png','reward_card');
asset('pool_details','content_material.png','pool_content');
asset('lottery_history','history_empty_icon.png','history_empty');
asset('lottery_history','lottery_ui_v3_history_icon_normal.png','history_icon');
asset('pool_details','detail_controls_v1_scroll_thumb_normal.png','scroll_thumb');
asset('pool_details','detail_controls_v1_scroll_track.png','scroll_track');
for(let state of ['normal','hover','pressed','disabled'])asset('common_interaction','button_secondary_'+state+'.png','button_secondary_'+state);
for(let name of ['back','combat','defense','growth'])asset('roguelike',name+'.png','rogue_'+name);
const rogueArtEntries=require('../ui_stage3_v1/prepare_assets.cjs')(repo,write,assets);
const cleanRel='images/custom_game/rogue_clean_base_v1/blank.png',cleanBytes=fs.readFileSync(p.join(repo,'panorama/src',cleanRel));
write(cleanRel,cleanBytes);assets.push({original_path:'panorama/src/'+cleanRel,runtime:cleanRel,sha256:hash(cleanBytes),kind:'clean_card_base'});
const rogueArt=read(p.join(repo,'art/ui/development/ui_stage3_v1/rogue_art.js')).replace('/*ROGUE_ART_ENTRIES*/',JSON.stringify(rogueArtEntries)).replace('/*ROGUE_CARD_BASE*/',JSON.stringify(assetPaths.rogue_combat)).replace('/*ROGUE_CLEAN_BASE*/',JSON.stringify('s2r://panorama/images/custom_game/rogue_clean_base_v1/blank_png.vtex'));
for(let name of ['card_normal_native','card_hover_native','product_hover_scrim','payment_normal','payment_selected','qr_loading','qr_outer','quantity_step','quantity_value','icon_points_dark','icon_u_currency_dark'])asset('shop_states',name+'.png','shop_'+name);
for(let state of ['normal','hover','pressed','disabled'])asset('shop_states','button_primary_'+state+'.png','button_primary_'+state);
for(let name of ['bundle_compact','bundle_footer_compact'])asset('shop_bundles',name+'.png','shop_'+name);
asset('common_controls','icon_check_dark.png','action_check');
asset('common_controls','icon_chevron_down_light.png','action_chevron');
asset('hud_top_boss','warning.png','boss_warning_icon');
for(let [name,key] of [['day_card','day'],['week_card','week'],['runtime_calendar_normal','calendar'],['runtime_check_claimed','claimed'],['runtime_crystals_medallion','crystals'],['runtime_rules_local_normal','rules'],['detail_controls_v1_badge_pass','premium'],['detail_controls_v1_badge_ready','ready'],['detail_controls_v1_badge_locked','locked'],['detail_controls_v1_icon_info_dark','info']])asset('daily',name+'.png','daily_'+key);
let css=read(p.join(here,'common.css'))+'\n'+read(p.join(here,'lottery_dialogs.css'))+'\n'+read(p.join(here,'daily.css'))+'\n'+read(p.join(here,'rogue.css'))+'\n'+read(p.join(here,'commerce.css'))+'\n'+read(p.join(here,'archive_navigation.css'))+'\n'+read(p.join(here,'archive_icons.css'));
css+='\n'+read(p.join(here,'lottery_results.css'))+'\n'+read(p.join(here,'boss_warning.css'));
css+='\n'+read(p.join(repo,'art/ui/development/shop_preview_v1/style.css'));
css+='\n'+read(p.join(repo,'art/ui/development/archive_polish_v1/nine_slice.css'));
css=css.replace(/asset\(([\w]+)\)/g,(_,k)=>{if(!assetPaths[k])throw Error('Missing asset '+k);return 'url("'+assetPaths[k]+'")';});
const bossWarning=read(p.join(here,'boss_warning.js')).replace('/*WARNING_ICON*/',JSON.stringify(assetPaths.boss_warning_icon));
// UI components may retain an earlier registry across native layout reloads.
// Resolve daily assets from their actual delivered registry at build time.
const dailyConfig={SurvivalUIRegistry:{assets:{}}};
require('vm').runInNewContext(read(p.join(source,'scripts/custom_game/daily_resources.js')),{GameUI:{CustomUIConfig:()=>dailyConfig}});
const dailyResources=dailyConfig.SurvivalUIRegistry.assets;
for(const entry of Object.values(dailyResources))if(!fs.existsSync(p.join(current,'images',entry.runtime)))throw Error('Missing delivered daily resource '+entry.runtime);
let helper=read(p.join(here,'common.js')).replace('/*ASSETS*/',JSON.stringify(assetPaths)).replace('/*DAILY_RESOURCES*/',JSON.stringify(dailyResources));
helper=read(p.join(repo,'art/ui/development/archive_polish_v1/nine_slice.js'))+'\n'+helper;
let daily=read(p.join(source,'scripts/custom_game/daily_rewards.js'));
daily=require('../ui_stage3_v1/patch_daily.cjs')(daily);
daily=daily.replace('U=cfg.SurvivalUI,data=','U=cfg.SurvivalUI,RH=cfg.RemainingHandoff,data=');
daily=daily.replace('width:1348,height:758','width:1344,height:752');
daily=daily.replace("function tip(p,title,body){U.Tooltip.Bind(p,{title:title,body:body});}","function tip(p,title,body){RH.DailyTooltip(p,title,body);}");
daily=daily.replace("p('DailyRulesText').AddClass('ArchiveHidden');","p('DailyRulesText').AddClass('ArchiveHidden');p('DailyTooltip').AddClass('ArchiveHidden');");
daily=daily.replace("function renderCards(){p('DailyCards').RemoveAndDeleteChildren();","var cardSignature='';\nfunction renderCards(){var next=JSON.stringify([data.cycle,data.premium]);if(next===cardSignature&&p('DailyCards').GetChildCount()===7)return;cardSignature=next;p('DailyCards').RemoveAndDeleteChildren();");
daily=daily.replace("function image(parent,id,cls){return U.Image(parent,id,cls);}","function image(parent,id,cls){return RH.DailyImage(parent,id,cls);}");
const dailyRewardArt="image(slot,artId(item),'DailyItemArt')";
if(daily.split(dailyRewardArt).length!==2)throw Error('Daily reward image anchor changed');
daily=daily.replace(dailyRewardArt,"((cfg.SurvivalItemArt&&cfg.SurvivalItemArt.Create(slot,item,'DailyItemArt'))||image(slot,artId(item),'DailyItemArt'))");
daily=daily.replaceAll("SetScaling('scale-to-fit')","SetScaling('stretch-to-fit-preserve-aspect')");
daily=daily.replace('U.ResourceInfo(item.art_id)','RH.DailyResourceInfo(item.art_id)');
daily=daily.replace(/for\(var r=0;r<3;r\+\+\)for\(var c=0;c<3;c\+\+\)\{.*?\}\n/,"RH.Window(p('DailyWindow'),p('DailyHeader'),p('DailyClose'));RH.SizeWindow(p('DailyWindow'),1344,752);\n");
daily=daily.replace("rect(image(p('DailyHeader'),'daily.icon.calendar.normal','DailyCalendar'),536,14,72,72);","rect(image(p('DailyHeader'),'daily.icon.calendar.normal','DailyCalendar'),547,24,38,38);");
daily=daily.replace("iconButton(p('DailyClose'),'close_local',shell.RequestClose);","p('DailyClose').SetPanelEvent('onactivate',shell.RequestClose);");
daily=daily.replace("var spinner=image(p('DailyClaim')","RH.Action(p('DailyClaim'));p('DailyMakeup').visible=false;\nvar spinner=image(p('DailyClaim')");
daily=daily.replace("var last=i===6,card=U.CardShell(p('DailyCards'),{});","var last=i===6,card=$.CreatePanel('Panel',p('DailyCards'),'');");
daily=daily.replace('last?996:43+i*159,last?187:194,last?320:153,last?405:385','last?1000:40+i*159,192,last?310:153,390');
daily=daily.replace("if(today&&!last)image(card,'daily.card.border.today','DailyTodayBorder');","RH.DailyCard(card,last,today);");
daily=daily.replace("p('DailyPassStatus').style.backgroundImage='url(\"'+U.Asset(Number(data.has_pass)===1?'daily.badge.pass.active':'daily.badge.pass.inactive')+'\")';","RH.DailyPass(p('DailyPassStatus'),Number(data.has_pass)===1);");
daily=require('../../../../tools/patch_daily_panel_lifetime.cjs')(daily);
let archive=read(p.join(source,'layout/custom_game/archive.xml'));
let controller=read(p.join(source,'scripts/custom_game/lottery_ui_handoff_bb9968eef7.js'));
controller=controller.replace('duplicate.text = "重复物品，已转化为"','duplicate.text = "已转化 "').replace('+ Number(item.converted_points || 0) + "积分"','+ Number(item.converted_points || 0) + " 积分"');
controller=controller.replace('LH=GameUI.CustomUIConfig().LotteryHandoff;','LH=GameUI.CustomUIConfig().LotteryHandoff, RH=GameUI.CustomUIConfig().RemainingHandoff;');
controller=controller.replace('if (target) target.text = String(value === undefined ? "" : value);','if (target) { target.text = String(value === undefined ? "" : value); if(id === "LotteryInfoRules"){target.html=true;target.text=RH.QualityText(value);} }');
controller=controller.replace('skipAnimation = false;','skipAnimation = !!$("#LotterySkipAnimation").checked;');
controller=controller.replace('function cancelAnimation() {','var skipRevealButton=$("#LotterySkipReveal");skipRevealButton.hittest=true;skipRevealButton.hittestchildren=false;skipRevealButton.SetPanelEvent("onactivate",function(){finishReveal();$.Msg("[LOTTERY_SKIP_UI] actual_results="+visibleResults.length);});\n    function cancelAnimation() {');
controller=controller.replace('U.Checkbox.Adopt($("#LotterySkipAnimation"));','RH.LotteryActions();U.Checkbox.Adopt($("#LotterySkipAnimation"));');
controller=controller.replace('function createRewardIcon(parent,item,className) {','function createRewardIcon(parent,item,className) {\n        // Daedalus is the display name; Valve\'s texture/item key is greater_crit. UI-only alias.\n        if(item.icon === "item_daedalus"){var art={};Object.keys(item).forEach(function(k){art[k]=item[k];});art.icon="item_greater_crit";item=art;}');
controller=controller.replace(/var infoShell=U.ModalShell.Adopt\((.*)\);/,(_,props)=>'var infoOptions='+props.replace('width:1045,height:760,fit:{widthFraction:.682,heightFraction:.80}','width:840,height:610,fit:{reference:[1672,941]}')+';\n    var infoShell=U.ModalShell.Adopt(infoOptions); RH.Window(infoOptions.panel,infoOptions.header,infoOptions.closeButton);');
controller=controller.replace('detailPoolId = null, detailState', 'historyPoolId = "map", detailPoolId = null, detailState');
controller=controller.replace('rows(pools).forEach(function (pool) {','rows(pools).forEach(function (pool,index) {');
controller=controller.replace('U.TabBar.Adopt(button); LH.Tab(button,pool,hostId);','U.TabBar.Adopt(button); LH.Tab(button,pool,hostId); if(hostId === "LotteryInfoTabs") RH.Tab(button,index);');
controller=controller.replace('hostId === "LotteryInfoTabs" ? detailPoolId : selectedPoolId','hostId === "LotteryInfoTabs" ? (activeFeature === "history" ? historyPoolId : detailPoolId) : selectedPoolId');
controller=controller.replace('if(hostId !== "LotteryInfoTabs") label.text=LH.Name(String(pool.id),label.text);','label.text=LH.Name(String(pool.id),label.text);');
controller=controller.replace('if (hostId === "LotteryInfoTabs") selectDetailPool(pool.id); else selectPool(pool.id);','if (hostId === "LotteryInfoTabs") { if(activeFeature === "history") {historyPoolId=String(pool.id);feature("history");} else selectDetailPool(pool.id); } else selectPool(pool.id);');
controller=controller.replace('        });\n    }\n\n    function renderGuarantee','        });\n        if(hostId === "LotteryInfoTabs") RH.TabSelection(host,activeFeature === "history");\n    }\n\n    function renderGuarantee');
controller=controller.replace('activeFeature = name; updateButtons();','if(name === "history" && activeFeature !== "history") historyPoolId=selectedPoolId;\n        activeFeature = name; updateButtons();');
controller=controller.replace('infoShell.Open();','RH.LotteryDialog(name,infoOptions); infoShell.Open();');
controller=controller.replace('tabs.visible = name === "details"','tabs.visible = name === "details" || name === "history"');
controller=controller.replace('if (name === "details") renderPoolTabs(knownPools, "LotteryInfoTabs");','if (name === "details" || name === "history") renderPoolTabs(knownPools, "LotteryInfoTabs");');
controller=controller.replace('createV3CardBorder(row);','RH.RewardCard(row,item);');
controller=controller.replace('rows(viewState && viewState.items).forEach(function (item) {','rows(viewState && viewState.items).forEach(function (item,index) {');
controller=controller.replace('row.hittestchildren = false;\n\n                poolCards','row.hittestchildren = false;row.SetHasClass("RHFourth",index%4===3);\n\n                poolCards');
const begin=controller.indexOf('            setText("LotteryInfoNote", "仅显示本次游戏中收到的最近30次抽奖结果');
const end=controller.indexOf('        } else if (name === "announcement")',begin);
if(begin<0||end<0)throw Error('History patch anchor missing');
controller=controller.slice(0,begin)+`            var entries=history.filter(function(entry){return String(entry.pool)===historyPoolId;});
            RH.History(host,entries,createRewardIcon,showTooltip,hideTooltip);
            setText("LotteryInfoNote", "仅本局最近30次抽取 · 跨局记录暂未接入");
            var total=0;entries.forEach(function(entry){total+=entry.items.length;});
            setText("LotteryInfoRules", "共 "+total+" 条奖励记录");
`+controller.slice(end);
let hud=read(p.join(source,'layout/custom_game/survival_hud.xml'));
hud=hud.replace(/<Image class="LotteryFunctionIcon " src="file:\/\/\{images\}\/custom_game\/lottery_handoff\/icons\/(?:check|refresh)\.svg" hittest="false" \/>/g,'');
hud=hud.replace('file://{images}/custom_game/lottery_handoff/icons/chevron.svg',assetPaths.action_chevron);
let rogue=read(p.join(source,'scripts/custom_game/rogue_reward_ui.js'));
rogue=rogue.replace('var U=GameUI.CustomUIConfig().SurvivalUI;','var prior=GameUI.CustomUIConfig().SurvivalRogueReward;if(prior&&prior.Dispose)prior.Dispose();var disposed=false;var U=GameUI.CustomUIConfig().SurvivalUI,life=U.Lifecycle();');
rogue=rogue.replace('function render(value){value=value||{};','function render(value){if(disposed)return;value=value||{};');
rogue=rogue.replace('GameEvents.Subscribe("ui_rogue_reward_result",','life.Subscribe("ui_rogue_reward_result",');
rogue=rogue.replace('CustomNetTables.SubscribeNetTableListener("survival_rogue_reward",','var tableSubscription=CustomNetTables.SubscribeNetTableListener("survival_rogue_reward",');
rogue=rogue.replace('config.SurvivalRogueReward={SetReducedMotion:','config.SurvivalRogueReward={Dispose:function(){disposed=true;cancel();life.Dispose();if(CustomNetTables.UnsubscribeNetTableListener)CustomNetTables.UnsubscribeNetTableListener(tableSubscription);if(config.SurvivalUILayers)config.SurvivalUILayers.Close("rogue_choice");},SetReducedMotion:');
const rogueArtAnchor='front.AddClass("RogueArt_"+group);';
if(rogue.split(rogueArtAnchor).length!==2)throw Error('Rogue art hook changed');
rogue=rogue.replace(rogueArtAnchor,rogueArtAnchor+'GameUI.CustomUIConfig().SurvivalRogueArt.Apply(front,data);');
rogue=rogue.replace('var augment=U.AugmentChoiceGroup();','var augment=GameUI.CustomUIConfig().RemainingHandoff.RogueSequence();');
rogue=rogue.replace('var x=836-total*272/2-(total-1)*62/2+index*334;','var x=836-total*290/2-(total-1)*68/2+index*358;');
rogue=rogue.replace('px 170px 0px','px 181px 0px').replace('(836-x-136)','(836-x-145)').replace('364.727px','333px');
rogue=rogue.replace('1.30+Math.max(0,cards.length-1)*.11','1.60+Math.max(0,cards.length-1)*.11');
rogue=rogue.replace('U.ActionButton.Adopt(panel("RogueRewardReroll"));','panel("RogueRewardReroll").visible=false;panel("RogueRewardReroll").hittest=false;');
rogue=rogue.replace('U.FullscreenShell.Adopt({panel:panel("RogueRewardBackdrop"),liveGame:true});','U.FullscreenShell.Adopt({panel:panel("RogueRewardBackdrop")});panel("RogueRewardBackdrop").style.backgroundColor="transparent";panel("RogueRewardBackdrop").style.backgroundImage="none";');
// The new layout starts closed. Release the previous layout's layer leases;
// otherwise the persistent HUD gate keeps rejecting clicks after hot reload.
controller=controller.replace('    GameEvents.Subscribe("ui_lottery_snapshot", render);','    close();\n    GameEvents.Subscribe("ui_lottery_snapshot", render);');
const commerce=read(p.join(repo,'art/ui/development/shop_preview_v1/data.js')).replace('/*PREVIEW_CATALOG*/',read(p.join(repo,'art/ui/development/shop_preview_v1/catalog.json')))+'\n'+read(p.join(repo,'art/ui/development/shop_preview_v1/view.js'));
const navigation=read(p.join(here,'archive_navigation.js')).replace('/*ARCHIVE_NAV_FILES*/',JSON.stringify(navFiles));
const icons=read(p.join(here,'archive_icons.js')).replace('/*ICON_ENTRIES*/',JSON.stringify(iconEntries));
const itemArt=read(p.join(here,'item_art.js')).replace('/*ICON_ENTRIES*/',JSON.stringify(iconEntries));
let shop=read(p.join(source,'scripts/custom_game/shop_ui.js'));
const shopIconAnchor='function createEntryIcon(parent, entry, className) {';
if(shop.split(shopIconAnchor).length!==2)throw Error('Shop icon entry anchor changed');
shop=shop.replace(shopIconAnchor,shopIconAnchor+'\n        var art=GameUI.CustomUIConfig().SurvivalItemArt; if(art&&art.Create(parent,entry,className))return;');
let shopTooltip=read(p.join(source,'scripts/custom_game/shop_tooltip.js'));
const shopTooltipAnchor='function createIcon(parent, entry) {';
if(shopTooltip.split(shopTooltipAnchor).length!==2)throw Error('Shop tooltip icon anchor changed');
shopTooltip=shopTooltip.replace(shopTooltipAnchor,shopTooltipAnchor+'\n        var art=GameUI.CustomUIConfig().SurvivalItemArt; if(art&&art.Create(parent,entry,"ShopTooltipMainIcon"))return;');
shopTooltip=shopTooltip.replace('if (!tooltip || !iconHost || !fields) return;','if (!tooltip || !iconHost || !fields) return;\n        var owner=byId("CustomShopWindow");tooltip.style.zIndex=String(Math.max(100000,Number(owner&&owner.style.zIndex)||0)+1);');
shopTooltip=shopTooltip.replace('numberOr(sourcePanel.actuallayoutwidth, 80);','numberOr(sourcePanel.actuallayoutwidth, 80) / scaleX;').replace('numberOr(sourcePanel.actuallayoutheight, 64);','numberOr(sourcePanel.actuallayoutheight, 64) / scaleY;').replace('numberOr(tooltip.actuallayoutheight, 310);','numberOr(tooltip.actuallayoutheight, 310) / scaleY;').replace('numberOr(parent.actuallayoutheight, 1080);','numberOr(parent.actuallayoutheight, 1080) / scaleY;');
shopTooltip=shopTooltip.replace('var y = sourceY + (sourceHeight - tooltipHeight) * 0.5;','var tipWidth=numberOr(tooltip.actuallayoutwidth,430)/scaleX,parentWidth=numberOr(parent.actuallayoutwidth,1920)/scaleX;\n            if(x+tipWidth+edge>parentWidth)x=sourceX-tipWidth-gap;\n            x=Math.max(edge,Math.min(x,parentWidth-tipWidth-edge));\n            var y = sourceY + (sourceHeight - tooltipHeight) * 0.5;');
let hudController=read(p.join(source,'scripts/custom_game/handoff_hud.js'));
hudController=(s=>s.replace('function art(parent,id,key) {','function art(parent,id,key) {if(key==="top_gold"||key==="top_wood"){var resource=create("Image",parent,id,false);resource.SetImage("s2r://panorama/images/custom_game/hud_resources_v1/"+(key==="top_gold"?"gold":"wood")+".vsvg");return resource;}').replace('style(value,{height:"fit-children",verticalAlign:"center"});','style(value,{height:"fit-children",verticalAlign:"center"});\n        if(id.indexOf("HandoffResource_")===0)style(value,{transform:"translateY(4px)"});'))(hudController);
for(const name of ['gold','wood']){const rel='images/custom_game/hud_resources_v1/'+name+'.svg',bytes=fs.readFileSync(p.join(repo,'panorama/src',rel));write(rel,bytes);assets.push({original_path:'panorama/src/'+rel,runtime:rel,sha256:hash(bytes),kind:'hud_resource_icon'});}

const slotFrameSource=read(p.join(repo,'panorama/src/scripts/custom_game/handoff_hud.js'));
const slotFrameHelper=slotFrameSource.match(/    \/\/ Shared uniform slot outline:[\s\S]*?    \/\/ End shared uniform slot outline\./);
if(!slotFrameHelper||!hudController.includes('    function art(parent,id,key) {'))throw Error('Uniform slot frame anchor changed');
hudController=hudController.replace('    function art(parent,id,key) {',slotFrameHelper[0]+'\n    function art(parent,id,key) {if(key==="slot_frame")return uniformSlotFrame(parent,id);');

const portraitCornerSource=read(p.join(repo,'panorama/src/scripts/custom_game/handoff_hud.js'));
const portraitCornerBlock=portraitCornerSource.match(/        \/\/ Remove the previous corner cover[\s\S]*?End legacy corner cleanup\./);
const portraitCornerAnchor='        place(native("PortraitContainer"),0,0,g.portraitSize,g.portraitSize);';
if(!portraitCornerBlock||!hudController.includes(portraitCornerAnchor))throw Error('Portrait corner insertion anchor changed');
hudController=hudController.replace(portraitCornerAnchor,portraitCornerAnchor+'\n'+portraitCornerBlock[0]);

const resourceArtSource=read(p.join(repo,'panorama/src/scripts/custom_game/handoff_hud.js'));
const resourceArtStart=resourceArtSource.indexOf('if(key==="top_gold"');
const resourceArtEnd=resourceArtSource.indexOf('return resource;}',resourceArtStart)+'return resource;}'.length;
if(resourceArtStart<0||resourceArtEnd<resourceArtStart)throw Error('Resource icon shared block missing');
hudController=hudController.replace(/if\(key==="top_gold"\|\|key==="top_wood"\)\{var resource=create\("Image"[\s\S]*?return resource;\}/,resourceArtSource.slice(resourceArtStart,resourceArtEnd));
if(!hudController.includes("var topScale=Math.min(w/1672,h/941);place(top,(w-1672*topScale)/2,0,1672,941);style(top,{transform:\"scale3d(\"+topScale+\",\"+topScale+\",1)\"});"))throw Error('HUD backdrop layout anchor changed');
hudController=hudController.replace("var topScale=Math.min(w/1672,h/941);place(top,(w-1672*topScale)/2,0,1672,941);style(top,{transform:\"scale3d(\"+topScale+\",\"+topScale+\",1)\"});","var topScale=Math.min(w/1672,h/941);place(top,(w-1672*topScale)/2,0,1672,941);style(top,{transform:\"scale3d(\"+topScale+\",\"+topScale+\",1)\"});\n        var backdropBleed=(w-1672*topScale)/(2*topScale)+24;\n        place(nodes.HandoffTopBackdrop,-backdropBleed,0,1672+backdropBleed,941);");
if(!hudController.includes("        var inv=native(\"inventory\");place(inv,g.inventoryX+15,55,358,242);style(inv,{overflow:\"noclip\",transform:\"none\",boxShadow:\"none\",backgroundImage:\"none\",backgroundColor:\"transparent\"});"))throw Error('Inventory cleanup anchor changed');
hudController=hudController.replace("        var inv=native(\"inventory\");place(inv,g.inventoryX+15,55,358,242);style(inv,{overflow:\"noclip\",transform:\"none\",boxShadow:\"none\",backgroundImage:\"none\",backgroundColor:\"transparent\"});","        var inv=native(\"inventory\");place(inv,g.inventoryX+15,55,358,242);style(inv,{overflow:\"noclip\",transform:\"none\",boxShadow:\"none\",backgroundImage:\"none\",backgroundColor:\"transparent\"});\n        // Clear native inventory separators; the shared skin owns all framing.\n        [inv,inv.FindChildTraverse(\"inventory_items\"),inv.FindChildTraverse(\"inventory_list_container\"),inv.FindChildTraverse(\"inventory_list\"),inv.FindChildTraverse(\"inventory_list2\")].forEach(function(p){\n            style(p,{border:\"0px\",boxShadow:\"none\",backgroundImage:\"none\",backgroundColor:\"transparent\"});\n        });\n        for(var cleanSlot=0;cleanSlot<6;cleanSlot++){\n            var nativeSlot=inv.FindChildTraverse(\"inventory_slot_\"+cleanSlot);\n            style(nativeSlot,{border:\"0px\",boxShadow:\"none\",backgroundImage:\"none\",backgroundColor:\"transparent\"});\n        }\n        // End native inventory separator cleanup.\n");
hudController=hudController.replace("place(inventory,g.inventoryX,23,401,307);","place(inventory,g.inventoryX,23,401,307);\n            var inventoryPaper=nodes.HandoffInventoryPaper||create(\"Panel\",background,\"HandoffInventoryPaper\",false);\n            place(inventoryPaper,g.inventoryX+12,49,366,263);style(inventoryPaper,{backgroundColor:\"#10303b\",borderRadius:\"3px\"});");
hudController=hudController.replace('[["gold",1193,1233],["wood",1350,1390],["population",1484,1524]]','[["gold",1194,1234],["wood",1339,1379],["population",1484,1524]]').replace('a[0]==="population"?143:112','105');
hudController=hudController.replace("        // These are decorative only. Keep active/cooldown/disabled/drag overlays intact.","        if(String(slot.id||\"\").indexOf(\"inventory_slot_\")===0)[\"ButtonSize\",\"ButtonWell\"].forEach(function(id){child(slot,id,{boxShadow:\"none\"});});\n        // These are decorative only. Keep active/cooldown/disabled/drag overlays intact.").replace("        [\"BackPackShadow\",\"BackpackShadow\"].forEach(function(id){child(inv,id,{opacity:\"0\"});});","        [\"BackPackShadow\",\"BackpackShadow\"].forEach(function(id){child(inv,id,{opacity:\"0\"});});\n        [\"InventoryBG\",\"HUDSkinInventoryBG\"].forEach(function(id){child(inv,id,{visibility:\"collapse\",border:\"0px\",boxShadow:\"none\"});});").replace(/\s*var inventoryPaper=nodes\.HandoffInventoryPaper\|\|create\("Panel",background,"HandoffInventoryPaper",false\);\s*place\(inventoryPaper,g\.inventoryX\+12,49,366,263\);style\(inventoryPaper,\{backgroundColor:"#10303b",borderRadius:"3px"\}\);/,'');
hudController=hudController.replace("        var block=native(\"center_block\"),portrait=native(\"PortraitGroup\");","        var block=native(\"center_block\"),portrait=native(\"PortraitGroup\");\n        // Native 10px skill inset shadows keep their old offsets and cross inventory.\n        for(var decorIndex=0;decorIndex<block.GetChildCount();decorIndex++){\n            var decor=block.GetChild(decorIndex);\n            if(decor.BHasClass(\"AbilityInsetShadowLeft\")||decor.BHasClass(\"AbilityInsetShadowRight\")){\n                style(decor,{visibility:\"collapse\",opacity:\"0\"});decor.hittest=false;decor.hittestchildren=false;\n            }\n        }\n");
if(!/                \/\/ Draw the approved transparent frame as one quad\.[\s\S]*?place\(barFrame,16,y,g\.barWidth,52\);style\(barFrame,\{zIndex:"1"\}\);/.test(hudController))throw Error('Health mana frame block changed');
hudController=hudController.replace(/                \/\/ Draw the approved transparent frame as one quad\.[\s\S]*?place\(barFrame,16,y,g\.barWidth,52\);style\(barFrame,\{zIndex:"1"\}\);/,"                // Health and mana use only their track, fill and number; no outer frame.");
// Keep the accepted navigation subset in the generated HUD as well as the source.
const navDefinition=/var nav=\[\[.*?\]\];/;
if(!navDefinition.test(hudController))throw Error('HUD navigation definition changed');
hudController=hudController.replace(navDefinition,'var nav=[["return","返回"],["treasure","宝物"],["archive","存档"],["lottery","抽奖"],["benefit","福利"],["shop","商城"]];');
hudController=hudController.replace('var actions={treasure:', 'var actions={shop:["SurvivalCommerceView","Open"],treasure:');
hudController=hudController.replace('"file://{images}/"+assets[key].file','key==="top_shop_64"?"s2r://panorama/images/custom_game/shop_preview_v1/shop_png.vtex":"file://{images}/"+assets[key].file');
// Native outline fallback avoids an empty newly introduced texture on live reload.
hudController=hudController.replace('function art(parent,id,key) {','function art(parent,id,key) {if(key==="top_shop_64"){var icon=create("Panel",parent,id,false),handle=create("Panel",icon,"",false),bag=create("Panel",icon,"",false);place(handle,26,18,12,15);style(handle,{border:"2px solid #e3ded0",borderRadius:"6px 6px 0px 0px"});place(bag,21,29,22,20);style(bag,{border:"2px solid #e3ded0",borderRadius:"2px"});return icon;}');
const tipBinding='tooltip(b,a[1]);';
if(hudController.split(tipBinding).length!==2)throw Error('HUD nav tooltip binding anchor changed');
hudController=hudController.replace(tipBinding,'/* Top navigation tooltips temporarily disabled. */');
const navArt='place(art(b,"","top_"+a[0]+"_64"),0,0,64,64);';
hudController=hudController.replace('place(social,474,70,192,130);','place(social,474,94,192,130);');
if(hudController.split(navArt).length!==2)throw Error('HUD nav label anchor changed');
hudController=hudController.replace(navArt,navArt+'b.style.height="88px";var caption=create("Label",b,"",false);caption.text=a[1];place(caption,0,62,64,24);caption.style.horizontalAlign="center";caption.style.width="fit-children";caption.style.minWidth="0px";caption.style.fontFamily="Source Han Sans SC";caption.style.fontSize="18px";caption.style.fontWeight="medium";caption.style.color="#f3ecdb";caption.style.textAlign="center";caption.style.textShadow="0px 1px 2px 2.0 #00000090";');
const invalidation='var serial=++eventSerial;lastSignature="";';
if(hudController.split(invalidation).length!==2)throw Error('HUD invalidation anchor changed');
// Ability level/cooldown events can fire every tick. The layout signature already
// includes the selected entity and every visible ability handle; preserve it.
hudController=require('../../../../tools/patch_hud_refresh.cjs')(hudController);
// Unscaled design children may exceed the screen width before the common scale.
// Native max-width constraints must not crop a ten-plus-skill HUD at that stage.
hudController=hudController.replace('width:w+"px",height:h+"px"','width:w+"px",height:h+"px",minWidth:w+"px",minHeight:h+"px",maxWidth:"10000px",maxHeight:"10000px"');
hudController=hudController.replace('f&&f.Compact?f.Compact(v):String(v===undefined?"—":v)','f&&f.Compact?f.Compact(v):f&&f.Format?f.Format(v):String(v===undefined?"—":v)');
const sharedComponents=read(p.join(repo,'panorama/src/scripts/custom_game/common/ui_components.js'));
const sharedLayers=read(p.join(repo,'panorama/src/scripts/custom_game/ui_layers.js'));
const hudGeometry=read(p.join(repo,'art/ui/development/ui_stage3_v1/geometry.js'));
const version=hash(css+helper+controller+daily+rogue+rogueArt+commerce+navigation+icons+hudController+hudGeometry+itemArt+shop+shopTooltip+bossWarning+sharedComponents+sharedLayers+JSON.stringify(assets.map(a=>[a.runtime,a.sha256]))).slice(0,10),prefix='remaining_'+version;
const inputs=['styles/custom_game/'+prefix+'.css','scripts/custom_game/'+prefix+'.js','scripts/custom_game/lottery_ui_'+prefix+'.js','layout/custom_game/survival_hud.xml'];
for(const [file,data] of [['scripts/custom_game/common/ui_components.js',sharedComponents],['scripts/custom_game/ui_layers.js',sharedLayers]]){write(file,data);inputs.push(file);}
hud=hud.replace('</styles>','<include src="file://{resources}/'+inputs[0]+'"/></styles>');
const itemArtPath='scripts/custom_game/item_art_'+prefix+'.js',shopPath='scripts/custom_game/shop_'+prefix+'.js';
const rewardInclude='<include src="file://{resources}/scripts/custom_game/reward_presentation.js" />';
if(!hud.includes(rewardInclude))throw Error('Reward presentation include missing');
hud=hud.replace(rewardInclude,rewardInclude+'<include src="file://{resources}/'+itemArtPath+'"/>');
hud=hud.replace('scripts/custom_game/shop_ui.js',shopPath);
write(itemArtPath,itemArt);write(shopPath,shop);inputs.push(itemArtPath,shopPath);
const shopTooltipPath='scripts/custom_game/shop_tooltip_'+prefix+'.js';
hud=hud.replace('scripts/custom_game/shop_tooltip.js',shopTooltipPath);
write(shopTooltipPath,shopTooltip);inputs.push(shopTooltipPath);
const hudControllerPath='scripts/custom_game/topnav_'+prefix+'.js';
const geometryPath='scripts/custom_game/geometry_'+prefix+'.js';
hud=hud.replace('scripts/custom_game/handoff_geometry.js',geometryPath);write(geometryPath,hudGeometry);inputs.push(geometryPath);
hud=hud.replace('scripts/custom_game/handoff_hud.js',hudControllerPath);write(hudControllerPath,hudController);inputs.push(hudControllerPath);
hud=hud.replace('<include src="file://{resources}/scripts/custom_game/lottery_ui_handoff_bb9968eef7.js" />','<include src="file://{resources}/'+inputs[1]+'"/><include src="file://{resources}/'+inputs[2]+'"/>');
write(inputs[0],css);write(inputs[1],helper);write(inputs[2],controller);write(inputs[3],hud);
write('scripts/custom_game/commerce_'+prefix+'.js',commerce);
hud=hud.replace('</scripts>','<include src="file://{resources}/scripts/custom_game/commerce_'+prefix+'.js"/></scripts>');write('layout/custom_game/survival_hud.xml',hud);
inputs.push('scripts/custom_game/commerce_'+prefix+'.js');
const bossPath='scripts/custom_game/boss_warning_'+prefix+'.js';
write(bossPath,bossWarning);inputs.push(bossPath);
hud=hud.replace('</scripts>','<include src="file://{resources}/'+bossPath+'"/></scripts>');write('layout/custom_game/survival_hud.xml',hud);
archive=archive.replace('</styles>','<include src="file://{resources}/'+inputs[0]+'"/></styles>');
if(!archive.includes(rewardInclude))throw Error('Archive reward presentation include missing');
archive=archive.replace(rewardInclude,rewardInclude+'<include src="file://{resources}/'+itemArtPath+'"/>');
const navigationPath='scripts/custom_game/navigation_'+prefix+'.js';
const archiveController='<include src="file://{resources}/scripts/custom_game/archive_180de7e38b.js" />';
if(!archive.includes(archiveController))throw Error('Archive navigation insertion anchor missing');
archive=archive.replace(archiveController,'<include src="file://{resources}/'+inputs[1]+'"/><include src="file://{resources}/'+navigationPath+'"/>'+archiveController);
write(navigationPath,navigation);inputs.push(navigationPath);
const iconPath='scripts/custom_game/icons_'+prefix+'.js';
archive=archive.replace(archiveController,'<include src="file://{resources}/'+iconPath+'"/>'+archiveController);
write(iconPath,icons);inputs.push(iconPath);
archive=archive.replace('<include src="file://{resources}/scripts/custom_game/daily_rewards.js" />','<include src="file://{resources}/scripts/custom_game/daily_'+prefix+'.js"/>');
write('scripts/custom_game/daily_'+prefix+'.js',daily);write('layout/custom_game/archive.xml',archive);
inputs.push('scripts/custom_game/daily_'+prefix+'.js','layout/custom_game/archive.xml');
let rogueLayout=read(p.join(source,'layout/custom_game/rogue_reward_ui.xml'));
const rogueArtPath='scripts/custom_game/rogue_art_'+prefix+'.js';
write(rogueArtPath,rogueArt);inputs.push(rogueArtPath);
rogueLayout=rogueLayout.replace('<include src="file://{resources}/scripts/custom_game/rogue_reward_ui.js" />','<include src="file://{resources}/'+rogueArtPath+'"/><include src="file://{resources}/scripts/custom_game/rogue_reward_ui.js" />');
rogueLayout=rogueLayout.replace('</styles>','<include src="file://{resources}/'+inputs[0]+'"/></styles>');
rogueLayout=rogueLayout.replace('<include src="file://{resources}/scripts/custom_game/rogue_reward_ui.js" />','<include src="file://{resources}/'+inputs[1]+'"/><include src="file://{resources}/scripts/custom_game/rogue_'+prefix+'.js"/>');
write('scripts/custom_game/rogue_'+prefix+'.js',rogue);write('layout/custom_game/rogue_reward_ui.xml',rogueLayout);
inputs.push('scripts/custom_game/rogue_'+prefix+'.js','layout/custom_game/rogue_reward_ui.xml');
const probeArg=process.argv.find(a=>a.startsWith('--probe='));
if(probeArg){
 const mode=probeArg.slice(8);if(!['details','history','dump','daily','shop','bundles','purchase'].includes(mode))throw Error('Unsupported read-only probe');
 const probe='scripts/custom_game/remaining_probe_'+Date.now()+'.js';
 write(probe,'(function(){ $.Schedule(1,function(){var c=GameUI.CustomUIConfig();c.SurvivalLottery.Open();$.Schedule(.6,function(){c.SurvivalLottery.Feature('+JSON.stringify(mode==='dump'?'details':mode)+');$.Schedule(.4,function(){var v={};["LotteryInfoDialog","LotteryInfoHeader","LotteryInfoTitle","LotteryInfoTabs","LotteryInfoBody","LotteryInfoList","LotteryInfoFooter","LotteryInfoRules"].forEach(function(id){var p=$("#"+id);v[id]={w:p.actuallayoutwidth,h:p.actuallayoutheight,x:p.actualxoffset,y:p.actualyoffset,s:p.actualuiscale_x,text:p.text};});$.Msg("[REMAINING_PROBE] "+JSON.stringify(v));c.RemainingHandoff.Dump();});});});})();');
 if(mode==='daily')write(probe,'(function(){$.Schedule(1,function(){var c=GameUI.CustomUIConfig();if(c.SurvivalLottery)c.SurvivalLottery.Close();c.SurvivalDaily.Open(false);});})();');
 if(['shop','bundles','purchase'].includes(mode))write(probe,'(function(){$.Schedule(1,function(){var c=GameUI.CustomUIConfig();c.SurvivalLottery.Close();c.SurvivalDaily.Close();c.SurvivalCommerceView.Open('+JSON.stringify(mode)+');});})();');
 hud=hud.replace('</scripts>','<include src="file://{resources}/'+probe+'"/></scripts>');write('layout/custom_game/survival_hud.xml',hud);inputs.splice(inputs.length-1,0,probe);
}
const preload='layout/custom_game/'+prefix+'_assets.xml';
// Build-only dependency manifest. Masters feed the bounded recipes; do not also
// compile full-resolution runtime textures for hundreds of inventory icons.
write(preload,'<root><Panel hittest="false" visible="false">'+assets.filter(a=>!['generated_archive_icon','generated_rogue_art'].includes(a.kind)).map(a=>'<Image src="'+(a.kind==='compiled_icon_recipe'?'s2r://panorama/'+a.runtime:'file://{images}/'+a.runtime.slice(7))+'" hittest="false"/>').join('')+'</Panel></root>');
inputs.unshift(preload);
fs.writeFileSync(p.join(here,'asset_audit.json'),JSON.stringify(assets,null,2));
fs.writeFileSync(p.join(here,'archive_icon_manifest.json'),JSON.stringify(iconEntries,null,2));
fs.writeFileSync(p.join(here,'build.json'),JSON.stringify({version,inputs,textureInputs:assets.filter(a=>a.kind==='compiled_icon_recipe').map(a=>a.runtime),hudSourceHash:hash(read(p.join(current,'layout/custom_game/survival_hud.xml'))),created:new Date().toISOString()},null,2));
console.log(JSON.stringify({version,inputs,assets:assets.length}));


