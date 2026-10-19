'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..'),work=path.join(root,'output/lottery_five_official_20261019'),out=path.join(root,'design_refs/lottery_five_official_20261019');
const catalogRoot=path.join(root,'design_refs/official_ui_catalog_20261019'),catalogFile=path.join(catalogRoot,'catalog.json');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),relative=f=>path.relative(root,f).replaceAll('\\','/');
const {fixture}=require('../lottery_gw2/fixture.cjs');
function build(){
 fs.mkdirSync(work,{recursive:true});fs.mkdirSync(out,{recursive:true});
 if(!fs.existsSync(catalogFile))throw Error('Build the official UI catalog first: tools/official_ui_catalog_20261019/build.cjs all');
 const catalog=JSON.parse(fs.readFileSync(catalogFile,'utf8')),recipe=JSON.parse(fs.readFileSync(path.join(__dirname,'schemes.json'),'utf8'));
 const byId=new Map(catalog.assets.map(r=>[r.id,r])),extraFile=path.join(work,'extra_native.json');
 const extras=fs.existsSync(extraFile)?JSON.parse(fs.readFileSync(extraFile,'utf8')).records:require('./extra_native.cjs').prepare(),byTreasure=new Map(extras.map(r=>[r.id,r]));
 const jobs=new Map(),manifest=[],schemeAssets=new Map();
 function job(file,size){const source=relative(file),key=hash(Buffer.from(source)).slice(0,16);if(!jobs.has(key))jobs.set(key,{key,source,maxSize:size||[2048,1152]});return key;}
 function official(id){const record=byId.get(id);if(!record)throw Error('Official UI ID missing: '+id);const file=path.join(catalogRoot,record.original);return {...record,_image:job(file),original:relative(file)};}
 function treasure(id){const record=byTreasure.get(id);if(!record)throw Error('Official treasure missing: '+id);const file=path.join(out,record.original);return {...record,_image:job(file),original:relative(file)};}
 const roleMap={background:'background',primary_button:'button',primary_button_hover:'buttonHover',sidebar_selected:'tabSelected',panel:'panel',panel_texture:'panel',sidebar_texture:'sidebar',divider:'divider',reward_frame:'frame',corner:'corner',outer_border:'outerFrame',small_icon:'emblem',currency_icon:'currency'};
 for(const theme of recipe.themes){const assets={};for(const row of theme.assets){const record=byId.get(row.id);if(!record||record.sourcePath!==row.sourcePath)throw Error('Official catalog identity drift: '+row.id);assets[roleMap[row.role]||row.role]=official(row.id);}assets.hero=treasure(theme.hero);assets.buttonSecondary=official(theme.secondaryButton||'UI02980');schemeAssets.set(theme.id,assets);}
 const controls={};for(const [key,resource]of Object.entries({close:'control_icons/24px/close.vsvg_c',plus:'control_icons/24px/plus.vsvg_c',arrow:'control_icons/24px/arrow_left.vsvg_c',check:'control_icons/24px/check.vsvg_c',info:'control_icons/24px/info.vsvg_c',history:'control_icons/history_png.vtex_c',ticket:'icon_ticket_png.vtex_c'})){const record=catalog.assets.find(r=>r.sourcePath==='panorama/images/'+resource)||catalog.assets.find(r=>key==='close'&&r.sourcePath==='panorama/images/control_icons/close_png.vtex_c');if(!record)throw Error('Official control missing: '+key);controls[key]=official(record.id);}
 const formal=fixture(),resources=JSON.parse(fs.readFileSync(path.join(root,'data/ui/item_resources.json'),'utf8')).items;
 function resolveResource(id){const row=resources.find(r=>r.id===id)||resources.find(r=>(r.aliases||[]).includes(id));if(!row)throw Error('Formal item image not registered: '+id);let candidates=[];if(row.source)candidates.push(path.join(root,row.source));const logical=row.uri.replace(/^s2r:\/\/panorama\/images\//,'').replace(/^file:\/\/\{images\}\//,'').replace(/\.vtex$/,'.png');candidates.push(path.join(root,'art/ui/sources',logical),path.join(root,'panorama/src/images',logical));const file=candidates.find(f=>fs.existsSync(f));if(!file)throw Error('Existing item image source not found: '+id);const key=job(file,[512,512]);manifest.push({kind:'current_game_item',id,uri:row.uri,file:relative(file)});return key;}
 const itemMap=new Map(formal.items.map(r=>[r.item_id,r])),grade={ur:5,ssr:4,sr:3,r:2,n:1};
 const tickets={normal:resolveResource('lottery_ticket'),special:resolveResource('special_lottery_ticket')};
 const poolHeroes={map:'T13',cultivation:'T10',dragon_knight:'T12',summer:'T20'};
 const pools=formal.pools.map(pool=>{
  const members=formal.members.filter(m=>m.pool_id===pool.pool_id),items=members.flatMap(m=>m.item_id==='*'?formal.items:[itemMap.get(m.item_id)]).filter(Boolean).sort((a,b)=>(grade[b.quality]||0)-(grade[a.quality]||0)||a.item_id.localeCompare(b.item_id));
  const rewards=items.map(r=>({id:r.item_id,name:r.display_name.replace(/·永久$/,''),rarity:r.quality.toUpperCase(),_image:resolveResource(r.item_id),description:r.description}));
  const special=pool.ticket_content_id==='special_lottery_ticket',pity=formal.pity.find(p=>p.pool_id===pool.pool_id&&p.trigger_mode==='batch_only');
  return {id:pool.pool_id,name:pool.display_name,subtitle:special?'金色抽奖券':'普通抽奖券',_icon:treasure(poolHeroes[pool.pool_id])._image,ticketKind:special?'special':'normal',_ticket:tickets[special?'special':'normal'],tickets:120,singleCost:Number(pool.single_cost),tenCost:Number(pool.ten_cost),pity:'十连保底 '+String(pity&&pity.target_quality||'ssr').toUpperCase(),featured:rewards[0],rewards};
 });
 const jobsFile=path.join(work,'image_jobs.json'),preparedFile=path.join(work,'prepared_images.json'),jobList=[...jobs.values()];
 let reusable=false;
 if(fs.existsSync(jobsFile)&&fs.existsSync(preparedFile)){
  const previous=JSON.parse(fs.readFileSync(preparedFile,'utf8'));
  reusable=JSON.stringify(JSON.parse(fs.readFileSync(jobsFile,'utf8')))===JSON.stringify(jobList)&&jobList.every(j=>previous[j.key]&&previous[j.key].originalSha256===hash(fs.readFileSync(path.join(root,j.source))));
 }
 fs.writeFileSync(jobsFile,JSON.stringify(jobList,null,2));
 const localPython=path.join(process.env.LOCALAPPDATA||'','Programs/Python/Python314/python.exe'),python=process.env.DOTA_UI_PYTHON||(fs.existsSync(localPython)?localPython:'python');
 if(!reusable){const result=cp.spawnSync(python,[path.join(__dirname,'prepare_images.py')],{windowsHide:true,stdio:'inherit'});if(result.status!==0)throw Error('Review image preparation failed');}else console.log('FIVE_LOTTERY_REVIEW_IMAGES_REUSED_VERIFIED');
 const prepared=JSON.parse(fs.readFileSync(preparedFile,'utf8'));
 function finalAsset(row){const p=prepared[row._image];manifest.push({kind:'official_ui',id:row.id,uri:row.uri,sourcePath:row.sourcePath,file:row.original,sourceSha256:row.sourceSha256,originalSha256:p.originalSha256,previewSize:p.previewSize});return {id:row.id,uri:row.uri,sourcePath:row.sourcePath,preview:p.preview,original:row.original,width:row.width,height:row.height};}
 const schemes=recipe.themes.map(theme=>({id:theme.id,name:theme.title,kicker:theme.kicker,description:theme.description,palette:theme.palette,assets:Object.fromEntries(Object.entries(schemeAssets.get(theme.id)).map(([key,row])=>[key,finalAsset(row)]))}));
 for(const pool of pools){pool.icon=prepared[pool._icon].preview;pool.ticketIcon=prepared[pool._ticket].preview;delete pool._icon;delete pool._ticket;for(const r of pool.rewards){r.image=prepared[r._image].preview;delete r._image;}pool.featured=pool.rewards[0];}
 const data={meta:{title:'官方 UI × 激战 2 布局 · 五套抽奖界面',source:'界面背景、按钮、边框、装饰和宝箱原画均来自本机 Dota 2 官方资源；抽奖券与奖品沿用当前游戏的资源目录。',notes:['布局沿用当前1672×941参考画布：顶部标题与余额、左侧四奖池、右侧主场景、下方珍藏预览和单抽/十连。','五套采用不同官方背景与按钮素材，原始资源不做重绘；HTML内嵌的是供评审使用的缩放副本。','名称、消耗、奖品和保底文字来自当前项目CSV；余额和开奖结果为本地演示样例，不提交游戏或支付事件。']},schemes,controls:Object.fromEntries(Object.entries(controls).map(([key,row])=>[key,finalAsset(row)])),pools};
 const html=require('./template.cjs').render(data),file=path.join(out,'五套官方抽奖界面.html');fs.writeFileSync(file,html);
 fs.writeFileSync(path.join(out,'asset_manifest.json'),JSON.stringify({sourceCatalog:relative(catalogFile),catalogSha256:hash(fs.readFileSync(catalogFile)),schemes:recipe.themes.map(t=>({id:t.id,title:t.title,hero:t.hero,assets:t.assets})),sources:manifest,formalSources:formal.source,htmlSha256:hash(Buffer.from(html)),imageCount:jobs.size,htmlBytes:Buffer.byteLength(html),nativeGameVerified:false},null,2));
 fs.writeFileSync(path.join(work,'data.json'),JSON.stringify(data));console.log(JSON.stringify({status:'PASS',schemes:schemes.length,pools:pools.map(p=>({id:p.id,rewards:p.rewards.length})),images:jobs.size,htmlBytes:Buffer.byteLength(html),file:relative(file)}));
}
module.exports={build};if(require.main===module)build();
