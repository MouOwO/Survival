'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),work=path.join(root,'output/lottery_emerald_buttons_20261019'),out=path.join(root,'design_refs/lottery_emerald_buttons_20261019');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function scope(css,id){return css.replace(/(^|\})\s*([^{}]+)\{/g,(all,before,selectors)=>before+'\n'+selectors.split(',').map(selector=>'[data-scene-scheme="'+id+'"] '+selector.trim()).join(',')+'{');}
function build(){
 const input=path.join(root,'output/lottery_five_official_20261019/data.json');
 if(!fs.existsSync(input))throw Error('Build the five official lottery previews first');
 const original=JSON.parse(fs.readFileSync(input,'utf8')),forest=original.schemes.find(s=>s.id==='s5');if(!forest)throw Error('Approved forest theme missing');
 const rounds=require('./rounds.cjs');fs.mkdirSync(work,{recursive:true});fs.mkdirSync(out,{recursive:true});
 const data={...original,meta:{...original.meta,title:'幽林翡翠 · 按钮五轮优化',notes:original.meta.notes.concat(['固定用户选定的幽林翡翠主题，逐轮累积优化按钮；默认显示最后一轮。'])},schemes:rounds.map(round=>({...forest,id:round.id,name:round.name,kicker:round.kicker,description:round.description}))};
 let html=require('../lottery_five_official_20261019/template.cjs').render(data);
 html=html.replaceAll('五套同屏对比','五轮同屏对比').replaceAll('抽奖界面 · 五套官方素材方案','幽林翡翠 · 按钮五轮优化').replaceAll('五套完整界面对比','五轮按钮优化对比').replace('按激战 2 的奖池布局组合官方素材。所有抽奖与余额均为本地样例。','幽林翡翠主题 · 五轮累积改进 · 可对比尺寸与交互状态').replace('选定方案编号和需要调整的位置后，可直接按这套素材接入游戏。','默认显示最后一轮，可逐轮查看改进。抽奖与余额仅为本地演示。');
 html=html.replace(':schemes[0].id,pool:',':schemes[schemes.length-1].id,pool:');
 let css='';for(let i=0;i<rounds.length;i++)css+=scope(rounds.slice(0,i+1).map(r=>r.css).join('\n'),rounds[i].id)+'\n';
 css+='\n.lottery-scene .main-readability{background:linear-gradient(90deg,#101119c9,#12131b10 65%),linear-gradient(0deg,#0c1218fa,#0c1218a8 18%,transparent 60%)}\n';
 html=html.replace('</style>',css+'\n</style>');
 const stateControl='<label class="review-button-state" style="font-size:12px;color:#b2c5bc;display:flex;gap:8px;align-items:center">按钮状态 <select id="buttonState" style="font:inherit;background:#16241d;color:#e3eee5;padding:7px;border:1px solid #456352"><option value="normal">正常</option><option value="hover">悬停</option><option value="pressed">按下</option><option value="focus">键盘焦点</option><option value="disabled">票券不足</option><option value="busy">开启中</option></select></label>';
 html=html.replace('<button type="button" id="compareToggle">',stateControl+'<button type="button" id="compareToggle">');
 const extra=`<script>
(function(){
 var select=document.getElementById('buttonState');
 window.updateButtonPreview=function(){var state=document.body.dataset.buttonPreview||'normal';document.querySelectorAll('.draw-action').forEach(function(button){['hover','pressed','focus','disabled','busy'].forEach(function(value){button.classList.toggle('preview-'+value,state===value);});var unavailable=state==='disabled'||state==='busy';if(unavailable){button.disabled=true;button.setAttribute('aria-busy',String(state==='busy'));var text=button.querySelector('.draw-label');if(text)text.textContent=state==='busy'?'开启中…':'票券不足';}else{button.removeAttribute('aria-busy');}});};
 select.addEventListener('change',function(){document.body.dataset.buttonPreview=select.value;lotteryDemoAPI.setPool(lotteryDemoAPI.getState().pool);window.updateButtonPreview();});
 window.emeraldReviewAPI={setButtonState:function(value){select.value=value;select.dispatchEvent(new Event('change'));},getButtonState:function(){return select.value;}};
 window.updateButtonPreview();
 var opener=null,activeModal=null;
 document.addEventListener('click',function(event){var button=event.target.closest('[data-modal]');if(button)opener=button.getAttribute('data-modal');},true);
 function syncModalFocus(){var modal=document.querySelector('#mainCanvas .game-modal');if(modal&&modal!==activeModal){activeModal=modal;var first=modal.querySelector('button:not(:disabled),input:not(:disabled),[tabindex="0"]');if(first)first.focus({preventScroll:true});}else if(!modal&&activeModal){activeModal=null;var button=opener&&document.querySelector('#mainCanvas [data-modal="'+opener+'"]');if(button)button.focus({preventScroll:true});}}
 new MutationObserver(syncModalFocus).observe(document.getElementById('mainCanvas'),{childList:true,subtree:true});
 document.addEventListener('keydown',function(event){if(event.key!=='Tab'||!activeModal)return;var controls=[].slice.call(activeModal.querySelectorAll('button:not(:disabled),input:not(:disabled),[tabindex="0"]')).filter(function(element){return element.getClientRects().length>0;});if(!controls.length){event.preventDefault();return;}var first=controls[0],last=controls[controls.length-1];if(event.shiftKey&&(document.activeElement===first||!activeModal.contains(document.activeElement))){event.preventDefault();last.focus();}else if(!event.shiftKey&&(document.activeElement===last||!activeModal.contains(document.activeElement))){event.preventDefault();first.focus();}},true);
})();
</script>`;
 html=html.replace('function renderScene(){ $(\'mainCanvas\').innerHTML=sceneMarkup(currentScheme(),currentPool(),true);resize() }','function renderScene(){ $(\'mainCanvas\').innerHTML=sceneMarkup(currentScheme(),currentPool(),true);resize();if(window.updateButtonPreview)window.updateButtonPreview(); }');
 html=html.replace('</body>',extra+'\n</body>');
 const file=path.join(out,'幽林翡翠_按钮五轮优化.html');fs.writeFileSync(file,html);
 const manifest={title:data.meta.title,rounds:rounds.map(({css,...r})=>r),roundCount:rounds.length,sourceDataSha256:hash(fs.readFileSync(input)),htmlSha256:hash(Buffer.from(html)),htmlBytes:Buffer.byteLength(html),approvedTheme:{id:forest.id,background:forest.assets.background.sourcePath,primary:forest.assets.button.sourcePath,secondary:forest.assets.buttonSecondary.sourcePath},productionFilesChangedByPreview:false};
 fs.writeFileSync(path.join(out,'rounds.json'),JSON.stringify(manifest,null,2));fs.writeFileSync(path.join(work,'data.json'),JSON.stringify(data));
 fs.copyFileSync(file,path.join(out,'round_'+rounds.length+'.html'));
 console.log(JSON.stringify({success:true,rounds:rounds.length,html:path.relative(root,file),htmlSha256:manifest.htmlSha256}));
}
module.exports={build,scope};if(require.main===module)build();
