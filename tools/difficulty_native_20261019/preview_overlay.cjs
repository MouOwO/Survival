'use strict';
const fs=require('node:fs'),path=require('node:path');
const original=fs.readFileSync,repo=path.resolve(__dirname,'../..');
fs.readFileSync=function(file,options){
 if(typeof file==='string'){
  const relative=path.relative(repo,path.resolve(file)).replaceAll('\\','/');
  if(['panorama/src/scripts/custom_game/survival_ui.js','panorama/src/styles/custom_game/archive_difficulty.css'].includes(relative)){
   return original.call(fs,path.join(__dirname,'owned_after',relative),options);
  }
 }
 return original.call(fs,file,options);
};
