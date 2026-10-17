'use strict';
// Execute the same display-only resolver the live marketplace uses.
const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const root=path.resolve(process.argv[4]||path.join(__dirname,'../..')),file='panorama/src/scripts/custom_game/common/commerce_components.js';
const source=fs.readFileSync(path.join(root,file),'utf8'),cfg={SurvivalUI:{}};
const context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg}});
const resourcesFile='panorama/src/scripts/custom_game/common/item_resources.js';
vm.runInContext(fs.readFileSync(path.join(root,resourcesFile),'utf8'),context,{filename:resourcesFile,timeout:2000});
const artFile='panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js';
const artSource=fs.readFileSync(path.join(root,artFile),'utf8');
vm.runInContext(artSource,context,{filename:artFile,timeout:2000});
vm.runInContext(source,context,{filename:file,timeout:2000});
const bundle=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const catalog=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
const items=[...bundle.configs.commerce_catalog.rows,...catalog.products];
const icons={};
for(const item of items)icons[item.sku]=cfg.SurvivalCommerceComponents.ProductIcon(item);
process.stdout.write(JSON.stringify({resolver:file,resolver_sha256:crypto.createHash('sha256').update(source).digest('hex'),item_art:artFile,item_art_sha256:crypto.createHash('sha256').update(artSource).digest('hex'),icons}));
