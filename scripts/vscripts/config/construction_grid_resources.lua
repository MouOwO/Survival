-- All four footprint phases share the startup readiness barrier. Each particle
-- owns its resident texture dependency; retain native mip filtering for zoom.
local resources = {}
for phase = 0, 3 do
    resources[#resources + 1] = {
        resource_type = "particle",
        path = "particles/survival_grid/reference_grid_" .. phase .. ".vpcf",
    }
end
return resources
