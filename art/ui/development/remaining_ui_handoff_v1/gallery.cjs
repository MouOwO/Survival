const fs=require('fs'),p=require('path');
const root=__dirname,out=p.join(root,'evidence');
const groups=[
 ['奖池详情 · 实机已验证',['final_pool_map','final_pool_cultivation','final_pool_dragon','final_pool_summer','final_pool_summer_scrolled','final_pool_tooltip','final_pool_close_hover'],'pool_details'],
 ['抽奖记录 · 本局真实记录',['final_history_map','final_history_scrolled','final_history_cultivation','final_history_dragon','final_history_summer','final_history_close'],'lottery_history'],
 ['每日奖励 · 领取前截图 / 已领取 / 无通行证 / Tooltip',['daily_ready_before_claim','final_daily_claimed','final_daily_tooltip','final_daily_reopen'],'daily'],
 ['商城与礼包 · 仅空状态实机验证，业务接口阻塞',['final_shop_empty','final_bundles_empty','final_purchase_unconfigured'],'shop'],
 ['肉鸽 · 实际服务器调试候选',['rogue_first','final_rogue_hover','rogue_selected'],'roguelike'],
 ['主界面、存档与抽奖结果回归',['final_archive_default','final_main_open','final_main_summer','final_main_ten_hover','final_single_skipped','final_ten_results','button_hover_contact'],'lottery']
];
const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
let html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>UI 接入实机验收</title><style>
body{background:#172d37;color:#e5e8e2;font:16px/1.7 "Microsoft YaHei",sans-serif;margin:0;padding:28px;max-width:1500px;margin:auto}h1,h2{font-weight:500;color:#efdfb9}a{color:#a8d6e4}p{max-width:1100px}.notice{border:1px solid #a88c57;padding:15px;background:#263f49}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(370px,1fr));gap:18px}figure{margin:0;background:#10222b;padding:10px}img{max-width:100%;display:block}figcaption{font-size:14px;overflow-wrap:anywhere}details{padding:10px;background:#243f4a;margin:12px 0}summary{cursor:pointer}video{width:100%;max-width:1000px}.compare{position:relative}.compare img{width:100%}.compare .actual{position:absolute;inset:0;opacity:.5}input{width:300px}small{color:#b4c1c5}</style>
<h1>剩余 UI 接入：实际游戏证据</h1><p class="notice"><a href="nav_rogue_fix.html">最新：存档分隔线滚动、肉鸽透明背景及放大裁切修复（含实机录屏）</a>。以下保留上一轮原始截图，肉鸽背景以最新修复页为准。</p><p class="notice">运行环境：隔离测试插件 <b>survival_ui_handoff_v1</b>，实际客户端 1672×941，单人 local_fixture。正式 survival UI 未覆盖。这里是截图/录屏浏览页，不是游戏 UI 的静态替代实现。商城支付、自然周末高级装备及第二分辨率尚未通过实机验证。</p>
<p><a href="../README.md">完成状态、修改文件与阻塞说明</a> · <a href="../deployment_verification.json">部署保护校验</a> · <a href="comparisons/manifest.json">对齐坐标</a></p>
<p>并排图左侧是交接确认图，右侧是实际游戏截图；内容差异包括真实奖励、无通行证、已领取及未配置接口。不能据此认定业务已全部完成。</p>`;
for(const [title,files,page] of groups){html+=`<h2>${esc(title)}</h2><div class="grid">`;for(const name of files){if(!fs.existsSync(p.join(out,name+'.png')))throw Error('Missing evidence '+name);html+=`<figure><a href="${name}.png"><img loading="lazy" src="${name}.png"></a><figcaption>${name}</figcaption></figure>`;}html+='</div>';html+=`<details><summary>查看与确认图的并排及 50% 叠加对照</summary><a href="comparisons/${page}_pair.png"><img loading="lazy" src="comparisons/${page}_pair.png"></a><p><a href="comparisons/${page}_overlay.png">打开半透明叠加图</a></p></details>`;}
html+=`<h2>实际游戏录屏</h2><p><a href="rogue_motion.avi">肉鸽入场、翻面、悬停：8.04 秒 / 25fps / MJPEG AVI</a> · <a href="button_hover.avi">单抽/十连快速移入移出：6.04 秒 / 25fps</a></p><p>录屏来自游戏窗口采集，未使用生成帧。浏览器若不能直接播放 AVI，请下载后用支持 MJPEG 的播放器打开。暂停提示属于测试地图原生画面。</p><h2>验收边界</h2><ul><li>奖池仍使用真实 Dota 物品小图；原图分辨率和固有深色背景仍在，没有冒充最终定制物品美术。</li><li>奖池外框在包内未完整去字分层，当前复用公共九宫格窗口；字号与外框细节仍需对照验收。</li><li>每日奖励实际为累计七次循环；通行证额外高级装备由服务器返回“待配置”。</li><li>商城、礼包和订单截图仅证明组件布局/空状态已在游戏渲染；不证明商品、支付或发货已接通。</li><li>第二分辨率调整未实际生效，不能标为已验证。</li></ul></html>`;
fs.writeFileSync(p.join(out,'index.html'),html);console.log('Evidence gallery created; source captures are linked without substitution.');
