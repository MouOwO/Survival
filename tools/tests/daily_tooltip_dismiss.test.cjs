const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
h.setCursor(0,0);h.load('daily_remaining_5d5c1152eb.js');cfg.SurvivalDaily.Open(false);
for(let index=0;index<7;index++){
 const header=nodes['DailyGW2Weekday_'+index];if(!header)continue;
 assert.equal(header.hittest,false,'Weekday headings remain non-interactive');
 assert.equal(header.events.onmouseover,undefined,'Weekday headings do not open a tooltip');
 assert.equal(header.events.onmouseout,undefined,'Weekday headings do not schedule tooltip dismissal');
 assert.equal(header.__dailyGW2Tooltip,undefined,'Weekday headings have no tooltip definition');
}
const first=nodes.DailyGW2Day_1,second=nodes.DailyGW2Day_2,tip=nodes.DailyGW2Tooltip;
first.events.onmouseover();h.flushFinite();assert(tip.visible,'An open daily page keeps its real reward tooltip');
const at=tip.GetPositionWithinWindow();h.setCursor(at.x+10,at.y+10);tip.events.onmouseover();assert(!tip.visible,'Entering the tooltip hides immediately');
first.events.onmouseout();first.events.onmouseover();second.events.onmouseover();h.flushFinite();assert(!tip.visible,'Neither delayed measurement nor another source underneath the dismissed area reopens it');
h.setCursor(0,0);h.flushFinite();first.events.onmouseover();assert(tip.visible,'Leaving the old source and tooltip area permits a new hover');
cfg.SurvivalDaily.Close();h.flushFinite();assert(!tip.visible,'Closing the page invalidates pending tooltip positioning');
const retired=tip.events.onmouseover;cfg.SurvivalDaily.Dispose();assert.doesNotThrow(retired);assert.equal(cfg.SurvivalTooltipDismiss.Inspect().owners,0,'Disposal releases the daily hover policy');
assert(!h.sent.some(row=>/claim|purchase|checkout/.test(row.name)),'Tooltip input never submits a transactional request');
console.log('DAILY_TOOLTIP_DISMISS_PASS: real renderer, immediate hide, old-area suppression, rearm, measurement cancellation and disposal');
