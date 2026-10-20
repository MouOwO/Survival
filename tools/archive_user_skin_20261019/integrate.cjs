'use strict';
// Narrow, guarded integration; preserve unrelated concurrent archive changes.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/archive_user_skin_20261019');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const background='        var background=make("Panel",canvas,"ArchiveV10Shell_Background","ArchiveV10Image");pos(background,18,20,narrow(1164),860);background.hittest=false;background.hittestchildren=false;\n        style(background,{backgroundImage:\'url("s2r://panorama/images/custom_game/archive_user_skin_v1/background.vtex")\',backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",backgroundColor:"transparent",opacityMask:\'url("file://{images}/custom_game/archive_user_skin_v1/background_fade.svg")\'});';
const header='        var header=make("Panel",canvas,"ArchiveV10Shell_Header","ArchiveV10Image");pos(header,18,20,narrow(1164),72);header.hittest=false;header.hittestchildren=false;\n        // Back the whole title line, with 14px above and below the live text.\n        style(header,{backgroundImage:"none",backgroundColor:"#090c0ff5",opacityMask:\'url("file://{images}/custom_game/archive_user_skin_v1/right_fade.svg")\'});\n        serif(label(canvas,"存档",53,34,330,44,34,"#fff5d9","left","ArchiveV10WindowTitle"));';
const overlays=[['sidebar_background','sidebarBackground','30,76,sidebarWidth,788','ArchiveV10Shell_Sidebar'],['content_background','contentBackground','contentX(356),76,808,788','ArchiveV10Shell_Content']];
const changes=[];
for(const relative of ['scripts/custom_game/archive_v10.js','styles/custom_game/archive_v10.css']){
 const file=path.join(root,'panorama/src',relative),before=fs.readFileSync(file);let text=before.toString().replaceAll('\r\n','\n');
 if(relative.endsWith('.js')){
  if(!text.includes('archive_user_skin_v1/background.vtex')){
   const old=/^        component\(canvas,"window_background",18,20,narrow\(1164\),860,"ArchiveV10Shell_Background"\);$/m;
   assert(old.test(text),'Expected unchanged archive background boundary');text=text.replace(old,background);
  }
  if(!text.includes('archive_user_skin_v1/right_fade.svg')){
   const old=/^        (?:var header=)?component\(canvas,"header_strip",18,20,narrow\(1164\),56,"ArchiveV10Shell_Header"\);\n(?:        (?:\/\/[^\n]*|style\(header,\{backgroundColor:"#[a-fA-F0-9]+"\}\);)\n)*        serif\(label\(canvas,"存档",53,\d+,330,44,34,"#fff5d9","left","ArchiveV10WindowTitle"\)\);/m;
   assert(old.test(text),'Expected original archive title strip block');text=text.replace(old,header);
  }
  for(const [key,variable,box,id]of overlays){
   const old='        component(canvas,"'+key+'",'+box+',"'+id+'");';
   const replacement='        var '+variable+'=make("Panel",canvas,"'+id+'","ArchiveV10Image");pos('+variable+','+box+');'+variable+'.hittest=false;'+variable+'.hittestchildren=false;style('+variable+',{backgroundImage:"none",backgroundColor:"transparent"});';
   if(text.includes(old))text=text.replace(old,replacement);
   assert(text.includes(replacement),'Old opaque subpanel cannot cover the user background: '+id);
  }
  assert(text.includes(background)&&text.includes(header),'Final title/background integration stays exact');
 }else{
  assert(/#ArchiveV10Shell_Background \{ background-color:[^;]+; \}/.test(text));
  text=text.replace(/#ArchiveV10Shell_Background \{ background-color:[^;]+; \}/,'#ArchiveV10Shell_Background { background-color:transparent; }');
  text=text.replace(/#ArchiveV10Shell_Header \{ background-color:[^;]+; \}/,'#ArchiveV10Shell_Header { background-color:#090c0ff5; }');
  text=text.replace(/#ArchiveV10Shell_Sidebar \{ background-color:[^;]+; \}/,'#ArchiveV10Shell_Sidebar { background-color:transparent; }');
  text=text.replace(/#ArchiveV10Shell_Content \{ background-color:[^;]+; \}/,'#ArchiveV10Shell_Content { background-color:transparent; }');
 }
 if(!before.equals(Buffer.from(text))){
  const backup=path.join(out,'integration_'+Date.now()+'_'+crypto.randomBytes(3).toString('hex'),relative);fs.mkdirSync(path.dirname(backup),{recursive:true});fs.writeFileSync(backup,before);
  assert.equal(sha(fs.readFileSync(file)),sha(before),'Concurrent source changed during integration');fs.writeFileSync(file,text);changes.push(relative);
 }
}
const files=['scripts/custom_game/archive_v10.js','styles/custom_game/archive_v10.css','layout/custom_game/archive_user_skin_assets.xml',...['background.png','background.vtex','background_fade.svg','right_fade.svg'].map(name=>'images/custom_game/archive_user_skin_v1/'+name)].map(relative=>({path:relative,sha256:sha(fs.readFileSync(path.join(root,'panorama/src',relative)))}));
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'compile_plan.json'),JSON.stringify({files},null,2));
console.log('ARCHIVE_USER_SKIN_INTEGRATION_PASS '+JSON.stringify({changes,js:files[0].sha256,css:files[1].sha256}));
