-- Historical probe-format compatibility only. Its temporary phasing/Hull20
-- assertions and optional stable-phase windows describe the old fixture;
-- passing this suite is NOT current collision or native gameplay acceptance.
-- Current acceptance uses wall_trajectory_oracle.lua and its strict self-test:
-- zero phased frames, fixed hull, raw/swept physical separation, no jumps.
-- The native probe must distinguish physical hull penetration from compressed
-- avoidance padding. Exercise the actual fixture oracle, including the real
-- west-stair solid pair that exposed the former false positive.
package.path='scripts/vscripts/?.lua;'..package.path
for _,name in ipairs({'systems/wall_navigation_service','systems/wall_navigation_geometry',
    'systems/wall_melee_contact','modifiers/modifier_enemy_wall_ai','core/json_encoder'}) do
    package.loaded[name]={}
end
local probe=assert(loadfile('scripts/vscripts/tests/wall_native_redesign_probe.lua'))()
local classify=assert(probe._body_pair_overlap_for_test)
local function pair(distance,a,b) return classify(a,b,distance*distance) end
local front={hull=20,padded=30,phased=false}
local rear={hull=32,padded=42,phased=false}
local native=pair(60.981053867163,front,rear)
assert(not native.hard_overlap and not native.solid_overlap and native.padded_overlap,
    'native soft-padding compression was misreported as a solid-body overlap')
local penetration=pair(45,front,rear)
assert(penetration.hard_overlap and penetration.solid_overlap,
    'a genuine raw-hull solid-body penetration escaped the collision oracle')
local phased=pair(45,{hull=20,padded=30,phased=true},rear)
assert(phased.hard_overlap and phased.phased_overlap and not phased.solid_overlap,
    'legal short phased entry was classified as a solid-body collision failure')
assert(not pair(50,front,rear).hard_overlap,'two-unit numerical tolerance was lost')
assert(pair(49.99,front,rear).solid_overlap,'numerical tolerance swallowed deeper physical penetration')
assert(not pair(72,front,rear).padded_overlap,'fully separated avoidance envelopes still overlap')
assert(not pair(64,{hull=0,padded=10},{hull=0,padded=10}).hard_overlap,
    'a zero native hull was enlarged by the test oracle')
assert(native.raw==52 and native.padded==72,'the oracle lost native radius diagnostics')
local timed_out=assert(probe._replacement_deadline_exceeded_for_test)
assert(not timed_out({replace=true,victim=1,replacement=1,replacement_seconds=10}),
    'an unrequested replacement deadline changed the native acceptance rule')
assert(not timed_out({replace=true,victim=1,replacement=1,replacement_seconds=8,max_replacement_seconds=8}),
    'a replacement exactly at its explicit deadline was rejected')
assert(timed_out({replace=true,victim=1,replacement=1,replacement_seconds=8.001,max_replacement_seconds=8}),
    'a long overall test duration hid a late replacement')
assert(not timed_out({replace=false,victim=1,replacement=1,replacement_seconds=10,max_replacement_seconds=8}),
    'a disabled replacement scenario was given a replacement deadline')
local stable_phase_failures=assert(probe._stable_phase_failures_for_test)
local stable_overlap,stable_actor=stable_phase_failures({phased_count=1,phased_overlaps=1})
assert(not stable_overlap and not stable_actor,
    'legal entry during formation or after vacancy was treated as stable permanent phasing')
stable_overlap,stable_actor=stable_phase_failures({maximum_stable_phased_overlaps=0,maximum_stable_phased_count=1})
assert(not stable_overlap and stable_actor,
    'a permanent phased actor without physical overlap escaped stable acceptance')
stable_overlap,stable_actor=stable_phase_failures({maximum_stable_phased_overlaps=1,maximum_stable_phased_count=2})
assert(stable_overlap and stable_actor,
    'stable phased penetration escaped the dedicated phase acceptance rule')
local four_source_min_x=assert(probe._four_source_min_x_for_test)
assert(four_source_min_x(20,512)==-512,'four-source footprint retained an unrelated linear spawn tail')
assert(four_source_min_x(16,384)==-448,'four-source first ring footprint was not bounded to its actual spawn depth')
assert(not pcall(four_source_min_x,20,384),'four-source terrain check omitted the farthest spawn hull')
print('WALL_NATIVE_PROBE_ORACLE_PASS native_padding=diagnostic solid_penetration=fail phased_entry=separate stable_phase=fail tolerance=2 replacement_deadline=optional four_sources=bounded')
