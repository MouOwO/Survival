"use strict";
// Exact read-only Dota VPK icons exported for browser preview, not runtime replacements.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),crypto=require("node:crypto"),vm=require("node:vm"),{pathToFileURL}=require("node:url");
const {open}=require("../vpk_inspect.cjs"),{csv}=require("../shop_ui_12h/catalog.cjs");
const root=process.cwd(),base=path.resolve("design_refs/purple_ui_10h/work/native_preview"),viewer=path.resolve("output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe");
fs.mkdirSync(base,{recursive:true});
const native=JSON.parse(fs.readFileSync("panorama/src/images/custom_game/shop_v2/inventory_manifest.json","utf8")).icons;
const shopNames=csv("data/csv/商店系统/shop_entries.csv").filter(r=>r.enabled==="1").map(r=>native[r.content_id]).filter(Boolean).map(e=>e.uri);
const fragmentNames=csv("data/csv/存档系统/archive_item_icons.csv").filter(r=>r.enabled==="1"&&r.category_id==="fragment"&&r.art_status==="valve_native").map(r=>"file://{images}/"+r.icon_path);
const treasureNames=csv("data/csv/肉鸽奖励系统/rogue_reward_cards.csv").filter(r=>r.enabled==="1").slice(0,20).map(r=>"file://{images}/spellicons/"+r.icon_name+".png");
const lotteryNames=["ogre_axe","crimson_guard","mjollnir"].map(name=>"file://{images}/items/"+name+".png");
const commerceCfg={SurvivalUI:{}};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/commerce_components.js","utf8"),{GameUI:{CustomUIConfig:()=>commerceCfg}});
const commerceNames=csv("data/csv/商城兑换系统/commerce_products.csv").filter(p=>p.enabled==="1").map(p=>commerceCfg.SurvivalCommerceComponents.ProductIcon(p)).filter(uri=>/^(items|spellicons)\//.test(uri)).map(uri=>"file://{images}/"+uri);
const names=[...new Set(shopNames.concat(fragmentNames,treasureNames,lotteryNames,commerceNames))];
const vpkFile=path.resolve("../../dota/pak01_dir.vpk"),vpk=open(vpkFile),aliases={},records=[],missing=[];
for(const uri of names){
 const match=/^file:\/\/\{images\}\/((?:items|spellicons|econ)\/[A-Za-z0-9_/-]+)\.png$/.exec(uri);if(!match)continue;
 const resource="panorama/images/"+match[1]+"_png.vtex_c";
 const entry=vpk.entries.find(e=>e.path===resource);if(!entry){if(shopNames.includes(uri))throw Error("Official shop icon unavailable: "+resource);missing.push({uri,resource});continue;}
 const data=vpk.read(entry),name=path.posix.basename(match[1])+(match[1].startsWith("econ/")?"_"+crypto.createHash("sha256").update(resource).digest("hex").slice(0,8):"");
 const compiled=path.join(base,name+"_png.vtex_c"),decoded=path.join(base,name+"_png.png");
 if(!fs.existsSync(decoded)){fs.writeFileSync(compiled,data);cp.execFileSync(viewer,["-i",compiled,"-o",decoded,"-d"],{windowsHide:true,stdio:"pipe"});}
 if(!fs.existsSync(decoded))throw Error("Decoded icon missing: "+decoded);
 aliases[uri]=pathToFileURL(decoded).href;records.push({uri,resource,sha256:crypto.createHash("sha256").update(data).digest("hex"),png:path.relative(root,decoded)});
}
fs.writeFileSync(path.join(base,"manifest.json"),JSON.stringify({kind:"exact_official_dota_vpk_preview_only",aliases,records,missing},null,2));
console.log("NATIVE_PREVIEW_ICONS_EXPORTED "+records.length+" MISSING "+missing.length);if(missing.length)console.log(JSON.stringify(missing));
