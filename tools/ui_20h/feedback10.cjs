'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const root='design_refs/ui_20h/work/feedback10',stateFile=root+'/state.json';
const files=['panorama/src/scripts/custom_game/archive_jade.js','panorama/src/styles/custom_game/common/jade_ui.css','panorama/src/scripts/custom_game/production_progress.js','panorama/src/styles/custom_game/production_progress.css'];
const scope='.ArchiveRoot #ArchiveWindow.ArchiveJade';
const recipes=[
 {id:'R01',area:'archive',feature:'aspect',name:'标题画面保持比例',variables:['标题图片等比填充','关闭按钮移到题头上角'],css:''},
 {id:'R02',area:'archive',feature:'nav',name:'移除旧导航金框',variables:['被动导航底层替代旧框','分隔线和文本重量'],css:`${scope} #ArchiveTabs .ArchiveTab{background-image:none;}${scope} #ArchiveTabs .ArchiveTab Label{font-weight:normal;font-size:21px;z-index:3;} .JadeNavSurface{width:209px;height:54px;background-size:100% 100%;opacity:0;z-index:0;}.ArchiveTab:selected .JadeNavSurface{opacity:1;background-image:url("file://{images}/custom_game/commerce_jade_v1/nav_selected.png");}.ArchiveTab:hover .JadeNavSurface{opacity:1;background-image:url("file://{images}/custom_game/commerce_jade_v1/nav_hover.png");}.ArchiveTab:selected:hover .JadeNavSurface{background-image:url("file://{images}/custom_game/commerce_jade_v1/nav_selected.png");} ${scope} .ArchiveNavIcon{z-index:3;} ${scope} .ArchiveNavLine{z-index:2;} ${scope} .ArchiveNavGlow{z-index:1;}`},
 {id:'R03',area:'archive',feature:'surface',name:'商品卡纸玉材质',variables:['共享商品卡九宫格','悬停边缘代替全片变亮'],css:`${scope} #ArchiveGrid .ArchiveCard{background-image:none;background-color:transparent;border:0px;} ${scope} #ArchiveGrid .ArchiveCard:hover{border:1px solid #bea373;background-color:#faf9f350;} .JadeCardSurface{width:100%;height:100%;z-index:0;} ${scope} .ArchiveNameHost,${scope} .ArchiveUnlockBadge{z-index:3;}`},
 {id:'R04',area:'archive',feature:'badges',name:'状态与计数分层',variables:['去掉状态装饰金框','进度改为无底数字','状态胶囊位置'],css:`${scope} #ArchiveGrid .ArchiveCount{position:76px 7px 0px;width:58px;height:20px;background-image:none;background-color:transparent;font-size:14px;} ${scope} #ArchiveGrid .ArchiveUnlockBadge{position:26px 115px 0px;width:91px;height:18px;background-image:none;background-color:#dce2da;color:#657470;border-radius:9px;font-size:12px;} ${scope} #ArchiveGrid .ArchiveUnlockBadge.Unlocked{background-image:none;background-color:#cce1d2;color:#295e4e;}`},
 {id:'R05',area:'archive',feature:'icons',name:'奖励图标落地层次',variables:['移除方形色框','底部柔和投影','浅玉图标托底'],css:'.JadeObjectShadow{position:35px 84px 0px;width:73px;height:7px;background-color:#25494e1e;border-radius:50%;z-index:1;} .JadeObjectWell{position:20px 13px 0px;width:103px;height:84px;background-image:url("file://{images}/custom_game/commerce_jade_v1/art_well.png");background-size:100% 100%;opacity:0.3;z-index:1;}'},
 {id:'R06',area:'archive',feature:'seam',name:'窗口纸底与背景衔接',variables:['象牙纸底细层次','标题与正文过渡','底部细金线'],css:'.JadeHeaderSeam{position:0px 110px 0px;width:869px;height:26px;background-image:url("file://{images}/custom_game/commerce_jade_v1/content_transition.png");background-size:100% 100%;z-index:1;opacity:0.45;} .JadeFooterLine{position:110px 574px 0px;width:434px;height:1px;background-color:#b9a67555;z-index:0;}'},
 {id:'R07',area:'archive',feature:'tip',name:'提示层文本层次',variables:['名称字号及玉色分隔','正文行距'],css:'#ArchiveTooltip.JadeTooltip #ArchiveTooltipName{font-size:23px;color:#faf4e3;} #ArchiveTooltip.JadeTooltip #ArchiveTooltipEffect{font-size:17px;line-height:26px;} #ArchiveTooltip.JadeTooltip #ArchiveTooltipDivider{opacity:0.35;}'},
 {id:'R08',area:'queue',feature:'queueClean',name:'名额独立一行与双成本留白',variables:['名额移出头像','成本分行间距','双成本面板高度'],css:'#SurvivalProductionPanel.CompactTraining .ProductionTrainingCount{background-color:transparent;font-size:22px;color:#c4d7cf;text-align:center;} #SurvivalProductionPanel.CompactTraining .ProductionTrainingLevel{background-color:#173a43cc;} #SurvivalProductionPanel.CompactTraining .ProductionTrainingCost{color:#f1efe1;}'},
 {id:'R09',area:'queue',feature:'queueHorizontal',name:'横排双币成本候选',variables:['双成本改为横排','减少双成本高度'],css:''},
 {id:'R10',area:'hud',feature:'hud',name:'顶栏透明边缘与资源组',variables:['资源局部渐变代替方块底','导航悬停改为淡色反馈'],css:'#HandoffResource_goldRow,#HandoffResource_woodRow,#HandoffResource_populationRow{background-color:gradient(linear,0% 0%,0% 100%,from(#173d4610),to(#173d4660));border-radius:12px;} .HandoffNav:hover{background-color:gradient(linear,0% 0%,0% 100%,from(#8bbcb200),to(#8bbcb22a));brightness:1.08;}'},
];
function save(file,data){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,data);}
function snapshot(dir){const closure=JSON.parse(fs.readFileSync('design_refs/ui_20h/work/dependencies.json','utf8').replace(/^\uFEFF/,''));const current=[...new Set([...files,...closure.map(p=>'panorama/src/'+p)])];const manifest=current.map(p=>{const b=fs.readFileSync(p);save(dir+'/'+p,b);return {path:p,sha256:crypto.createHash('sha256').update(b).digest('hex')};});save(dir+'/manifest.json',JSON.stringify(manifest,null,2));}
function apply(ids){const features=Object.fromEntries(recipes.map(r=>[r.feature,ids.includes(r.id)]));
 save(root+'/recipes.json',JSON.stringify(recipes,null,2));
 let js=fs.readFileSync(root+'/baseline/'+files[0],'utf8');
 js=js.replace('var nav = view.NavIcon, card = view.Card, init = view.Init;', 'var refinement='+JSON.stringify(features)+';\n    var nav = view.NavIcon, card = view.Card, init = view.Init;');
 js=js.replace('nav.call(view, toggle, id, key);',`nav.call(view, toggle, id, key);
        if(refinement.nav){
            toggle.Children().forEach(function(child){if(child.BHasClass('ArchiveNavSelectedFrame')||child.BHasClass('ArchiveNavSeparator'))child.visible=false;});
            style(toggle,{backgroundImage:'none'});passive(toggle,'JadeNavSurface');
        }`);
 js=js.replace('card.call(view, node);',`card.call(view, node);
        if(refinement.surface){
            node.Children().forEach(function(child){if(child.BHasClass('ArchiveNormalFrame')||child.BHasClass('ArchiveSelectedFrame'))child.visible=false;});
            if(cfg.SurvivalNineSlice)cfg.SurvivalNineSlice.Create(node,'file://{images}/custom_game/commerce_jade_v1/product_normal.png',143,138,[12,12,12,12],'JadeCardSurface');
        }
        if(refinement.badges&&!node.BHasClass('ArchiveTitleCard')&&typeof node.__archiveUnlocked==='boolean'){
            node.Children().forEach(function(child){if(child.BHasClass('ArchiveStateIcon'))child.visible=false;});
            var badge=$.CreatePanel('Label',node,'');badge.AddClass('ArchiveUnlockBadge');badge.SetHasClass('Unlocked',node.__archiveUnlocked);badge.text=node.__archiveUnlocked?'已解锁':'未解锁';badge.hittest=false;
        }
        if(refinement.icons){
            passive(node,'JadeObjectWell');passive(node,'JadeObjectShadow');
            node.Children().forEach(function(child){if(child.BHasClass('ArchiveArt'))style(child,{border:'0px',backgroundColor:'transparent',zIndex:'2'});});
        }`);
 js=js.replace('init.call(view);',`init.call(view);
        var archiveRoot=$.GetContextPanel(),node=function(id){return archiveRoot.FindChildTraverse(id);};
        var window=node('ArchiveWindow');window.AddClass('ArchiveJade');window.RemoveClass('UIModal');window.RemoveClass('ReferenceWindow');
        window.Children().forEach(function(child){if(child.BHasClass('ReferenceFrame')||child.BHasClass('ReferenceAtmosphere'))child.visible=false;});
        style(node('ArchiveHeaderArt'),{backgroundImage:'url("file://{images}/custom_game/commerce_jade_v1/header.png")',backgroundSize:'100% 100%',backgroundPosition:'0px 0px',visibility:'visible'});
        style(window,{backgroundImage:'none',backgroundColor:'#f2f1e8',border:'1px solid #a4b7ac88',boxShadow:'none',width:'869px',height:'713px',padding:'0px'});
        style(node('ArchiveHeader'),{backgroundImage:'none',backgroundColor:'transparent'});
        style(node('ArchiveTitleBlock'),{backgroundImage:'none',backgroundColor:'transparent',border:'0px'});
        style(node('ArchiveHeaderArt'),{brightness:'1',saturation:'1'});
        style(node('ArchiveTitle'),{color:'#234957'});style(node('ArchiveSubtitle'),{color:'#466962'});
        style(node('ArchiveContent'),{backgroundColor:'#f2f1e8'});
        var backing=node('ArchiveSidebarBacking');if(backing){backing.SetImage('file://{images}/custom_game/commerce_jade_v1/sidebar.png');style(backing,{visibility:'visible',position:'0px 0px 0px',width:'214px',height:'589px',zIndex:'0'});}
        style(node('ArchiveTabs'),{zIndex:'2'});style(node('ArchiveContent'),{zIndex:'2'});
        style(node('ArchivePageHeader'),{visibility:'visible',height:'70px'});style(node('ArchivePageTitle'),{visibility:'visible'});
        style(node('ArchiveBook'),{visibility:'collapse'});
        var contentBacking=node('ArchiveContentBacking');if(contentBacking)contentBacking.visible=false;
        var close=node('ArchiveClose');if(close){close.RemoveAndDeleteChildren();var closeArt=$.CreatePanel('Image',close,'');closeArt.AddClass('ArchiveCloseImage');closeArt.SetImage('file://{images}/custom_game/commerce_jade_v1/close_normal.png');closeArt.hittest=false;}
        if(refinement.aspect){
            var header=node('ArchiveHeaderArt');style(header,{backgroundImage:'none'});
            var left=passive(header,'JadeHeaderLeft'),right=passive(header,'JadeHeaderRight');
            [left,right].forEach(function(part){style(part,{width:'434.5px',height:'124px',backgroundImage:'url("file://{images}/custom_game/commerce_jade_v1/header.png")',backgroundSize:'1771px 124px',backgroundRepeat:'no-repeat'});});
            style(left,{position:'0px 0px 0px',backgroundPosition:'left top'});style(right,{position:'434.5px 0px 0px',backgroundPosition:'right top'});
            style(node('ArchiveClose'),{position:'808px 23px 0px'});
        }
        if(refinement.seam){
            style(node('ArchiveContent'),{backgroundImage:'url("file://{images}/custom_game/commerce_jade_v1/window.png")',backgroundSize:'100% 100%'});
            passive(node('ArchiveWindow'),'JadeHeaderSeam');passive(node('ArchiveContent'),'JadeFooterLine');
        }`);
 js=js.replace('view.Init = function () {',`var originalPalette=view.ApplyPalette;
    if(originalPalette)view.ApplyPalette=function(){
        // Jade uses the engine's text layout; the legacy callback repeatedly
        // changes runtime font families and schedules a second font scaler.
        if(view.HideCardText)view.HideCardText();
        cfg.ArchiveTheme.Apply($.GetContextPanel().FindChildTraverse('ArchiveWindow'));
        var walk=function(node){
            var parent=node.GetParent&&node.GetParent();
            if(node.BHasClass('ArchiveItemName'))style(node,{color:'#234957',fontSize:'18px',lineHeight:'23px',position:'0px 0px 0px',width:'100%',height:'23px',textAlign:'center',horizontalAlign:'left',verticalAlign:'top',textOverflow:'ellipsis',transform:'none'});
            if(node.BHasClass('ArchiveTitleArt'))style(node,{position:'13px 23px 0px',width:'117px',height:'61px',margin:'0px',horizontalAlign:'left',transform:'none',zIndex:'2'});
            if(node.BHasClass('ArchiveTitleCard'))style(node,{flowChildren:'none',padding:'0px'});
            if(node.BHasClass('ArchiveTitleName'))style(node,{position:'7px 92px 0px',width:'129px',height:'23px',margin:'0px',color:'#234957',fontSize:'16px',zIndex:'3'});
            if(node.BHasClass('ArchiveTitleAction'))style(node,{position:'7px 115px 0px',width:'129px',height:'18px',margin:'0px',padding:'0px',horizontalAlign:'left',transform:'none',fontSize:'12px',zIndex:'3'});
            if(node.BHasClass('ArchiveNameHost'))style(node,{position:'7px 92px 0px',width:'129px',height:'23px',zIndex:'3'});
            if(node.BHasClass('ArchiveCostHost'))style(node,{position:'7px 135px 0px',width:'129px',height:'23px',zIndex:'3'});
            if(node.BHasClass('ArchiveWorkCost'))style(node,{position:'0px 0px 0px',width:'100%',height:'23px',fontSize:'13px',lineHeight:'23px',color:'#31574f',horizontalAlign:'left',verticalAlign:'top',textAlign:'center',transform:'none'});
            if(node.BHasClass('ArchiveLevelHost'))style(node,{position:'8px 137px 0px',width:'36px',height:'22px',zIndex:'3'});
            if(node.BHasClass('ArchiveFragmentLevel'))style(node,{position:'0px 0px 0px',width:'100%',height:'22px',fontSize:'12px',color:'#31574f',horizontalAlign:'left',verticalAlign:'top',transform:'none'});
            if(node.BHasClass('ArchiveCountHost'))style(node,{position:refinement.badges?'76px 1px 0px':'83px 7px 0px',width:refinement.badges?'58px':'53px',height:refinement.badges?'17px':'20px',zIndex:'4'});
            if(refinement.badges&&node.BHasClass('ArchiveUnlockBadge'))style(node,{color:node.BHasClass('Unlocked')?'#295e4e':'#657470',fontSize:'12px'});
            if(node.BHasClass('ArchiveCount'))style(node,{color:'#31574f',fontSize:'13px',lineHeight:refinement.badges?'17px':'20px',backgroundColor:'transparent',backgroundImage:'none',position:parent&&parent.BHasClass('ArchiveCountHost')?'0px 0px 0px':'83px 7px 0px',width:'53px',height:refinement.badges?'17px':'20px',padding:'0px',margin:'0px',horizontalAlign:'left',verticalAlign:'top',transform:'none'});
            if(node.id==='ArchiveContext')style(node,{position:'0px 58px 0px',width:'540px',height:'18px',fontSize:'12px',textOverflow:'ellipsis',horizontalAlign:'left',textAlign:'left',transform:'none'});
            if(parent&&parent.BHasClass('ArchiveTab')&&typeof node.text==='string')style(node,{color:parent.checked?'#234957':'#e8ede0',fontWeight:'normal'});
            if(node.id==='ArchiveWindow')style(node,{backgroundColor:'#f2f1e8',backgroundImage:'none'});
            if(node.id==='ArchiveBody')style(node,{backgroundColor:'transparent'});
            if(node.id==='ArchiveContent')style(node,{backgroundColor:'#f2f1e8'});
            if(node.id==='ArchiveTitle'||node.id==='ArchivePageTitle')style(node,{color:'#234957'});
            if(node.id==='ArchiveTitle')style(node,{fontSize:'38px',textAlign:'center'});
            if(node.id==='ArchivePageTitle')style(node,{fontSize:'30px'});
            if(node.id==='ArchiveSubtitle')style(node,{fontSize:'14px'});
            if(node.id==='ArchiveSummary')style(node,{fontSize:'15px'});
            if(node.BHasClass('ArchiveArt'))style(node,{position:'25px 18px 0px',width:'93px',height:'74px',zIndex:'2'});
            if(node.BHasClass('ArchiveRewardIcon')&&parent&&parent.BHasClass('ArchiveArt')&&!parent.BHasClass('ArchivePortraitViewport'))style(node,{position:'0px 0px 0px',width:'100%',height:'100%'});
            if(node.id==='ArchiveSummary'||node.id==='ArchiveHint'||node.id==='ArchiveStatus'||node.id==='ArchiveSubtitle')style(node,{color:'#59756f'});
            if(node.BHasClass('ArchiveCard'))style(node,{backgroundColor:refinement.surface?'transparent':'#fafaf155',border:refinement.surface?'0px':'1px solid #97aea35a'});
            if(refinement.icons&&node.BHasClass('ArchiveArt'))style(node,{border:'0px',backgroundColor:'transparent',brightness:'1',saturation:'1'});
            if(parent&&parent.id&&parent.id.indexOf('ArchiveFilter_')===0&&typeof node.text==='string')style(node,{color:parent.checked?'#f4f1df':'#234957',fontSize:'14px'});
            if(node.Children)node.Children().forEach(walk);
        };
        walk($.GetContextPanel().FindChildTraverse('ArchiveWindow'));
    };
    var showTooltip=view.Show;
    view.Show=function(){
        showTooltip.apply(view,arguments);
        var context=$.GetContextPanel(),tip=context.FindChildTraverse('ArchiveTooltip');
        jade.Tooltip(tip);
        if(refinement.tip){
            style(context.FindChildTraverse('ArchiveTooltipName'),{fontSize:'23px',color:'#faf4e3'});
            style(context.FindChildTraverse('ArchiveTooltipEffect'),{fontSize:'17px',lineHeight:'26px'});
        }
    };
    view.Init = function () {`);
 save(files[0],js);
 const geometry=fs.readFileSync('panorama/src/styles/custom_game/archive_handoff_180de7e38b.css','utf8').split(/\r?\n/).filter(line=>line.includes('{')&&!line.includes('ArchiveTooltip')&&!line.includes('ArchiveAssetCompile')).map(line=>{const split=line.indexOf('{');let selectors=line.slice(0,split).split(',').map(s=>{s=s.trim();if(s.startsWith('.ArchiveRoot #ArchiveWindow'))return s.replace('.ArchiveRoot #ArchiveWindow',scope);if(s.startsWith('.ArchiveRoot '))return s.replace('.ArchiveRoot ',scope+' ');return scope+' '+s;}).join(',');return selectors+line.slice(split);}).join('\n');
 const inherited=fs.readFileSync(root+'/baseline/'+files[1],'utf8').split(/\r?\n/).map(line=>line.startsWith('.ArchiveJade ')?line.replaceAll('.ArchiveJade ',scope+' '):line).join('\n');
 let css=geometry+'\n'+inherited+'\n/* Compatibility: counter labels remain children of their cards. */\n'+scope+' #ArchiveGrid .ArchiveCountHost{position:83px 7px 0px;width:53px;height:20px;} '+scope+' #ArchiveGrid .ArchiveCountHost .ArchiveCount{position:0px 0px 0px;width:100%;height:100%;align:left top;} '+scope+' #ArchiveReferenceEmblem,'+scope+' #ArchiveNavScrollHint{visibility:collapse;}\n/* Additional reference review, purposeful candidates R01–R10. */\n'+recipes.filter(r=>ids.includes(r.id)).map(r=>'/* '+r.id+' '+r.name+' */\n'+r.css).join('\n');save(files[1],css);
 let production=fs.readFileSync(root+'/baseline/'+files[2],'utf8');
 if(features.queueClean){
  production=production.replace('layoutB && !dualCost ? 240 : 252','dualCost ? 278 : 256').replace('dualCost ? 134 : layoutB ? 116 : 126','dualCost ? 160 : 138');
  production=production.replace('place(button.count, cellWidth - 64, 54, 60, 25);','place(button.count, 4, 78, cellWidth - 8, 25);');
  production=production.replace('layoutB ? 80 : 88','107').replace('layoutB ? 80 : 87','104');
  production=production.replace('place(button.woodIcon, 4, 83, 18, 18); place(button.cost, 23, 79, 65, 28);','place(button.woodIcon, 8, 107, 18, 18); place(button.cost, 30, 103, cellWidth - 34, 28);');
  production=production.replace('place(button.goldIcon, 4, 108, 18, 18); place(button.gold, 23, 102, cellWidth - 27, 28);','place(button.goldIcon, 8, 133, 18, 18); place(button.gold, 30, 129, cellWidth - 34, 28);');
  production=production.replace('layoutB && !dualCost ? 179 : 191','dualCost ? 217 : 195');
 }
 if(features.queueHorizontal){
  production=production.replace('dualCost ? 278 : 256','256').replace('dualCost ? 160 : 138','138');
  production=production.replace('place(button.woodIcon, 8, 107, 18, 18); place(button.cost, 30, 103, cellWidth - 34, 28);','place(button.woodIcon, 4, 107, 18, 18); place(button.cost, 24, 103, (cellWidth - 48) / 2, 28);');
  production=production.replace('place(button.goldIcon, 8, 133, 18, 18); place(button.gold, 30, 129, cellWidth - 34, 28);','place(button.goldIcon, cellWidth / 2 + 2, 107, 18, 18); place(button.gold, cellWidth / 2 + 22, 103, cellWidth / 2 - 26, 28);');
  production=production.replace('dualCost ? 217 : 195','195');
 }
 save(files[2],production);save(files[3],fs.readFileSync(root+'/baseline/'+files[3]));
 cp.execFileSync(process.execPath,['tools/ui_20h/preview.cjs'],{stdio:'pipe'});
 return features;
}
(async()=>{const [action,id,...reason]=process.argv.slice(2);
 if(action==='init'){
  if(fs.existsSync(stateFile))throw Error('Feedback baseline exists; refusing to overwrite');
  snapshot(root+'/baseline');save(root+'/baseline/BEST_VERSION.json',fs.readFileSync('design_refs/ui_20h/BEST_VERSION.json'));
  save(stateFile,JSON.stringify({started:new Date().toISOString(),baseline:'prior v029 (rejected by user)',kept:[],trials:[]},null,2));
  save(root+'/recipes.json',JSON.stringify(recipes,null,2));return;
 }
 const state=JSON.parse(fs.readFileSync(stateFile,'utf8')),recipe=recipes.find(r=>r.id===id);
 if(action==='apply'){if(!recipe)throw Error('Unknown candidate');const candidate=[...state.kept.filter(x=>x!==id),id];apply(candidate);state.current=id;state.currentIds=candidate;snapshot(root+'/'+id+'/source');state.trials.push({...recipe,parent:[...state.kept],at:new Date().toISOString()});save(stateFile,JSON.stringify(state,null,2));console.log('ACTUAL_SOURCE_APPLIED '+id);return;}
 if(action==='keep'||action==='reject'){
  const trial=state.trials.findLast(r=>r.id===id);if(!trial)throw Error('Trial missing');trial.decision=action;trial.reason=reason.join(' ');if(action==='keep')state.kept=state.currentIds;
  apply(state.kept);save(stateFile,JSON.stringify(state,null,2));console.log('DECISION '+id+' '+action);return;
 }
 if(action==='capture'){
  const b=await browser();try{const area=recipe?.area||'archive';for(const stage of area==='queue'?['waiting','costs']:['normal']){
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:1910,y:1070});await b.go('design_refs/ui_20h/work/preview/index.html','?page='+(area==='queue'?'':area)+'&state='+stage);
   const box=area==='hud'?{x:0,y:0,width:1920,height:120}:await b.run(`(()=>{const r=nodes.${area==='queue'?'SurvivalProductionPanel':'ArchiveWindow'}.el.getBoundingClientRect();return {x:Math.max(0,r.x-8),y:Math.max(0,r.y-8),width:r.width+16,height:r.height+16};})()`);
   if(box.width<100||box.height<100)throw Error('Incomplete component render: '+id);
   if(area==='archive'&&await b.run('document.querySelectorAll(".ArchiveCard").length')!==24)throw Error('Archive fixture did not render all 24 rows');
   const dest=root+'/'+id+'/'+stage;await b.shot(dest+'.png');if(area!=='hud')await b.shot(dest+'_crop.png',box);else await b.shot(dest+'_crop.png',{x:0,y:0,width:1920,height:120});
   const target=area==='queue'?'.ProductionTrainingSlot':area==='hud'?'.HandoffNav':'.ArchiveCard';const pos=await b.run(`(()=>{const r=document.querySelector('${target}').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...pos});await b.shot(dest+'_hover.png');
   save(dest+'.json',JSON.stringify({candidate:id,area,stage,clip:box,kind:'actual production components; browser adapter; native battle backdrop',resolution:[1920,1080],previewIncludesLegacyFrames:true},null,2));
  }console.log('CANDIDATE_CAPTURED '+id);}finally{b.close();}return;
 }
 throw Error('Unknown action');
})().catch(e=>{console.error(e);process.exitCode=1});
