'use strict';
// Reuse the production-source market fixture, with output isolated to this task.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const catalogs=`from pathlib import Path
import json,sys
sys.path.insert(0,str(Path('server').resolve()))
from archive_backend.commerce_catalog import build_catalog
from payment_backend.csv_catalog import build
out=Path('output/shop_promo_gcoin_20261018/catalogs.json');out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps({'wallet':build_catalog(Path.cwd()),'payment':build(Path.cwd())['catalog']},ensure_ascii=False,indent=2),encoding='utf-8')`;
const compiled=cp.spawnSync(process.env.SURVIVAL_PYTHON||'C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe',['-B','-X','utf8','-c',catalogs],{encoding:'utf8',windowsHide:true});
if(compiled.status!==0)throw Error(compiled.stderr||'Read-only formal catalog export failed');
const builder='tools/shop_icon_quality_20261017/preview_market.cjs';
let source=fs.readFileSync(builder,'utf8');
const anchor="const out='output/shop_icon_clarity_20261017/preview';";
if(!source.includes(anchor))throw Error('Production market fixture output anchor changed');
source=source.replace(anchor,"const out='output/shop_promo_gcoin_20261018/preview';");
source=source.replaceAll('output/shop_icon_quality_20261017/catalogs.json','output/shop_promo_gcoin_20261018/catalogs.json');
source=source.replace('商城图标 · 正式 XML / JS / CSS 与后端编译数据 · 本地 VIP12 / 未持有样例 · 非游戏截图','商城促销与 G币 · 实际 XML / JS / CSS · 本地样例 · 非游戏截图');
vm.runInNewContext(source,{require,process,console,__dirname},{filename:builder});
