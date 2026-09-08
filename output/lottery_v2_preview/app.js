const app=document.querySelector('#app'), iconRoot='../../panorama/src/images/custom_game/lottery_handoff/icons/';
const names=['ticket','plus','gift','announcement','pool','history','close','checkbox_off','checkbox_on','chevron','info','check','refresh','star'];
const escapeHTML=v=>String(v||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon=n=>`<img class="function" src="${iconRoot+n}.svg" alt="${n}">`;
const art=item=>`<img class="art" src="items/${item.icon.replace('item_','')}.png" alt="${escapeHTML(item.display_name)}">`;
let selectedPool='map', rewards=[];
function showPool(id){
 selectedPool=id;const pool=data.pools.find(p=>p.pool_id===id),members=data.members.filter(m=>m.pool_id===id);
 rewards=data.items.filter(item=>members.some(m=>m.item_id==='*'||m.item_id===item.item_id));
 app.innerHTML=`<section class="modal"><div class="dialog"><div class="heading">${icon('pool')}<h1>奖池详情</h1><button class="icon-only" onclick="app.innerHTML=''">${icon('close')}</button></div><nav>${data.pools.map(p=>`<button data-pool="${p.pool_id}" class="${p.pool_id===id?'selected':''}" onclick="showPool('${p.pool_id}')">${escapeHTML(p.display_name)}${icon('star')}</button>`).join('')}</nav><div class="body"><div class="grid">${rewards.map((item,i)=>`<button class="reward" data-item="${item.item_id}" onclick="select(${i})">${art(item)}<span>${escapeHTML(item.display_name)}</span><small>${item.quality.toUpperCase()}</small></button>`).join('')}</div><aside id="selection"></aside></div><footer>${icon('info')}<p>${escapeHTML(pool.description)}<br>单抽 ${pool.single_cost} / 十连 ${pool.ten_cost} 张${pool.pool_group==='map'?'抽奖券':'特殊抽奖券'}</p><button class="confirm" onclick="app.innerHTML=''">${icon('check')}确认</button></footer></div></section>`;
 select(0);
}
function select(index){const item=rewards[index];document.querySelectorAll('.reward').forEach((n,i)=>n.classList.toggle('selected',i===index));document.querySelector('#selection').innerHTML=item?`${art(item)}<h2>${escapeHTML(item.display_name)}</h2><p>${item.quality.toUpperCase()} · ${escapeHTML(item.duration_text)} · 持有 —/${item.max_owned}</p><div class="description">${escapeHTML(item.description)}</div>`:'暂无奖励';}
function showIcons(){app.innerHTML=`<div class="states"><h1>功能图标 · v2 原 SVG</h1><p>同轮廓、同一资源；状态仅调整亮度与底色。浅色、深色、灰色底共同检查透明边缘。</p><table><thead><tr><th>资源</th>${['普通','悬停','按下','禁用','选中'].map(s=>`<th>${s}</th>`).join('')}</tr></thead><tbody>${names.map(n=>`<tr><th>${n}.svg</th>${['normal','hover','pressed','disabled','selected'].map(state=>`<td><button class="state ${state}" ${state==='disabled'?'disabled':''}>${icon(n)}</button><button class="state light ${state}">${icon(n)}</button><button class="state gray ${state}">${icon(n)}</button></td>`).join('')}</tr>`).join('')}</tbody></table></div>`;}
showPool('map');
