'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {createHarness}=require('../../tests/fixtures/menus_v10_harness.cjs');
const h=createHarness();h.load('common/vip_badges.js');const badge=h.cfg.SurvivalVIPBadges;
for(let n=1;n<=12;n++)assert.equal(badge.Resolve({id:'vip_privilege_'+String(n).padStart(2,'0')}),n);
for(const value of [null,undefined,'',false,true,-1,0,1.5,13,NaN,Infinity])assert.equal(badge.Level(value),0);
for(const item of [{id:'commerce_video_p044',level:8},{id:'vip_other_10'},{id:'vip_medal_99'},{}])assert.equal(badge.Resolve(item),0,'Only canonical formal VIP identities resolve');
const parent=h.nodes.VIPEmblem.GetParent(),first=badge.Render(parent,12,{width:74,height:74});assert.equal(first.number.text,'12');assert(first.image.image.endsWith('/vip.svg'));const counts={...h.counts};assert.equal(badge.Render(parent,12,{width:74,height:74}),first);assert.deepEqual(h.counts,counts,'The same level does not reallocate or rewrite styles/text');badge.Render(parent,0);assert.equal(first.host.visible,false);badge.Render(parent,1);assert.equal(first.number.text,'1');assert(first.host.visible);
h.load('vip_catalog.js');h.load('vip_window.js');h.setProfile({vip_badge:1});h.net('survival_player_public_profiles','0');h.cfg.SurvivalVIP.Open();
for(const row of h.cfg.VIPRewardCatalog.rewards.filter(x=>x.group_id==='privileges')){const cell=h.nodes['VIPCard_'+row.reward_id].__menuV10Cell;assert.equal(cell.stage.__survivalVIPBadge.number.text,String(row.level));assert.equal(cell.countHost.visible,false,'A VIP level is part of the icon, never a fake quantity');}
h.nodes.VIPCard_vip_privilege_01.events.onmouseover();h.flushFinite();assert(h.nodes.VIPTooltipCondition.text.includes('达标自动赠送一次'));assert(!h.nodes.VIPTooltipCondition.text.includes('手动'));
const conditionFiles=['panorama/src/scripts/custom_game/vip_window.js','panorama/src/scripts/custom_game/common/archive_tooltip.js'];conditionFiles.forEach(file=>assert(fs.readFileSync(file,'utf8').includes('达标自动赠送一次')));
console.log('VIP_BADGE_PASS: 12 formal levels; invalid values; canonical identities; native SVG reuse; stable badge reuse; zero hidden quantities; automatic privilege copy.');
