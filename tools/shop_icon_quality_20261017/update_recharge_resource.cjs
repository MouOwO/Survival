'use strict';
const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const file='data/ui/item_resources.json',before=fs.readFileSync(file),table=JSON.parse(before),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const row=table.items.find(r=>r.id==='u_coin_recharge');assert(row);
const native=JSON.parse(fs.readFileSync('output/shop_icon_quality_20261017/native/manifest.json')).records.find(r=>r.uri==='file://{images}/econ/tools/compendium_2015_charm_coins_750.png');assert(native);
const old=JSON.parse(JSON.stringify(row));row.uri=native.uri;row.source_size=[native.width,native.height];
assert.equal(hash(fs.readFileSync(file)),hash(before),'Concurrent resource edit');fs.writeFileSync(file,JSON.stringify(table,null,2)+'\n');
fs.writeFileSync('output/shop_icon_quality_20261017/recharge_resource_change.json',JSON.stringify({id:row.id,before:old,after:row,native,previousHash:hash(before),newHash:hash(fs.readFileSync(file)),review:'Exact native gold coin stacks; no pixel-art coin, no low-resolution screenshot'},null,2)+'\n');
console.log(hash(fs.readFileSync(file)));
