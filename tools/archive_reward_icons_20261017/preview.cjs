'use strict';
// Reuse the existing actual-source assembly in a separate evidence directory.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const out='design_refs/archive_reward_icons_20261017';fs.mkdirSync(out,{recursive:true});
const files=[out+'/native/manifest.json','design_refs/vip_bundle_icons_20261017/native_candidates/manifest.json'];
const aliases={};for(const file of files){for(const row of JSON.parse(fs.readFileSync(file,'utf8')).records){aliases[row.uri]=row.previewPng;if(row.uri.startsWith('file://{images}/'))aliases['s2r://panorama/images/'+row.uri.slice('file://{images}/'.length).replace(/\.png$/,'_png.vtex')]=row.previewPng;}}
const manifest=out+'/native/merged_aliases.json';fs.writeFileSync(manifest,JSON.stringify({kind:'exact_installed_dota_native_preview_only',aliases},null,2)+'\n');
let code=fs.readFileSync('tools/vip_bundle_icons_20261017/preview.cjs','utf8');
code=code.replaceAll('design_refs/vip_bundle_icons_20261017/preview',out+'/preview');
code=code.replace("if(previewState.page==='archive'){","if(previewState.page==='archive'&&params.get('category')==='commerce_goods'){");
code=code.replace("cfg.SurvivalCommerceView.SelectCategory('vip');","cfg.SurvivalCommerceView.SelectCategory(params.get('category')||'bundles');");
code=code.replace("const group=scope==='badges'?'privileges':'packages';","const group=['privileges','medals','packages'].includes(scope)?scope:scope==='badges'?'privileges':'packages';");
code=code.replace('VIP 礼包图标 · 实际 XML / JS / CSS','星悦 / VIP / 礼包图标 · 实际 XML / JS / CSS');
const temporary=out+'/preview_impl.cjs';fs.writeFileSync(temporary,code);
const source=crypto.createHash('sha256').update(fs.readFileSync('data/ui/item_resources.json')).digest('hex');
const result=cp.spawnSync(process.execPath,[temporary,'--expected-hash',source,'--native-aliases',manifest],{encoding:'utf8',windowsHide:true});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);if(result.status!==0)process.exit(result.status||1);
