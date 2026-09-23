-- Explicit, read-only Workshop entry for the integrated main-map arenas.
-- Console: script_reload_code tests/manual_integrated_arenas_check
if not IsServer() or not IsInToolsMode() or GetMapName() ~= 'template_map' then
    print('[INTEGRATED_ARENAS] SKIP requires server-side Workshop template_map')
    return
end

-- script_reload_code reloads this entry, so also invalidate the probe module.
-- V4 has 42 relocated rooms; use its current marker/path/teleport probe.
-- It briefly creates four local probe units and removes each before returning.
if Entities:FindByName(nil, 'v4_northeast_field_1_center') then
    package.loaded['tests/map_c6_layout_v4_check'] = nil
    return require('tests/map_c6_layout_v4_check')
end
package.loaded['tests/manual_integrated_arenas'] = nil
return require('tests/manual_integrated_arenas').run()
