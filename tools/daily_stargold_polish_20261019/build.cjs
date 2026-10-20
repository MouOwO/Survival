'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'design_refs/daily_stargold_polish_20261019'),base=path.join(root,'design_refs/daily_official_five_20261019');
process.chdir(root);fs.mkdirSync(out,{recursive:true});fs.mkdirSync(path.join(out,'baseline'),{recursive:true});fs.mkdirSync(path.join(out,'assets'),{recursive:true});fs.mkdirSync(path.join(out,'rewards'),{recursive:true});
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const freeze=(name,bytes)=>{const target=path.join(out,name);if(fs.existsSync(target))assert.equal(hash(fs.readFileSync(target)),hash(bytes),'Frozen baseline changed: '+name);else fs.writeFileSync(target,bytes);};
for(const name of ['preview.css','preview.js','rewards.json','native_assets.json','04_星穹鎏金.html'])freeze('baseline/'+name,fs.readFileSync(path.join(base,name)));
freeze('00_原始04.png',fs.readFileSync(path.join(base,'04_星穹鎏金.png')));
const native=JSON.parse(fs.readFileSync(path.join(out,'baseline/native_assets.json'),'utf8'));
const required=['ti2026_galaxy','ti2026_texture','ti2026_header','ti2026_button_weekly','ti2026_slot','classic_slot_active','shared_check','shared_lock','shared_close'];
for(const key of required){const r=native.records.find(r=>r.key===key),bytes=fs.readFileSync(path.join(base,r.local));assert.equal(hash(bytes),r.hash.png);freeze(r.local,bytes);}
const rewardData=JSON.parse(fs.readFileSync(path.join(out,'baseline/rewards.json'),'utf8'));
for(const item of Object.values(rewardData.items)){const icon=item.icon,bytes=fs.readFileSync(path.join(base,icon.previewLocal));assert.equal(hash(bytes),icon.sha256);freeze(icon.previewLocal,bytes);}
const shortlist=JSON.parse(fs.readFileSync(path.join(out,'provenance.json'),'utf8'));
for(const key of ['gold_hud_secondary','gold_bounty_border','gold_bounty_fill','gold_crown_divider','gold_ti26_slot']){const a=shortlist.records.find(r=>r.key===key);assert(a,key);assert.equal(hash(fs.readFileSync(path.join(out,a.local))),a.hash.png);}
const rounds=[
 {id:1,name:'按钮重选',notes:['以官方黑底鎏金倒角替换平金色条形按钮，保持原生4:1比例。','领取按钮单独居中，规则按钮独立靠右，不再挤偏主操作。'],css:String.raw`
.polish .claim{position:absolute;left:50%;top:6px;transform:translateX(-50%);width:256px;height:64px;font-size:20px}
.polish .claim .face{background-image:url('assets/gold_hud_secondary.png');background-size:100% 100%}
.polish .claim span{color:#f6e1a8;letter-spacing:2px;text-shadow:0 1px 2px #000}
.polish .calendar-actions{position:relative;gap:0;padding-top:0}
.polish .rules-button{position:absolute;right:8px;top:23px;width:100px;min-width:0;height:30px;border:0;border-bottom:1px solid #82704d77;background:transparent;color:#b2a489;font-size:12px}
.polish .rules-button .face{display:none}
.polish .buy{width:224px;height:56px;font-size:18px}
.polish .buy .face{background-image:url('assets/gold_hud_secondary.png')}
.polish .action:hover{filter:brightness(1.15)}.polish .action:active{filter:brightness(.87)}
`},
 {id:2,name:'物品格精修',notes:['TI金角保留为装饰，外轮廓改为连续细金线。','今日奖励用克制金色高亮；已领勾淡化，数量统一在边框内。'],css:String.raw`
.polish .slot{background-color:#10110f;border:1px solid #76643e;box-shadow:inset 0 0 0 1px #141611}
.polish .slot-bg{opacity:.74}
.polish .slot:before{inset:3px;border:1px solid #c5a35a20;box-shadow:none}
.polish .today .slot{background:radial-gradient(ellipse at center,#9f733521,#11120f 76%);box-shadow:0 0 14px #caa95d22}
.polish .today .slot:after{background:none;inset:-1px;border:1px solid #edcf88;box-shadow:inset 0 0 0 2px #a8873a3d,0 0 12px #d9b35222;opacity:1}
.polish .claimed .check{width:15px;height:15px;right:7px;top:7px;opacity:.58}
.polish .claimed .item-icon{filter:brightness(.48) saturate(.32)}
.polish .claimed .day-head{color:#908b7b}.polish .future .item-icon{filter:brightness(.82) saturate(.88) drop-shadow(0 2px 4px #0008)}
.polish .quantity{z-index:8;right:8px;bottom:6px;color:#eee4c6;font-size:18px}.polish .claimed .quantity{color:#9e9a87}
.polish .today .quantity{right:8px;bottom:6px;color:#ffe2a5}.polish .day-head{font-size:12px}
.polish .today .day-head{color:#efcf88}.polish .today .day-head em{font-size:10px;border-bottom:1px solid #b6934c80;line-height:15px}
`},
 {id:3,name:'层次与留白',notes:['压暗大面积斜金纹理，让奖励和标题更突出。','缩短标题区，增加原生细金饰条，统一标题与正文层级。'],css:String.raw`
.polish .window{background:#141614}.polish .window:before{opacity:.28}
.polish .header{height:104px;background:#10120f;border-bottom:1px solid #8b744640}
.polish .header:before{opacity:.23;background-position:center 41%}
.polish .header h1{font-size:36px;letter-spacing:4px;color:#f1ddae;font-weight:500;transform:translateY(-6px)}
.polish .header p{display:none}
.polish .header .ornament{display:none}.polish .native-divider{position:absolute;left:50%;bottom:6px;transform:translateX(-50%);width:300px;height:24px;object-fit:contain;opacity:.62;pointer-events:none}
.polish .header h1,.polish .header p{position:relative;z-index:1}
.polish .section-head h2{font-size:20px;letter-spacing:1px;color:#ddcfaa}
.polish .summary{font-size:12px;color:#a59c85;gap:14px}.polish .summary b{color:#ebce86}.polish .progress{height:2px;background:#afa17f20}
.polish .weekday{font-size:15px;color:#ab9e7e}.polish .footer{font-size:12px;color:#a0977e;letter-spacing:.5px}
.polish .artboard{background-image:linear-gradient(#06080ba6,#080a0dba),var(--scene)}
`},
 {id:4,name:'月卡与悬浮',notes:['月卡区与日历统一黑金材质、细线和层级。','月卡按钮采用官方内凹角描边，悬浮说明使用不透明底板、逐条效果。'],css:String.raw`
.polish .pass-panel{background:linear-gradient(180deg,#121612,#0c100d);border-left:1px solid #77623b88;border-right:1px solid #423b29;padding:0 14px}
.polish .pass-panel:before{opacity:.07}.polish .pass-heading h2{font-size:20px;letter-spacing:1.5px;color:#e1c887}.polish .pass-heading p{font-size:10px;letter-spacing:.8px;color:#a2977c}
.polish .milestone{background:linear-gradient(160deg,#171b14,#0f120e);border:1px solid #6c5d3a;box-shadow:inset 0 0 0 2px #0d100c;}
.polish .milestone:before{opacity:.62}.polish .milestone:after{content:'';position:absolute;inset:3px;border:1px solid #b69a4b1b;pointer-events:none}
.polish .milestone .when{font-size:11px;letter-spacing:1px;color:#aaa087;top:12px}.polish .milestone[data-monthly="7"] .when{color:#d5bb7f}
.polish .milestone .reward-name{font-size:16px;letter-spacing:1px;color:#d9caa6;margin-top:9px}.polish .milestone .lock{width:14px;height:14px;top:11px;right:10px;opacity:.36}
.polish .milestone .item-icon{filter:brightness(.78) saturate(.67) drop-shadow(0 2px 5px #0008)}
.polish .buy{width:224px;height:52.2667px;font-size:17px}
.polish .buy .face{background-image:none}
.polish .buy .face:before{content:'';position:absolute;inset:0;background:#21221a;mask:url('assets/gold_bounty_fill.png') center/100% 100% no-repeat;-webkit-mask:url('assets/gold_bounty_fill.png') center/100% 100% no-repeat}
.polish .buy .face:after{content:'';position:absolute;inset:0;background:#c2a96e;mask:url('assets/gold_bounty_border.png') center/100% 100% no-repeat;-webkit-mask:url('assets/gold_bounty_border.png') center/100% 100% no-repeat}
.polish .buy span{color:#ddc68f;letter-spacing:1px}
.polish .tooltip{background:#10150f;border:1px solid #8a754c;box-shadow:0 12px 36px #000c;padding:18px 20px;width:320px}
.polish .tooltip h3{color:#efd49a}.polish .tooltip .tip-line{line-height:1.85;color:#dfd6bf}.polish .tooltip .tip-note{color:#a89a79;border-color:#80704a66}
`},
 {id:5,name:'整体收口',notes:['统一日历与月卡基线、间距、关闭按钮及页脚。','保留完整原生图标与克制高亮，形成黑金最终建议稿。'],css:String.raw`
.polish .window{border:1px solid #8b7647;box-shadow:0 25px 90px #000d,0 0 0 4px #171813ba,inset 0 0 0 1px #b49a5220}
.polish .body{padding:18px 40px 0;gap:30px;grid-template-columns:minmax(0,1fr) 252px}
.polish .section-head{padding:0 6px;height:40px}.polish .weekdays{height:30px}.polish .calendar{gap:12px;padding:0 5px}
.polish .day-head{padding:0 6px;letter-spacing:.2px;height:23px;line-height:21px}
.polish .pass-heading{height:70px}.polish .milestones{gap:12px}
.polish .header .close{right:20px;top:18px;width:30px;height:30px;padding:8px;border:1px solid #9c87504d;background:#0e110cbd}
.polish .header .close img{opacity:.64}.polish .header .close:hover{background:#54401f4a;border-color:#b2975f88}
.polish .rules-button{right:8px;width:92px;color:#b4a783;letter-spacing:.4px}
.polish .footer{height:43px;border-top:1px solid #9d824422;margin:0 36px;font-size:11px;color:#a89b7a;gap:0}
.polish .calendar-actions,.polish .pass-actions{height:76px}.polish .pass-actions{padding-top:0}
.polish .claim{top:6px}.polish .action:focus-visible{outline:1px solid #f0d594;outline-offset:3px}
.polish .day:hover .slot{filter:brightness(1.1)}.polish .milestone:hover{filter:brightness(1.1);border-color:#d7b96e}
`}
];
let n=Number(process.argv[2]||5);assert(Number.isInteger(n)&&n>=1&&n<=5);
const original=fs.readFileSync(path.join(out,'baseline/04_星穹鎏金.html'),'utf8');
let html=original.replace('<body class="ti2026"','<body class="ti2026 polish" data-round="'+n+'"')
 .replace('href="preview.css"','href="R'+n+'.css"').replace('src="preview.js"','src="preview.js"')
 .replace('<title>04 星穹鎏金 · 每日登录奖励</title>','<title>第'+n+'轮 · 星穹鎏金优化</title>')
 .replace('方案 04','第 '+n+' 轮').replace('TI 星空 · 深金纹理 · 金角物品格',rounds[n-1].name+' · 星穹鎏金递进优化');
if(n>=3)html=html.replace('<i class="ornament"></i>','<i class="ornament"></i><img class="native-divider" src="assets/gold_crown_divider.png" alt="">').replace('每日相约 · 好礼常伴','28日签到 · 每日好礼');
if(n>=4)html=html.replace('累计签到，领取三份珍藏','7 / 14 / 21 次累计签到奖励');
const css=fs.readFileSync(path.join(out,'baseline/preview.css'),'utf8')+'\n'+rounds.slice(0,n).map(r=>'/* R'+r.id+' '+r.name+' */\n'+r.css).join('\n');
// Browser file origins reject external CSS masks; inline the exact native PNG bytes.
const transportedCss=css.replace(/url\('assets\/(gold_bounty_(?:fill|border))\.png'\)/g,(_,key)=>'url("data:image/png;base64,'+fs.readFileSync(path.join(out,'assets',key+'.png')).toString('base64')+'")');
fs.writeFileSync(path.join(out,'R'+n+'.css'),transportedCss);fs.writeFileSync(path.join(out,'R'+n+'_星穹鎏金.html'),html);
fs.writeFileSync(path.join(out,'preview.js'),fs.readFileSync(path.join(out,'baseline/preview.js')));
const info={id:n,name:rounds[n-1].name,html:'R'+n+'_星穹鎏金.html',css:'R'+n+'.css',png:'R'+n+'_星穹鎏金.png',notes:rounds[n-1].notes,cumulativeRounds:rounds.slice(0,n).map(r=>r.id),hashes:{html:hash(Buffer.from(html)),css:hash(Buffer.from(transportedCss))}};
fs.writeFileSync(path.join(out,'R'+n+'_changes.json'),JSON.stringify(info,null,2)+'\n');
const existing=fs.existsSync(path.join(out,'rounds.json'))?JSON.parse(fs.readFileSync(path.join(out,'rounds.json'),'utf8')):[];
const all=existing.filter(r=>r.id!==n).concat(info).sort((a,b)=>a.id-b.id);fs.writeFileSync(path.join(out,'rounds.json'),JSON.stringify(all,null,2)+'\n');
console.log(JSON.stringify({status:'ROUND_BUILT',round:n,name:info.name,cumulativeRounds:info.cumulativeRounds,productionFilesChanged:false}));
