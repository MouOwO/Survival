'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const crypto = require('crypto');
const { fileURLToPath } = require('url');
const { browser, sleep } = require('./browser.cjs');

const project = path.resolve(__dirname, '../..');
const source = path.join(project, 'design_refs/archive_official_variants_20261019');
const output = path.join(project, 'output/archive_official_variants_20261019/preview');
const reportFile = path.join(output, 'visual_report.json');
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

// DOM observations run against the built interactive preview. They intentionally
// do not duplicate category, search, ownership, selection or tooltip logic.
const observe = `(() => {
  const visible = node => {
    if (!node) return false;
    const r = node.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    let left=0, top=0, right=innerWidth, bottom=innerHeight;
    for (let parent=node;parent;parent=parent.parentElement) {
      const s=getComputedStyle(parent);
      if (parent.hidden || s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) === 0) return false;
      if (parent !== node && ['hidden','clip','auto','scroll'].includes(s.overflowX)) {
        const box=parent.getBoundingClientRect(); left=Math.max(left,box.x); right=Math.min(right,box.right);
      }
      if (parent !== node && ['hidden','clip','auto','scroll'].includes(s.overflowY)) {
        const box=parent.getBoundingClientRect(); top=Math.max(top,box.y); bottom=Math.min(bottom,box.bottom);
      }
    }
    return r.right>left && r.x<right && r.bottom>top && r.y<bottom;
  };
  const rect = node => { const r = node.getBoundingClientRect(); return { x:r.x, y:r.y, width:r.width, height:r.height, right:r.right, bottom:r.bottom, cx:r.x+r.width/2, cy:r.y+r.height/2 }; };
  const cards = [...document.querySelectorAll('button[data-item-id]')].filter(visible).map(node => {
    const icon = node.querySelector('[data-item-icon], .item-icon, img');
    const label = node.querySelector('[data-item-name], .item-name, .entry-name, .item-title');
    return { id:node.dataset.itemId, unlocked:node.dataset.unlocked, text:node.innerText, ariaLabel:node.getAttribute('aria-label'), rect:rect(node), icon:icon && rect(icon), name:label ? label.textContent.trim() : node.textContent.trim().split('\\n')[0], nameRect:label && rect(label) };
  });
  const tip = document.querySelector('#item-tooltip');
  const detail = document.querySelector('[data-role="detail"], #item-detail, #detail-panel, .detail-panel');
  const failures = [];
  const texts = [...document.querySelectorAll('body *')].filter(node => visible(node) && node.childElementCount === 0 && node.textContent.trim() && !['SCRIPT','STYLE','OPTION'].includes(node.tagName));
  for (const node of texts) {
    const s = getComputedStyle(node);
    if (s.overflowY === 'auto' || s.overflowY === 'scroll' || s.overflowX === 'auto' || s.overflowX === 'scroll') continue;
    const range = document.createRange(); range.selectNodeContents(node);
    const text = range.getBoundingClientRect(), box = node.getBoundingClientRect();
    if (text.width && (text.x < box.x - 2 || text.right > box.right + 2 || text.y < box.y - 3 || text.bottom > box.bottom + 3)) {
      failures.push({text:node.textContent.trim().slice(0,120), className:String(node.className), textRect:{x:text.x,y:text.y,right:text.right,bottom:text.bottom}, box:rect(node)});
    }
  }
  return { state:ArchivePreview.getState(), title:document.title, bodyWidth:document.body.scrollWidth, bodyHeight:document.body.scrollHeight, viewport:{width:innerWidth,height:innerHeight}, cards, tooltip:{visible:visible(tip),text:tip ? tip.innerText : '',rect:tip ? rect(tip) : null}, detail:detail ? {text:detail.innerText,rect:rect(detail)} : null, textOverflow:failures };
})()`;

async function assets(active) {
  return active.run(`(async () => {
    const urls = new Set([...document.images].map(image => image.currentSrc || image.src));
    for (const node of document.querySelectorAll('*')) {
      for (const value of [getComputedStyle(node).backgroundImage, getComputedStyle(node,'::before').backgroundImage, getComputedStyle(node,'::after').backgroundImage]) {
        for (const match of value.matchAll(/url\\(["']?([^"')]+)["']?\\)/g)) urls.add(new URL(match[1],location.href).href);
      }
    }
    return Promise.all([...urls].filter(Boolean).map(async url => {
      const image = new Image(); image.src=url;
      try { await image.decode(); return {url,loaded:true,width:image.naturalWidth,height:image.naturalHeight}; }
      catch (error) { return {url,loaded:false,error:String(error)}; }
    }));
  })()`);
}

function checkLayout(snapshot, label) {
  const { width, height } = snapshot.viewport;
  assert(snapshot.bodyWidth <= width + 1 && snapshot.bodyHeight <= height + 1, label + ': page fits viewport');
  assert(snapshot.cards.length, label + ': visible archive items');
  for (const card of snapshot.cards) {
    assert(card.icon && card.icon.width > 0 && card.icon.height > 0, label + ': real icon for ' + card.id);
    assert(card.icon.x >= card.rect.x - 1 && card.icon.y >= card.rect.y - 1 && card.icon.right <= card.rect.right + 1 && card.icon.bottom <= card.rect.bottom + 1, label + ': icon stays inside item ' + card.id);
    if (card.nameRect) assert(card.nameRect.x >= card.rect.x - 1 && card.nameRect.right <= card.rect.right + 1, label + ': name stays inside item ' + card.id);
  }
  assert.deepEqual(snapshot.textOverflow, [], label + ': text stays inside its own layout box');
}

async function api(active, method, ...args) {
  const result = await active.run('ArchivePreview[' + JSON.stringify(method) + '](...' + JSON.stringify(args) + ')');
  await sleep(90);
  return result;
}

async function clearSearch(active) {
  await active.run(`(() => { const input=document.querySelector('#item-search'); input.value=''; input.dispatchEvent(new Event('input',{bubbles:true})); })()`);
  await sleep(70);
}

async function interactionChecks(active) {
  const result = {};
  await api(active, 'setCategory', 'clear');
  await api(active, 'setFilter', 'all');
  await clearSearch(active);
  const initial = await active.run(observe);
  assert(initial.cards.length > 1, 'Clear category includes multiple items');
  assert(initial.cards.every(card => ['true', 'false'].includes(card.unlocked)), 'Items expose real unlock status for review');
  result.clearInitial = initial;
  const target = initial.cards[Math.min(1,initial.cards.length - 1)];
  const search = await active.run(`(() => {const r=document.querySelector('#item-search').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await active.click(search.x, search.y);
  await active.call('Input.insertText', { text: target.name });
  await sleep(100);
  result.search = await active.run(observe);
  assert(result.search.cards.some(card => card.id === target.id), 'Search preserves the matching item');
  assert(result.search.cards.length < initial.cards.length, 'Search filters the visible items');
  await clearSearch(active);
  await api(active, 'setFilter', 'unlocked');
  result.unlocked = await active.run(observe);
  assert(result.unlocked.cards.length && result.unlocked.cards.every(card => card.unlocked === 'true'), 'Unlocked filter shows unlocked items');
  await api(active, 'setFilter', 'locked');
  result.locked = await active.run(observe);
  assert(result.locked.cards.length && result.locked.cards.every(card => card.unlocked === 'false'), 'Locked filter shows locked items');
  await api(active, 'setFilter', 'all');
  const item = (await active.run(observe)).cards.find(card => card.id !== initial.cards[0].id) || initial.cards[0];
  const textPoint = item.nameRect ? { x:item.nameRect.cx, y:item.nameRect.cy } : { x:item.rect.cx, y:item.rect.bottom-5 };
  await active.click(textPoint.x, textPoint.y);
  result.clicked = await active.run(observe);
  assert(result.clicked.detail && result.clicked.detail.text.includes(item.name), 'Clicking item changes the actual detail panel');
  assert.equal(result.clicked.tooltip.visible, false, 'Tooltip stays hidden over item text');
  await active.move(item.icon.cx, item.icon.cy);
  await sleep(160);
  result.iconHover = await active.run(observe);
  assert.equal(result.iconHover.tooltip.visible, true, 'Hovering actual item icon shows tooltip');
  assert(result.iconHover.tooltip.text.includes(item.name), 'Tooltip describes the icon under the pointer');
  assert(result.iconHover.tooltip.rect.x >= 0 && result.iconHover.tooltip.rect.right <= result.iconHover.viewport.width && result.iconHover.tooltip.rect.y >= 0 && result.iconHover.tooltip.rect.bottom <= result.iconHover.viewport.height, 'Tooltip stays on screen');
  await active.move(textPoint.x, textPoint.y);
  result.textHover = await active.run(observe);
  assert.equal(result.textHover.tooltip.visible, false, 'Moving to the text hides tooltip');
  // Rapid icon-to-text-to-icon movement exercises the actual hover handlers.
  await active.move(item.icon.cx, item.icon.cy);
  await active.move(textPoint.x, textPoint.y);
  await active.move(item.icon.cx, item.icon.cy);
  await sleep(160);
  result.rapidHover = await active.run(observe);
  assert.equal(result.rapidHover.tooltip.visible, true, 'Tooltip reappears after rapid icon hover');
  await active.move(3, 3);
  await api(active, 'setCategory', 'points');
  await api(active, 'setFilter', 'all');
  await clearSearch(active);
  result.points = await active.run(observe);
  assert(result.points.cards.length, 'Points category displays items');
  assert(result.points.cards.every(card => /解锁/.test(card.ariaLabel) && ['true','false'].includes(card.unlocked) && !/拥有\s*[0-9]|已拥有\s*[0-9]/.test(card.text)), 'Unique point items expose unlock status without quantities');
  assert(result.points.detail && /解锁/.test(result.points.detail.text) && !/拥有\s*[0-9]|已拥有\s*[0-9]/.test(result.points.detail.text), 'Selected unique item shows unlock status and duplicate conversion');
  checkLayout(result.points, 'Points detail');
  return result;
}

function sourceHashes() {
  const result = {};
  const walk = directory => {
    if (!fs.existsSync(directory)) return;
    for (const entry of fs.readdirSync(directory, { withFileTypes:true })) {
      const file = path.join(directory,entry.name);
      if (entry.isDirectory()) walk(file);
      else if (/\.(html|css|cjs|js|json)$/.test(entry.name)) result[path.relative(project,file).replaceAll('\\','/')] = digest(file);
    }
  };
  for (const directory of [source,__dirname]) {
    walk(directory);
  }
  return result;
}

async function main() {
  fs.mkdirSync(output, { recursive: true });
  const report = {
    status: 'RUNNING', startedAt: new Date().toISOString(), sourceHashes: sourceHashes(), resolutions: [],
    limits: ['This checks five standalone archive design previews in Chrome using decoded official UI artwork; it does not replace or validate a native in-game archive screen.', 'Search, filtering, detail selection, tooltip and image loading are observed in the actual generated preview, with no backend mutation.']
  };
  let active;
  try {
    active = await browser({ output });
    for (const [width, height] of [[1600, 900], [1280, 720]]) {
      await active.viewport(width, height);
      const resolution = { width, height, variants: [] };
      for (const id of ['01', '02', '03', '04', '05']) {
        await active.go(path.join(source, 'index.html'), '?capture=' + id);
        await active.run(`(() => {if(!window.ArchivePreview)throw new Error('ArchivePreview API unavailable');return true})()`);
        await active.move(3, 3);
        const snapshot = await active.run(observe);
        const images = await assets(active);
        assert(images.length > 3 && images.every(asset => asset.loaded && asset.width > 0 && asset.height > 0), id + ': every referenced image loads');
        for (const asset of images) {
          if (asset.url.startsWith('file:')) asset.sha256 = digest(fileURLToPath(asset.url));
        }
        checkLayout(snapshot, id + ' at ' + width);
        const screenshot = 'scheme_' + id + '_' + width + 'x' + height + '.png';
        await active.shot(path.join(output, screenshot), { x: 0, y: 0, width, height });
        const checks = await interactionChecks(active);
        resolution.variants.push({ id, screenshot, snapshot, images, checks });
      }
      report.resolutions.push(resolution);
    }
    report.runtimeErrors = active.events.filter(event => event.method === 'Runtime.exceptionThrown' || (event.method === 'Runtime.consoleAPICalled' && event.params.type === 'error'));
    assert.deepEqual(report.runtimeErrors, [], 'No JavaScript runtime or console errors');
    report.finalSourceHashes = sourceHashes();
    assert.deepEqual(report.finalSourceHashes, report.sourceHashes, 'Sources remain unchanged throughout preview verification');
    const themes = JSON.parse(fs.readFileSync(path.join(__dirname,'themes.json'),'utf8')).themes;
    const figures = report.resolutions[0].variants.map(variant => {
      const theme = themes.find(value => value.id === variant.id);
      return '<figure><img src="' + variant.screenshot + '"><figcaption>' + variant.id + ' / ' + theme.title + ' · ' + theme.family + '</figcaption></figure>';
    }).join('');
    fs.writeFileSync(path.join(output, 'overview.html'), '<!doctype html><meta charset="utf-8"><title>官方 UI 存档方案对比</title><style>*{box-sizing:border-box}body{margin:0;padding:28px;background:#111a20;color:#e3e6e7;font-family:"Microsoft YaHei",sans-serif}h1{font-size:26px;font-weight:500;margin:0 0 20px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:22px}figure{margin:0;background:#202b32;padding:8px;border:1px solid #526270}img{width:100%;display:block}figcaption{font-size:20px;padding:10px 6px 4px}</style><h1>官方 UI · 存档界面五套方案</h1><div class="grid">' + figures + '</div>');
    await active.viewport(1640, 1580);
    await active.go(path.join(output, 'overview.html'));
    await active.shot(path.join(output, 'overview.png'), { x: 0, y: 0, width: 1640, height: 1580 });
    report.exports = [];
    for (const theme of themes) {
      const original = path.join(output,'scheme_' + theme.id + '_1600x900.png');
      const target = path.join(source,theme.id + '_' + theme.title + '.png');
      fs.copyFileSync(original,target);
      assert.equal(digest(original),digest(target),'Export preserves unedited screenshot pixels');
      report.exports.push({path:path.relative(project,target).replaceAll('\\','/'),sha256:digest(target)});
    }
    const overviewExport = path.join(source,'五套方案总览.png');
    fs.copyFileSync(path.join(output,'overview.png'),overviewExport);
    report.exports.push({path:path.relative(project,overviewExport).replaceAll('\\','/'),sha256:digest(overviewExport)});
    report.status = 'PASS'; report.finishedAt = new Date().toISOString();
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ status: report.status, resolutions: report.resolutions.map(value => ({ width: value.width, height: value.height, variants: value.variants.length })), screenshots: 11, report: reportFile }));
  } catch (error) {
    report.status = 'FAIL'; report.failure = String(error); report.finishedAt = new Date().toISOString();
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
    throw error;
  } finally { if (active) await active.close(); }
}

if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
