(function(){
'use strict';
const D=window.COLLECTION_FIVE,$=id=>document.getElementById(id),root=$('collection');
const qualities={N:'#8bc580',R:'#76bdea',SR:'#b080dc',SSR:'#dfb456',UR:'#e3645b'};
const names={ex:'我的前女友',friend:'我的前男友',wife:'我的老婆',beast:'瑞兽赐福'},short={ex:'前女友',friend:'前男友',wife:'老婆',beast:'瑞兽'};
const icons={ex:'star',friend:'friends',wife:'rewards',beast:'trophy'};
let theme='classic',category='ex',filter=0,lastHover=null,sampleDraws=0;
const el=(type,cls,parent)=>{const n=document.createElement(type);if(cls)n.className=cls;if(parent)parent.append(n);return n;};
const image=(parent,key,cls)=>{const n=el('img',cls,parent);n.src=D.assets[key];n.alt='';n.draggable=false;return n;};
for(const [key,url]of Object.entries(D.assets))document.documentElement.style.setProperty('--'+key,`url("${url}")`);
for(const [key,url]of Object.entries(D.masks))document.documentElement.style.setProperty('--'+key+'Mask',`url("${url}")`);
document.documentElement.style.setProperty('--tooltip-bg',`url("${D.assets.tooltip}")`);
document.documentElement.style.setProperty('--rail-bg',`url("${D.assets.rail}")`);
document.querySelector('.collection-mark').src=D.assets.treasure;$('close').firstElementChild.src=D.assets.close;
$('ticketIcon').src=D.assets.ticket;document.querySelector('.draw-cost img').src=D.assets.ticket;
function hideTip(){$('tooltip').style.display='none';lastHover=null;}
function fit(){const margin=window.innerWidth<900?28:80,available=Math.min(window.innerWidth-margin,1360),height=parseInt(getComputedStyle(root).getPropertyValue('--panel-height'))||656;const scale=Math.min(1.12,available/1120,($('stage').clientHeight-35)/height);root.style.transform=`scale(${scale})`;}
function setTheme(id){
 const row=D.themes.find(t=>t.id===id)||D.themes[0];theme=row.id;root.className='theme-'+theme;
 $('themeNumber').textContent=row.number;$('themeName').textContent=row.name;$('themeSubtitle').textContent=row.subtitle;
 for(const b of $('themePicker').children){b.classList.toggle('active',b.dataset.theme===theme);b.setAttribute('aria-pressed',b.dataset.theme===theme?'true':'false');}
 document.body.dataset.theme=theme;hideTip();fit();history.replaceState(null,'','#'+theme);render();
}
for(const row of D.themes){const button=el('button','',$('themePicker'));button.dataset.theme=row.id;const number=el('small','',button);number.textContent=row.number;button.append(document.createTextNode(row.name));button.addEventListener('click',()=>setTheme(row.id));}
for(const tab of D.tabs){const button=el('button','',$('categories'));button.dataset.category=tab.id;button.title=names[tab.id];button.setAttribute('aria-label',names[tab.id]);image(button,icons[tab.id]);el('span','',button).textContent=short[tab.id];button.addEventListener('click',()=>{category=tab.id;filter=0;hideTip();render();});}
function showTip(item,event){
 const tip=$('tooltip');tip.replaceChildren();tip.style.setProperty('--quality',qualities[item.quality]||'#b7c5ce');
 const heading=el('div','tooltip-heading',tip),portrait=el('img','',heading);portrait.src=item.picture;portrait.alt=item.name;
 const text=el('div','',heading);el('h3','',text).textContent=item.name;el('div','meta',text).textContent=item.quality+' · '+names[category];
 const effect=el('div','effect',tip);for(const line of String(item.description||'').split(/\n|；/)){el('div','',effect).textContent=line;}
 el('div','owned',tip).textContent=(item.count?'已拥有 '+item.count+' / '+item.target:'尚未收集')+(item.draw_enabled===0?' · 暂未开放':'');
 tip.style.display='block';lastHover=item.id;positionTip(event);
}
function positionTip(event){const tip=$('tooltip');const rect=tip.getBoundingClientRect();let x=event.clientX+20,y=event.clientY+18;if(x+rect.width>innerWidth-15)x=event.clientX-rect.width-20;if(y+rect.height>innerHeight-15)y=innerHeight-rect.height-15;tip.style.left=Math.max(12,x)+'px';tip.style.top=Math.max(12,y)+'px';}
function render(){
 const rows=D.pages[category],owned=rows.filter(r=>r.count>0).length,social=D.social[category];
 $('headerCategory').textContent=names[category];
 for(const b of $('categories').children){b.classList.toggle('active',b.dataset.category===category);b.setAttribute('aria-current',b.dataset.category===category?'page':'false');}
 const summary=$('collectionSummary');summary.replaceChildren();el('strong','',summary).textContent=owned+' / '+rows.length;summary.append(document.createTextNode(' 已收集'));el('small','',summary).textContent='永久收藏';
 $('currencyName').textContent=social.currency_name;$('ticketCount').textContent=social.tickets;
 $('meterFill').style.width=(owned/rows.length*100)+'%';$('meterLabel').textContent=owned+' / '+rows.length;
 $('ownershipFilter').firstChild.textContent=['全部收藏','已拥有','未拥有'][filter];
 const grid=$('grid');grid.replaceChildren();const visible=rows.filter(item=>filter===0||filter===1&&item.count>0||filter===2&&item.count===0);
 for(const item of visible){
  const card=el('button','tile'+(!item.count?' unowned':'')+(item.draw_enabled===0?' unavailable':''),grid);card.setAttribute('role','listitem');card.setAttribute('aria-label',item.name+'，'+item.quality+'，拥有'+item.count);card.dataset.item=item.id;card.style.setProperty('--quality',qualities[item.quality]||'#9aa5a5');
  const portrait=el('img','portrait',card);portrait.src=item.picture;portrait.alt=item.name;portrait.draggable=false;
  el('span','slot-frame',card);el('span','rarity',card).textContent=item.quality;
  if(item.count>0)el('span','quantity',card).textContent=item.count;
  el('span','tile-name',card).textContent=item.name;
  if(item.draw_enabled===0)el('span','tag-unavailable',card).textContent='待开放';
  card.addEventListener('mouseenter',e=>showTip(item,e));card.addEventListener('mousemove',positionTip);card.addEventListener('mouseleave',hideTip);
  card.addEventListener('focus',()=>{const r=card.getBoundingClientRect();showTip(item,{clientX:r.right,clientY:r.top});});card.addEventListener('blur',hideTip);
  // Clicking a collection entry never adds a persistent selection outline.
 }
 $('empty').style.display=visible.length?'none':'block';
}
$('ownershipFilter').addEventListener('click',()=>{filter=(filter+1)%3;hideTip();render();});
$('close').addEventListener('click',()=>{root.hidden=true;$('reopen').hidden=false;hideTip();});
$('reopen').addEventListener('click',()=>{root.hidden=false;$('reopen').hidden=true;fit();});
$('draw').addEventListener('click',()=>{
 const social=D.social[category];if(social.tickets<social.draw_cost)return;
 const rows=D.pages[category].filter(i=>i.draw_enabled!==0&&i.count<i.target);if(!rows.length)return;
 const item=rows[(sampleDraws++*7+2)%rows.length];item.count++;social.tickets-=social.draw_cost;hideTip();render();
 const card=document.querySelector(`[data-item="${item.id}"]`);if(card)card.classList.add('reward-pulse');
});
addEventListener('resize',fit);addEventListener('keydown',e=>{if(e.key==='Escape')hideTip();if(/^[1-5]$/.test(e.key))setTheme(D.themes[Number(e.key)-1].id);});
addEventListener('hashchange',()=>{if(location.hash.slice(1)!==theme)setTheme(location.hash.slice(1));});
window.CollectionPreview={SetTheme:setTheme,Select(id){category=id;filter=0;hideTip();render();},Inspect(){return{theme,category,filter,items:document.querySelectorAll('.tile').length,selectedItems:document.querySelectorAll('.tile.selected,[data-selected="true"]').length,owned:D.pages[category].filter(i=>i.count>0).length,tickets:D.social[category].tickets,tooltip:lastHover,sample:true};}};
setTheme(location.hash.slice(1)||'classic');
})();
