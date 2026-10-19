'use strict';
// Five review concepts assembled from exact installed Valve components.
// This tool never loads the game's controller or sends an account request.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/lottery_native_concepts_20261019');
const content=JSON.parse(fs.readFileSync(path.join(__dirname,'content.json'),'utf8'));
const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'native_assets.json'),'utf8'));
const sources=new Map();
const uri=file=>pathToFileURL(path.resolve(root,file)).href;
function native(suffix){
 const row=manifest.records.find(r=>r.resource==='panorama/images/'+suffix+'.vtex_c');
 if(!row)throw Error('Missing official component '+suffix);
 const bytes=fs.readFileSync(path.join(root,row.path));
 if(crypto.createHash('sha256').update(bytes).digest('hex')!==row.pngSha256)throw Error('Changed official resource '+suffix);
 sources.set(row.resource,row);return uri(row.path);
}
const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const image=(file,cls,extra='')=>'<img class="'+cls+'" src="'+esc(file)+'" '+extra+' draggable="false" alt="">';
const themes=[
 {id:'reborn',number:'01',name:'经典军械库',english:'REBORN',description:'原生铁灰石板 · 紧凑矩形导航 · 锻铁按钮',
  panel:'hud/reborn/bg_scoreboard_psd',side:'hud/reborn/quickbuy_bg_psd',header:'hud/reborn/inventory_panel_png',
  nav:'gray_button_off_png',navOn:'gray_button_on_png',button:'gray_button_off_png',primary:'gray_button_on_png',well:'hud/reborn/inventory_item_well_psd'},
 {id:'crownfall',number:'02',name:'皇冠远征',english:'CROWNFALL',description:'深靛铜金 · 斜切导航 · 官方六角按钮',
  panel:'events/crownfall/visual_novel/vn_background_act4_png',side:'events/crownfall/buttons/tabs_background_png',header:'events/crownfall/buttons/tab_background_png',
  nav:'events/crownfall/buttons/tabs_background_png',navOn:'events/crownfall/buttons/tabs_background_png',button:'events/crownfall/buttons/button_secondary_bg_psd',primary:'events/crownfall/buttons/button_primary_bg_psd',well:'hud/reborn/inventory_item_well_psd',buttonOutline:'events/crownfall/buttons/button_secondary_outline_psd',primaryOutline:'events/crownfall/buttons/button_primary_outline_psd'},
 {id:'carnival',number:'03',name:'暗金秘库',english:'DARK CARNIVAL',description:'暗棕木纹 · 铜金铆钉 · 机械包边按钮',
  panel:'events/dark_carnival/splash/panel_background_png',side:'events/dark_carnival/textures/texture_fabric_png',header:'events/dark_carnival/overworld/panel_title_container_png',
  nav:'events/dark_carnival/buttons/button_border_png',navOn:'events/dark_carnival/buttons/button_border_png',button:'events/dark_carnival/buttons/button_border_png',primary:'events/dark_carnival/buttons/button_border_png',well:'hud/reborn/inventory_item_well_psd',frame:'events/dark_carnival/splash/popup_border_png',screw:'events/dark_carnival/textures/screw_png'},
 {id:'plus',number:'04',name:'鎏金典藏',english:'DOTA PLUS',description:'深青石纹 · 柔金奖励按钮 · 规整双列珍藏',
  panel:'dota_plus/dota_plus_bg_psd',side:'dota_plus/dota_plus_horizontal_banner_background_png',header:'dota_plus/shop_button_bg_psd',
  nav:'dota_plus/relic_agi_button_psd',navOn:'dota_plus/relic_rare_button_psd',button:'dota_plus/relic_agi_button_psd',primary:'dota_plus/relic_rare_button_psd',well:'hud/reborn/inventory_item_well_psd'},
 {id:'international',number:'05',name:'国际邀请赛',english:'THE INTERNATIONAL',description:'乌木织纹 · 冷金导航 · 水晶奖励边框',
  panel:'compendium/international2024/dashboard/points_bg_texture_png',side:'compendium/international2024/sidenav_background_png',header:'compendium/international2024/flag_texture_png',
  nav:'gray_button_off_png',navOn:'compendium/international2024/dashboard/selected_nav_bg_png',button:'gray_button_off_png',primary:'hud/reborn/the_international_2024/shop_launcher_button_inrange_psd',well:'hud/reborn/inventory_item_well_psd',rewardFrame:'compendium/international2023/rewardpage_outerborder_psd'}
];
const assetNames=['panel','side','header','nav','navOn','button','primary','well','frame','screw','rewardFrame','buttonOutline','primaryOutline'];
let themedCSS='';for(const t of themes){const defs=assetNames.filter(k=>t[k]).map(k=>'--'+k+':url("'+native(t[k])+'")');themedCSS+='body[data-theme="'+t.id+'"]{'+defs.join(';')+'}\n';}
const nativePlus=content.uiAssets.plus,nativeClose=manifest.records.find(r=>r.resource==='panorama/images/control_icons/x_close_png.vtex_c'),nativeBack=manifest.records.find(r=>r.resource==='panorama/images/control_icons/arrow_solid_left_png.vtex_c');
[nativeClose,nativeBack].filter(Boolean).forEach(r=>sources.set(r.resource,r));
const ticket=uri(content.tickets.special.path),scene=uri(content.scene.path),game=uri(content.gameBackground.path);
const chest=manifest.records.find(r=>r.resource==='panorama/images/events/dark_carnival/overworld/rewards/reward_treasure_large_png.vtex_c');
if(!chest)throw Error('Official central treasure illustration has not been exported yet');
sources.set(chest.resource,chest);
const poolIconIds=[7,5,0,1];
const tabs=content.pools.map((p,i)=>'<button class="pool'+(p.selected?' selected':'')+'" data-id="'+p.id+'"><i class="native-nav"></i>'+image(uri(content.rewards[poolIconIds[i]].iconPath),'pool-icon')+'<span>'+esc(p.name)+'</span><b class="selected-mark">◆</b></button>').join('');
const rewards=content.rewards.map(r=>'<button class="reward" data-quality="'+r.quality+'" title="'+esc(r.name)+'"><span class="reward-well">'+image(uri(r.iconPath),'reward-icon')+'<b class="rarity">'+r.quality+'</b></span><span class="reward-name">'+esc(r.name)+'</span></button>').join('');
function action(type,text,cost){return'<button class="draw '+type+'"><i class="native-button"></i><i class="native-button outline"></i><span>'+text+'</span><small>'+image(ticket,'cost-icon')+' '+cost+'</small></button>';}
const css=fs.readFileSync(path.join(__dirname,'concepts.css'),'utf8');
const html='<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>五套官方组件抽卡界面 · 方案预览</title><style>'+css+'\n'+themedCSS+'\n@font-face{font-family:GameChinese;src:url("'+uri(content.fonts.sans.path)+'")}\n.game-context{background-image:url("'+game+'")} .pool-art{background-image:url("'+scene+'")}\n</style></head><body data-theme="reborn">'+
 '<div class="game-context"></div><div class="game-dim"></div><div class="viewport"><section class="window" aria-label="抽卡界面方案"><div class="window-surface"></div><div class="window-frame"></div><header><div class="header-native"></div><button class="back">'+image(uri(nativeBack.path),'back-native')+' 返回</button><div class="header-separator"></div><h1>抽奖</h1><div class="wallet">'+image(ticket,'wallet-icon')+'<span class="balance">'+content.balance+'</span><button class="recharge" aria-label="获取代币">'+(nativePlus?image(uri(nativePlus.path),'native-plus'):'+')+'</button></div><button class="close" aria-label="关闭">'+(nativeClose?image(uri(nativeClose.path),'native-close'):'×')+'</button></header>'+
 '<aside><div class="sidebar-native"></div><div class="sidebar-heading">珍藏宝箱</div><nav>'+tabs+'</nav><div class="sidebar-rule"></div><div class="sidebar-bottom">珍藏 · 永久</div></aside>'+
 '<main><div class="pool-art"></div><div class="art-shade"></div><div class="hero-copy"><div class="eyebrow">珍 藏 宝 箱</div><h2>'+esc(content.selectedPoolName)+'</h2><p>开启宝箱，收集英雄与箭塔的珍藏奖励。</p></div><div class="treasure-stage"><div class="treasure-aura"></div>'+image(uri(chest.path),'hero-treasure')+'<div class="chest-shadow"></div></div>'+
 '<div class="preview-heading"><span>奖池珍藏</span><button class="details">奖池详情 <b>›</b></button></div><div class="reward-strip">'+rewards+'</div>'+
 '<footer><div class="footer-rule"></div><div class="utility"><div class="utility-links"><button>抽奖记录</button><span>·</span><button>规则</button></div><label class="skip"><input type="checkbox"><i></i>跳过动画</label></div><div class="purchase-area"><div class="pity">十连必得 <strong>UR</strong></div><div class="actions">'+action('secondary','开启一次','1')+action('primary','开启十次','10')+'</div></div></footer></main>'+
 '<div class="ornament tl"></div><div class="ornament tr"></div><div class="ornament bl"></div><div class="ornament br"></div></section></div>'+
 '<div class="concept-caption"><span id="concept-number">01</span><strong id="concept-name">经典军械库</strong><i></i><span id="concept-family">REBORN</span><em>官方组件组装 · 激战 2 布局参考 · 方案预览</em></div>'+
 '<script>const themes='+JSON.stringify(themes.map(({id,number,name,english,description})=>({id,number,name,english,description})))+';window.setConcept=function(id){const t=themes.find(t=>t.id===id)||themes[0];document.body.dataset.theme=t.id;document.getElementById("concept-number").textContent=t.number;document.getElementById("concept-name").textContent=t.name;document.getElementById("concept-family").textContent=t.english;return t;};setConcept(new URLSearchParams(location.search).get("theme"));window.fit=function(){document.querySelector(".viewport").style.transform="translate(-50%,-50%) scale("+Math.min(innerWidth/1920,innerHeight/1080)+")";};fit();addEventListener("resize",fit);window.conceptReady=document.fonts.ready.then(()=>Promise.all([...document.images].map(i=>i.decode()))).then(()=>true);</script></body></html>';
fs.mkdirSync(path.join(out,'render'),{recursive:true});fs.writeFileSync(path.join(out,'render/index.html'),html);
const report={kind:'five_offline_native_component_concepts',productionModified:false,layoutReference:'GW2 Black Lion chest / trading company adapted to four pools and two existing draw actions',themes:themes.map(t=>({id:t.id,number:t.number,name:t.name,description:t.description,components:Object.fromEntries(assetNames.filter(k=>t[k]).map(k=>[k,'panorama/images/'+t[k]+'.vtex_c']))})),content:{poolId:content.selectedPoolId,balance:content.balance,allRewardsFromActualPool:true,rewards:content.rewards.map(r=>({id:r.id,name:r.name,quality:r.quality,source:r.source,iconSha256:r.iconSha256})),treasureIllustration:chest.resource,ticketArt:content.tickets.special.path},officialResources:[...sources.values()],htmlSha256:crypto.createHash('sha256').update(html).digest('hex')};
fs.writeFileSync(path.join(out,'assembly.json'),JSON.stringify(report,null,2)+'\n');
console.log('FIVE_NATIVE_CONCEPTS_BUILT '+sources.size+' official components');
