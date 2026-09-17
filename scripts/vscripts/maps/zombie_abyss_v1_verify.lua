-- Read-only integration check for the independently generated terrain map.
if GetMapName() ~= "zombie_abyss_v1" then error("Load zombie_abyss_v1 first") end
local tests = {
{name="central_island", x=-768.0, y=896.0, land=true, z=384},
{name="western_upper", x=-8896.0, y=2560.0, land=true, z=512},
{name="western_circle", x=-9152.0, y=-128.0, land=true, z=384},
{name="western_lower", x=-8896.0, y=-3744.0, land=true, z=384},
{name="northeast_plateau", x=8320.0, y=3488.0, land=true, z=640},
{name="northeast_terrace_1", x=6720.0, y=5248.0, land=true, z=768},
{name="northeast_terrace_2", x=6720.0, y=4160.0, land=true, z=768},
{name="northeast_terrace_3", x=6720.0, y=3072.0, land=true, z=768},
{name="northeast_terrace_4", x=6720.0, y=1984.0, land=true, z=768},
{name="east_annex", x=4416.0, y=-352.0, land=true, z=384},
{name="northeast_islet", x=4352.0, y=2880.0, land=true, z=320},
{name="eastern_islet", x=7488.0, y=-2112.0, land=true, z=384},
{name="eastern_coast", x=9888.0, y=-2016.0, land=true, z=512},
{name="southwest_cross", x=-3976.0, y=-4912.0, land=true, z=384},
{name="training_01", x=-5920.0, y=5440.0, land=true, z=384},
{name="training_02", x=-4768.0, y=5440.0, land=true, z=384},
{name="training_03", x=-3616.0, y=5440.0, land=true, z=384},
{name="training_04", x=-2464.0, y=5440.0, land=true, z=384},
{name="training_05", x=800.0, y=5440.0, land=true, z=384},
{name="training_06", x=2016.0, y=5440.0, land=true, z=384},
{name="training_07", x=3232.0, y=5440.0, land=true, z=384},
{name="training_08", x=4448.0, y=5440.0, land=true, z=384},
{name="training_09", x=-5920.0, y=-2688.0, land=true, z=384},
{name="training_10", x=-4768.0, y=-2688.0, land=true, z=384},
{name="training_11", x=-3616.0, y=-2688.0, land=true, z=384},
{name="training_12", x=-2464.0, y=-2688.0, land=true, z=384},
{name="training_13", x=800.0, y=-2688.0, land=true, z=384},
{name="training_14", x=2016.0, y=-2688.0, land=true, z=384},
{name="training_15", x=3232.0, y=-2688.0, land=true, z=384},
{name="training_16", x=4448.0, y=-2688.0, land=true, z=384},
{name="training_17", x=-128.0, y=-4160.0, land=true, z=384},
{name="training_18", x=2112.0, y=-4160.0, land=true, z=384},
{name="training_19", x=4352.0, y=-4160.0, land=true, z=384},
{name="training_20", x=7168.0, y=-4160.0, land=true, z=384},
{name="training_21", x=9920.0, y=-4160.0, land=true, z=384},
{name="training_22", x=-128.0, y=-5696.0, land=true, z=256},
{name="training_23", x=2112.0, y=-5696.0, land=true, z=256},
{name="training_24", x=4352.0, y=-5696.0, land=true, z=256},
{name="training_25", x=7168.0, y=-5696.0, land=true, z=256},
{name="training_26", x=9920.0, y=-5696.0, land=true, z=256},
{name="central_water", x=-3000.0, y=2200.0, land=false, z=128},
{name="western_water", x=-5632.0, y=1600.0, land=false, z=128},
{name="abyss_gap", x=0.0, y=-3000.0, land=false, z=128}
}
local failures=0
for _,t in ipairs(tests) do
 local v=Vector(t.x,t.y,t.z)
 local walk=GridNav:IsTraversable(v) and not GridNav:IsBlocked(v)
 local h=GetGroundHeight(v,nil)
 local ok=(walk == t.land) and (not t.land or math.abs(h-t.z)<100)
 if not ok then failures=failures+1 end
 print("[ABYSS_VERIFY]",t.name,ok and "PASS" or "FAIL", "walk",walk,"height",h,"expected",t.z)
end
print("[ABYSS_VERIFY] TOTAL",#tests,"FAILURES",failures)
