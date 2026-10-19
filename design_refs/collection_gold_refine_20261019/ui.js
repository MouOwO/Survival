(function(){
'use strict';
const D=window.COLLECTION_GOLD,$=id=>document.getElementById(id),root=$('collection');
const quality={N:'#93c88c',R:'#76bdea',SR:'#b080dc',SSR:'#dfb456',UR:'#ed746a'};
const names={ex:'我的前女友',friend:'我的前男友',wife:'我的老婆',beast:'瑞兽赐福'},short={ex:'前女友',friend:'前男友',wife:'老婆',beast:'瑞兽'},icons={ex:'star',friend:'friends',wife:'rewards',beast:'trophy'};
let round=5,category='ex',filter=0,lastHover=null,draws=0;
const el=(type,cls,parent)=>{const n=document.createElement(type);if(cls)n.className=cls;if(parent)parent.append(n);return n;};
const image=(parent,key,cls)=>{const n=el('img',cls,parent);n.src=D.assets[key];n.alt='';n.draggable=false;return n;};
function nine(parent,key,extra=''){
 const spec=D.slices.find(s=>s.key===key),node=el('span','nine '+extra,parent);node.dataset.slice=key;node.setAttribute('aria-hidden','true');
 const [l,t,r,b]=spec.targetLTRB;node.style.setProperty('--l',l+'px');node.style.setProperty('--t',t+'px');node.style.setProperty('--r',r+'px');node.style.setProperty('--b',b+'px');
 for(const part of spec.parts){const p=el('img','slice-'+part.row+part.column,node);p.src=part.file;p.alt='';p.draggable=false;if(!part.paint)p.style.visibility='hidden';}
 return node;
}
for(const [key,url]of Object.entries(D.assets))document.documentElement.style.setProperty('--'+key,`url("${url}")`);
document.querySelector('.collection-mark').src=D.assets.treasure;$('close').firstElementChild.src=D.assets.close;$('ticketIcon').src=D.assets.ticket;document.querySelector('.draw-cost img').src=D.assets.ticket;
nine(document.querySelector('.outer-frame'),'window');nine(document.querySelector('.rail-panel'),'window');
nine($('draw'),'button','control-slice');nine($('ownershipFilter'),'button','control-slice');nine($('close'),'button','control-slice');
function hideTip(){$('tooltip').style.display='none';lastHover=null;}
function fit(){const size=D.rounds[round-1].size,margin=innerWidth<1000?24:64,scale=Math.min(1.13,(innerWidth-margin)/size[0],($('stage').clientHeight-30)/size[1]);root.style.transform=`scale(${Math.max(.35,scale)})`;}
function setRound(value){
 round=Math.max(1,Math.min(5,+value||5));const meta=D.rounds[round-1];root.className='round-'+round;root.style.setProperty('--panel-width',meta.size[0]+'px');root.style.setProperty('--panel-height',meta.size[1]+'px');
 $('roundName').textContent='第 '+round+' 轮 · '+meta.name;$('roundChange').textContent=meta.change;document.body.dataset.round=round;
 for(const b of $('roundPicker').children){b.classList.toggle('active',+b.dataset.round===round);b.setAttribute('aria-pressed',+b.dataset.round===round?'true':'false');}
 hideTip();fit();history.replaceState(null,'','#round'+round);render();
}
for(const meta of D.rounds){const b=el('button','',$('roundPicker'));b.dataset.round=meta.id;el('small','',b).textContent='R'+meta.id;b.append(document.createTextNode(meta.id===5?'紧凑定稿':meta.name));b.addEventListener('click',()=>setRound(meta.id));}
for(const tab of D.tabs){const b=el('button','',$('categories'));b.dataset.category=tab.id;b.title=names[tab.id];b.setAttribute('aria-label',names[tab.id]);nine(b,'button','control-slice');image(b,icons[tab.id],'category-icon');el('span','category-label',b).textContent=short[tab.id];b.addEventListener('click',()=>{category=tab.id;filter=0;$('drawResult').textContent='';hideTip();render();});}
function showTip(item,event){
 const tip=$('tooltip');tip.replaceChildren();tip.style.setProperty('--quality',quality[item.quality]);tip.dataset.round=round;if(round>=4)nine(tip,'window');
 const body=el('div','tip-body',tip),heading=el('div','tooltip-heading',body),portrait=el('img','',heading);portrait.src=item.picture;portrait.alt=item.name;
 const title=el('div','',heading);el('h3','',title).textContent=item.name;el('div','meta',title).textContent=item.quality+' · '+names[category];
 const effect=el('div','effect',body);for(const line of String(item.description||'').split(/\n|；/))el('div','',effect).textContent=line;
 el('div','owned',body).textContent=(item.count?'已拥有 '+item.count+' / '+item.target:'尚未收集')+(item.draw_enabled===0?' · 暂未开放':'');
 tip.style.display='block';lastHover=item.id;positionTip(event);
}
function positionTip(event){const t=$('tooltip'),r=t.getBoundingClientRect();let x=event.clientX+16,y=event.clientY+16;if(x+r.width>innerWidth-12)x=event.clientX-r.width-16;if(y+r.height>innerHeight-12)y=innerHeight-r.height-12;t.style.left=Math.max(12,x)+'px';t.style.top=Math.max(12,y)+'px';}
function render(){
 const rows=D.pages[category],owned=rows.filter(i=>i.count>0).length,social=D.social[category];$('headerCategory').textContent=names[category];
 for(const b of $('categories').children){b.classList.toggle('active',b.dataset.category===category);b.setAttribute('aria-current',b.dataset.category===category?'page':'false');}
 const summary=$('collectionSummary');summary.replaceChildren();el('strong','',summary).textContent=owned+' / '+rows.length;summary.append(document.createTextNode(' 已收集'));if(round<5)el('small','',summary).textContent='永久收藏';
 $('currencyName').textContent=social.currency_name;$('ticketCount').textContent=social.tickets;$('meterFill').style.width=owned/rows.length*100+'%';$('meterLabel').textContent=owned+' / '+rows.length;$('filterLabel').textContent=['全部收藏','已拥有','未拥有'][filter];
 const grid=$('grid');grid.replaceChildren();const visible=rows.filter(i=>filter===0||filter===1&&i.count>0||filter===2&&i.count===0);
 for(const item of visible){
  const card=el('button','tile'+(!item.count?' unowned':'')+(item.draw_enabled===0?' unavailable':''),grid);card.dataset.item=item.id;card.setAttribute('role','listitem');card.setAttribute('aria-label',item.name+'，'+item.quality+'，拥有'+item.count);card.style.setProperty('--quality',quality[item.quality]);
  const p=el('img','portrait',card);p.src=item.picture;p.alt=item.name;p.draggable=false;
  if(round>=3)nine(card,'slot','slot-frame');else el('span','legacy-slot-frame',card);
  el('span','rarity',card).textContent=item.quality;if(item.count>0)el('span','quantity',card).textContent=item.count;
  if(item.draw_enabled===0)el('span','tag-unavailable',card).textContent='待开放';
  card.addEventListener('mouseenter',e=>showTip(item,e));card.addEventListener('mousemove',positionTip);card.addEventListener('mouseleave',hideTip);card.addEventListener('focus',()=>{const r=card.getBoundingClientRect();showTip(item,{clientX:r.right,clientY:r.top});});card.addEventListener('blur',hideTip);
 }
 $('empty').style.display=visible.length?'none':'block';
}
$('ownershipFilter').addEventListener('click',()=>{filter=(filter+1)%3;hideTip();render();});$('close').addEventListener('click',()=>{root.hidden=true;$('reopen').hidden=false;hideTip();});$('reopen').addEventListener('click',()=>{root.hidden=false;$('reopen').hidden=true;fit();});
$('draw').addEventListener('click',()=>{const s=D.social[category];if(s.tickets<s.draw_cost){$('drawResult').textContent='抽奖券不足';return;}const rows=D.pages[category].filter(i=>i.draw_enabled!==0&&i.count<i.target);if(!rows.length)return;const item=rows[(draws++*7+2)%rows.length];item.count++;s.tickets-=s.draw_cost;hideTip();render();$('drawResult').textContent='获得 '+item.name;});
addEventListener('resize',fit);addEventListener('keydown',e=>{if(e.key==='Escape')hideTip();if(/^[1-5]$/.test(e.key))setRound(+e.key);});addEventListener('hashchange',()=>{const n=+location.hash.replace('#round','');if(n!==round)setRound(n);});
window.CollectionPreview={SetRound:setRound,Select(id){category=id;filter=0;hideTip();render();},Inspect(){return{round,category,filter,items:document.querySelectorAll('.tile').length,selectedItems:document.querySelectorAll('.tile.selected,[data-selected="true"]').length,owned:D.pages[category].filter(i=>i.count>0).length,tickets:D.social[category].tickets,tooltip:lastHover,sample:true};}};
setRound(+location.hash.replace('#round','')||5);
})();
