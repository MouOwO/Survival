// Loads the production components into the existing Panorama behavioral harnesses.
const fs=require('fs'),vm=require('vm');
module.exports=function(env,Panel,root){
 const methods={GetParent(){return this.parent},GetChildCount(){return this.children.length},GetChild(i){return this.children[i]},SetImage(path){this.image=path},BHasClass(c){return this.classes.has(c)},IsValid(){return true}};
 for(const [k,v] of Object.entries(methods))if(!Panel.prototype[k])Panel.prototype[k]=v;
 if(!env.$.GetContextPanel)env.$.GetContextPanel=()=>root;
 if(!env.$.DispatchEvent)env.$.DispatchEvent=()=>{};
 for(const name of ['ui_registry','ui_components'])vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/'+name+'.js','utf8'),env);
};
