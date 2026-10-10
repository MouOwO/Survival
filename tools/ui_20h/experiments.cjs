'use strict';const fs=require('fs');const {browser}=require('../shop_ui_12h/cdp.cjs');const base='design_refs/ui_20h/work/candidates';
const experiments=[
 [5,'queue','降低训练衬底透明度','训练玻璃更轻', '#SurvivalProductionPanel.CompactTraining{background:#31565d9c}',null],
 [6,'queue','象牙训练面板','检验浅底是否适用于战斗 HUD','#SurvivalProductionPanel.CompactTraining{background:#eeefe4ed}#SurvivalProductionPanel.CompactTraining .label{color:#234957}',null],
 [7,'queue','移除选项的小框','减少四块卡片的碎片感','.ProductionTrainingSlot{border-color:transparent!important;background:transparent!important}',null],
 [8,'queue','增大成本字号','改善 720p 成本读取','#SurvivalProductionPanel.CompactTraining .ProductionTrainingCost{font-size:28px}',null],
 [9,'queue','缩小头像','检查留白与辨识度的权衡','',"document.querySelectorAll('.ProductionTrainingIcon').forEach(e=>{e.style.width='64px';e.style.height='64px';})"],
 [10,'queue','队列 progress 青玉','减少活动进度金色权重','.ProductionProgressFill{background:#83b6ae}',null],
 [11,'hud','减弱顶部衬底','释放战场画面','#HandoffTopBackdrop{opacity:.55}',null],
 [12,'hud','属性字增大','检验 720p 属性可读性','',"document.querySelectorAll('[id^=HandoffStat_]').forEach(e=>e.style.fontSize='25px')"],
 [13,'hud','资源局部衬底','避免整条黑顶栏','#HandoffResource_goldRow,#HandoffResource_woodRow,#HandoffResource_populationRow{background:#173d4675;border-radius:4px}',null],
 [14,'hud','技能槽金边减半','保留正方形结构，降低描边重量','',"document.querySelectorAll('[style*=\"border\"]').forEach(e=>{if(e.style.border.includes('2px solid'))e.style.borderWidth='1px'})"],
 [15,'hud','入口标签淡玉色','检验图标标签的一体化','',"document.querySelectorAll('.HandoffNav .label').forEach(e=>e.style.color='#d0e2d9')"],
 [16,'hud','悬停更亮','检验入口反馈是否过重','.HandoffNav:hover{background:#79b6af85;filter:brightness(1.35)}',null],
 [17,'archive','条目更浅','降低卡片底和窗口底的硬分界','.ArchiveJade #ArchiveGrid .ArchiveCard{background:#ffffff42}',null],
 [18,'archive','条目细边','检验无金色常驻边框的安静程度','.ArchiveJade #ArchiveGrid .ArchiveCard{border-color:#97aea35a}',null],
 [19,'archive','名称加大','提高长名称与常规名称的可读性','',"document.querySelectorAll('.ArchiveItemName').forEach(e=>e.style.fontSize='18px')"],
 [20,'archive','进度深浅对比','避免角标盖过主图','.ArchiveJade #ArchiveGrid .ArchiveCount{background:#31574f;color:#f4f1df}',null],
 [21,'archive','导航光晕减弱','检验金光与下对齐线的权重','.ArchiveTab.Selected .ArchiveNavGlow{opacity:.55}',null],
 [22,'archive','标题更强','检查题头与条目层级','',"document.querySelector('#ArchiveTitle').style.fontSize='42px'"],
 [23,'archive','图标轻微增大','检查 4 列卡片中图标辨识度','.ArchiveJade #ArchiveGrid .ArchiveArt{width:99px;height:78px;left:22px;top:14px}',null],
 [24,'archive','金色条目 hover','对比细边与光晕','.ArchiveJade #ArchiveGrid .ArchiveCard:hover{box-shadow:0 0 8px #cfb67980}',null],
 [25,'shared','共享按钮浅玉','购买/领取类按钮材质','.JadeAction{filter:brightness(1.12)}',null],
 [26,'shared','共享按钮深玉','检查 disabled 与默认按钮分离','.JadeAction{filter:brightness(.85)}',null],
 [27,'shared','tooltip 象牙','检验浅 tooltip 与浅弹窗的层级','.JadeTooltip{background:#f2f1e8;color:#234957}.JadeTooltip .label{color:#234957}',null],
 [28,'shared','tooltip 青玉','检验沿用深玉提示层','.JadeTooltip{background:#173d46f5;border:1px solid #92aaa4;border-radius:4px}',null]
].map(([id,area,name,purpose,css,script])=>({id:'v'+String(id).padStart(3,'0'),area,name,purpose,css,script,variables:script?1:Math.min(3,(css.match(/:/g)||[]).length),parent:'v004 + approved shop B17/L21/T23'}));
fs.writeFileSync('design_refs/ui_20h/work/experiments.json',JSON.stringify(experiments,null,2));
(async()=>{const b=await browser();try{for(const e of experiments.filter(e=>Number(e.id.slice(1))>=Number(process.argv[2]||0)&&Number(e.id.slice(1))<=Number(process.argv[3]||99))){const page=e.area==='hud'?'hud':e.area==='archive'?'archive':e.area==='shared'?'archive':'';await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:1910,y:1070});await b.go('design_refs/ui_20h/work/preview/index.html','?page='+page+'&state=waiting');await b.run('document.querySelectorAll(".PreviewExperiment").forEach(x=>x.remove());const s=document.createElement("style");s.className="PreviewExperiment";s.textContent='+JSON.stringify(e.css)+';document.head.append(s);');if(e.script)await b.run(e.script);if(e.area==='shared')await b.run('const a=$.CreatePanel("Button",panoRoot,"SharedActionPreview");a.style.position="760px 380px 0px";a.style.zIndex="200100";a.style.width="188px";a.style.height="46px";const l=$.CreatePanel("Label",a,"");l.text="领取奖励";l.style.width="100%";l.style.height="100%";l.style.textAlign="center";l.style.fontSize="24px";cfg.SurvivalJade.Action(a);const t=$.CreatePanel("Panel",panoRoot,"SharedTooltipPreview");t.style.position="760px 450px 0px";t.style.zIndex="200100";t.style.width="320px";t.style.height="180px";const x=$.CreatePanel("Label",t,"");x.text="原生物品 · 奖励说明\\n效果、价格与文字保持独立";x.style.position="20px 24px 0px";x.style.width="280px";x.style.fontSize="18px";cfg.SurvivalJade.Tooltip(t);true;');await b.shot(base+'/'+e.id+'_default.png');let target=e.area==='queue'?'.ProductionTrainingSlot':e.area==='hud'?'.HandoffNav':e.area==='archive'?'.ArchiveCard':'#SharedActionPreview';const pos=await b.run('(()=>{const r=document.querySelector('+JSON.stringify(target)+').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()');await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...pos});await b.shot(base+'/'+e.id+'_hover.png');const clips={queue:{x:700,y:770,width:400,height:240},hud:{x:0,y:0,width:1920,height:150},archive:{x:460,y:140,width:1000,height:820},shared:{x:735,y:365,width:380,height:290}};await b.shot(base+'/'+e.id+'_crop.png',e.id==='v012'?{x:730,y:940,width:170,height:135}:e.id==='v014'?{x:800,y:885,width:410,height:185}:e.area==='hud'?{x:1360,y:0,width:560,height:130}:clips[e.area]);console.log('EXPERIMENT_CAPTURED '+e.id+' '+e.area);} }finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
