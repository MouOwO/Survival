"use strict";
const fs=require("node:fs"),path=require("node:path"),{pathToFileURL}=require("node:url");
const {csv,fixture}=require("../shop_ui_12h/catalog.cjs");
const out="design_refs/purple_ui_10h/work/shop_preview";fs.mkdirSync(out,{recursive:true});
const uri=p=>pathToFileURL(path.resolve(p)).href;
function gradient(s){return s.replace(/gradient\(linear,[^;{}]*?from\((#[0-9a-f]+)\),(?:color-stop\([^)]*\),)*to\((#[0-9a-f]+)\)\)/gi,"linear-gradient(180deg,$1,$2)");}
function css(file){
 let s=fs.readFileSync(file,"utf8");const defs={};s=s.replace(/@define\s+(\w+):\s*([^;]+);/g,(_,k,v)=>{defs[k]=v;return "";});for(const[k,v]of Object.entries(defs))s=s.replace(new RegExp("\\b"+k+"\\b","g"),v);
 s=gradient(s).replace(/background-color:\s*(linear-gradient\([^;{}]+\))/g,"background:$1").replaceAll("file://{images}/",uri("panorama/src/images")+"/");
 s=s.replace(/\bLabel\b/g,".label").replace(/\bImage\b/g,"img").replace(/\bButton\b/g,".button").replaceAll(":selected",".Selected").replaceAll(":disabled",".UIDisabled");
 s=s.replace(/position:\s*(-?[\d.]+px)\s+(-?[\d.]+px)\s+0px/g,"position:absolute;left:$1;top:$2");
 s=s.replace(/flow-children:\s*(none|right-wrap|right|down)/g,(_,v)=>v==="none"?"display:block":`display:flex;flex-direction:${v==="down"?"column":"row"};${v==="right-wrap"?"flex-wrap:wrap":""}`);
 s=s.replace(/width:\s*fill-parent-flow\(1\)/g,"flex:1;min-width:0");
 s=s.replace(/overflow:\s*squish scroll/g,"overflow-x:hidden;overflow-y:auto").replace(/overflow:\s*scroll squish/g,"overflow-x:auto;overflow-y:hidden").replace(/overflow:\s*noclip/g,"overflow:visible").replace(/overflow:\s*clip/g,"overflow:hidden");
 s=s.replace(/visibility:\s*collapse/g,"display:none").replace(/visibility:\s*visible/g,"display:block;visibility:visible").replace(/(width|height):\s*fit-children/g,"$1:max-content");
 s=s.replace(/align:\s*center center/g,"left:50%;top:50%;transform:translate(-50%,-50%)").replace(/align:\s*left top/g,"transform:none").replace(/align:\s*right top/g,"left:auto;right:0;top:0;transform:none");
 s=s.replace(/horizontal-align:\s*center/g,"left:50%;transform:translateX(-50%)").replace(/horizontal-align:\s*right/g,"left:auto;right:0").replace(/vertical-align:\s*center/g,"top:50%;transform:translateY(-50%)").replace(/vertical-align:\s*bottom/g,"top:auto;bottom:0");
 return s.replace(/text-overflow:\s*shrink/g,"text-overflow:ellipsis;overflow:hidden").replace(/brightness:\s*([\d.]+)/g,"filter:brightness($1)").replace(/text-shadow:[^;]+/g,"text-shadow:0 1px 3px #050309").replace(/box-shadow:[^;]+/g,"box-shadow:0 2px 9px #0006").replace(/ignore-parent-flow:\s*true/g,"--pano-ignore-flow:true");
}
const native=JSON.parse(fs.readFileSync("panorama/src/images/custom_game/shop_v2/inventory_manifest.json","utf8")).icons;
const aliases={};
for(const entry of Object.values(native)){
 const candidate="spellicons/survival/native/"+entry.name+".png";
 if(fs.existsSync("panorama/src/images/"+candidate))aliases[entry.uri]=candidate;
}
for(const file of fs.readdirSync("panorama/src/images/spellicons/survival/native"))if(file.endsWith(".png")){
 aliases["file://{images}/items/"+file]="spellicons/survival/native/"+file;
 aliases["file://{images}/spellicons/"+file]="spellicons/survival/native/"+file;
}
const officialManifest="design_refs/purple_ui_10h/work/native_preview/manifest.json";
if(fs.existsSync(officialManifest))Object.assign(aliases,JSON.parse(fs.readFileSync(officialManifest,"utf8")).aliases);
const entries=csv("data/csv/商店系统/shop_entries.csv").filter(r=>r.enabled==="1").map((r,i)=>({
 entry_id:r.shop_entry_id,shop_id:r.category_id,content_id:r.content_id,content_type:r.category_id==="weapon"?"weapon":r.category_id==="rebirth"?"rebirth":r.category_id==="challenge"?"challenge":"item",
 name:r.display_name,description:r.notes,gold_cost:Number(r.gold_cost),wood_cost:Number(r.wood_cost),purchase_limit:Number(r.purchase_limit),stock_max:Number(r.stock_max),stock:Number(r.stock_max)||0,owned_count:0,sort_order:i,visible:1,purchasable:1,
 icon:(native[r.content_id]||{}).name?(native[r.content_id].type==="ability"?"":"item_")+native[r.content_id].name:"item_branches",icon_type:(native[r.content_id]||{}).type||"item"
}));
const hud=fs.readFileSync("panorama/src/layout/custom_game/survival_hud.xml","utf8");
const shopXML="<root>"+hud.slice(hud.indexOf('<Panel id="ShopBackdrop"'),hud.indexOf('<Panel id="CustomAbilityTooltip"'))+"</root>";
const commonStyles=["common/ui_components.css","common/ui_typography.css","remaining_5d5c1152eb.css","reference_windows.css"];
const shellCSS="panorama/src/styles/custom_game/common/purple_shell.css",shellJS="panorama/src/scripts/custom_game/common/purple_shell.js";
for(const mode of ["shop","commerce"]){
 const styles=[...commonStyles,...(mode==="shop"?["shop.css","shop_purple.css"]:["common/commerce_purple.css"])];
 if(fs.existsSync(shellCSS))styles.push("common/purple_shell.css");
 fs.writeFileSync(out+"/"+mode+".css",styles.map(s=>css("panorama/src/styles/custom_game/"+s)).join("\n"));
 const scripts=["common/ui_registry.js","ui_layers.js","common/ui_components.js",...(fs.existsSync(shellJS)?["common/purple_shell.js"]:[])];
 if(mode==="shop")scripts.push("reference_windows.js","remaining_5d5c1152eb.js","native_ui_icons.js","item_art_remaining_5d5c1152eb.js","shop_tooltip_remaining_5d5c1152eb.js","shop_remaining_5d5c1152eb.js");
 else scripts.push("reference_windows.js","remaining_5d5c1152eb.js","common/commerce_components.js","commerce_remaining_5d5c1152eb.js");
 const font=uri("design_refs/shop_ui_12h/fonts/SourceHanSansSC-Regular.otf");
 const backdrop=uri("design_refs/ui_20h/work/baseline/battle_no_queue.png");
 const extra=`*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden}body{background:#201631 url('${backdrop}') center/cover;font-family:Han}body:before{content:"";position:absolute;inset:0;background:#09051099;pointer-events:none}.panel{position:absolute;flex-shrink:0}.panel[hidden]{display:none!important}.label{display:block;font-family:Han;font-weight:400;pointer-events:none}.button{cursor:pointer}img{object-fit:contain}.Hidden,.UIClosed{display:none!important}#PreviewRoot{inset:0;width:100%;height:100%}.UIModal{isolation:isolate}.UIModalInputShield{pointer-events:none}.CommercePurple .RCPurpleDetail>.panel,#ShopEntryTooltip>.panel{position:relative;left:auto;top:auto;transform:none}.CommercePurple .RCPurpleDetail>.label,#ShopEntryTooltip>.label{position:relative;left:auto;top:auto;transform:none}#ShopTooltipTitleBlock{position:relative!important;left:auto!important;top:auto!important;transform:none!important}#ShopTooltipTitleBlock>.label{position:relative;left:auto;top:auto;transform:none}#ShopItemList{align-content:flex-start}#ShopHeader{background:none!important}#ShopModeToggles>.panel{position:relative;left:auto;top:auto;transform:none}.preview-caption{position:fixed;left:8px;bottom:8px;padding:4px 8px;background:#1b1232;color:#d8c2ef;font:12px Han;z-index:1000000}@font-face{font-family:Han;src:url('${font}')}@font-face{font-family:"Source Han Sans SC";src:url('${font}')}`;
 const data=`window.IMAGE_ROOT=${JSON.stringify(uri("panorama/src/images")+"/")};window.CATALOG_FIXTURE=${JSON.stringify(fixture())};window.IMAGE_ALIASES=${JSON.stringify(aliases)};window.SHOP_FIXTURE=${JSON.stringify(entries)};window.SHOP_XML=${JSON.stringify(shopXML)};window.PREVIEW_MODE=${JSON.stringify(mode)};`;
 const after=mode==="shop"?'cfg.SurvivalShop.SetUnlocks({shop:true});cfg.SurvivalShop.Open();previewShopTab(new URLSearchParams(location.search).get("category")||"equipment");':'cfg.SurvivalCommerceView.Open();selectCategory(new URLSearchParams(location.search).get("category")||"technology");';
 fs.writeFileSync(out+"/"+mode+".html",`<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="${mode}.css"><style>${extra}</style><div id="PreviewRoot"></div><div class="preview-caption">真实生产组件 · 本地 CSV 只读展示，示例状态 · 未连接账号、游戏或支付</div><script>${data}</script><script src="${uri("tools/shop_ui_12h/adapter.js")}"></script><script src="${uri("tools/purple_ui_10h/shop_preview_adapter.js")}"></script>${scripts.map(s=>'<script src="'+uri("panorama/src/scripts/custom_game/"+s)+'"></script>').join("")}<script>${after}syncFlows();</script>`);
}
console.log("PURPLE_SHOP_PREVIEW_BUILT "+path.resolve(out));
module.exports={css};

for(const mode of ["shop","commerce"])fs.appendFileSync(out+"/"+mode+".html",`<style>.CommercePurple .RCPurpleDetail:not(.Visible){display:none!important}.CommercePurple .RCPurpleDetail.Visible{display:flex!important}.ShopStockLabel{left:auto!important;right:3px!important;width:max-content!important}.ShopCardName{display:block!important}#CustomShopWindow.ShopPurple .ShopShelfSlot{box-shadow:none!important;background:none!important}</style>`);
for(const mode of ["shop","commerce"])fs.appendFileSync(out+"/"+mode+".html",`<style>.PurpleShell #ShopHeader{display:block!important}.PurpleClose{left:auto!important;right:9px!important}.PurpleCornerTR,.PurpleCornerBR{left:auto!important;right:0!important}.PurpleCornerBL,.PurpleCornerBR{top:auto!important;bottom:0!important}.PurpleTabIcon{left:50%!important;transform:translateX(-50%)!important}</style>`);
