'use strict';
// Local crops of actual V10 composite icons, with no native game interaction.
const fs=require('fs'),assert=require('node:assert/strict'),{browser}=require('../shop_ui_12h/cdp.cjs');
const input='design_refs/archive_v10/work/preview/index.html',out='design_refs/archive_v10/work/browser';
async function main(){const b=await browser();try{for(const category of ['endless','titles']){await b.go(input,'?category='+category);assert.equal(await b.run('previewReady'),true);const clip=await b.run(`(()=>{const cards=nodes.ArchiveGrid.Children().filter(c=>c.visible&&c.__v10).slice(0,4),rects=cards.map(c=>c.el.getBoundingClientRect()),x=Math.floor(Math.min(...rects.map(r=>r.x))-4),y=Math.floor(Math.min(...rects.map(r=>r.y))-4),right=Math.ceil(Math.max(...rects.map(r=>r.right))+4),bottom=Math.ceil(Math.max(...rects.map(r=>r.bottom))+4);return {x,y,width:right-x,height:bottom-y};})()`);await b.shot(out+'/category_'+category+'_icons.png',clip);console.log('V10_ICON_CROP '+category);}}finally{b.close();}}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
