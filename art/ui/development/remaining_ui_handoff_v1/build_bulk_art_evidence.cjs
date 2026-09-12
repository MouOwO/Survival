// Build a browseable index of actual, unmodified game-window captures.
const fs=require('fs'),p=require('path'),here=__dirname,folder=p.join(here,'evidence');
const read=name=>JSON.parse(fs.readFileSync(p.join(here,name),'utf8').replace(/^\uFEFF/,''));
const deployment=read('deployment_verification.json'),mapping=read('archive_icon_manifest.json');
const esc=s=>String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
const groups=[
 ['好友 / 前女友 / 瑞兽','ab35e63403',[
  ['bulk_art_friend_complete.png','好友：真实列表'],['bulk_art_friend_last_page.png','好友：40 项试览末页'],
  ['bulk_art_ex_complete.png','前女友：真实列表'],['bulk_art_ex_corrected_page.png','前女友：修订角色'],['bulk_art_ex_last_page.png','前女友：40 项试览末页'],
  ['bulk_art_beast_complete.png','瑞兽：真实列表'],['bulk_art_beast_tooltip.png','瑞兽：真实效果 Tooltip'],['bulk_art_beast_last_page.png','瑞兽：40 项试览末页']]],
 ['钓鱼存档','c3372672c1',[
  ['bulk_art_fishing_live.png','26 张鱼类已接入；服务器未返回库存，保留待同步状态'],['bulk_art_fishing_page4.png','鱼类试览第四页及末页禁用']]],
 ['神兵 / 建筑 / 商店','96e1f85553',[
  ['bulk_art_fragment_live.png','神兵：真实列表'],['bulk_art_fragment_page2.png','神兵：12 项试览第二页'],
  ['bulk_art_building_complete.png','建筑：按真实装备名称制作的 9 张图'],['bulk_art_building_page2.png','建筑：第二页'],
  ['bulk_art_shop_trial_page1.png','商店：图标试览第一页；不代表购买验证'],['bulk_art_shop_trial_page2.png','商店：10 项试览第二页']]],
 ['最后一批积分 / 秘法图标','1316df6e49',[
  ['final_points_art_page1.png','积分道具：100 项试览第一页'],['final_points_art_last.png','积分道具：末页及最后四张新图'],
  ['final_pet_art_page1.png','秘法牢笼：54 项试览第一页'],['final_pet_art_last.png','秘法牢笼：试览末页']]],
 ['奖池共用新图','f0886b0d0b',[
  ['final_pool_map.png','抽奖奖池详情：共用新的真实物品图']]],
 ['每日奖励 / 实际商店','39ec85cc89 → 73bf488994',[
  ['final_daily_art.png','每日奖励：实际配置对应的各自新图（39ec85cc89）'],
  ['final_daily_claim_reopen.png','普通奖励已领取；无通行证不阻挡普通领取（39ec85cc89）'],
  ['final_shop_tooltip_fixed.png','实际金币木材商店：新图与正确层级的 Tooltip（73bf488994）']]]
];
const captures=[];
let sections='';
for(const [title,version,photos] of groups){
 let body='';
 for(const [file,caption] of photos){
  if(!fs.existsSync(p.join(folder,file)))continue;
  captures.push({file,caption,version,kind:'actual_game_capture'});
  body+='<figure><a href="'+file+'"><img loading="lazy" src="'+file+'"></a><figcaption>'+esc(caption)+'<br>采集版本：'+esc(version)+'</figcaption></figure>';
 }
 if(body)sections+='<h2>'+esc(title)+'</h2><div class="grid">'+body+'</div>';
}
const page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>批量图标 · 游戏实机记录</title><style>body{margin:0 auto;padding:28px;max-width:1560px;background:#173744;color:#f0eadc;font:16px/1.7 "Microsoft YaHei",sans-serif}h1,h2{font-weight:500;color:#eed49b}a{color:#abd6e3}.notice{padding:16px;background:#244753;border:1px solid #a8905e}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(560px,1fr));gap:18px}figure{margin:0;padding:10px;background:#112d39}img{display:block;width:100%}figcaption{font-size:14px;padding-top:8px}@media(max-width:650px){.grid{grid-template-columns:1fr}}</style><h1>批量存档与商店图标 · 实机记录</h1><p class="notice">这些图片直接采集自隔离测试地图 <b>survival_ui_handoff_v1</b> 的 1672×941 游戏窗口。正式 survival UI 未覆盖。各图标明采集版本，早期阶段截图不会冒充当前完整版本。当前部署 '+esc(deployment.version)+'，映射 '+mapping.length+' 张。</p><p><a href="../bulk_art/index.html">离线资源审阅（不是游戏截图）</a> · <a href="../bulk_art/art_audit.json">透明边缘与来源审计</a> · <a href="../README.md">修改与验收说明</a></p><p>“图标试览”是游戏内只读美术检查：不表示持有，不发放奖励。实际列表保持服务器的数量、属性与解锁状态。商城实际购买、付费商品目录与鱼类库存同步不属于本页截图已经验证的结果。</p>'+sections+'</html>';
fs.writeFileSync(p.join(folder,'bulk_art_game.html'),page);
fs.writeFileSync(p.join(folder,'bulk_art_capture_manifest.json'),JSON.stringify({deployment:deployment.version,captures},null,2));
let index=fs.readFileSync(p.join(folder,'index.html'),'utf8');
if(!index.includes('href="bulk_art_game.html"'))index=index.replace('<h1>剩余 UI 接入：实际游戏证据</h1>','<h1>剩余 UI 接入：实际游戏证据</h1><p class="notice"><a href="bulk_art_game.html">最新：批量自制存档与商店图标实机记录</a>。下方是之前 UI 布局验收的历史截图，旧物品图以新记录页为准。</p>');
fs.writeFileSync(p.join(folder,'index.html'),index);
console.log('Indexed actual game captures:',captures.length);
