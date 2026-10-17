'use strict';
const fs=require('fs'),path=require('path'),{spawnSync}=require('child_process'),{pathToFileURL}=require('url');
const repo=path.resolve(__dirname,'../../..'),out=path.join(repo,'design_refs/vip_recharge_20261016/ui/preview');
const build=spawnSync(process.execPath,[path.join(repo,'tools/archive_parchment/preview.cjs'),'--out',out],{cwd:repo,encoding:'utf8',windowsHide:true});if(build.stdout)process.stdout.write(build.stdout);if(build.stderr)process.stderr.write(build.stderr);if(build.status)process.exit(build.status);
const file=path.join(out,'index.html'),adapter=pathToFileURL(path.join(repo,'tools/archive_v10/adapter.js')).href,widgets=pathToFileURL(path.join(repo,'tools/endless_leaderboard/preview_widgets.js')).href;
const fixture=JSON.parse(fs.readFileSync(path.join(repo,'design_refs/archive_commerce_goods_20261016/ui/projection_fixture.json'),'utf8'));
let html=fs.readFileSync(file,'utf8');html=html.replace('<script src="'+adapter+'"></script>','<script src="'+adapter+'"></script><script src="'+widgets+'"></script>');
const injected=`<script>
window.vipGoodsFixture=${JSON.stringify(fixture.owned).replace(/</g,'\\u003c')};
window.vipPreviewReady=window.previewReady.then(async function(ok){
 if(!ok)return false;
 const page=new URLSearchParams(location.search).get('page')||'leaderboard';
 if(page==='leaderboard'){
  cfg.SurvivalArchive.SelectCategory('shop');const rows=leaderboardSampleRows();rows.forEach((row,i)=>{row.vip_level=i<12?12-i:i%13;row.vip_medal_level=i<10?10-i:i%11;});rows[2].vip_medal_level=0;leaderboardPreviewDeliver(rows,'vip_preview_v1');
 }else if(page==='goods'){
  if(!PREVIEW_FIXTURE.v10.categories.some(c=>c.id==='commerce_goods'))PREVIEW_FIXTURE.v10.categories.push({id:'commerce_goods',name:'商城道具'});
  const rows=JSON.parse(JSON.stringify(vipGoodsFixture.rows)).filter(r=>/^vip_/.test(r.id));rows.forEach((r,i)=>{r.count=1;r.count_known=1;r.quantity_unknown=0;r.unlocked=1;});previewFixturePages.commerce_goods=rows;await previewSelect('commerce_goods');
 }else if(page==='vip'){
  cfg.SurvivalArchive.Close();emitNet('survival_player_public_profiles','0',{vip_badge:1});const snapshot={ok:true,level:12,balance:9999,recharge_total_fen:1250000,rows:{}};cfg.VIPRewardCatalog.rewards.forEach((row,i)=>snapshot.rows[i]={id:row.reward_id,owned:row.group_id==='privileges'?1:0,eligible:1,affordable:1});emit('survival_vip_snapshot',snapshot);cfg.SurvivalVIP.Open();
 }
 await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
});
</script>`;
html=html.replace('</html>',injected+'</html>').replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1VIP 充值等级 / 已购勋章 · 正式 XML / JS / CSS · 隔离样例 · 非游戏截图、未连接账号服务$2');fs.writeFileSync(file,html);
console.log('VIP_PREVIEW_BUILT '+path.relative(repo,file));
