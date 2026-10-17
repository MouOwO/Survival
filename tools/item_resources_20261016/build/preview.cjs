'use strict';
// The real active XML/JS/CSS and formal data with isolated account state only.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const repo=path.resolve(__dirname,'../../..'),out=path.join(repo,'design_refs/item_resources_20261016/build/preview');
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
function run(program,args){const r=cp.spawnSync(program,args,{cwd:repo,encoding:'utf8',windowsHide:true});if(r.status!==0)throw Error((r.stdout||'')+(r.stderr||'')+String(r.error||''));if(r.stdout)console.log(r.stdout.trim());}
run(process.env.LUA51||'C:/Program Files/lua/bin/lua5.1.exe',['tools/item_resources_20261016/build/project_fixture.lua',path.join(out,'goods_fixture.json')]);
const goods=JSON.parse(fs.readFileSync(path.join(out,'goods_fixture.json'),'utf8'));
run(process.execPath,['tools/menus_v10/preview.cjs','--out',path.relative(repo,out)]);
const filename=path.join(out,'index.html');let html=fs.readFileSync(filename,'utf8');
const key='window.PREVIEW_FIXTURE=',next=';window.PREVIEW_SOURCE_ROOT=',start=html.indexOf(key)+key.length,end=html.indexOf(next,start);
if(start<key.length||end<start)throw Error('Production fixture field not found.');
const fixture=JSON.parse(html.slice(start,end));
fixture.v10.pages.commerce_goods=goods.rows;
if(!fixture.v10.categories.some(c=>c.id==='commerce_goods'))fixture.v10.categories.push({id:'commerce_goods',name:'商城道具'});
const h=JSON.parse(fs.readFileSync('server/bundles/current.json','utf8')).hash;
const bundlePath='server/bundles/'+h+'/bundle.json',bundleBytes=fs.readFileSync(bundlePath);
if(crypto.createHash('sha256').update(bundleBytes).digest('hex')!==h)throw Error('Active bundle integrity mismatch.');
const cfg=JSON.parse(bundleBytes).configs;
fixture.commerce.wallet.products=cfg.commerce_catalog.rows.filter(p=>p.enabled).map(p=>({...p,purchase_method:'wallet',owned:0,reward_lines:(p.grants||{}).lines||[],currency_name:{u_coin:'U币',shop_points:'积分',shop_gold:'金币'}[p.currency]}));
html=html.slice(0,start)+JSON.stringify(fixture).replaceAll('</script','<\\/script')+html.slice(end);
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1统一物品资源 · 真实 XML / JS / CSS 与正式数据 · 离线持有样例 · 未连接游戏、账号、抽奖或支付$2');
const readyScript=`<script>
window.itemResourceReady=previewReady.then(async function(ok){
 if(!ok)return false;
 if(previewState.page==='commerce')cfg.SurvivalCommerceView.SelectCategory('all');
 if(previewState.page==='lottery'&&params.get('pool')){
  const raw=PREVIEW_FIXTURE.lottery,id=params.get('pool'),pools=raw.pools.map(x=>({...x,id:x.pool_id,single_cost:Number(x.single_cost),ten_cost:Number(x.ten_cost),ui_order:Number(x.ui_order),unlocked:true,tickets:20,ticket_name:'抽奖券'})),selected=pools.find(x=>x.id===id);
  if(!selected)throw Error('Unknown formal pool '+id);
  selected.pity=raw.pity.filter(x=>x.pool_id===id).map(x=>({...x,threshold:Number(x.threshold),quality:x.target_quality,batch_size:Number(x.threshold),label:'十连保底 '+x.target_quality.toUpperCase()}));
  const items=raw.members.filter(x=>x.pool_id===id).map(x=>raw.items.find(r=>r.item_id===x.item_id)).filter(Boolean).map(x=>({...x,id:x.item_id,name:x.display_name,duplicate_points:Number(x.duplicate_points),exchange_points:Number(x.exchange_points),exchange_enabled:Number(x.exchange_enabled),max_owned:Number(x.max_owned),owned:0,owned_count:0,at_max_owned:0}));
  cfg.SurvivalLottery.CloseInfo();cfg.SurvivalLottery.SelectPool(id);emit('ui_lottery_snapshot',{snapshot_scope:'main',selected_pool_id:id,selected_pool:selected,pools,items,shop_points:425,starjoy_points:320,pity:selected.pity});cfg.SurvivalLottery.Feature('details');
 }
 syncLayout();await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
});
</script>`;
html=html.replace('</html>',readyScript+'</html>');
fs.writeFileSync(filename,html);
const manifestPath=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
assembly.kind='item_resource_consistency_production_assembly';assembly.notGameCapture=true;
assembly.syntheticOwnership=true;assembly.goodsCount=goods.rows.length;assembly.bundle={hash:h,path:bundlePath};
fs.writeFileSync(manifestPath,JSON.stringify(assembly,null,2)+'\n');
console.log('ITEM_RESOURCE_PREVIEW_BUILT '+path.relative(repo,filename));
