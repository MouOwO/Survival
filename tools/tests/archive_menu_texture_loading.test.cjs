'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {textureInfo}=require('../test_construction_grid_resources.cjs');
const root=path.resolve(__dirname,'../..');
const registry=JSON.parse(fs.readFileSync(path.join(root,'data/ui/item_resources.json'),'utf8'));
const uris=[...new Set(registry.items.flatMap(row=>[row.uri,row.overlay_uri])
    .filter(uri=>uri&&uri.startsWith('s2r://panorama/images/custom_game/archive_gpu_regular/')))];
assert(uris.length>0,'Registered archive textures are exercised');
for(const uri of uris){
    const relative=uri.slice('s2r://panorama/images/'.length);
    const master=fs.readFileSync(path.join(root,'art/ui/sources',relative),'utf8');
    const source=fs.readFileSync(path.join(root,'panorama/src/images',relative),'utf8');
    assert.equal(source.replace(/\r\n/g,'\n'),master.replace(/\r\n/g,'\n'),uri+': authored recipe mirrors agree');
    assert.match(source,/"m_bNoLod"\s+"bool"\s+"1"/,uri+': full resolution is requested');
    const info=textureInfo(fs.readFileSync(path.join(root,uri.slice(6)+'_c')));
    assert.equal(info.flags&8,8,uri+': actual compiled texture disables LOD');
    assert(info.width>=62&&info.height>=62,uri+': enough source pixels for archive cards');
}
console.log('ARCHIVE_MENU_TEXTURE_LOADING_PASS '+uris.length+' registered textures');
