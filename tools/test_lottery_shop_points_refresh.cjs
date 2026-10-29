"use strict";
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const loader=fs.readFileSync('tools/test_lottery_updates.cjs','utf8').split('suite+=')[0];
const checks=String.raw`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
config.SurvivalPurpleLottery={Version:'lottery_current_20261018',Owns(owner){return owner===root;},IsAlive(){return true;},IsReady(){return true;},Open(){},Close(){},Apply(){},Snapshot(){},Fit(){return true;}};
const walletReads=[];
config.SurvivalCommerceWallet={Invalidate:key=>{walletReads.push(key);return true;},Refresh:()=>{throw Error('Invalidate-capable wallet must use queued API');}};
function data(){return {...snapshot('map',99),shop_points:825,starjoy_points:17};}
function textOf(p){return [p.text||'',...p.children.map(textOf)].join(' ');}
ui.Open();events.ui_lottery_snapshot(data());nodes.LotterySkipAnimation.checked=true;ui.SetSkipAnimation();
ui.DrawSingle();const q=requests.filter(r=>r.n==='ui_lottery_draw_request').at(-1).p;
const result={ok:1,request_id:q.request_id,pool_id:'map',count:1,results:[{id:'ssr',name:'重复SSR',quality:'ssr',duplicate:true,converted_points:400,converted_currency:'shop_points'}],snapshot:data()};
ui.Close();events.ui_lottery_result(result);advance(0);
assert.equal(walletReads.length,1,'successful hidden result must invalidate wallet outside animation');
events.ui_lottery_result(result);advance(20);assert.equal(walletReads.length,1,'duplicate result must not refresh again');
ui.Open();ui.Feature('history');
assert(textOf(nodes.LotteryInfoList).includes('400 商城积分'),'history must name the newly credited shop currency');
ui.CloseInfo();ui.CloseResult();ui.DrawSingle();const legacy=requests.filter(r=>r.n==='ui_lottery_draw_request').at(-1).p;
events.ui_lottery_result({...result,request_id:legacy.request_id,results:[{id:'old',name:'旧版本奖励',quality:'sr',duplicate:true,converted_points:100}]});ui.SkipReveal();advance(0);
ui.Feature('history');assert(textOf(nodes.LotteryInfoList).includes('100 曙光积分'),'legacy starjoy receipt keeps its currency and uses the approved display name');
assert(!textOf(nodes.LotteryInfoList).includes('100 商城积分'),'renaming the label cannot convert a legacy receipt into shop points');
ui.CloseInfo();ui.CloseResult();ui.DrawSingle();const failed=requests.filter(r=>r.n==='ui_lottery_draw_request').at(-1).p;
events.ui_lottery_result({ok:0,request_id:failed.request_id,error:'lottery_ticket_insufficient',snapshot:data()});advance(0);assert.equal(walletReads.length,2,'failure does not invalidate wallet');
ui.CloseResult();ui.DrawSingle();const unmatched=requests.filter(r=>r.n==='ui_lottery_draw_request').at(-1).p;
events.ui_lottery_result({...result,request_id:'unmatched_request'});advance(0);assert.equal(walletReads.length,2,'foreign receipt cannot cause account refresh');
config.SurvivalCommerceWallet=null;events.ui_lottery_result({...result,request_id:unmatched.request_id});advance(0);
config.SurvivalCommerceWallet={Invalidate:key=>{walletReads.push(key);return true;}};
advance(2);assert.equal(walletReads.length,3,'late-loaded wallet receives bounded retry');
ui.Dispose();advance(60);assert.equal(walletReads.length,3,'disposed callbacks cannot send refresh');
console.log('LOTTERY_SHOP_POINTS_REFRESH_PASS: hidden success, receipt dedup, explicit shop vs legacy starjoy, failure/mismatch, late wallet and dispose');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(checks)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});',{require:require('node:module').createRequire(path.resolve(__filename)),console});
