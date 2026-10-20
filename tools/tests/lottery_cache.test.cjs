"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), vm = require("node:vm"), crypto = require("node:crypto");
const source = fs.readFileSync("panorama/src/scripts/custom_game/common/lottery_cache.js", "utf8");
const md5 = value => crypto.createHash("md5").update(value).digest("hex");
const hash = "a".repeat(64), nextHash = "b".repeat(64);
const ids = ["map", "cultivation", "dragon_knight", "summer"];
function catalog(revision="r1", name="实际奖励") {
    const pools = ids.map(id => ({id, revision, display_name:id, description:"公开说明", ticket_content_id:id==="map"?"lottery_ticket":"special_lottery_ticket", single_cost:1,ten_cost:10,pity:[{label:"十连保底 UR"}]}));
    return {schema:1,snapshots:pools.map(pool => ({selected_pool_id:pool.id,selected_pool:pool,pools,items:[{id:"reward",quality:"ur",name,description:"真实效果",max_owned:1}]}))};
}
function encode(data, configHash=hash) {
    // The generator publishes an ASCII canonical JSON string, not a second
    // JSON serialization of the parsed JavaScript object.
    const raw=JSON.stringify(data).replace(/[\u007f-\uffff]/g,c=>"\\u"+c.charCodeAt(0).toString(16).padStart(4,"0"));
    return {catalog_json:raw,md5:md5(raw),config_hash:configHash};
}
function fixture(seed=encode(catalog()), initial={session_id:"session1",setup:{mode_id:"standard"}}) {
    const config={SurvivalLotteryCatalogSeed:seed},handlers={},requests=[],queue=[],logs=[];
    let state=initial,account="76561198000000000",clock=0,subscription=0;
    const tables=new Map();
    const env={GameUI:{CustomUIConfig:()=>config},Game:{GetLocalPlayerInfo:()=>({player_steamid:account})},
        $:{Schedule:(seconds,fn)=>queue.push({at:clock+seconds,fn}),Msg:x=>logs.push(x)},
        CustomNetTables:{GetTableValue:()=>state,SubscribeNetTableListener:(name,fn)=>{const id=++subscription;tables.set(id,fn);return id;},UnsubscribeNetTableListener:id=>tables.delete(id)},
        GameEvents:{Subscribe:(name,fn)=>{const id=++subscription;(handlers[name] ||=new Map()).set(id,fn);return id;},Unsubscribe:id=>Object.values(handlers).forEach(map=>map.delete(id)),SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}};
    vm.createContext(env);
    vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/ui_snapshot_cache.js","utf8"),env);
    const load=()=>{vm.runInContext(source,env);return config.SurvivalLotteryCache;};
    const emit=(name,packet)=>{for(const fn of [...(handlers[name]?.values() || [])])fn(packet);};
    const stamp=(snapshot,options={})=>({...snapshot,session_id:state.session_id,account_id:String(BigInt(account)&0xffffffffn),profile_mode:state.setup.mode_id==="pure"?"pure":"standard",config_hash:config.SurvivalLotteryCache.Catalog().config_hash,catalog_md5:config.SurvivalLotteryCache.Catalog().md5,...options});
    const dynamic=(id="map",tickets=20,options={})=>stamp({...catalog(options.revision || "r1").snapshots.find(p=>p.selected_pool_id===id),selected_pool:{...catalog(options.revision || "r1").snapshots.find(p=>p.selected_pool_id===id).selected_pool,tickets,unlocked:true,unlock_progress:100,update_unread:true},items:[{id:"reward",owned_count:1,owned:true,at_max_owned:true}],shop_points:250,...options});
    function advance(seconds){const end=clock+seconds;while(true){queue.sort((a,b)=>a.at-b.at);if(!queue.length || queue[0].at>end)break;const next=queue.shift();clock=next.at;next.fn();}clock=end;}
    function transfer(seed,transferId="transfer1",sequence=1) {
        const chunks=[];for(let i=0;i<seed.catalog_json.length;i+=1000)chunks.push(seed.catalog_json.slice(i,i+1000));
        return chunks.map((catalog_chunk,index)=>({ok:1,unchanged:0,catalog_md5:seed.md5,config_hash:seed.config_hash,transfer_id:transferId,chunk:index+1,chunks:chunks.length,catalog_chunk,catalog_sequence:sequence,session_id:state.session_id}));
    }
    const api=load();
    return {api,config,env,requests,logs,load,emit,stamp,dynamic,advance,transfer,setState(value){state=value;for(const fn of tables.values())fn("survival_loading","state",state);},setAccount(value){account=value;for(const fn of tables.values())fn("survival_loading","state",state);}};
}

test("RFC 1321 vectors, UTF-8, block boundaries and malformed surrogates",()=>{
    const h=fixture();
    const vectors=["","a","abc","message digest","abcdefghijklmnopqrstuvwxyz","ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789","12345678901234567890123456789012345678901234567890123456789012345678901234567890","奖池珍藏 🎟️","\ud800x\udc00"];
    for(const n of [55,56,57,63,64,65,127,128,129,8192])vectors.push("x".repeat(n));
    for(const value of vectors)assert.equal(h.api.MD5(value),md5(value),JSON.stringify(value.slice(0,50)));
});

test("login handshake is independent of the renderer; seed displays immediately with drawing blocked",()=>{
    const h=fixture();assert.equal(h.requests.length,1);assert.equal(h.requests[0].name,"ui_lottery_catalog_sync");assert.equal(h.requests[0].payload.md5,encode(catalog()).md5);
    for(const id of ids){const view=h.api.Snapshot(id);assert.equal(view.items[0].name,"实际奖励");assert.equal(view.authoritative_ready,false);assert.equal(view.selected_pool.tickets,0);assert.equal(h.api.IsAuthoritative(id),false);}
    h.emit("ui_lottery_catalog",{ok:1,unchanged:1,catalog_md5:h.api.Catalog().md5,config_hash:hash,catalog_sequence:1,session_id:"session1"});
    const before=h.config.SurvivalLotteryCacheState.catalog;
    h.api.Refresh();h.api.Snapshot("summer");assert.equal(h.requests.length,1,"local reads do not request snapshots or catalogues");
    h.load();assert.strictEqual(h.config.SurvivalLotteryCacheState.catalog,before,"same MD5 and module reload retain the already parsed local catalogue");assert.equal(h.requests.length,1);
});

test("startup session arrival initiates synchronization before any lottery presentation exists",()=>{
    const h=fixture(encode(catalog()),null);assert.equal(h.requests.length,0);
    h.setState({session_id:"session1",setup:{mode_id:""}});assert.equal(h.requests.length,1);
    h.setState({session_id:"session1",setup:{mode_id:"standard"}});assert.equal(h.requests.length,1,"mode selection does not download the same static catalogue again");
});

test("lost startup replies recover in the background and a module reload does not repeat the handshake",()=>{
    const h=fixture();h.load();assert.equal(h.requests.filter(r=>r.name==="ui_lottery_catalog_sync").length,1);
    h.advance(3.1);assert.equal(h.requests.filter(r=>r.name==="ui_lottery_cache_resync").length,1);
    assert.equal(h.requests.at(-1).payload.md5,h.api.Catalog().md5,"recovery includes the local digest so missing catalogue fragments can be retransmitted");
    h.emit("ui_lottery_catalog",{ok:1,unchanged:1,catalog_md5:h.api.Catalog().md5,config_hash:hash,catalog_sequence:1,session_id:"session1"});
    h.emit("ui_lottery_snapshot",h.dynamic("map",20,{snapshot_scope:"cache",cache_sequence:1}));
    const before=h.requests.length;h.advance(6);assert.equal(h.requests.length,before,"complete static and dynamic replies stop the recovery timer");
});

test("authoritative overlays preserve published static data and update ordinary main/transaction snapshots",()=>{
    const h=fixture();const packet=h.dynamic();packet.items[0].name="unverified static override";packet.selected_pool.display_name="unverified heading";
    assert.equal(h.api.Ingest(packet),true);assert.equal(h.api.IsAuthoritative("map"),true);
    const view=h.api.Snapshot("map");assert.equal(view.items[0].name,"实际奖励");assert.equal(view.selected_pool.display_name,"map");assert.equal(view.items[0].owned_count,1);assert.equal(view.selected_pool.tickets,20);assert.equal(view.shop_points,250);
    view.items[0].name="mutated caller copy";assert.equal(h.api.Snapshot("map").items[0].name,"实际奖励");
    h.api.Ingest(h.dynamic("map",19));assert.equal(h.api.Snapshot("map").selected_pool.tickets,19,"main/transaction snapshots update the shared cache, not only cache-scoped pushes");
    h.load();assert.equal(h.config.SurvivalLotteryCache.Snapshot("map").selected_pool.tickets,19);assert.equal(h.config.SurvivalLotteryCache.IsAuthoritative("map"),true);
});

test("session, account, profile mode, content hash and revision reject stale dynamic data",()=>{
    const h=fixture();const good=h.dynamic();h.api.Ingest(good);
    for(const override of [{session_id:"old-session"},{account_id:"other-account"},{profile_mode:"pure"},{config_hash:nextHash},{catalog_md5:"c".repeat(32)}])assert.equal(h.api.Ingest({...good,...override}),false);
    assert.equal(h.api.Snapshot("map").selected_pool.tickets,20);
    h.setState({session_id:"session1",setup:{mode_id:"pure"}});assert.equal(h.api.IsAuthoritative("map"),false);assert.equal(h.api.Ingest(good),false);
    const pure=h.dynamic("map",7);h.api.Ingest(pure);assert.equal(h.api.Snapshot("map").selected_pool.tickets,7);
    h.setAccount("76561198000000001");assert.equal(h.api.IsAuthoritative("map"),false);assert.equal(h.api.Ingest(pure),false);
    h.setState({session_id:"session2",setup:{mode_id:"pure"}});assert.equal(h.api.Ingest(good),false);assert.equal(h.api.Snapshot("map").items[0].name,"实际奖励","static public content survives identity changes");
    const mismatch=h.dynamic("map",100,{revision:"r2"});assert.equal(h.api.Ingest(mismatch),false);assert(h.requests.some(r=>r.name==="ui_lottery_cache_resync"));
});

test("the production SteamID64 client identity matches the provider's lossless 32-bit SteamAccountID",()=>{
    const h=fixture();
    assert.equal(h.config.SurvivalLotteryCacheState.identity.account,"39734272","76561198000000000 maps to the HTTP provider's SteamAccountID");
    const realPacket={...h.dynamic(),account_id:"39734272"};
    assert.equal(h.api.Ingest(realPacket),true);assert.equal(h.api.IsAuthoritative("map"),true);
    assert.equal(h.api.Ingest({...realPacket,account_id:"39734273"}),false,"another account's private balance is rejected");
    assert.equal(h.api.Ingest({...realPacket,account_id:"76561198000000000"}),false,"the wire contract remains the provider's 32-bit identity");
    h.setAccount("76561198000000001");assert.equal(h.config.SurvivalLotteryCacheState.identity.account,"39734273");assert.equal(h.api.Ingest(realPacket),false);
    for(const value of ["39734272",39734272]){h.setAccount(value);assert.equal(h.config.SurvivalLotteryCacheState.identity.account,"39734272");assert.equal(h.api.Ingest(realPacket),true);}
    h.setAccount("76561197960265729");assert.equal(h.config.SurvivalLotteryCacheState.identity.account,"1","account IDs below the double-precision SteamID64 increment boundary stay exact");
});

test("new catalogue fragments commit atomically after MD5 validation, including out-of-order delivery",()=>{
    const h=fixture();h.api.Ingest(h.dynamic());
    const replacement=encode(catalog("r2","更新后物品"),nextHash),packets=h.transfer(replacement,"version2",2);
    for(const packet of packets.slice(1).reverse())h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Snapshot("map").items[0].name,"实际奖励","partial content is never rendered");assert.equal(h.api.IsAuthoritative("map"),true);
    h.emit("ui_lottery_catalog",packets[0]);assert.equal(h.api.Catalog().md5,replacement.md5);assert.equal(h.api.Snapshot("map").items[0].name,"更新后物品");assert.equal(h.api.IsAuthoritative("map"),false,"old ownership and balances cannot enable a new configuration");
    assert.equal(h.api.Ingest(h.dynamic("map",12,{revision:"r2"})),true);assert.equal(h.api.IsAuthoritative("map"),true);
    for(const packet of h.transfer(encode(catalog()),"late-version1",1))h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Catalog().md5,replacement.md5,"late older versions cannot roll back a committed update");
    h.load();assert.equal(h.config.SurvivalLotteryCache.Catalog().md5,replacement.md5,"re-running the packed seed cannot overwrite a verified hot catalogue");
});

test("same public MD5 with a new settlement hash invalidates authority; old-session catalogues are ignored",()=>{
    const h=fixture();h.api.Ingest(h.dynamic());const original=h.config.SurvivalLotteryCacheState.catalog;
    h.emit("ui_lottery_catalog",{ok:1,unchanged:1,catalog_md5:h.api.Catalog().md5,config_hash:nextHash,catalog_sequence:2,session_id:"session1"});
    assert.strictEqual(h.config.SurvivalLotteryCacheState.catalog,original);assert.equal(h.api.Catalog().config_hash,nextHash);assert.equal(h.api.IsAuthoritative("map"),false);
    h.api.Ingest(h.dynamic("map",8));assert.equal(h.api.IsAuthoritative("map"),true);
    const next=encode(catalog("r2","更新后物品"),nextHash);
    for(const packet of h.transfer(next,"conflicting-same-version",2))h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Snapshot("map").items[0].name,"实际奖励","one server version cannot carry two catalogue hashes");
    h.setState({session_id:"session2",setup:{mode_id:"standard"}});
    for(const packet of h.transfer(next,"old-room",50))h.emit("ui_lottery_catalog",{...packet,session_id:"session1"});
    assert.equal(h.api.Snapshot("map").items[0].name,"实际奖励");
    for(const packet of h.transfer(next,"new-room",1))h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Snapshot("map").items[0].name,"更新后物品","sequence numbers reset for a new room");
});

test("observing a trusted new hash blocks old-config drawing until the catalogue and dynamic state agree",()=>{
    const h=fixture();for(const id of ids)h.api.Ingest(h.dynamic(id));
    const stale=h.dynamic("map",21);
    h.emit("ui_lottery_snapshot",{...h.dynamic("map",22),config_hash:nextHash});
    for(const id of ids)assert.equal(h.api.IsAuthoritative(id),false,"the old settlement configuration is blocked for every pool");
    assert.equal(h.api.Ingest(stale),false,"a delayed old-hash push cannot reopen drawing while the new catalogue is pending");
    h.emit("ui_lottery_catalog",{ok:1,unchanged:1,catalog_md5:h.api.Catalog().md5,config_hash:nextHash,catalog_sequence:2,session_id:"session1"});
    h.api.Ingest(h.dynamic("map",22));assert.equal(h.api.IsAuthoritative("map"),true);
    assert.equal(h.api.Ingest(stale),false);assert.equal(h.api.IsAuthoritative("map"),true,"known retired hashes are ignored without disabling the newer valid balance");
});

test("an older transfer cannot interrupt a newer catalogue already being assembled",()=>{
    const h=fixture(),newer=encode(catalog("r3","新一版"),nextHash);
    const packets=h.transfer(newer,"new-transfer",3);h.emit("ui_lottery_catalog",packets[0]);
    for(const packet of h.transfer(encode(catalog("r2","旧一版"),nextHash),"late-transfer",2))h.emit("ui_lottery_catalog",packet);
    for(const packet of packets.slice(1))h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Snapshot("map").items[0].name,"新一版");
});

test("invalid MD5 and incomplete transfers preserve the last complete catalogue and recover in the background",()=>{
    const h=fixture(),original=h.api.Catalog().md5, replacement=encode(catalog("r2","new"),nextHash);
    const broken=h.transfer(replacement,"broken",2);broken[0].catalog_chunk=broken[0].catalog_chunk.replace("schema","invalid_schema");
    for(const packet of broken)h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Catalog().md5,original);assert.equal(h.requests.filter(r=>r.name==="ui_lottery_cache_resync").length,1);
    const incomplete=h.transfer(replacement,"missing-fragment",2);h.emit("ui_lottery_catalog",incomplete[0]);h.advance(3.1);
    assert.equal(h.api.Catalog().md5,original);assert(!h.requests.some(r=>r.name==="ui_lottery_snapshot_request"));
    h.advance(2);assert(h.requests.filter(r=>r.name==="ui_lottery_cache_resync").length>=2,"a lost background recovery reply is retried without reopening the UI");
});

test("oversized, contradictory and malformed fragments cannot replace the catalogue",()=>{
    const h=fixture(),original=h.api.Catalog().md5,replacement=encode(catalog("r2","new"),nextHash);
    const valid=h.transfer(replacement,"oversize",2)[0];
    for(const packet of [{...valid,catalog_chunk:"x".repeat(3501)},{...valid,chunk:0},{...valid,chunks:1025},{...valid,chunk:1.5},{...valid,config_hash:"invalid"},{...valid,session_id:"other-room"}])h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Catalog().md5,original);
    const duplicate=h.transfer(replacement,"contradiction",2);h.emit("ui_lottery_catalog",duplicate[0]);h.emit("ui_lottery_catalog",{...duplicate[0],catalog_chunk:duplicate[0].catalog_chunk+"x"});
    for(const packet of duplicate.slice(1))h.emit("ui_lottery_catalog",packet);
    assert.equal(h.api.Catalog().md5,original,"conflicting copies retire the whole transfer");
});

test("cache patch chunks are atomic and sequence/baseline errors resynchronize outside the interface",()=>{
    const h=fixture();h.api.Ingest(h.dynamic("map",20,{snapshot_scope:"cache",cache_sequence:1}));
    const patch=(chunk,changes,options={})=>h.stamp({selected_pool_id:"map",snapshot_scope:"cache_patch",cache_sequence:2,base_sequence:1,chunk,chunks:2,changes,...options});
    h.emit("ui_lottery_snapshot",patch(2,[{path:["items","1","owned_count"],value:0}]));assert.equal(h.api.Snapshot("map").selected_pool.tickets,20);
    h.emit("ui_lottery_snapshot",patch(1,[{path:["selected_pool","tickets"],value:18}]));assert.equal(h.api.Snapshot("map").selected_pool.tickets,18);assert.equal(h.api.Snapshot("map").items[0].owned_count,0);
    h.emit("ui_lottery_snapshot",patch(1,[],{cache_sequence:1,chunks:1}));assert.equal(h.api.Snapshot("map").selected_pool.tickets,18,"duplicate or old patches do not regress balances");
    h.emit("ui_lottery_snapshot",patch(1,[],{cache_sequence:3,base_sequence:999,chunks:1}));assert.equal(h.api.Snapshot("map").selected_pool.tickets,18);assert(h.requests.some(r=>r.name==="ui_lottery_cache_resync"));
    h.api.Ingest(h.dynamic("map",17,{snapshot_scope:"cache",cache_sequence:4}));assert.equal(h.api.Snapshot("map").selected_pool.tickets,17);
});

test("a delayed read receipt never rolls back a newer ticket or ownership push",()=>{
    const h=fixture();h.api.Ingest(h.dynamic("map",10,{snapshot_scope:"cache",cache_sequence:1}));
    const old=h.dynamic("map",20,{snapshot_scope:"read"});old.selected_pool.update_unread=false;old.items[0].owned_count=0;
    h.api.Ingest(old);assert.equal(h.api.Snapshot("map").selected_pool.tickets,10);assert.equal(h.api.Snapshot("map").items[0].owned_count,1);assert.equal(h.api.Snapshot("map").selected_pool.update_unread,false);
    h.api.Ingest({...old,read_error:"read_save_failed"});assert.equal(h.api.IsAuthoritative("map"),true,"an unread-flag write failure does not invalidate the wallet");
    h.emit("ui_lottery_snapshot",h.stamp({selected_pool_id:"map",snapshot_scope:"cache_patch",cache_sequence:2,base_sequence:1,chunk:1,chunks:1,changes:[{path:["selected_pool","tickets"],value:9}]}));
    assert.equal(h.api.Snapshot("map").selected_pool.tickets,9,"read acknowledgements preserve the delta baseline");
});

test("late transaction snapshots cannot overwrite a newer cache version or an incomplete patch baseline",()=>{
    const h=fixture();h.api.Ingest(h.dynamic("map",10,{snapshot_scope:"cache",cache_sequence:3}));
    assert.equal(h.api.Ingest(h.dynamic("map",20,{cache_sequence:2})),false);
    assert.equal(h.api.Ingest(h.dynamic("map",99)),false,"unversioned production snapshots cannot replace an established version");
    assert.equal(h.api.Snapshot("map").selected_pool.tickets,10);
    assert.equal(h.api.Ingest(h.dynamic("map",9,{cache_sequence:4})),true);
    h.emit("ui_lottery_snapshot",h.stamp({selected_pool_id:"map",snapshot_scope:"cache_patch",cache_sequence:5,base_sequence:4,chunk:1,chunks:1,changes:[{path:["selected_pool","tickets"],value:8}]}));
    assert.equal(h.api.Snapshot("map").selected_pool.tickets,8,"a transaction receipt can establish the next authoritative patch baseline");
});

test("unknown or malformed balances cannot authorize even a free draw",()=>{
    const h=fixture();for(const tickets of [undefined,null,"20",-1,0.5,NaN]){const packet=h.dynamic("map",0);packet.selected_pool.tickets=tickets;packet.selected_pool.single_cost=0;h.api.Ingest(packet);assert.equal(h.api.IsAuthoritative("map"),false);}
    h.api.Ingest(h.dynamic("map",0));assert.equal(h.api.IsAuthoritative("map"),true);
});

test("errors keep local content, suspend drawing and restore authority after a valid push",()=>{
    const h=fixture();h.api.Ingest(h.dynamic());
    h.api.Ingest(h.stamp({selected_pool_id:"map",error:"archive_config_mismatch"}));
    assert.equal(h.api.Snapshot("map").items[0].name,"实际奖励");assert.equal(h.api.Snapshot("map").selected_pool.tickets,20);assert.equal(h.api.IsAuthoritative("map"),false);
    h.api.Ingest(h.dynamic("map",19));assert.equal(h.api.IsAuthoritative("map"),true);
    h.api.Invalidate("map");assert.equal(h.api.IsAuthoritative("map"),false);assert(h.requests.some(r=>r.name==="ui_lottery_cache_resync"));
});

test("dedicated read acknowledgements never request display contents",()=>{
    const h=fixture();h.api.ReadAck({id:"map",revision:"r1"},"details");
    assert.equal(h.requests.at(-1).name,"ui_lottery_read_ack");assert.deepEqual(JSON.parse(JSON.stringify(h.requests.at(-1).payload)),{pool_id:"map",read_action:"details",revision:"r1"});
    assert(!h.requests.some(r=>r.name==="ui_lottery_snapshot_request"));
});

test("the generated local seed has a verified digest and is loaded before the cache/controller",()=>{
    const config={};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/lottery_catalog_seed.js","utf8"),{GameUI:{CustomUIConfig:()=>config}});
    const seed=config.SurvivalLotteryCatalogSeed;assert.equal(seed.md5,md5(seed.catalog_json));assert(/^[\x00-\x7f]+$/.test(seed.catalog_json));
    const h=fixture(seed);assert.deepEqual(JSON.parse(JSON.stringify(h.api.Catalog().pools)).sort(),ids.slice().sort());
    for(const id of ids){assert(h.api.Snapshot(id).items.length>0);assert.equal(h.api.IsAuthoritative(id),false);}
    const xml=fs.readFileSync("panorama/src/layout/custom_game/survival_hud.xml","utf8");
    assert(xml.indexOf("lottery_catalog_seed.js")<xml.indexOf("common/lottery_cache.js"));assert(xml.indexOf("common/lottery_cache.js")<xml.indexOf("lottery_ui_remaining_5d5c1152eb.js"));
    const controller=fs.readFileSync("panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js","utf8");
    assert(!controller.includes("ui_lottery_snapshot_request"));assert(!controller.includes("正在切换奖池"));assert(!controller.includes("正在读取"));
});
