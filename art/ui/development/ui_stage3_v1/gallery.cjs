// Index only inspected native captures. Debug/defeat captures stay outside delivery.
const fs=require('fs'),p=require('path'),crypto=require('crypto');
const here=__dirname,repo=p.resolve(here,'../../../..'),out=p.join(here,'evidence');
const rows=[
 ['HUD：十技能、竖排属性、固定人物位置','../ui_handoff_v1/evidence/stage3_hud_ten_final.png','hud_bottom'],
 ['HUD：三技能位置对照','../remaining_ui_handoff_v1/evidence/stage3_hud_three_fixed.png',''],
 ['HUD：七技能位置对照','../remaining_ui_handoff_v1/evidence/stage3_hud_seven_fixed.png',''],
 ['存档：实际进度与图标','../remaining_ui_handoff_v1/evidence/stage3_archive_delivered.png','archive'],
 ['存档：筛选为空、内部点击后保留窗口','../remaining_ui_handoff_v1/evidence/stage3_final_archive_inside.png',''],
 ['地图抽奖：默认池','../remaining_ui_handoff_v1/evidence/stage3_stable_lottery.png','lottery'],
 ['地图抽奖：暑期池','../remaining_ui_handoff_v1/evidence/stage3_stable_lottery_summer.png',''],
 ['详情：地图池，底层仍为暑期池','../remaining_ui_handoff_v1/evidence/stage3_stable_pool_map.png','pool_details'],
 ['详情：修仙池','../remaining_ui_handoff_v1/evidence/stage3_stable_pool_xiuxian.png',''],
 ['详情：龙脊尖兵','../remaining_ui_handoff_v1/evidence/stage3_stable_pool_dragon.png',''],
 ['详情：暑期池','../remaining_ui_handoff_v1/evidence/stage3_stable_pool_summer.png',''],
 ['详情：真实物品效果 Tooltip','../remaining_ui_handoff_v1/evidence/stage3_stable_pool_tooltip.png',''],
 ['记录：当前玩家21份实际奖励','../remaining_ui_handoff_v1/evidence/stage3_stable_history_actual.png','lottery_history'],
 ['记录：暑期池为空','../remaining_ui_handoff_v1/evidence/stage3_stable_history_empty.png',''],
 ['每日：普通与通行证区域分开','../remaining_ui_handoff_v1/evidence/stage3_stable_daily.png','daily'],
 ['每日：双击领取后仅累计1次；内部空白点击仍打开','../remaining_ui_handoff_v1/evidence/stage3_stable_daily_inside.png',''],
 ['商店：现有金币木材货架，未冒充积分商城','../ui_handoff_v1/evidence/stage3_shop_actual.png','shop'],
 ['商店：真实效果、价格与购买条件','../remaining_ui_handoff_v1/evidence/stage3_shop_tooltip_verified.png',''],
 ['1280×720：十技能 HUD','../ui_handoff_v1/evidence/stage3_hud_1280_ten.png',''],
 ['1280×720：存档','../remaining_ui_handoff_v1/evidence/stage3_archive_1280.png',''],
 ['1280×720：每日已领取','../remaining_ui_handoff_v1/evidence/stage3_daily_1280.png',''],
 ['1280×720：抽奖','../remaining_ui_handoff_v1/evidence/stage3_lottery_1280.png',''],
 ['1280×720：奖池详情','../remaining_ui_handoff_v1/evidence/stage3_pool_1280.png','']
];
const videos=[['single_final','单抽真实结果',159],['ten_final','十连真实结果',159],['ten_skip_final','十连跳过',119],['rogue_delivered','肉鸽新插画与动画（1768×992）',139],['rogue_delivered_1280','肉鸽新插画与动画（1280×720）',139],['boss_current','实际第五波 BOSS 警告',95]];
const esc=s=>s.replace(/[&<>\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const rel=f=>p.relative(out,f).replace(/\\/g,'/');
const manifest=[];let html='<!doctype html><meta charset="utf-8"><title>第三阶段 · 实际游戏证据</title><style>body{background:#17343e;color:#f2ebdf;font:16px sans-serif;margin:24px}a{color:#e7cf8b}article{margin:28px 0;padding:16px;border:1px solid #66828a}.pair{display:grid;grid-template-columns:1fr 1fr;gap:14px}img{max-width:100%;height:auto}figure{margin:0}figcaption{padding:10px 0}button,input{margin:8px}small{color:#c0d3d4}</style><h1>UI 第三阶段 · 实际游戏证据</h1><p>隔离测试副本 survival_ui_handoff_v1。原始游戏截图，无合成界面。并排确认图仅用于审阅布局，不表示已经完成逐像素匹配。录屏为连续真实采集帧；AVI 可下载播放。</p><p><a href="../README.md">状态、缺项与版本说明</a> · <a href="../art/index.html">52张插画离线审阅（不是实机证据）</a></p>';
for(const [title,file,page] of rows){const f=p.resolve(here,file);if(!fs.existsSync(f))throw Error(file);const bytes=fs.readFileSync(f);const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20);manifest.push({title,file:p.relative(repo,f).replace(/\\/g,'/'),width,height,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),source:'native Dota window'});html+='<article><h2>'+esc(title)+'</h2><div class="pair"><figure><a href="'+rel(f)+'"><img loading="lazy" src="'+rel(f)+'"></a><figcaption>实际游戏 '+width+'×'+height+'</figcaption></figure>';const ref=p.join(repo,'art/ui/development/ui_handoff_v1/received/ui_import_handoff_v1/pages',page,'approved_preview.png');if(page&&fs.existsSync(ref))html+='<figure><img loading="lazy" src="'+rel(ref)+'"><figcaption>交接确认图（布局参考；示例数据不写入游戏）</figcaption></figure>';html+='</div></article>';}
for(const [name,title,last] of videos){const folder=p.join(out,name+'_frames'),m=JSON.parse(fs.readFileSync(p.join(folder,'capture.json'),'utf8').replace(/^\uFEFF/,''));html+='<article><h2>'+title+'</h2><a href="'+name+'.avi">下载真实录屏 AVI</a><p>'+m.width+'×'+m.height+' · '+(m.elapsedMs/1000).toFixed(2)+'秒</p><img id="v_'+name+'" src="'+name+'_frames/'+String(last).padStart(5,'0')+'.jpg"><p><button data-name="'+name+'" data-count="'+m.frames.length+'" data-fps="'+m.fps+'">逐帧播放</button><input aria-label="录屏帧" type="range" min="0" max="'+(m.frames.length-1)+'" value="'+last+'" data-name="'+name+'"></p></article>';manifest.push({title,file:'art/ui/development/ui_stage3_v1/evidence/'+name+'.avi',width:m.width,height:m.height,durationMs:m.elapsedMs,source:'native Dota continuous capture'});}
html+='<script>let timer;function frame(n,i){document.getElementById("v_"+n).src=n+"_frames/"+String(i).padStart(5,"0")+".jpg"}document.querySelectorAll("input").forEach(e=>e.oninput=()=>{clearInterval(timer);frame(e.dataset.name,+e.value)});document.querySelectorAll("button[data-name]").forEach(b=>b.onclick=()=>{clearInterval(timer);let i=0;timer=setInterval(()=>{frame(b.dataset.name,i++);if(i>=+b.dataset.count)clearInterval(timer)},1000/+b.dataset.fps)});</script>';
fs.writeFileSync(p.join(out,'index.html'),html);fs.writeFileSync(p.join(out,'manifest.json'),JSON.stringify(manifest,null,2));console.log('Indexed '+manifest.length+' inspected native evidence items');
