local function placeholder()
    return class({})
end

for index = 1, 6 do
    _G["ability_survival_builder_slot_" .. tostring(index) .. "_placeholder"] =
        placeholder()
end

return _G.ability_survival_builder_slot_1_placeholder