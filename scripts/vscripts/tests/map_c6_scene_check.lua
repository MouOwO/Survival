if not IsInToolsMode() or GetMapName()~='survival_c6' then return end
local previews=0
for _,e in ipairs(Entities:FindAllByClassname('prop_dynamic')) do
    local model=e.GetModelName and e:GetModelName() or ''
    if model=='models/heroes/axe/axe.vmdl'
        or model=='models/creeps/neutral_creeps/n_creep_golem_a/neutral_creep_golem_a.vmdl' then
        previews=previews+1
    end
end
print('[C6_SCENE] preview_actors_in_game='..previews..' test_units='..(C6Stress and #C6Stress.units or 0))
assert(previews==0,'room scale reference actors should be editor-only')
