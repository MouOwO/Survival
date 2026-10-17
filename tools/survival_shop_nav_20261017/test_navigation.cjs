'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {makeFixture,read}=require('./fixture.cjs');
function close(actual, expected, message) { assert(Math.abs(actual - expected) <= 1.1, message + ` (${actual} vs ${expected})`); }
function overlaps(a, b) { return a.x < b.x+b.width && a.x+a.width > b.x && a.y < b.y+b.height && a.y+a.height > b.y; }

test('locked entrance is absent; activation and relocking preserve the top row and original actions', () => {
    const f = makeFixture(), shop = f.entry('survival_shop');
    assert.equal(f.visible(shop), false); f.click(shop); assert.deepEqual(f.actions, []);
    const firstRow = ['return','treasure','archive','lottery','benefit','shop','vip'];
    const lockedPortrait = {...f.rect(f.portrait)};
    const original = Object.fromEntries(firstRow.map(id => [id, {...f.rect(f.entry(id))}]));
    const effects = f.rect(f.currentTop().FindChildTraverse('HandoffCombatEffects'));
    f.unlock(true); assert.equal(f.visible(shop), true); assert.equal(shop.enabled, true);
    f.click(shop); assert.deepEqual(f.actions, ['survival_shop']);
    for (const id of ['treasure','archive','lottery','benefit','shop']) f.click(f.entry(id));
    assert.deepEqual(f.actions, ['survival_shop','treasure','archive','lottery','benefit','shop']);
    f.stack.push('purchase_confirm'); f.click(shop); assert.equal(f.actions.length, 6, 'modal blocks background navigation'); f.stack.pop();
    const a = f.rect(shop), treasure = f.rect(f.entry('treasure'));
    close(a.x+a.width/2, treasure.x+treasure.width/2, 'second-row shop is centered under treasure');
    assert(a.y >= treasure.y + treasure.height, 'shop is fully below top row');
    assert.equal(overlaps(a, f.rect(f.entry('return'))), false);
    const top = f.rect(f.currentTop()), globalShop = {...a,x:a.x+top.x,y:a.y+top.y};
    assert.equal(overlaps(globalShop,f.rect(f.portrait)),false,'hero shortcut moves below the second row');
    assert(f.rect(f.portrait).y>lockedPortrait.y,'activating shop moves the hero shortcut down');
    assert.equal(f.cfg.HandoffWorldOcclusion.length,5,'only the active shop adds a second-row world-label exclusion');
    const exclusion=f.cfg.HandoffWorldOcclusion.at(-1);
    close(exclusion.x,globalShop.x,'world-label exclusion follows shop x');
    close(exclusion.y,globalShop.y,'world-label exclusion follows shop y');
    close(exclusion.width,globalShop.width,'world-label exclusion follows shop width');
    close(exclusion.height,globalShop.height,'world-label exclusion follows shop height');
    for (const id of firstRow) assert.deepEqual(f.rect(f.entry(id)), original[id]);
    assert.deepEqual(f.rect(f.currentTop().FindChildTraverse('HandoffCombatEffects')), effects);
    f.unlock(false); assert.equal(f.visible(shop), false); assert.equal(shop.enabled, false);
    assert.deepEqual(f.rect(f.portrait),lockedPortrait,'relocking returns the hero shortcut to its original row');
    assert.equal(f.cfg.HandoffWorldOcclusion.length,4,'hidden shop leaves no second-row world-label exclusion');
    for (const id of firstRow) assert.deepEqual(f.rect(f.entry(id)), original[id]);
    assert.deepEqual(f.warnings, []);
});

test('collection follows only visible first-row buttons, independent of the lower shop', () => {
    const f = makeFixture(), top = f.rect(f.currentTop()), before = f.rect(f.collection());
    const effects = f.rect(f.currentTop().FindChildTraverse('HandoffCombatEffects'));
    close(before.x, top.x+effects.x+effects.width+2*top.width/630, 'collection follows compacted effects');
    f.unlock(true); f.refreshCollection(); assert.deepEqual(f.rect(f.collection()), before);
    // A wide second-row entry must never push collection out of the first row.
    f.entry('survival_shop').style.position = '800px 140px 0px';
    f.entry('survival_shop').style.width = '300px';
    f.refreshCollection(); assert.deepEqual(f.rect(f.collection()), before);
    f.click(f.collection()); assert.equal(f.actions.at(-1), 'collection');
    f.loadCode(read('collection_nav.js')); f.refreshCollection();
    assert.equal(f.ctx.FindChildTraverse('HandoffHUD').children.filter(p => p.id === 'HandoffNav_collection' && p.IsValid()).length, 1);
    assert.deepEqual(f.rect(f.collection()), before);
    assert.deepEqual(f.warnings, []);
});

test('viewport changes and bounded repair keep the moved shop and compacted top row', () => {
    const f = makeFixture(); f.unlock(true);
    for (const [width,height,pixelScale] of [[960,720,1],[1280,720,1],[1920,1080,1],[2560,1440,1.25],[3440,1440,1]]) {
        f.ctx.actuallayoutwidth=width; f.ctx.actuallayoutheight=height;
        f.ctx.actualuiscale_x=f.ctx.actualuiscale_y=pixelScale;
        f.advance(1200); f.refreshCollection();
        const top=f.rect(f.currentTop()), shop=f.rect(f.entry('survival_shop')), treasure=f.rect(f.entry('treasure'));
        close(shop.x+shop.width/2,treasure.x+treasure.width/2,'pixel-snapped shop center');
        assert(shop.y>=treasure.y+treasure.height-1,'second row stays below first row');
        assert(shop.y+shop.height<=top.height+1,'second row fits navigation host');
        assert.equal(overlaps({...shop,x:shop.x+top.x,y:shop.y+top.y},f.rect(f.portrait)),false,'hero shortcut never overlaps the lower shop');
        const vip=f.rect(f.entry('vip')), market=f.rect(f.entry('shop'));
        const scale=Math.min((width/pixelScale-16)/1672,height/pixelScale/941);
        close(vip.x,Math.round(362*scale*pixelScale)/pixelScale,'VIP fills removed shop space');
        assert(vip.x>=market.x+market.width-1&&vip.x-(market.x+market.width)<4,'first-row spacing stays compact');
        const saved={...shop}; f.advance(1600); assert.deepEqual(f.rect(f.entry('survival_shop')),saved,'periodic repair retains second row');
        const collection=f.rect(f.collection()), effects=f.rect(f.currentTop().FindChildTraverse('HandoffCombatEffects'));
        close(collection.x,top.x+effects.x+effects.width+2*top.width/630,'collection stays next to effects after resize');
        assert(f.visible(f.entry('survival_shop')));
    }
    assert.deepEqual(f.warnings, []);
});

test('HUD replacement retains unlock state and collection reattaches without duplicate entries', () => {
    const f=makeFixture(); f.unlock(true);
    const oldHost=f.ctx.FindChildTraverse('HandoffHUD');
    function remove(panel) {for(const child of panel.children.slice())remove(child); if(panel.IsValid())panel.DeleteAsync();}
    remove(oldHost); const nextHost=new f.Panel('Panel','HandoffHUD',f.ctx);
    f.load(); f.advance(500); f.refreshCollection();
    assert.equal(f.visible(f.entry('survival_shop')),true,'already-active shop is shown on HUD reload');
    assert.equal(f.collection().GetParent(),nextHost);
    assert.equal(nextHost.children.filter(p=>p.id==='HandoffNav_collection'&&p.IsValid()).length,1);
    f.click(f.entry('survival_shop')); assert.equal(f.actions.at(-1),'survival_shop');
    f.unlock(false);assert.equal(f.visible(f.entry('survival_shop')),false);
    assert.deepEqual(f.warnings, []);
});
