'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {browser}=require('../archive_blackgold_refine_20261019/browser.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/archive_row_stripes_20261020');
const inspect=`(()=>{
 const cards=nodes.ArchiveGrid.Children().filter(p=>p.visible&&p.__v10&&p.__archiveCategory===previewState.category);
 const walk=p=>[p,...p.Children().flatMap(walk)];
 return {errors:previewErrors.slice(),calls:previewCalls.length,rows:cards.map(p=>{
 const back=walk(p).find(c=>c.BHasClass('ArchiveParchmentRowBacking'));
 return {name:p.__v10.name.text,count:p.__v10.count.text,
 rect:[p.style.position,p.style.width,p.style.height],
 paint:back?{color:back.style.backgroundColor,opacity:back.style.opacity}:null};
 })};
})()`;
async function run(){
 const b=await browser({output:out}),report=[];
 try{
  for(const [width,height]of [[1600,900],[1280,720]]){
   await b.viewport(width,height);
   await b.go(path.join(root,'output/archive_blackgold_refine_20261019/preview/index.html'),'?category=clear');
   assert(await b.run('previewReady'));
   for(const category of ['clear','endless','work','points']){
    await b.run(`previewSelect(${JSON.stringify(category)})`);
    for(const mode of ['all','locked','unlocked']){
     await b.run(`cfg.SurvivalArchive.Filter('${mode}');syncLayout()`);
     const before=await b.run(inspect);
     assert.deepEqual(before.errors,[]);
     const rows=before.rows.filter(r=>r.paint);
     if(category==='points')assert.equal(rows.length,0,'Do not stripe the item grid');
     rows.forEach((r,i)=>{
      assert.equal(r.paint.opacity,'1');
      assert(r.paint.color.includes(i%2?'#191e19':'#363c30'),'Visible row parity starts light');
     });
     await b.run('cfg.SurvivalArchiveBlackGold.Apply();syncLayout()');
     assert.deepEqual(await b.run(inspect),before,'Repaint preserves data, geometry, parity and event count');
     report.push({width,height,category,mode,rows:rows.length});
     if(category==='clear'&&mode==='all'){
      assert(rows.length>=5);
      await b.shot(path.join(out,`clear_${width}.png`),{x:0,y:0,width,height});
     }
    }
   }
  }
  fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify({status:'PASS',nativeCapture:false,cases:report},null,2));
  console.log('ARCHIVE_ROW_STRIPES_PASS '+report.length+' cases; browser preview, not game capture');
 }finally{await b.close();}
}
run().catch(e=>{console.error(e);process.exitCode=1;});
