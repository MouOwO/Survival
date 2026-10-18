'use strict';
// Exact user PNGs and real production components, offline browser preview only.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/lottery_user_tickets_20261018');
process.chdir(root);fs.mkdirSync(out,{recursive:true});
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const save=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);};
save(path.join(out,'tool_backup/preview.cjs'),fs.readFileSync(__filename));
const records=['normal','special'].map(name=>{
    const png=path.join(root,'panorama/src/images/custom_game/lottery_ticket_user_v1/'+name+'.png');
    const bytes=fs.readFileSync(png);
    return {name,png,uri:'s2r://panorama/images/custom_game/lottery_ticket_user_v1/'+name+'_png.vtex',
        width:bytes.readUInt32BE(16),height:bytes.readUInt32BE(20),sha256:sha(png)};
});
const compileReport=path.join(out,'compile_candidate.json');
if(fs.existsSync(compileReport)){
    const compiled=JSON.parse(fs.readFileSync(compileReport,'utf8').replace(/^\uFEFF/,''));
    for(const row of records){
        const resource=compiled.records.find(item=>item.kind==='texture'&&item.id===row.name);
        if(!resource)continue;
        if(sha(resource.compiled_snapshot)!==resource.compiled_sha256)throw Error('Compiled texture snapshot changed: '+row.name);
        const png=path.join(out,'native_preview',row.name+'.png');fs.mkdirSync(path.dirname(png),{recursive:true});
        const decoded=cp.spawnSync(path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'),
            ['-i',resource.compiled_snapshot,'-o',png,'-d'],{windowsHide:true,encoding:'utf8'});
        row.nativeCompiledSha256=resource.compiled_sha256;row.nativeInfo=resource.native_info;
        if(decoded.status===0&&fs.existsSync(png))row.nativePreviewPng=png;
        else row.nativeDecodeLimitation='Installed Source2Viewer cannot decode the new RED2 KV3 revision; it may return exit 0 without a PNG. Browser uses the exact original user PNG. Native dimensions/alpha are independently verified in compile_candidate.json.';
    }
}
const report={kind:'lottery_user_tickets_offline_browser_preview',gameVerified:false,originalPixelsUnchanged:true,
    sourcePngs:records,geometry:'contain; original alpha; no CSS tint, filter, or wash on ticket pixels',
    fixture:'Ticket balance 20, owned count 0, and shop balance 1234 are explicit isolated samples. Names, prices, grants, and pool definitions come from repository CSV.',screens:[]};
const sheet=path.join(out,'sizes.html'),brown=pathToFileURL(path.join(root,'panorama/src/images/custom_game/shop_v10_v1/window_substrate.png')).href;
save(sheet,`<!doctype html><meta charset="utf-8"><title>抽奖券原图尺寸对照 · 离线</title><style>
*{box-sizing:border-box}body{margin:0;padding:24px;background:#151c22;color:#eee7d6;font:16px "Microsoft YaHei",sans-serif}h1{font-size:26px;margin:0 0 12px}p{color:#bcb7ac;margin:0 0 22px}.grid{display:grid;grid-template-columns:110px repeat(4,1fr);gap:12px;align-items:center}.head{text-align:center;color:#e4d7b9}.cell{height:164px;display:flex;align-items:center;justify-content:center;border:1px solid #766e5c;background:#252c32}.brown{background:#433b30 url("${brown}") center/cover}.cell img{object-fit:contain;display:block}.size{font-size:22px;text-align:center;color:#c8bfae}
</style><h1>用户抽奖券原图 · 128 / 64 / 32 / 24 像素</h1><p>普通/特殊两张原始 RGBA PNG，完整等比显示，保留透明区域。未裁图、重绘或调色；这张图是离线尺寸检查，并非实机截图。</p><main class="grid"><div></div><div class="head">普通券 · 深灰</div><div class="head">特殊券 · 深灰</div><div class="head">普通券 · 灰褐底纹</div><div class="head">特殊券 · 灰褐底纹</div>${[128,64,32,24].map(size=>`<div class="size">${size}px</div>${[0,1,0,1].map((index,column)=>`<div class="cell ${column>1?'brown':''}"><img width="${size}" height="${size}" src="${pathToFileURL(records[index].png).href}"></div>`).join('')}`).join('')}</main>`);
function execute(script,args=[]){
    const result=cp.spawnSync(process.execPath,[script,...args],{cwd:root,encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024});
    if(result.status!==0)throw Error(script+' failed: '+result.stdout+'\n'+result.stderr);
}
function replaceVariable(html,startText,endText,transform){
    const start=html.indexOf(startText)+startText.length;
    if(start<startText.length)throw Error('Missing preview marker '+startText);
    let end=start,depth=0,string=false,escaped=false;
    for(;end<html.length;end++){
        const ch=html[end];
        if(string){if(escaped)escaped=false;else if(ch==='\\')escaped=true;else if(ch==='"')string=false;continue;}
        if(ch==='"')string=true;
        else if(ch==='{'||ch==='[')depth++;
        else if(ch==='}'||ch===']'){depth--;if(depth===0){end++;break;}}
    }
    if(end<=start||depth!==0)throw Error('Unterminated preview object '+startText);
    return html.slice(0,start)+JSON.stringify(transform(JSON.parse(html.slice(start,end)))).replaceAll('</script','<\\/script')+html.slice(end);
}
function aliases(html){
    return replaceVariable(html,'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE=',data=>{
        for(const row of records){const image=pathToFileURL(row.nativePreviewPng||row.png).href;data[row.uri]=image;data['custom_game/lottery_ticket_user_v1/'+row.name+'.png']=image;}
        return data;
    });
}
function localAdapter(folder,html){
    const original=path.join(root,'tools/archive_v10/adapter.js');
    const source=fs.readFileSync(original,'utf8').replace('function cssValue(value){',
        'function cssValue(value){if(typeof value==="string")value=value.replace(/s2r:\\/\\/panorama\\/images\\/[^"\\\')\\s]+\\.vtex/g,function(uri){return PREVIEW_ASSET_PATHS[uri]||uri;});');
    save(path.join(folder,'adapter.js'),source);
    return html.replace(pathToFileURL(original).href,'adapter.js');
}
// Reuse the newest production lottery fixture. Its own base builder is limited
// to this fresh subdirectory and cannot overwrite its earlier review captures.
const lotteryBuild='output/lottery_final_20261018/user_ticket_components';
execute('tools/lottery_final_20261018/preview.cjs',['--out',lotteryBuild]);
const lotteryFolder=path.join(out,'lottery');fs.mkdirSync(lotteryFolder,{recursive:true});
for(const entry of fs.readdirSync(lotteryBuild,{withFileTypes:true}))if(entry.isFile())fs.copyFileSync(path.join(lotteryBuild,entry.name),path.join(lotteryFolder,entry.name));
let lotteryHtml=fs.readFileSync(path.join(lotteryFolder,'index.html'),'utf8');
lotteryHtml=localAdapter(lotteryFolder,aliases(lotteryHtml));
save(path.join(lotteryFolder,'index.html'),lotteryHtml);
// The shop uses the actual row/icon renderer with both real ticket product
// definitions. Only eligibility, balances, and ownership are isolated samples.
const marketFolder=path.join(out,'market');
execute('tools/menus_v10/preview.cjs',['--out',marketFolder]);
let marketHtml=fs.readFileSync(path.join(marketFolder,'index.html'),'utf8');
const allow=new Set(['common/item_resources','ui_snapshot_cache','common/ui_typography','common/ui_registry','common/ui_components',
    'common/tooltip_dismiss','common/reward_feedback','ui_layers','archive_v10_data','common/menu_v10','common/purple_shell',
    'reward_presentation','native_ui_icons','item_art_remaining_5d5c1152eb','reference_windows','remaining_5d5c1152eb',
    'shop_v10_assets','black_lion_market_model','black_lion_market','video_shop_bundles','common/commerce_components',
    'commerce_wallet','commerce_remaining_5d5c1152eb'].map(name=>'scripts/custom_game/'+name+'.js'));
marketHtml=replaceVariable(marketHtml,'window.PREVIEW_LAYOUTS=',';window.PREVIEW_SOURCES=',layouts=>{
    const hud=layouts.find(row=>row.rel==='layout/custom_game/survival_hud.xml');if(!hud)throw Error('Production HUD missing');
    hud.scripts=hud.scripts.filter(file=>allow.has(file));return [hud];
});
marketHtml=replaceVariable(marketHtml,'window.PREVIEW_SOURCES=',';window.PREVIEW_FIXTURE=',sources=>{
    for(const key of Object.keys(sources))if(key.endsWith('.js')&&!allow.has(key))delete sources[key];return sources;
});
const csv=require('../shop_ui_12h/catalog.cjs').csv;
const commerce=csv('data/csv/商城兑换系统/commerce_products.csv').find(row=>row.sku==='video_p001');
const payment=csv('data/csv/商城支付系统/payment_products.csv').find(row=>row.sku==='special_lottery_ticket_single');
if(!commerce||!payment)throw Error('Existing ticket product definitions missing');
const item=(row,price)=>({sku:row.sku,title:row.display_name,description:row.description,category_id:row.category_id,
    product_type:row.product_type,item_id:row.ownership_id,icon:row.icon,sort_order:Number(row.sort_order),
    purchase_limit:Number(row.purchase_limit),owned:0,enabled:1,purchase_method:'cash',currency:'u_coin',currency_name:'G币',
    amount_fen:price,u_coin_price:price,u_coin_per_yuan:100,price,
    reward_lines:[{kind:'item',id:'special_lottery_ticket',quantity:1,label:'特殊抽奖券'}]});
const products=[item(commerce,Number(commerce.price)),item(payment,Math.round(Number(payment.price_yuan)*100))];
marketHtml=replaceVariable(marketHtml,'window.PREVIEW_FIXTURE=',';window.PREVIEW_SOURCE_ROOT=',fixture=>{
    fixture.commerce={paid:{categories:[{id:'item',label:'道具'}],products,catalog_hash:'LOCAL_TWO_REAL_TICKET_PRODUCTS'},
        wallet:{categories:[],products:[],balances:{u_coin:1234,shop_points:0,shop_gold:0}}};return fixture;
});
marketHtml=localAdapter(marketFolder,aliases(marketHtml));
marketHtml=marketHtml.replace('</html>',`<script>window.ticketMarketReady=previewReady.then(async ok=>{if(!ok)return false;cfg.SurvivalCommerceView.UpdateCatalog(PREVIEW_FIXTURE.commerce.paid);cfg.SurvivalCommerceView.UpdateWalletCatalog(PREVIEW_FIXTURE.commerce.wallet);cfg.SurvivalCommerceView.SelectCategory('all');syncLayout();await document.fonts.ready;return true;});</script></html>`);
save(path.join(marketFolder,'index.html'),marketHtml);
report.productSources=[commerce,payment].map(row=>({sku:row.sku,name:row.display_name,configuredPrice:row.price||row.price_yuan,icon:row.icon}));
save(path.join(out,'report.json'),JSON.stringify(report,null,2));
console.log('USER_TICKET_PREVIEWS_BUILT '+out);
if(!process.argv.includes('--capture'))process.exit(0);
const {browser}=require('../lottery_final_20261018/browser.cjs');
const hold=setInterval(()=>{},1000);
(async()=>{
    const b=await browser();
    try{
        await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1080,deviceScaleFactor:1,mobile:false});
        await b.go(sheet);
        const missing=await b.run('[...document.images].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src)');
        if(missing.length)throw Error('Ticket sheet image decode failure '+JSON.stringify(missing));
        await b.shot(path.join(out,'sizes.png'),1600,1080);report.screens.push({name:'sizes',file:'sizes.png',images:16});
        for(const pool of ['map','dragon_knight']){
            await b.go(path.join(lotteryFolder,'index.html'),'?pool='+pool+'&tickets=20');
            if(!await b.run('previewReady'))throw Error('Lottery initialization failed '+JSON.stringify(await b.run('previewErrors')));
            const details=await b.run(`(()=>{syncLayout();const root=nodes.LotteryGW2Root;return{selected:cfg.SurvivalPurpleLottery.Inspect().selected,errors:previewErrors,calls:previewCalls,tickets:Object.values(nodes).filter(n=>/Ticket/.test(n.id)&&n.el).map(n=>({id:n.id,background:n.style.backgroundImage,wash:n.style.washColor,fit:n.style.backgroundSize,text:n.text}))};})()`);
            if(details.errors.length)throw Error('Lottery fixture errors '+JSON.stringify(details.errors));
            if(details.calls.some(call=>/draw_request|purchase|create/.test(call.name||'')))throw Error('Unexpected write request in a read-only fixture');
            details.backgroundImages=await b.run(`(async()=>{const panels=[nodes.LotteryGW2TicketIcon,...nodes.LotterySingleButton.FindChildrenWithClassTraverse('LHDrawTicket'),...nodes.LotteryTenButton.FindChildrenWithClassTraverse('LHDrawTicket')];const result=[];for(const panel of panels){const css=getComputedStyle(panel.el),url=css.backgroundImage.match(/^url\\(["']?(.*?)["']?\\)$/);if(!url)throw Error('No rendered ticket background '+panel.id);const image=new Image();image.src=url[1];await image.decode();const bounds=panel.el.getBoundingClientRect();if(!image.naturalWidth||!bounds.width||!bounds.height||css.display==='none'||css.visibility==='hidden'||css.opacity==='0'||css.maskImage!=='none')throw Error('Ticket background is missing or hidden '+panel.id);result.push({id:panel.id||panel.el.className,url:image.src,decoded:true,width:image.naturalWidth,height:image.naturalHeight,bounds:bounds.toJSON(),mask:css.maskImage});}if(result.length!==3)throw Error('Expected balance, single and ten ticket backgrounds');return result;})()`);
            await b.shot(path.join(out,'lottery_'+pool+'.png'),1600,1080);report.screens.push({name:pool,file:'lottery_'+pool+'.png',...details});
        }
        await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false});
        await b.go(path.join(marketFolder,'index.html'),'?page=commerce');
        if(!await b.run('ticketMarketReady'))throw Error('Shop initialization failed '+JSON.stringify(await b.run('previewErrors')));
        const market=await b.run(`(()=>{syncLayout();const menu=cfg.SurvivalBlackLionMarket.GetWindow();return{errors:previewErrors,rows:menu.content.FindChildrenWithClassTraverse('BLMarketRow').map(row=>({name:row.__menuCell.namePanel.text,icons:[...row.el.querySelectorAll('img')].filter(i=>i.src.includes('lottery_ticket_user_v1')).map(i=>({src:i.src,width:i.naturalWidth,height:i.naturalHeight,decoded:i.complete&&i.naturalWidth>0,fit:getComputedStyle(i).objectFit}))})),calls:previewCalls};})()`);
        if(market.errors.length)throw Error('Shop fixture errors '+JSON.stringify(market.errors));
        if(market.rows.length!==2||market.rows.some(row=>!row.icons.length||row.icons.some(icon=>!icon.decoded||!icon.src.endsWith('/special.png'))))throw Error('Both actual product rows must share the special ticket icon: '+JSON.stringify(market.rows));
        await b.shot(path.join(out,'market_tickets.png'),1600,900);report.screens.push({name:'market',file:'market_tickets.png',...market});
        for(const row of records)if(sha(row.png)!==row.sha256)throw Error('Original ticket PNG was changed');
        report.status='PASS_OFFLINE_BROWSER';
        console.log('USER_TICKET_BROWSER_PASS '+out);
    }catch(error){report.status='FAIL_OFFLINE_BROWSER';report.failure=error.stack||String(error);throw error;}
    finally{save(path.join(out,'report.json'),JSON.stringify(report,null,2));b.close();clearInterval(hold);}
})().catch(error=>{clearInterval(hold);console.error(error);process.exitCode=1;});
