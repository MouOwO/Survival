'use strict';

// A deterministic layout model for the actual renderer and its actual CSS.
// Native layout pixels and the menu's CSS Fit transform are intentionally
// separate. This is not a replacement for the native Panorama acceptance run.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const base = path.resolve(__dirname, '../../..');
const scripts = path.join(base, 'panorama/src/scripts/custom_game');
const styles = path.join(base, 'panorama/src/styles/custom_game');
const camel = key => key.replace(/-([a-z])/g, (_, c) => c.toUpperCase());

function harness({nativeScale = .75, fitScale = .6, rootWidth = 1920, rootHeight = 1080,
    layoutDelay = 0, sourceTransform = code => code, dismissTransform = code => code,
    cssTransform = code => code} = {}) {
    let cursor = [0, 0], time = 0, timerId = 0, checkouts = 0, created = 0, textWrites = 0;
    const jobs = new Map(), scheduled = [], requests = [];
    const css = cssTransform(['menus_v10_commerce.css', 'black_lion_market.css']
        .map(file => fs.readFileSync(path.join(styles, file), 'utf8')).join('\n'));
    const rules = [];
    for (const match of css.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const values = {};
        for (const declaration of match[2].split(';')) {
            const index = declaration.indexOf(':');
            if (index >= 0) {
                const key = camel(declaration.slice(0, index).trim()), value = declaration.slice(index + 1).trim();
                values[key] = value;
                if (key === 'margin' || key === 'padding') {
                    const parts = value.split(/\s+/), expanded = [parts[0], parts[1] ?? parts[0], parts[2] ?? parts[0], parts[3] ?? parts[1] ?? parts[0]];
                    ['Top', 'Right', 'Bottom', 'Left'].forEach((side, i) => { values[key + side] = expanded[i]; });
                }
            }
        }
        for (const selector of match[1].split(',')) {
            if (selector.includes(':') || selector.includes('>')) continue;
            rules.push({selector: selector.trim(), values,
                weight: (selector.match(/#/g) || []).length * 100 + (selector.match(/\./g) || []).length * 10});
        }
    }
    function simple(node, selector) {
        const name = selector.match(/^[A-Za-z]+/);
        if (name && node.paneltype !== name[0]) return false;
        for (const match of selector.matchAll(/([.#])([\w-]+)/g)) {
            if (match[1] === '.' ? !node.classes.has(match[2]) : node.id !== match[2]) return false;
        }
        return true;
    }
    function matches(node, selector) {
        const parts = selector.split(/\s+/);
        if (!simple(node, parts.pop())) return false;
        for (let part = parts.pop(), ancestor = node.parent; part; part = parts.pop()) {
            while (ancestor && !simple(ancestor, part)) ancestor = ancestor.parent;
            if (!ancestor) return false;
            ancestor = ancestor.parent;
        }
        return true;
    }
    function computed(node) {
        const result = {}, priorities = {};
        rules.forEach(({selector, values, weight}, index) => {
            if (!matches(node, selector)) return;
            for (const [key, value] of Object.entries(values)) {
                const priority = weight * 10000 + index;
                if (!(key in priorities) || priority >= priorities[key]) { result[key] = value; priorities[key] = priority; }
            }
        });
        return Object.assign(result, node.style);
    }
    function edges(value) {
        const values = String(value || '0px').split(/\s+/).map(v => parseFloat(v) || 0);
        return [values[0], values[1] ?? values[0], values[2] ?? values[0], values[3] ?? values[1] ?? values[0]];
    }
    function px(value, fallback) { return /^-?[\d.]+px$/.test(String(value)) ? parseFloat(value) : fallback; }
    function width(node) {
        if (node === root) return rootWidth / nativeScale;
        const c = computed(node), declared = c.width;
        if (/^[\d.]+%$/.test(String(declared))) {
            const parent = node.parent, pc = computed(parent), pe = edges(pc.padding);
            return (width(parent) - pe[1] - pe[3]) * parseFloat(declared) / 100;
        }
        return px(declared, node.parent ? width(node.parent) : 276);
    }
    function height(node, ignoreCap = false) {
        if (node.visible === false || computed(node).visibility === 'collapse') return 0;
        const c = computed(node), padding = edges(c.padding), border = c.borderTop ? 1 : 0;
        ['Top', 'Right', 'Bottom', 'Left'].forEach((side, i) => { padding[i] = px(c['padding' + side], padding[i]); });
        let natural;
        if (node.paneltype === 'Label') {
            const font = px(c.fontSize, 17), line = px(c.lineHeight, Math.ceil(font * 1.25));
            const available = Math.max(1, width(node) - padding[1] - padding[3]);
            const text = time + 1e-8 < node.layoutReady ? node.previousText : node.text;
            natural = String(text || '').split(/\r?\n/).reduce((count, value) => {
                const units = [...value].reduce((sum, char) => sum + (/[^\x00-\x7f]/.test(char) ? 1 : .55), 0);
                return count + Math.max(1, Math.ceil(units * font / available));
            }, 0) * line;
        } else if (c.flowChildren === 'down') {
            natural = node.children.reduce((sum, child) => {
                const cc = computed(child), margin = edges(cc.margin);
                if (!child.visible || cc.visibility === 'collapse') return sum;
                return sum + height(child) + px(cc.marginTop, margin[0]) + px(cc.marginBottom, margin[2]);
            }, 0);
        } else {
            natural = node.children.reduce((maximum, child) => {
                const pos = String(computed(child).position || '0px 0px').split(/\s+/);
                return Math.max(maximum, (parseFloat(pos[1]) || 0) + height(child));
            }, 0);
        }
        let value = px(c.height, natural + padding[0] + padding[2] + border);
        value = Math.max(px(c.minHeight, 0), value);
        return ignoreCap ? value : Math.min(px(c.maxHeight, Infinity), value);
    }
    class Panel {
        constructor(type, parent, id = '') {
            created++; this.paneltype = type; this.id = id; this.parent = parent;
            this.children = []; this.style = {}; this.events = {}; this.classes = new Set();
            this.visible = true; this.enabled = true; this.hittest = true; this.hittestchildren = true;
            this.actualuiscale_x = this.actualuiscale_y = nativeScale;
            this._text = ''; this.previousText = ''; this.layoutReady = 0; this.scrollOffset = 0;
            if (parent) parent.children.push(this);
        }
        check() { assert(!this.deleted, 'stale callbacks must not access deleted native panels'); }
        IsValid() { return !this.deleted; }
        GetParent() { this.check(); return this.parent; }
        Children() { this.check(); return this.children; }
        AddClass(value) { this.check(); value.split(/\s+/).forEach(v => this.classes.add(v)); }
        RemoveClass(value) { this.check(); this.classes.delete(value); }
        BHasClass(value) { this.check(); return this.classes.has(value); }
        SetHasClass(value, on) { on ? this.AddClass(value) : this.RemoveClass(value); }
        SetPanelEvent(name, fn) { this.check(); this.events[name] = fn; }
        SetImage(value) { this.check(); this.image = value; }
        SetScaling() { this.check(); }
        DeleteAsync() {
            this.check(); this.children.slice().forEach(child => child.DeleteAsync()); this.deleted = true;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
        }
        set text(value) { this.check(); textWrites++; this.previousText = this._text; this._text = String(value); this.layoutReady = time + layoutDelay; }
        get text() { this.check(); return this._text; }
        get actuallayoutwidth() { this.check(); return this === root ? rootWidth : width(this) * nativeScale; }
        get actuallayoutheight() { this.check(); return this === root ? rootHeight : height(this) * nativeScale; }
        GetPositionWithinWindow() {
            this.check();
            if (this === root) return {x: 0, y: 0};
            if (this === window) return {x: 100, y: 80};
            const at = this.parent.GetPositionWithinWindow();
            const local = String(computed(this).position || '0px 0px').split(/\s+/);
            return {x: at.x + (parseFloat(local[0]) || 0) * nativeScale * fitScale,
                y: at.y + (parseFloat(local[1]) || 0) * nativeScale * fitScale};
        }
        ScrollToBottom() { this.check(); this.scrollOffset = Math.max(0, height(this.children[0]) - height(this)); }
    }
    const root = new Panel('Panel', null, 'Root'), window = new Panel('Panel', root, 'MarketWindow');
    window.style.width = '1120px'; window.style.height = '790px';
    const layer = new Panel('Panel', window, 'Details'); layer.style.width = '1120px'; layer.style.height = '790px';
    function skin(tip, market) {
        if (market) tip.AddClass('BLMarketDetail');
        const surface = new Panel('Panel', tip);
        if (market) surface.AddClass('BLMarketDetailSurface');
        return {surface, Resize(w, h) {
            surface.style.position = market ? '0px 0px 0px' : '24px 24px 0px';
            surface.style.width = (market ? w : w - 48) + 'px'; surface.style.height = (market ? h : h - 48) + 'px';
        }};
    }
    const cfg = {SurvivalUI: {}, SurvivalMenuV10: {SkinTooltip: tip => skin(tip, false)},
        SurvivalBlackLionMarket: {SkinTooltip: tip => skin(tip, true)}};
    const $ = {GetContextPanel: () => root, CreatePanel: (type, parent, id) => new Panel(type, parent, id),
        Schedule(delay, fn) { const value = {id: ++timerId, delay, at: time + delay, fn}; scheduled.push(value); jobs.set(value.id, value); return value.id; },
        CancelScheduled(id) { jobs.delete(id); }};
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg, GetCursorPosition: () => cursor},
        GameEvents: {SendCustomGameEventToServer: (...value) => requests.push(value)}});
    function load(file) {
        let code = fs.readFileSync(path.join(scripts, file), 'utf8');
        if (file === 'common/commerce_components.js') code = sourceTransform(code);
        if (file === 'common/tooltip_dismiss.js') code = dismissTransform(code);
        vm.runInContext(code, context, {filename: file});
    }
    load('common/tooltip_dismiss.js');
    ['common/item_resources.js', 'common/vip_badges.js', 'reward_presentation.js', 'item_art_remaining_5d5c1152eb.js'].forEach(load);
    load('common/commerce_components.js');
    function advance(duration) {
        const end = time + duration; let ticks = 0;
        while (true) {
            const next = [...jobs.values()].filter(value => value.at <= end).sort((a, b) => a.at - b.at || a.id - b.id)[0];
            if (!next) break;
            assert(++ticks < 10000, 'tooltip jobs must not spin'); jobs.delete(next.id); time = next.at; next.fn();
        }
        time = end;
    }
    function bind(item = {}, {market = true, y = 40, rewards = [], effect = '攻击力 +10'} = {}) {
        const card = new Panel('Panel', window);
        card.style.position = '40px ' + y + 'px 0px'; card.style.width = '144px'; card.style.height = '64px';
        const buy = new Panel('Button', card); buy.events.onactivate = () => { if (buy.enabled) checkouts++; };
        const purchase = buy.events.onactivate;
        const props = {market, detailLayer: layer, menu: {Scale: () => fitScale}, sourceWidth: 144,
            windowWidth: 1120, windowHeight: 790, rewards, effect, action: () => checkouts++};
        const data = {sku: 'sample', title: '样例商品', product_type: 'single', description: '配置描述', ...item};
        const tip = cfg.SurvivalCommerceComponents.BindDetail(card, data, props, data.product_type === 'bundle');
        return {card, tip, buy, purchase, surface: tip.Children()[0], props};
    }
    function inside(node, dx = 4, dy = 4) { const at = node.GetPositionWithinWindow(); cursor = [at.x + dx, at.y + dy]; }
    function descendants(node) { return [node, ...node.Children().flatMap(descendants)]; }
    function find(node, cls) { const value = descendants(node).find(node => node.BHasClass(cls)); assert(value, 'missing ' + cls); return value; }
    function hover(entry) { inside(entry.card); entry.card.events.onmouseover(); }
    function dispose(...entries) { entries.forEach(entry => { if (entry.tip.IsValid()) entry.card.__purpleDispose(); }); }
    return {cfg, bind, advance, inside, hover, dispose, descendants, find, jobs, scheduled, requests, computed,
        logicalHeight: height, logicalWidth: width, counters: () => ({created, textWrites}),
        checkoutCount: () => checkouts, setCursor: value => { cursor = value; }, fitScale, nativeScale};
}
module.exports = {harness};
