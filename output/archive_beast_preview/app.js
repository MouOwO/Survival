(() => {
  'use strict';
  const data = window.ARCHIVE_DATA, $ = id => document.getElementById(id);
  const icons = ['◇','◈','▱','✧','⊙','∞','♧','♡','✦'];
  const rule = `每次消耗${data.rule.draw_cost}张${data.rule.currency_name} · 剩余数量决定抽取权重 · 重复获得叠加效果`;
  const fullRule = `挑战3获取${data.rule.currency_name} · 每项挑战每日最多${data.rule.daily_limit}张 · 奖励效果按持有数量叠加`;
  let snapshot = null, toastTimer;
  const itemNodes = new Map();
  const toast = message => { const t = document.querySelector('.toast'); t.textContent = message; t.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => t.hidden = true, 3500); };
  $('subtitle').textContent = data.subtitle;
  $('summary').innerHTML = `已拥有 <b>${data.sample.owned}</b>/${data.rows.length} 种 · 共 <b>${data.sample.total}</b> 件`;
  $('recent').textContent = '获得：' + data.sample.last_name;
  $('tickets').innerHTML = `福签：<b>${data.sample.tickets}</b>`;
  $('short-rule').textContent = rule;
  $('full-rule').textContent = rule + '。' + fullRule;
  data.categories.forEach((name, i) => {
    const button = document.createElement('button');
    button.className = 'nav-item' + (i === 8 ? ' selected' : '');
    button.innerHTML = `<span class="nav-symbol" aria-hidden="true">${icons[i]}</span><span></span>`;
    button.lastElementChild.textContent = name;
    button.setAttribute('aria-current', i === 8 ? 'page' : 'false');
    button.onclick = () => { if (i !== 8) toast('本次仅预览「瑞兽赐福」，其他分类共用此导航样式。'); };
    $('nav').append(button);
  });
  function moveTip(x, y) {
    const tip = $('tooltip');
    tip.style.left = Math.max(12, Math.min(x + 18, innerWidth - tip.offsetWidth - 12)) + 'px';
    tip.style.top = Math.max(12, Math.min(y + 14, innerHeight - tip.offsetHeight - 12)) + 'px';
  }
  function showTip(item, x, y) {
    const tip = $('tooltip');
    tip.querySelector('h3').textContent = item.name;
    tip.querySelector('p').textContent = item.description + '（每件）';
    tip.querySelector('.tooltip-count').textContent = item.count === null ? `持有数量待接入 · 数量上限 ${item.target}` : `已拥有${item.count}件 · 数量上限 ${item.target}`;
    tip.hidden = false; moveTip(x, y);
  }
  data.rows.forEach(item => {
    const card = document.createElement('div'); card.className = 'item unknown'; card.tabIndex = 0;
    card.dataset.id = item.id;
    card.innerHTML = '<div class="seal" aria-hidden="true"></div><div class="item-name"></div><div class="count"><span class="current">—</span><span class="slash">/</span><span class="target"></span></div>';
    card.querySelector('.seal').textContent = item.name.slice(0, 1);
    card.querySelector('.item-name').textContent = item.name;
    card.querySelector('.target').textContent = item.target;
    card.setAttribute('aria-label', item.name + '，持有数量待接入，上限' + item.target);
    card.onmouseenter = e => showTip(item, e.clientX, e.clientY);
    card.onmousemove = e => moveTip(e.clientX, e.clientY);
    card.onmouseleave = card.onblur = () => $('tooltip').hidden = true;
    card.onfocus = () => { const r = card.getBoundingClientRect(); showTip(item, r.right, r.top); };
    itemNodes.set(item.id, card); $('grid').append(card);
  });
  $('grid').onscroll = () => $('tooltip').hidden = true;
  $('draw').title = '玩家资源和奖池限制待接入；示例余额不能用于抽奖';
  $('draw').onclick = () => {
    if ($('draw').disabled) return;
    $('draw').disabled = true;
    // A preview emits intent only. A host can provide the existing game adapter.
    window.dispatchEvent(new CustomEvent('archive-draw-intent', { detail: { pool_id: 'beast' } }));
    toast('已触发抽奖交互预览，等待数据返回；未向游戏服务器发送请求。');
  };
  document.querySelector('.close').onclick = () => { document.querySelector('.archive').hidden = true; $('reopen').hidden = false; $('tooltip').hidden = true; };
  $('reopen').onclick = () => { document.querySelector('.archive').hidden = false; $('reopen').hidden = true; };
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { if (!$('tooltip').hidden) $('tooltip').hidden = true; else document.querySelector('.close').click(); } });
  $('states-toggle').onclick = () => { const board = document.querySelector('.state-board'); board.hidden = !board.hidden; if (!board.hidden) board.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); };
  document.querySelector('.demo-draw:not(:disabled)').onclick = () => toast('可用按钮的样式演示，不执行抽奖。');
  const sourceHanAvailable = document.fonts.check('16px "Source Han Sans SC"', '瑞兽赐福') && document.fonts.check('16px "Source Han Serif SC"', '存档');
  // FontFaceSet.check can succeed on missing fonts; use measured fallback differences as well.
  function installed(name) {
    const canvas = document.createElement('canvas'), ctx = canvas.getContext('2d'), text = '存档瑞兽赐福ABC012345';
    ctx.font = '32px monospace'; const base = ctx.measureText(text).width;
    ctx.font = `32px "${name}", monospace`; return Math.abs(ctx.measureText(text).width - base) > .1;
  }
  const sans = installed('Source Han Sans SC'), serif = installed('Source Han Serif SC');
  $('font-status').textContent = sans && serif && sourceHanAvailable ? '预览：思源字体 · 游戏内待验证' : '字体回退：宋体 / 微软雅黑 · 游戏内思源字体待验证';
  window.ArchivePreview = {
    setSnapshot(packet) {
      if (packet.category_id !== 'beast') throw new Error('Expected beast snapshot');
      snapshot = packet;
      const rows = Array.isArray(packet.rows) ? packet.rows : Object.values(packet.rows || {});
      const counts = new Map(rows.map(row => [row.id, row.count]));
      let owned = 0, total = 0, known = 0;
      for (const item of data.rows) {
        const value = counts.get(item.id);
        item.count = value === null || value === undefined || !Number.isFinite(Number(value)) ? null : Math.max(0, Number(value));
        const card = itemNodes.get(item.id);
        card.className = 'item ' + (item.count === null ? 'unknown' : item.count === 0 ? 'unowned' : item.count >= item.target ? 'owned maxed' : 'owned');
        card.querySelector('.current').textContent = item.count === null ? '—' : String(item.count);
        card.setAttribute('aria-label', `${item.name}，${item.count === null ? '持有数量待接入' : '已拥有' + item.count}，上限${item.target}`);
        if (item.count !== null) { known++; total += item.count; if (item.count > 0) owned++; }
      }
      $('summary').textContent = known === 40 ? `已拥有 ${owned}/40 种 · 共 ${total} 件` : '持有明细待接入';
      $('summary-source').textContent = known === 40 ? '来自传入档案快照' : `已接入 ${known}/40 项，缺失项保持未知`;
      document.querySelector('.collection-track i').style.width = owned / 40 * 100 + '%';
      const social = packet.social;
      $('tickets').textContent = social && social.tickets != null ? '福签：' + social.tickets : '福签：待接入';
      $('recent').textContent = packet.last_draw && packet.last_draw.pool_id === 'beast' ? '获得：' + packet.last_draw.name : '暂无最近获得记录';
      $('recent-example').hidden = $('ticket-example').hidden = true;
      $('draw').disabled = !(social && Number(social.tickets) >= data.rule.draw_cost && Number(social.remaining) > 0 && Number(packet.pending) !== 1);
      $('draw').title = $('draw').disabled ? '资源不足、奖池已满或正在保存' : '抽取一次';
    },
    getSnapshot: () => snapshot,
    getItems: () => data.rows.map(item => ({ ...item }))
  };
})();
