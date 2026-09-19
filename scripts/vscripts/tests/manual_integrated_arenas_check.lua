-- Explicit, read-only Workshop entry for the integrated main-map arenas.
-- Console: script_reload_code tests/manual_integrated_arenas_check
if not IsServer() or not IsInToolsMode() or GetMapName() ~= 'template_map' then
    print('[INTEGRATED_ARENAS] SKIP requires server-side Workshop template_map')
    return
end

-- script_reload_code reloads this entry, so also invalidate the probe module.
package.loaded['tests/manual_integrated_arenas'] = nil
return require('tests/manual_integrated_arenas').run()
