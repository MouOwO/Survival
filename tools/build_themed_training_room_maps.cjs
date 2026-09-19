// Reuse the approved courtyard navigation/support geometry and daylight exactly.
// Only the output namespace and assets/markers come from each theme's manifests.
const fs=require('fs');
const themes=['wood_training_room','attribute_training_room','greater_attribute_training_room'];
const source=fs.readFileSync(__dirname+'/build_gold_training_room_map.cjs','utf8');
for(const ns of themes){
 const script=source.replaceAll('gold_training_room',ns).replaceAll('gold-training-room',ns.replaceAll('_','-'))
  .replaceAll('gold_room_',ns+'_').replaceAll('GOLD_ROOM_MAP',ns.toUpperCase()+'_MAP');
 new Function('require','__dirname',script)(require,__dirname);
}
