'use strict';
// Read-only isolated Workshop census, outside timed captures. No profiles/auth.
// --self-test exercises transport parsing without contacting the game.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const PREFIX = '[WORLD_CENSUS_CHUNK] ';

function makeLuaCensus(token) {
  if (!/^WORLD_CENSUS_[a-f0-9]{16}$/.test(token)) throw Error('Invalid census marker');
  return `assert(IsServer() and IsInToolsMode() and GetMapName()=='template_map');
local mode=GameRules:GetGameModeEntity();local isolation=assert(_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION);assert(isolation.mode==mode);
local MAX_ENTITIES,MAX_INPUTS,MAX_UNKNOWN=20000,60000,64;
local r={schema='native_world_census_v2',counts={entities=0,base_npcs=0,alive_npcs=0,dead_npcs=0,npc_status_unverified=0,props=0,wearables=0,other_non_npcs=0},
 names={},classes={},groups={},unknown_samples={},builders={},formal_buildings={},holders={},errors={},
 limits={world_walk=MAX_ENTITIES,total_inputs=MAX_INPUTS,unknown_samples=MAX_UNKNOWN},
 enumeration={sources={},walk={supported=false,completed=false},coverage='partial_candidates',wildcard_complete_not_assumed=true}};
local function inc(t,k) t[k]=(t[k] or 0)+1 end;
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end;
local function positive(v) return finite(v) and v>0 and v==math.floor(v) and v or nil end;
local function text(v) return type(v)=='string' and #v<=180 and not v:find('%c') and v or nil end;
local function field(u,k) local ok,v=pcall(function() return u and u[k] end);return ok and v or nil end;
local function call(u,k,...)
 local fn=field(u,k);if type(fn)~='function' then return nil,'unavailable' end;
 local ok,v=pcall(fn,u,...);if not ok then inc(r.errors,'native_'..k);return nil,'failed' end;return v,nil;
end;
local function has(u,name) return call(u,'HasModifier',name)==true end;
local function slot(v) return finite(v) and v>=0 and v<=23 and v==math.floor(v) and v or nil end;
local function entity_index(u) return positive(call(u,'entindex')) end;
local function list_source(name)
 local x={attempted=true,returned=0,added=0,duplicates=0};r.enumeration.sources[name]=x;return x;
end;
local seen_handles,seen_indices,metas={}, {}, {};
local inputs=0;local holder_roles={};local formal_roles={};
local function meta_for(u)
 local class=text(call(u,'GetClassname')) or 'class_unavailable';
 local base,base_error=call(u,'IsBaseNPC');
 local kind=class=='prop_dynamic' and 'prop' or class=='dota_item_wearable' and 'wearable' or base==true and 'base_npc'
  or base==false and 'non_npc' or (class:match('^npc_') or holder_roles[u] or formal_roles[u]) and 'npc_unverified' or class=='class_unavailable' and 'entity_unverified' or 'non_npc';
 local index=entity_index(u);local alive=nil;local name='';
 if kind=='base_npc' or kind=='npc_unverified' or kind=='entity_unverified' then alive=call(u,'IsAlive');name=text(call(u,'GetUnitName')) or '' end;
 if type(alive)~='boolean' then alive=nil end;if type(base)~='boolean' then base=nil end;
 local owner=field(u,'survival_player_id');if slot(owner)==nil then owner=call(u,'GetPlayerOwnerID') end;
 local m={entindex=index,identity_valid=index~=nil,classname=class,name=name,kind=kind,alive=alive,
  owner=slot(owner),npc_status=base,npc_status_error=base_error};
 if kind=='prop' or kind=='wearable' or kind=='non_npc' then m.group=kind;return m end;
 m.health_bar=has(u,'modifier_single_health_bar');m.enemy_ai=has(u,'modifier_enemy_wall_ai');
 m.staged=field(u,'survival_challenge_11_staged')==true;
 m.staging_health_bar_paused=field(u,'survival_challenge_staging_health_bar_paused')==true;
 local building=text(field(u,'survival_building_id')) or formal_roles[u];
 local worker=text(field(u,'survival_worker_type'));
 local placeholder=field(u,'survival_deleted_hero_placeholder')==true or has(u,'modifier_survival_placeholder_anchor');
 local corpse=alive==false and field(u,'survival_monster_corpse')==true;
 local practice=has(u,'modifier_practice_monster_ai');
 local visual=field(u,'survival_visual_only')==true;
 m.building_id=building;m.worker_type=worker;
 m.visual_only=visual;m.native_wearable_visual=field(u,'survival_is_native_wearable_visual')==true;
 m.visual_owner_entindex=positive(field(u,'survival_native_wearable_owner_entindex'));
 m.asset_id=text(field(u,'survival_model_asset_id'));
 m.corpse_started=field(u,'survival_corpse_started')==true;m.building_death_visual=field(u,'survival_building_death_visual')==true;
 m.encounter_id=text(field(u,'survival_encounter_id'));
 m.group=holder_roles[u] and 'observer_holder' or field(u,'survival_rebirth_scene_display')==true and 'rebirth_display'
  or m.native_wearable_visual and 'native_wearable_carrier' or field(u,'survival_blademaster_visual_caster')==true and 'blademaster_visual_caster'
  or visual and 'visual_only' or field(u,'survival_is_grid_preview')==true and 'grid_preview' or placeholder and 'hero_placeholder'
  or m.building_death_visual and 'building_corpse' or corpse and 'monster_corpse'
  or m.staged and 'challenge_11_staged' or field(u,'survival_is_wave_monster')==true and 'wave'
  or field(u,'survival_is_challenge_monster')==true and 'challenge' or practice and 'practice_or_challenge'
  or slot(field(u,'survival_training_owner_player_id'))~=nil and 'endless_training'
  or field(u,'survival_builder_id')~=nil and 'builder'
  or (worker or field(u,'survival_worker_id') or field(u,'survival_lumberjack_id')) and 'worker'
  or field(u,'survival_monkey_king_clone')==true and 'monkey_king_clone'
  or field(u,'survival_blademaster_clone')==true and 'blademaster_clone'
  or field(u,'survival_exclusive_summon')==true and 'exclusive_summon'
  or building and 'building' or field(u,'survival_tree_owner_id')~=nil and 'resource_tree'
  or field(u,'survival_archive_hub')~=nil and 'archive_hub' or field(u,'survival_hero_id')~=nil and 'combat_hero'
  or m.encounter_id and 'encounter_monster' or 'other';
 if holder_roles[u] then m.holder_role=holder_roles[u] end;
 local owner_handle=call(u,'GetOwner');if owner_handle and call(owner_handle,'IsNull')~=true then m.owner_entindex=entity_index(owner_handle) end;
 return m;
end;
local function visit(u,source)
 inputs=inputs+1;if inputs>MAX_INPUTS then r.enumeration.input_limit_reached=true;return nil end;
 if u==nil then return nil end;
 if type(u)~='userdata' and type(u)~='table' then inc(r.errors,'invalid_candidate_type');return nil end;
 if call(u,'IsNull')==true then inc(r.errors,'null_candidate');return nil end;
 if seen_handles[u] then source.duplicates=source.duplicates+1;return metas[u] end;
 local index=entity_index(u);
 if index and seen_indices[index] then source.duplicates=source.duplicates+1;return metas[seen_indices[index]] end;
 seen_handles[u]=true;if index then seen_indices[index]=u end;
 local ok,m=pcall(meta_for,u);
 if not ok or not m then
  inc(r.errors,'metadata_failed');m={entindex=index,identity_valid=index~=nil,classname='class_unavailable',name='',kind='entity_unverified',group='other',metadata_failed=true};
 end;
 metas[u]=m;source.added=source.added+1;inc(r.counts,'entities');inc(r.classes,m.classname);
 if not m.identity_valid then inc(r.errors,'invalid_or_unavailable_entindex') end;
 if m.kind=='base_npc' then
  inc(r.counts,'base_npcs');inc(r.groups,m.group);if m.name~='' then inc(r.names,m.name) end;
  if not m.identity_valid then inc(r.counts,'base_npc_identity_unverified') end;
  if m.alive==true then inc(r.counts,'alive_npcs') elseif m.alive==false then inc(r.counts,'dead_npcs') else inc(r.counts,'alive_status_unverified') end;
  if m.staged then inc(r.counts,'challenge_11_staged') end;
 elseif m.kind=='prop' then inc(r.counts,'props') elseif m.kind=='wearable' then inc(r.counts,'wearables')
 elseif m.kind=='non_npc' then inc(r.counts,'other_non_npcs') else inc(r.counts,'npc_status_unverified') end;
 if m.group=='other' or not m.identity_valid or m.kind=='npc_unverified' or m.kind=='entity_unverified' then
  if #r.unknown_samples<MAX_UNKNOWN then r.unknown_samples[#r.unknown_samples+1]=m else inc(r.counts,'unknown_details_omitted') end;
 end;
 return m;
end;
local holder_keys={tree='survival_tree_attack_observer_holder_v1',lumberjack='survival_lumberjack_attack_observer_holder',enemy='survival_enemy_attack_observer_holder',tower='survival_tower_damage_observer_holder'};
for role,key in pairs(holder_keys) do local u=field(mode,key);if u then holder_roles[u]=role end end;
local bus=package.loaded['core/event_bus'];local events=package.loaded['core/events'];
local requests={};
for id=0,3 do
 local ok,x=false,nil;
 if bus and type(bus.request)=='function' and events then ok,x=pcall(bus.request,events.BUILDING_LIST_REQUEST,{player_id=id,handles_only=true}) end;
 local source=list_source('formal_buildings_'..id);source.ok=ok and type(x)=='table' and x.ok==true;
 if source.ok then for i,entry in ipairs(type(x.buildings)=='table' and x.buildings or {}) do if i>MAX_ENTITIES then source.truncated=true;break end;if type(entry)=='table' and entry.unit then
  requests[#requests+1]={unit=entry.unit,source=source};formal_roles[entry.unit]=text(entry.building_id) or 'formal_building';source.returned=source.returned+1;
 end end end;
 r.formal_buildings[#r.formal_buildings+1]={id=id,ok=source.ok,returned=source.returned};
end;
-- Preserve formal summaries before a bounded whole-world/fallback sweep.
for _,entry in ipairs(requests) do visit(entry.unit,entry.source) end;
local holder_source=list_source('known_observer_holders');
for role,key in pairs(holder_keys) do local u=field(mode,key);local m=nil;
 if u then holder_source.returned=holder_source.returned+1;m=visit(u,holder_source) end;
 r.holders[role]={present=u~=nil,native_valid=m~=nil and m.identity_valid==true,entity=m};
end;
local builder_source=list_source('formal_builders');
for id=0,3 do
 local ok,x=false,nil;if bus and type(bus.request)=='function' and events then ok,x=pcall(bus.request,events.BUILDER_GET_REQUEST,{player_id=id}) end;
 local u=ok and type(x)=='table' and x.builder or nil;local m=nil;
 if u then builder_source.returned=builder_source.returned+1;m=visit(u,builder_source) end;
 r.builders[#r.builders+1]={id=id,ok=ok and type(x)=='table' and x.ok==true,request_failed=not ok,native_valid=m~=nil and m.identity_valid==true,entity=m};
end;
local first_fn,next_fn=field(Entities,'First'),field(Entities,'Next');
if type(first_fn)=='function' and type(next_fn)=='function' then
 r.enumeration.walk.supported=true;
 local source=list_source('Entities.First_Next');local ok,u=pcall(first_fn,Entities);
 if not ok then r.enumeration.walk.reason='first_failed' else
  local walked={};local steps=0;
  while u~=nil and steps<MAX_ENTITIES do
   if walked[u] then r.enumeration.walk.reason='repeated_handle';break end;walked[u]=true;steps=steps+1;source.returned=source.returned+1;visit(u,source);
   local advanced,next_unit=pcall(next_fn,Entities,u);
   if not advanced then r.enumeration.walk.reason='next_failed';break end;u=next_unit;
  end;
  r.enumeration.walk.visited=steps;
  if u==nil then r.enumeration.walk.completed=true;r.enumeration.walk.reason='exhausted'
  elseif steps>=MAX_ENTITIES then r.enumeration.walk.reason='entity_limit' end;
 end;
else r.enumeration.walk.reason='api_unavailable' end;
local function collect(name,host,method,...)
 local source=list_source(name);local values,why=call(host,method,...);source.ok=type(values)=='table';source.status=why or (source.ok and 'returned_table' or 'not_table');
 if source.ok then for i,u in ipairs(values) do if i>MAX_ENTITIES then source.truncated=true;break end;source.returned=source.returned+1;visit(u,source) end end;
end;
if not r.enumeration.walk.completed then
 for _,class in ipairs({'npc_dota_*','npc_dota_creature','npc_dota_building','npc_dota_fort','npc_dota_tower','npc_dota_barracks','npc_dota_thinker','npc_dota_hero','prop_dynamic','dota_item_wearable'}) do collect('classname:'..class,Entities,'FindAllByClassname',class) end;
end;
collect('HeroList.GetAllHeroes',HeroList,'GetAllHeroes');
r.native_state=call(GameRules,'State_Get');r.in_progress=DOTA_GAMERULES_STATE_GAME_IN_PROGRESS;
r.wall_rules_loaded=type((package.loaded['systems/building_defeat_rules'] or {}).player_for_completed_wall);
local observer=package.loaded['systems/tower_damage_observer'];
if observer and type(observer.wall_feedback_snapshot)=='function' then
 local ok,value=pcall(observer.wall_feedback_snapshot);if ok and type(value)=='table' then r.wall_feedback=value else r.wall_feedback={available=false,snapshot_failed=true} end;
else r.wall_feedback={available=false} end;
r.enumeration.inputs=inputs;r.enumeration.world_consistent=GameRules:GetGameModeEntity()==mode and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION==isolation;
if r.enumeration.walk.completed and not r.enumeration.input_limit_reached and r.enumeration.world_consistent then r.enumeration.coverage='bounded_world_entity_walk_completed' end;
local encoded=require('core/json_encoder').encode(r);local first,index=1,0;
while first<=#encoded do local last=math.min(#encoded,first+1100);while last<#encoded and encoded:byte(last+1)>=128 and encoded:byte(last+1)<=191 do last=last-1 end;
 index=index+1;print('${PREFIX}'..require('core/json_encoder').encode({index=index,data=encoded:sub(first,last)}));first=last+1 end;print('${token}')`;
}

function parseNativeOutput(output, token) {
  if (typeof output !== 'string' || output.length > 8 * 1024 * 1024) throw Error('Native report exceeds transport bound');
  if (token && !output.split(/\r?\n/).some(line => line.trim() === token)) throw Error('Native completion marker missing');
  let chunks;
  try { chunks = output.split(/\r?\n/).filter(line => line.startsWith(PREFIX)).map(line => JSON.parse(line.slice(PREFIX.length))); }
  catch { throw Error('Native chunk parse failed'); }
  if (!chunks.length || chunks.length > 8192 || chunks.some((chunk, i) => chunk.index !== i + 1 || typeof chunk.data !== 'string')) throw Error('Native report incomplete');
  let result;
  try { result = JSON.parse(chunks.map(chunk => chunk.data).join('')); } catch { throw Error('Native JSON parse failed'); }
  if (!result || result.schema !== 'native_world_census_v2' || !result.counts || !result.groups || !Array.isArray(result.builders)
      || !Array.isArray(result.unknown_samples) || result.unknown_samples.length > 64 || !result.enumeration) throw Error('Native census schema invalid');
  return result;
}

function summarizeReport(result, file) {
  return {file, counts: result.counts, groups: result.groups, builders: result.builders,
    wall_feedback: result.wall_feedback};
}

function selfTest() {
  const assert = require('node:assert/strict'), marker = 'WORLD_CENSUS_1234567890abcdef';
  const fixture = {schema: 'native_world_census_v2', counts: {base_npcs: 479, props: 81}, groups: {wave: 244, other: 3},
    builders: [{id: 0, native_valid: true}], wall_feedback: {enabled: false}, enumeration: {coverage: 'partial_candidates'},
    unknown_samples: [{name: 'unknown_单位', entindex: 913, kind: 'base_npc'}]};
  const encoded = JSON.stringify(fixture), split = encoded.indexOf('单位') + 1;
  const output = ['ordinary engine output', PREFIX + JSON.stringify({index: 1, data: encoded.slice(0, split)}),
    PREFIX + JSON.stringify({index: 2, data: encoded.slice(split)}), marker].join('\r\n');
  assert.deepEqual(parseNativeOutput(output, marker), fixture);
  assert.throws(() => parseNativeOutput(output.replace('"index":2', '"index":3'), marker), /incomplete/);
  assert.throws(() => parseNativeOutput(output.replace(marker, ''), marker), /marker missing/);
  assert.throws(() => parseNativeOutput(PREFIX + '{bad json}', null), /chunk parse/);
  const oversized = {...fixture, unknown_samples: Array(65).fill({name: 'unknown'})};
  assert.throws(() => parseNativeOutput(PREFIX + JSON.stringify({index: 1, data: JSON.stringify(oversized)})), /schema/);
  const summary = summarizeReport(fixture, 'evidence.json');
  assert.equal(summary.counts.base_npcs, 479);
  assert(!('unknown_samples' in summary) && !('names' in summary) && !JSON.stringify(summary).includes('unknown_单位'));
  assert.equal(parseNativeOutput(output, marker).enumeration.coverage, 'partial_candidates');
  console.log('NATIVE_WORLD_CENSUS_PARSER_PASS Unicode chunks, ordering/completion/schema bounds, unknown metadata and summary separation; no game connection');
}

async function main(argv) {
  if (argv[0] === '--self-test') { selfTest(); return; }
  const label = argv[0];
  if (!label || !/^[a-z0-9_]{1,64}$/.test(label)) throw Error('Unique lowercase label required');
  const file = path.resolve(__dirname, '../output/four_operation_extreme_20261012', label + '.json');
  if (fs.existsSync(file)) throw Error('Existing evidence is never overwritten');
  const token = 'WORLD_CENSUS_' + crypto.randomBytes(8).toString('hex');
  const {ConsoleSession} = require('./map_c6/console-session.cjs');
  const session = new ConsoleSession({timeoutMs: 15000, historyTimeoutMs: 60000});
  try {
    await session.connect();
    const response = await session.send([{name: 'dota_run_lua', arguments: {code: makeLuaCensus(token)}}], token, 100);
    const result = parseNativeOutput(response.output, token);
    fs.writeFileSync(file, JSON.stringify(result, null, 2), {flag: 'wx'});
    console.log(JSON.stringify(summarizeReport(result, file), null, 2));
  } finally { await session.close(); }
}

module.exports = {makeLuaCensus, parseNativeOutput, summarizeReport};
if (require.main === module) main(process.argv.slice(2)).catch(error => {console.error(error.message); process.exitCode = 1;});
