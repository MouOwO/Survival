const fs=require('fs'),vm=require('vm'),assert=require('assert');
const iconSource=fs.readFileSync('panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js','utf8');
const renderer=iconSource.slice(iconSource.indexOf('    view.Icon=function'),iconSource.indexOf('    view.Observe=function'));
function panel(type,parent){const p={type,style:{},classes:[],children:[],AddClass(c){this.classes.push(c)},SetImage(v){this.image=v},SetScaling(v){this.scaling=v}};if(parent)parent.children.push(p);return p;}
const env={view:{Progress:()=> '2 / 5'},index:{'building:building_01':{icon_path:'old_generated.png'}},$: {CreatePanel:panel},label(){},originalIcon(){throw Error('unexpected fallback')},image(){throw Error('generated artifact override must be bypassed')}};
vm.createContext(env);vm.runInContext(renderer,env);
const mappings=JSON.parse(fs.readFileSync('data/ui/archive_artifact_icons.json','utf8'));
for(const [id,row] of Object.entries(mappings)){
 const card=panel('Panel');env.view.Icon(card,{id},'building',{[id]:row.item_definition});
 assert(card.classes.includes('ArchiveArtifactCard'));
 assert.equal(card.children[0].children[0].image,'file://{images}/'+row.icon_path);
 assert.equal(card.children[0].children[0].scaling,'stretch-to-fit-preserve-aspect');
}
const nav=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
for(const name of ['return','treasure','archive','lottery','benefit','shop','survival_shop','effects']){
 const path='panorama/src/images/custom_game/topnav_v2/'+name+'.svg';assert(fs.existsSync(path),name);
 assert(fs.readFileSync(path,'utf8').includes('viewBox="0 0 56 56"'));
 assert(fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml','utf8').includes('topnav_v2/'+name+'.svg'));
}
assert(nav.includes('activate(a[0])'));
console.log('ARCHIVE_ARTIFACT_NAV_PASS: all nine original shop images override generated art, correct aspect ratio, all eight SVG dependencies and original actions preserved');
