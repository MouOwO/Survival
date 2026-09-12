const U=config.SurvivalUI,states=['普通','悬停','按下','选中','禁用','请求中'],matrix=document.getElementById('matrix');
function state(p,i){if(i===1)p.AddClass('PreviewHover');if(i===2)p.AddClass('PreviewPressed');U.State.Set(p,{selected:i===3,enabled:i!==4,busy:i===5});if(i===3)p.checked=true;return p}
function row(name,factory){const row=document.createElement('div');row.className='row';const label=document.createElement('label');label.textContent=name;row.append(label);states.forEach((s,i)=>{const d=document.createElement('div');d.className='demo';row.append(d);const h=new Panel('Panel',null,'',d);state(factory(h,i),i)});matrix.append(row)}
const headings=document.createElement('div');headings.className='row columns';headings.innerHTML='<label>组件</label>'+states.map(s=>'<div>'+s+'</div>').join('');matrix.append(headings);
row('顶部图标',h=>U.IconButton(h,{iconId:'icon.nav.archive',label:'存档'}));
row('关闭入口',h=>{const p=new Panel('Button',h,'');U.CloseButton(p,()=>{});p.el.style.position='relative';p.el.style.right='auto';p.el.style.top='auto';return p});
row('玉白按钮',h=>U.ActionButton(h,{label:'确认'}));row('香槟金按钮',h=>U.ActionButton(h,{label:'开启 10 个',variant:'gold'}));
row('侧栏导航',h=>U.NavToggle(h,{label:'通关存档',iconId:'icon.nav.archive'}));
row('顶部页签',h=>U.TabBar(h,{items:[{id:'map',label:'地图宝箱'}]}).panel.children[0]);
row('复选框',h=>U.Checkbox(h,{label:'跳过动画'}));
const cards=host('cards');[{}, {current:3,required:5,selected:true},{current:7}].forEach((p,i)=>{const c=U.CardShell(cards,{bodyVariant:i===1?'outline':'square',title:i===2?'无上限 · 隐藏进度':'状态样例 '+(i+1),selected:p.selected});U.Icon(c,'icon.pool_details',70);U.ProgressBadge(c,p)});
const product=U.VipBundleCard(host('product'),{name:'内容变体测试',prices:[{amount:3,currencyName:'币种 A'},{amount:9,currencyName:'币种 B'}],eligible:false,requiredVipLevel:2,items:[{name:'测试项',quantity:1}]});product.AddClass('sampleCard');
const buttons=host('modalButtons');window.showModal=function(width,height){const scrim=new Panel('Panel',root,''),p=new Panel('Panel',scrim,''),header=new Panel('Panel',p,''),title=new Panel('Label',header,''),close=new Panel('Button',header,'');title.text='共用弹窗 · 尺寸验证';const body=new Panel('Panel',p,'');body.AddClass('sampleBody');body.el.innerHTML='同一个 ModalShell，传入不同设计尺寸。<small>窗口外点击关闭；窗口内点击保持；右上角只关闭当前窗口。</small><small>此处没有绘制游戏场景背景。当前为浏览器预览。</small>';let shell;shell=U.ModalShell.Adopt({id:'preview',panel:p,scrim,root,header,titlePanel:title,closeButton:close,width,height,fit:{reference:[1672,941]},onClose(){shell.Close()}});shell.Open();window.currentModal=shell;return shell};
U.ActionButton(buttons,{label:'小弹窗 720 × 480',action:()=>showModal(720,480)});U.ActionButton(buttons,{label:'宽弹窗 1208 × 806',action:()=>showModal(1208,806)});
window.previewReady=true;
