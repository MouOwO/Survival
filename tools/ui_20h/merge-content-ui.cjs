'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const content='D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival/panorama',source='panorama/src',out='output/ui_20h/content_entry_merge';
fs.mkdirSync(out,{recursive:true});
const entry='layout/custom_game/archive.xml';
fs.writeFileSync(out+'/game_archive.xml',fs.readFileSync(source+'/'+entry));fs.writeFileSync(out+'/content_archive.xml',fs.readFileSync(content+'/'+entry));
let xml=fs.readFileSync(content+'/'+entry,'utf8');
assert(!xml.includes('jade_ui.css')&&!xml.includes('archive_jade.js'));
xml=xml.replace('</styles>','<include src="file://{resources}/styles/custom_game/common/jade_ui.css"/></styles>');
xml=xml.replace('<include src="file://{resources}/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js" />','<include src="file://{resources}/scripts/custom_game/common/jade_components.js"/><include src="file://{resources}/scripts/custom_game/archive_jade.js"/><include src="file://{resources}/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js" />');
assert(xml.includes('title_world_overlap_v30.js')&&xml.includes('native_ui_icons.js'));
fs.writeFileSync(source+'/'+entry,xml);
const imported=[],seen=new Set();
function visit(rel){if(seen.has(rel))return;seen.add(rel);const p=source+'/'+rel;if(!fs.existsSync(p)){const from=content+'/'+rel;assert(fs.existsSync(from),'missing dependency '+rel);fs.mkdirSync(path.dirname(p),{recursive:true});fs.copyFileSync(from,p);imported.push(rel);}if(rel.endsWith('.xml'))for(const m of fs.readFileSync(p,'utf8').matchAll(/file:\/\/\{resources\}\/([^"']+\.(?:xml|css|js))/g))visit(m[1]);}
visit(entry);
fs.writeFileSync(out+'/imported.json',JSON.stringify({preserved:'all merged content title/VIP scripts and original event bindings',added:'shared Jade styles and passive presentation hooks only',imported,at:new Date().toISOString()},null,2));
console.log('CANONICAL_ENTRY_MERGED',imported.length,'previously missing source dependencies');
