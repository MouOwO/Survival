const assert = require('assert'), fs = require('fs'), path = require('path'), vm = require('vm');
const base = path.resolve(__dirname, '../../panorama/src');
const xml = fs.readFileSync(path.join(base, 'layout/custom_game/arcade_multiplayer_test.xml'), 'utf8');
const css = fs.readFileSync(path.join(base, 'styles/custom_game/arcade_multiplayer_test.css'), 'utf8');
const source = fs.readFileSync(path.join(base, 'scripts/custom_game/arcade_multiplayer_test.js'), 'utf8');
let checks = 0;
function check(value, message) { assert.ok(value, message); checks++; }
function harness(options = {}) {
    const ids = {}, schedule = [], callbacks = [], network = [], messages = [], rootNodes = [];
    let map = {map_name: options.map || 'template_map'}, cachedReads = 0;
    class Panel {
        constructor(id, parent) { this.id=id; this.parent=parent; this.children=[]; this.classes={}; this.style={}; this.visible=true; this.hittest=true; this.hittestchildren=true; this.handlers={}; this.text=''; if(parent)parent.children.push(this);else rootNodes.push(this);if(id)ids[id]=this; }
        FindChildTraverse(id) { for(const c of this.children){if(c.id===id)return c;const found=c.FindChildTraverse(id);if(found)return found;}return null; }
        IsValid() { return true; } Children() { return this.children; }
        AddClass(name) { this.classes[name]=true; } SetHasClass(name, value) { this.classes[name]=value; }
        SetPanelEvent(name, fn) { this.handlers[name]=fn; } RemoveAndDeleteChildren() { this.children=[]; }
    }
    const stack=[];
    for (const tag of xml.matchAll(/<(\/?)(Panel|Button|Label)\b([^>]*?)(\/?)>/g)) {
        if(tag[1]){stack.pop();continue;}
        const attrs=Object.fromEntries([...tag[3].matchAll(/(\w+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
        const item=new Panel(attrs.id||'',stack.at(-1));
        for(const c of (attrs.class||'').split(/\s+/).filter(Boolean))item.AddClass(c);
        for(const attr of ['visible','hittest','hittestchildren'])if(attrs[attr])item[attr]=attrs[attr]==='true';
        if(/visibility\s*:\s*collapse/.test(attrs.style||''))item.style.visibility='collapse';
        if(!tag[4])stack.push(item);
    }
    const root=rootNodes[0];
    const ctx={Game:{GetMapInfo(){if(map instanceof Error)throw map;return map;}},Players:{GetPlayerName(id){return 'Host <name> '+id;}},
        GameEvents:{SendCustomGameEventToServer(...args){network.push(args);},SendEventClientSide(...args){network.push(args);}},
        CustomNetTables:{GetTableValue(){cachedReads++;return options.cached;},SubscribeNetTableListener(name,fn){callbacks.push({name,fn});return callbacks.length;},UnsubscribeNetTableListener(){}},
        $:{Msg(message){messages.push(message);},GetContextPanel(){return root;},CreatePanel(type,parent,id){return new Panel(id,parent);},Schedule(seconds,fn){schedule.push(fn);},DispatchEvent(...args){network.push(args);}}};
    if(!options.skipScript)vm.runInNewContext(source,ctx);
    function visible(node){for(let n=node;n;n=n.parent)if(!n.visible||n.style.visibility==='collapse')return false;return true;}
    return {root,ids,network,callbacks,messages,reads(){return cachedReads;},setMap(value){map=value;},monitor(){schedule.shift()();},
        visible(id){return visible(ids[id]);},receive(raw){callbacks[0].fn('survival_arcade_multiplayer_test','state',raw);},
        click(id){ids[id].handlers.onactivate();}};
}
const state={schema_version:1,enabled:1,session_only:1,online_players:2,capacity:4,host_player_id:0,http_phase:'available',sequence:1};
for (const id of ['ArcadeTestCard','ArcadeTestPurchase']) {
    const h=harness({skipScript:true}); h.root.visible=true;
    check(h.ids[id].parent===h.root,'visual children are independent from host context');
    check(!h.visible(id),'actual XML defaults remain hidden without any script');
    check(new RegExp('\\.'+(id==='ArcadeTestCard'?'ArcadeTestCard':'ArcadeTestPurchase')+'\\s*\\{[^}]*visibility:\\s*collapse').test(css),'actual CSS also defaults visual child to collapse');
}
let h=harness({cached:state});h.root.visible=true;
check(!h.visible('ArcadeTestCard')&&!h.root.hittest&&!h.root.hittestchildren,'no fresh server state means transparent inactive HUD');
check(h.reads()===0,'old cached server state is never used as current authorization');
check(!/\.ArcadeTestContext\s*\{[^}]*(?:background|border|box-shadow)/.test(css),'host wrapper paints no overlay');
for(const map of ['ws4_lobby','template_map_extra','maps/template_map','maps/template_map.vpk_extra','']) {
    const test=harness();test.setMap({map_name:map,map_display_name:'template_map'});test.receive(state);test.root.visible=true;
    check(!test.visible('ArcadeTestCard')&&!test.root.hittestchildren,'only exact authoritative template_map can enable card');
}
for(const name of ['template_map','maps/template_map.vpk']) {
    const test=harness({map:name});
    check(!test.visible('ArcadeTestCard'),'both exact native map names still require a new server state');
    test.receive(state);check(test.visible('ArcadeTestCard'),'both exact supported map names display only with full eight-field state');
}
const bad=[null,{},Object.fromEntries(Object.entries(state).filter(([key])=>key!=='sequence')), {...state,sequence:0},{...state,sequence:2147483648},{...state,sequence:1.5},{...state,sequence:'1'}, {...state,schema_version:2},{...state,enabled:0},{...state,enabled:'true'}, {...state,session_only:false}, {...state,online_players:0}, {...state,online_players:5}, {...state,online_players:1.5}, {...state,online_players:NaN}, {...state,capacity:2}, {...state,host_player_id:-2}, {...state,host_player_id:24}, {...state,http_phase:'<script>'}, {...state,http_phase:'__proto__'}, {...state,order_id:'fake'},Object.create(state)];
for(const raw of bad){const test=harness();test.receive(state);test.receive(raw);test.root.visible=true;check(!test.visible('ArcadeTestCard')&&!test.root.hittestchildren,'malformed disabled or unrelated state fails closed');}
h.receive(state);
check(h.visible('ArcadeTestCard')&&h.ids.ArcadeTestPlayers.text==='在线：2 / 4','real server count displayed only after valid state');
check(h.ids.ArcadeTestHost.text==='房主：Host <name> 0','host comes from native player lookup');
h.receive({...state,host_player_id:-1});check(h.ids.ArcadeTestHost.text==='房主：尚未识别','unknown native host is explicitly unknown without inventing player zero');
check(h.ids.ArcadeTestHTTP.text==='HTTP：已收到响应','HTTP response does not claim successful cloud login');
h.click('ArcadeTestToggle');check(!h.visible('ArcadeTestBody')&&h.visible('ArcadeTestCard'),'small card can collapse');
h.click('ArcadeTestToggle');h.click('ArcadeTestPurchaseOpen');
check(h.visible('ArcadeTestPurchase'),'purchase window opens through real UI handler');
check(h.ids.ArcadeTestPrice.text==='配置售价 ¥58.00','formal monthly-pass price shown');
const products=h.ids.ArcadeTestProducts.Children();
check(products.length===3,'only three requested formal SKUs shown');
products[1].handlers.onactivate();check(h.ids.ArcadeTestPrice.text==='配置售价 ¥25.00'&&h.ids.ArcadeTestRewards.text.includes('特殊抽奖券'),'formal ticket selection works');
products[2].handlers.onactivate();check(h.ids.ArcadeTestPrice.text==='配置售价 ¥1.00'&&h.ids.ArcadeTestRewards.text.includes('G币 ×100'),'formal recharge selection works');
h.click('ArcadeTestClose');check(!h.visible('ArcadeTestPurchase'),'purchase window closes');
h.click('ArcadeTestPurchaseOpen');h.click('ArcadeTestScrim');check(!h.visible('ArcadeTestPurchase'),'outside click closes');
h.receive({...state,http_phase:'probing',online_players:1,sequence:2147483647});check(h.ids.ArcadeTestHTTP.text==='HTTP：检测中'&&h.ids.ArcadeTestPlayers.text==='在线：1 / 4','new server diagnostics update real count and stage');
h.click('ArcadeTestPurchaseOpen');h.setMap({map_name:'other_map'});h.monitor();h.root.visible=true;
check(!h.visible('ArcadeTestCard')&&!h.visible('ArcadeTestPurchase')&&!h.root.hittestchildren,'map transition collapses card and active purchase overlay');
h.setMap({map_name:'template_map'});h.monitor();check(!h.visible('ArcadeTestCard'),'return to template map requires a fresh state event');
h.receive(state);h.setMap(new Error('map API unavailable'));h.click('ArcadeTestPurchaseOpen');check(!h.visible('ArcadeTestCard')&&!h.visible('ArcadeTestPurchase'),'button action rechecks map before monitor');
check(h.network.length===0,'opening changing and closing products emits no network order event browser URL or client command');
check(!/SendCustomGameEventToServer|SendEventClientSide|DispatchEvent|CreateHTTPRequest|SendToConsole/.test(source),'preview source has no payment network or command route');
check(xml.includes('尚未连接支付后台，本局不可支付')&&xml.includes('并非实时云报价')&&xml.includes('不创建订单、不收款、不发放奖励'),'preview limits are visible in actual layout');
const diagnosticTest=harness();
check(diagnosticTest.messages.some(x=>x.includes('phase=script_loaded'))&&diagnosticTest.messages.some(x=>x.includes('phase=listener_ready')),'one-time diagnostics prove script and listener stages');
diagnosticTest.receive({...state,http_phase:'SECRET_PAYLOAD'});diagnosticTest.receive({...state,http_phase:'SECRET_PAYLOAD'});
check(diagnosticTest.messages.filter(x=>x.includes('phase=reject_http_phase')).length===1,'repeated rejection diagnostics are bounded to one message per stage');
check(diagnosticTest.messages.some(x=>x.includes('http_phase:string'))&&!diagnosticTest.messages.some(x=>x.includes('SECRET_PAYLOAD')||x.includes('Host <name>')),'diagnostics contain fixed field types without raw values or player names');
diagnosticTest.setMap({map_name:'maps/template_map.vpk\r\n[Injected]'});diagnosticTest.monitor();
check(!diagnosticTest.messages.some(x=>/[\r\n]/.test(x)||x.includes('[Injected]')),'map diagnostics cannot inject lines or brackets');
diagnosticTest.setMap({map_name:'maps/template_map.vpk'});diagnosticTest.receive(state);
check(diagnosticTest.messages.some(x=>x.includes('phase=enabled')&&x.includes('map_name=maps/template_map.vpk')),'diagnostic confirms exact accepted native map path after valid state');
console.log(JSON.stringify({status:'PASS',checks,scope:'Local XML/CSS and mocked Panorama behavior; native visuals and real two-player session NOT_RUN'},null,2));
