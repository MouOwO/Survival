'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');
const {images, ready} = require('./fixtures/archive_font_images.cjs');
const sourceFile = path.resolve(__dirname, '../../panorama/src/scripts/custom_game/common/archive_font_v36.js');
const override = process.argv[2] && fs.readFileSync(process.argv[2], 'utf8');
let scenarios = 0;
function load(h) {
    const original = fs.readFileSync;
    try {
        if (override) fs.readFileSync = function(file, ...args) {
            return path.resolve(String(file)) === sourceFile ? override : original.call(this, file, ...args);
        };
        h.load('common/archive_font_v36.js');
    } finally { fs.readFileSync = original; }
    return h.cfg.SurvivalArchiveFontV36;
}
function label(h, id='PendingFont', parent=h.root, value='通关存档 N1') {
    const n = new h.root.constructor('Label', parent, id);
    n.text = value;
    Object.assign(n.style, {fontSize:'21px', color:'#ad9853', width:'180px', height:'29px'});
    return n;
}
function native(n, message) {
    assert.equal(n.style.color, '#ad9853', message);
    const run = n.FindChildTraverse('ArchiveFontV36Glyphs');
    assert(!run || !run.visible, 'No unloaded atlas paints over native text');
}
function scenario(name, fn) { fn(); scenarios++; console.log('PASS ' + name); }

scenario('first paint and one ready atlas retain native text', () => {
    const h=createHarness(), font=load(h), n=label(h);
    font.Render(n); native(n, 'First paint cannot hide the only readable Label');
    const pages=images(h); pages[0].handlers.ImageLoaded();
    native(n, 'Page zero cannot certify page one');
    assert.equal(n.text, '通关存档 N1');
    assert.equal(h.scheduled.length, 0, 'Elapsed time cannot invent readiness');
    assert.equal(h.sent.length, 0);
});
scenario('both load events upgrade current text and preserve stable glyph identity', () => {
    const h=createHarness(), font=load(h), n=label(h);
    font.Render(n); n.text='神兵碎片'; ready(h);
    const run=n.FindChildTraverse('ArchiveFontV36Glyphs');
    assert(run && run.visible); assert.equal(n.style.color, '#ffffff00');
    assert.equal(n.text, '神兵碎片'); assert.equal(run.Children().length, 4);
    const first=run.Children()[0]; font.Render(n); assert.equal(run.Children()[0], first);
});
scenario('failed page remains native despite late loaded event', () => {
    const h=createHarness(), font=load(h), n=label(h);font.Render(n);
    const pages=images(h);pages[0].handlers.ImageLoaded();pages[1].handlers.ImageFailedLoad();
    native(n);pages[1].handlers.ImageLoaded();native(n);
    assert.deepEqual(Array.from(font.Inspect().pages), ['ready','failed']);
});
scenario('failure after conversion restores readable native labels', () => {
    const h=createHarness(),font=load(h),n=label(h);font.Render(n);const pages=ready(h);
    assert.equal(n.style.color,'#ffffff00');pages[0].handlers.ImageFailedLoad();native(n);
});
scenario('native image setup failure falls back despite late ready events', () => {
    const h=createHarness(), proto=h.root.constructor.prototype, original=proto.SetImage;
    proto.SetImage=function(){throw new Error('synthetic engine image setup failure');};
    let font;try {font=load(h);} finally {proto.SetImage=original;}
    const n=label(h);font.Render(n);native(n);
    images(h).forEach(page=>{if(page.handlers&&page.handlers.ImageLoaded)page.handlers.ImageLoaded();});native(n);
    assert.deepEqual(Array.from(font.Inspect().pages),['unavailable','unavailable']);
});
scenario('deleted pending label and tooltip never resurrect stale glyphs', () => {
    const h=createHarness(),font=load(h),gone=label(h,'DeletedFont'),tip=label(h,'NativeTooltip');
    tip.AddClass('ArchiveSharedTooltipText');tip.__archiveTooltipStyle={color:'#ad9853'};
    font.Render(gone);font.Render(tip);gone.DeleteAsync(0);
    assert.doesNotThrow(()=>ready(h));native(tip);
    assert.equal(font.Inspect().labels,0);
});
scenario('foreign HUD is supported and retired owners cannot alter replacement fonts', () => {
    const h=createHarness(),old=load(h),foreign=new h.root.constructor('Panel',null,'OtherHud');
    const n=label(h,'ForeignFont',foreign);old.Render(n);const oldPages=images(h);ready(h);
    assert.equal(n.style.color,'#ffffff00');const fresh=load(h);native(n,'Reload restores native while new owner loads');
    fresh.Render(n);ready(h);assert.equal(n.style.color,'#ffffff00');
    oldPages[0].handlers.ImageFailedLoad();old.Dispose();assert.equal(n.style.color,'#ffffff00');
    assert.equal(h.cfg.SurvivalArchiveFontV36,fresh);fresh.Dispose();native(n);fresh.Dispose();
});
scenario('owner removal and late native events are harmless', () => {
    const h=createHarness(),font=load(h),n=label(h);font.Render(n);const pages=images(h);
    h.root.DeleteAsync(0);
    assert.doesNotThrow(()=>{pages[0].handlers.ImageLoaded();pages[1].handlers.ImageFailedLoad();font.Dispose();font.Dispose();});
    assert.equal(font.Inspect().disposed,true);
});
scenario('unknown glyph fallback and native text color survive loading', () => {
    const h=createHarness(),font=load(h),n=label(h,'Unknown',h.root,'未收录😀');font.Render(n);ready(h);native(n);
    n.text='存档';font.Render(n);n.style.color='#ad9853';font.Render(n);
    const run=n.FindChildTraverse('ArchiveFontV36Glyphs');assert.equal(run.Children()[0].style.washColor,'#ad9853');
});
scenario('category replacement retires deleted labels from the owner registry', () => {
    const h=createHarness(),font=load(h),host=new h.root.constructor('Panel',h.root,'RowReplacement');ready(h);
    for(let round=0;round<5;round++){
        host.RemoveAndDeleteChildren();for(let i=0;i<12;i++)label(h,'Row_'+round+'_'+i,host,'存档');
        font.Scope(host);assert.equal(font.Inspect().labels,12);
    }
    host.RemoveAndDeleteChildren();font.Scope(host);assert.equal(font.Inspect().labels,0);
});
console.log('ARCHIVE_FONT_READINESS_PASS scenarios=' + scenarios + ' real_native_loading_verified=false');
