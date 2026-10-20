'use strict';
// Read-only audit of configured archive images and shipped texture payloads.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=process.cwd(),out=path.join(root,'output/archive_images_audit_20261018');
const {textureInfo}=require(path.join(root,'tools/test_construction_grid_resources.cjs'));
const vpk=require(path.join(root,'tools/vpk_inspect.cjs')).open(path.resolve(root,'../../dota/pak01_dir.vpk'));
const packedIndex=new Map(vpk.entries.map(row=>[row.path,row]));
const fixture=require(path.join(root,'tools/archive_v10/fixture.cjs')).fixture();
const registry=JSON.parse(fs.readFileSync(path.join(root,'data/ui/item_resources.json'),'utf8'));
const index=new Map();for(const row of registry.items)for(const key of [row.id,...(row.aliases||[])])index.set(key,row);
const aliases={};for(const file of ['design_refs/purple_ui_10h/work/native_preview/manifest.json','design_refs/archive_v10/work/native_icons/manifest.json','design_refs/archive_v10/work/icon_map_v11/native_aliases.json'])if(fs.existsSync(file))Object.assign(aliases,JSON.parse(fs.readFileSync(file,'utf8')).aliases||{});
function dimensions(file){try{const b=fs.readFileSync(file);if(b.subarray(0,8).toString('hex')==='89504e470d0a1a0a')return [b.readUInt32BE(16),b.readUInt32BE(20)];if(path.extname(file)==='.svg'){const s=b.toString(),v=s.match(/viewBox=["']([^"']+)/);if(v)return v[1].split(/[ ,]+/).slice(2).map(Number);}return null;}catch{return null;}}
function existing(paths){return paths.find(p=>fs.existsSync(p));}
function relative(p){return p?path.relative(root,p).replaceAll('\\','/'):null;}
function sourceFor(uri){if(!uri)return null;const key=uri.replace(/^file:\/\/\{images\}\//,'').replace(/^s2r:\/\/panorama\/images\//,'');const png=key.endsWith('.vtex')?key.replace(/\.vtex$/,'.png'):key;return existing([path.join(root,'panorama/src/images',png),path.join(root,'art/ui/sources',png)]);}
function compiledFor(uri){const p=uri.startsWith('s2r://')?uri.slice(6)+'_c':uri.startsWith('file://{images}/')?'panorama/images/'+uri.slice(16).replace(/\.([^.]+)$/,'_$1.vtex_c'):null;return p?existing([path.join(root,p)]):null;}
function texture(uri){
 const runtime=compiledFor(uri),source=sourceFor(uri),record={uri,source:relative(source),source_size:source&&dimensions(source),runtime:relative(runtime)};
 if(runtime){try{const b=fs.readFileSync(runtime),t=textureInfo(b);Object.assign(record,{runtime_size:[t.width,t.height],format:t.format,format_name:({1:'DXT1',2:'DXT5',28:'BGRA8888'})[t.format]||String(t.format),mips:t.mipLevels,no_lod:!!(t.flags&8),payload_bytes:t.payload.length,runtime_sha256:crypto.createHash('sha256').update(b).digest('hex')});}catch(error){record.runtime_error=String(error);}}
 if(!runtime){const packed=uri.startsWith('s2r://')?uri.slice(6)+'_c':uri.startsWith('file://{images}/')?'panorama/images/'+uri.slice(16).replace(/\.([^.]+)$/,'_$1.vtex_c'):null;const entry=packed&&packedIndex.get(packed);if(entry){try{const bytes=vpk.read(entry),t=textureInfo(bytes);Object.assign(record,{packaged_resource:packed,runtime_size:[t.width,t.height],format:t.format,format_name:({1:'DXT1',2:'DXT5',28:'BGRA8888'})[t.format]||'native_'+t.format,mips:t.mipLevels,no_lod:!!(t.flags&8),payload_bytes:t.payload.length,runtime_sha256:crypto.createHash('sha256').update(bytes).digest('hex')});}catch(error){record.packaged_error=String(error);}}else record.packaged_missing=!source;}
 const key=uri.replace(/^s2r:\/\/panorama\/images\//,'').replace(/^file:\/\/\{images\}\//,'').replace(/\.png$/,'.vtex');
 const recipe=existing([path.join(root,'panorama/src/images',key),path.join(root,'art/ui/sources',key)]);
 if(recipe){record.recipe=relative(recipe);const text=fs.readFileSync(recipe,'utf8'),p=text.match(/"m_fileName"\s+"string"\s+"([^"]+)"/);if(p){record.recipe_input=p[1];const rel=p[1].replace(/^panorama\/images\//,''),input=existing([path.join(root,'panorama/src/images',rel),path.join(root,'art/ui/sources',rel)]);record.recipe_source=relative(input);record.recipe_source_size=input&&dimensions(input);record.recipe_missing_source=!input;}}
 const a=aliases[uri];if(a){record.preview_alias=a;try{const file=a.startsWith('file:')?require('node:url').fileURLToPath(a):a;record.preview_alias_size=dimensions(file);}catch{}}
 return record;
}
const unique=new Map(),categories={},unmapped=[];
for(const [category,items]of Object.entries(fixture.pages)){
 const rows=[];for(const item of items){const resource=index.get(item.id);if(!resource){unmapped.push({category,id:item.id,name:item.name,icon:item.icon});continue;}const uri=resource.uri;if(uri&&!unique.has(uri))unique.set(uri,texture(uri));if(resource.overlay_uri&&!unique.has(resource.overlay_uri))unique.set(resource.overlay_uri,texture(resource.overlay_uri));rows.push({id:item.id,name:item.name,resource:resource.id,kind:resource.kind,uri,source_size:resource.source_size,fit:resource.fit});}
 const images=rows.filter(r=>r.kind==='image'),uris=[...new Set(images.map(r=>r.uri))],summary={rows:rows.length,image_rows:images.length,unique_images:uris.length,kinds:{},texture_groups:{},rows_detail:rows};
 for(const row of rows)summary.kinds[row.kind]=(summary.kinds[row.kind]||0)+1;
 for(const uri of uris){const t=unique.get(uri),key=[t?.runtime_size?.join('x')||t?.source_size?.join('x')||'unknown',t?.format_name||'source/packaged',t?.mips===undefined?'?':t.mips+'mips',t?.no_lod===undefined?'?':t.no_lod?'NO_LOD':'LOD'].join(' ');(summary.texture_groups[key]??=[]).push(uri);}
 categories[category]=summary;
}
const report={at:new Date().toISOString(),read_only:true,archive_image_logical_size:[62,62],registry_count:registry.items.length,categories,unique_textures:[...unique.values()],unmapped,notes:['Fixture formal IDs and descriptions come from current CSV; progress is synthetic.','Social ex/friend/beast pages migrated to collection and are included for asset completeness.','shop fixture represents acquired items; active shop archive page is now the leaderboard.','endless_emblem and layered_title do not render their registry URI as a normal bitmap.','Packaged official Dota assets may not exist as loose runtime files; exact native archive requires VPK metadata.']};
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({unmapped,unique:unique.size,categories:Object.fromEntries(Object.entries(categories).map(([k,v])=>[k,{rows:v.rows,kinds:v.kinds,groups:Object.fromEntries(Object.entries(v.texture_groups).map(([group,uris])=>[group,uris.length]))}]))},null,2));
