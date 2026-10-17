const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const scripts = path.resolve(__dirname, '../../panorama/src/scripts/custom_game');
function harness(options = {}) {
    const requests = [], clientEvents = [], subscriptions = new Map(), timers = [], paidCheckouts = [];
    class Panel {
        constructor(type, parent, id = '') {
            this.paneltype = type; this.id = id; this.parent = null; this.children = [];
            this.style = {}; this.events = {}; this.classes = new Set(); this.attrs = {};
            this.visible = true; this.enabled = true; this.actualuiscale_x = this.actualuiscale_y = 1;
            this.SetParent(parent);
        }
        IsValid() { return !this.deleted; }
        AddClass(v) { this.classes.add(v); }
        RemoveClass(v) { this.classes.delete(v); }
        BHasClass(v) { return this.classes.has(v); }
        SetHasClass(v, on) { on ? this.AddClass(v) : this.RemoveClass(v); }
        GetParent() { return this.parent; }
        SetParent(parent) {
            if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this);
            this.parent = parent; if (parent) parent.children.push(this);
        }
        Children() { return this.children; }
        GetChild(i) { return this.children[i]; }
        GetChildCount() { return this.children.length; }
        FindChildTraverse(id) { return this.id === id ? this : this.children.map(c => c.FindChildTraverse(id)).find(Boolean); }
        SetPanelEvent(name, fn) { this.events[name] = fn; }
        SetImage(uri) { this.image = uri; }
        SetScaling(v) { this.scaling = v; }
        SetFocus() {}
        SetAcceptsFocus() {}
        SetAttributeString(k, v) { this.attrs[k] = v; }
        GetAttributeString(k, fallback) { return this.attrs[k] === undefined ? fallback : this.attrs[k]; }
        GetPositionWithinWindow() { return {x: 450, y: 240}; }
        RemoveAndDeleteChildren() { this.children.slice().forEach(c => c.DeleteAsync()); }
        DeleteAsync() { this.children.slice().forEach(c => c.DeleteAsync()); this.deleted = true; this.SetParent(null); }
    }
    const root = new Panel('Panel', null, 'TestRoot');
    root.actuallayoutwidth = 1672; root.actuallayoutheight = 941;
    const cfg = {SurvivalShopPresentation:options.presentation||{groups:{home:['paid_1']}}};
    function $(id) { return root.FindChildTraverse(id.replace(/^#/, '')); }
    $.GetContextPanel = () => root;
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.Schedule = (delay, fn) => { const id = timers.length; timers.push({delay, fn}); return id; };
    $.CancelScheduled = id => { if (timers[id]) timers[id].cancelled = true; };
    $.RegisterEventHandler = $.RegisterForUnhandledEvent = $.DispatchEvent = $.Msg = () => {};
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetLocalPlayerID: () => 0, IsInToolsMode: () => false, GetGameTime: () => 1},
        GameEvents: {Subscribe(name, fn) { const list = subscriptions.get(name) || []; list.push(fn); subscriptions.set(name, list); return fn; },
            Unsubscribe(fn) { for (const [name, list] of subscriptions) subscriptions.set(name, list.filter(v => v !== fn)); },
            SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); },
            SendEventClientSide(name, payload) { clientEvents.push({name, payload}); }},
        CustomNetTables: {GetTableValue: () => null}});
    const load = file => vm.runInContext(fs.readFileSync(path.join(scripts, file), 'utf8'), context, {filename: file});
    ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js', 'remaining_5d5c1152eb.js',
        'archive_v10_data.js', 'common/menu_v10.js', 'black_lion_market_model.js', 'black_lion_market.js',
        'common/commerce_components.js', 'commerce_wallet.js'].forEach(load);
    let paid = options.paid || {products: [{sku:'paid_1',title:'真实商品',category_id:'technology',product_type:'single',icon:'items/rapier.png',
        enabled:true,amount_fen:900,reward_lines:[{id:'initial_gold',kind:'stat',label:'初始金币',quantity:10}]}],
        categories:[{id:'technology',label:'科技与服务'}]};
    cfg.SurvivalPayments = {GetCatalog: () => paid, RefreshCatalog() {}, Checkout(sku) { paidCheckouts.push(sku); return true; }};
    if(options.homeCatalogFixture!==false){
        // Keep legacy synthetic presentation fixtures separate from the reviewed home catalog.
        const fixtureHome = ((cfg.SurvivalShopPresentation.groups || {}).home || []).slice();
        cfg.SurvivalShopHomeCatalog = {
            List() { return fixtureHome.slice(); },
            Compose(products, listed) {
                const rows = Array.isArray(products) ? products : [];
                return fixtureHome.map(sku => rows.find(item => item && item.sku === sku))
                    .filter(item => item && typeof listed === 'function' && listed(item));
            }
        };
    }
    load('commerce_remaining_5d5c1152eb.js');
    function emit(name, data) { for (const fn of subscriptions.get(name) || []) fn(JSON.parse(JSON.stringify(data))); }
    function walletSnapshot(products, balances = {u_coin:12,shop_points:500,shop_gold:9}) {
        cfg.SurvivalCommerceWallet.Refresh();
        const request = requests.findLast(r => r.name === 'survival_commerce_request' && r.payload.action === 'catalog');
        assert(request, 'The existing catalog request must be used');
        const base = {request_id: request.payload.request_id, action:'catalog',ok:1};
        emit('survival_commerce_result', {...base,part:'begin',count:products.length,categories:[{id:'item',label:'道具与材料'}],balances});
        products.forEach((product, i) => emit('survival_commerce_result', {...base,part:'product',index:i+1,product}));
        emit('survival_commerce_result', {...base,part:'end'});
    }
    const menus = () => cfg.SurvivalMenuV10.Entries();
    const store = () => cfg.SurvivalBlackLionMarket.GetWindow();
    const cardList = () => store().content.Children()[0].Children();
    const descendants = (p, cls) => [p, ...p.Children().flatMap(c => descendants(c, cls))].filter(n => n.BHasClass(cls));
    return {cfg,root,requests,clientEvents,paidCheckouts,walletSnapshot,menus,store,cardList,descendants,timers,emit,load,
        get paid(){return paid;},updatePaid(data){paid=data;cfg.SurvivalCommerceView.UpdateCatalog(paid);}};
}
function walletItem(i) {
    return {sku:'wallet_'+i,title:'积分装备 '+i,category_id:'item',product_type:'single',icon:'items/rapier.png',
        enabled:1,owned:0,purchase_method:'wallet',currency:'shop_points',currency_name:'积分',price:10,
        purchase_limit:0,description:'攻击力 +10',reward_lines:[{id:'attack',kind:'stat',label:'攻击力',quantity:10}]};
}

module.exports={harness,walletItem};
