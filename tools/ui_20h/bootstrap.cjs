'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const base='design_refs/ui_20h';
for(const p of ['work/baseline','work/candidates','work/checkpoints','Delivery'])fs.mkdirSync(base+'/'+p,{recursive:true});
const source='design_refs/shop_ui_base';
fs.copyFileSync(source+'/TASK_SPEC_20H.md',base+'/TASK_SPEC_20H.md');
const files=['panorama/src/scripts/custom_game/production_progress.js','panorama/src/styles/custom_game/production_progress.css','panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','panorama/src/layout/custom_game/survival_hud.xml','panorama/src/layout/custom_game/archive.xml','panorama/src/scripts/custom_game/archive_handoff_180de7e38b.js','panorama/src/styles/custom_game/archive_handoff_180de7e38b.css'];
const hashes={};for(const f of files){const dest=base+'/work/checkpoints/baseline/'+f;fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(f,dest);hashes[f]=crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');}
fs.writeFileSync(base+'/work/checkpoints/baseline/manifest.json',JSON.stringify({at:new Date().toISOString(),files:hashes},null,2));
const tokens={hud:{background:'#173d46d9',edge:'#8da9a07a',text:'#f4f1df',muted:'#c1d0c8',gold:'#cfb679',shadow:'#061e2870'},modal:{background:'#f2f1e8',text:'#234957',muted:'#59756f',edge:'#93afa4',jade:'#477c7e',gold:'#cfb679'},type:{body:16,small:14,title:32},interaction:{hover:0.12,press:0.08},queue:{designWidth:600,option:76,waiting:42,padding:16}};
fs.writeFileSync(base+'/UI_TOKENS.json',JSON.stringify(tokens,null,2));
fs.writeFileSync(base+'/Plan.md',`# 20 小时 UI 迭代\n\n开始：${new Date().toISOString()}。预算上限 20 小时，按证据提前交付。\n\n1. 完成基线与资源盘点，主界面/训练 A、B 实际组件候选。\n2. 入口、资源、HUD 表面六组候选；冻结稳定区域。\n3. 训练布局和全状态，保留服务器名额/成本/解锁。\n4. 存档浅底、导航连续、独立光晕与金线、条目/tooltip。\n5. 复用公共按钮/标题/提示到已接入每日奖励、抽奖详情记录。\n6. 四分辨率、同状态对比、编译及游戏验证、交付。\n\n计划 24–36 个有目的候选，每轮 1–3 个变量；未改善则淘汰。\n`);
fs.writeFileSync(base+'/Progress.md',`# 进度\n\n- 当前工程已先按 stash → pull → pop → commit → push 提交到 origin/dev：ab6c3070。\n- 指定目录原来不存在，完整任务实际在 shop_ui_base；已读取并查看七张图，新迭代输出集中 ui_20h。原参考包不改。\n- 真实游戏启动中；预览使用同一生产组件与显式本地样例，不连接支付。\n- 基线源文件和哈希已保存。\n`);
fs.writeFileSync(base+'/Decisions.md',`# 决策记录\n\n- 保持现有底部 HUD 几何、存档 869×713 几何、商城 1600×920 几何。参考 06 只指导气质，不能替换游戏场景。\n- 训练前四个未满额等级是服务器与前端共同已有规则，不能改成全部等级同时开放；后续满额递补保留。\n- 训练队列只支持城市失效时整队退款，没有逐项取消 API。此次不新增业务；研究队列已有逐项取消，继续复用并改为悬停叉号。\n- 已有 native/train_lumberjack_01–08 与 repairer 图标可复用，不从效果图抠图。\n`);
fs.writeFileSync(base+'/BEST_VERSION.json',JSON.stringify({baseline:'ab6c3070',selected:{},gameValidation:'pending',experiments:[]},null,2));
console.log('UI20H_BASELINE_SAVED',files.length);
