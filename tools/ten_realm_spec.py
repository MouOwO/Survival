"""Approved ten square enclosed arenas. Source units, Z-up, floor at zero."""
NAMESPACE = 'ten_realm_arenas'
REVISION = 'ten_realms_v1_700x700'
FOOTPRINT = (700, 700)
DECK_Z = 0.0
WATER_Z = -42.0
WALL_THICKNESS = 28.0
WALL_CENTER = 336.0
CLEAR_HALF = 306.0
REVIEW_PITCH = 1280.0
NAMES = ('黄沙古垒','林间古环','沼泽沉垣','赤岩断谷','霜雪寒垒',
         '潮礁碧湾','熔岩黑岸','紫晶岩庭','天辉圣庭','夜魇荒庭')
BIOMES = ('desert','woodland','marsh','red_canyon','snow','coral','basalt','crystal','radiant','dire')
PALETTE = {
 'sand':(.72,.55,.32),'sand_wet':(.45,.37,.23),
 'sandstone':(.65,.49,.30),'sandstone_light':(.79,.65,.43),
 'forest_earth':(.32,.285,.18),'peat':(.29,.30,.19),'mud':(.22,.235,.175),
 'redstone':(.55,.285,.19),'redstone_light':(.69,.39,.27),'red_gravel':(.42,.23,.17),
 'snow':(.84,.89,.91),'ice':(.38,.61,.68),
 'coral':(.73,.70,.55),'coral_light':(.86,.82,.65),'shell_sand':(.71,.67,.51),
 'basalt':(.245,.27,.29),'basalt_wet':(.12,.17,.18),
 'schist':(.40,.375,.46),'quartz':(.70,.68,.76),'amethyst':(.38,.20,.55),
 'ivory':(.78,.765,.66),'ivory_light':(.88,.86,.77),
 'slate':(.37,.385,.385),'slate_wet':(.18,.22,.22),'bone':(.76,.735,.64),
 'stone':(.52,.55,.49),'stone_light':(.65,.665,.59),'stone_cool':(.47,.53,.53),
 'rock':(.45,.48,.43),'rock_wet':(.24,.32,.29),'mortar':(.285,.30,.265),'moss':(.29,.35,.14),
 'wood':(.32,.23,.14),'wood_light':(.47,.355,.21),'wood_end':(.50,.39,.24),'bark':(.265,.235,.17),
 'leaf':(.24,.37,.15),'leaf_light':(.42,.50,.20),'leaf_dark':(.13,.25,.14),
 'flower':(.91,.82,.51),'pink':(.87,.42,.51),'pink_light':(.98,.67,.72),
 'gold':(.81,.65,.32),'bronze':(.51,.365,.21),'iron':(.26,.29,.29),
 'teal':(.19,.39,.36),'red_cloth':(.37,.13,.12),
 'foam':(.47,.69,.66),'water':(.025,.16,.22),'water_shallow':(.045,.26,.29),
}
ROLE_ROWS = (
 ('sand','sandstone','sandstone_light','sandstone','sand_wet','sand','bronze'),
 ('forest_earth','stone','stone_light','rock','rock_wet','forest_earth','moss'),
 ('peat','stone','stone_cool','rock','mud','peat','wood'),
 ('redstone','redstone','redstone_light','redstone','red_gravel','red_gravel','bronze'),
 ('snow','stone_cool','snow','stone_cool','rock_wet','snow','ice'),
 ('coral','coral','coral_light','coral','shell_sand','shell_sand','bronze'),
 ('basalt','basalt','slate','basalt','basalt_wet','basalt','bronze'),
 ('schist','schist','quartz','schist','slate_wet','schist','amethyst'),
 ('ivory','ivory','ivory_light','stone_light','rock_wet','forest_earth','gold'),
 ('slate','slate','stone_cool','slate','slate_wet','mud','bone'),
)
def realm(rank):
    assert 1 <= rank <= 10
    roles=dict(zip(('ground','wall','cap','rock','wet','shore','accent'),ROLE_ROWS[rank-1]))
    return dict(rank=rank,name=f'realm_{rank:02}',label=NAMES[rank-1],biome=BIOMES[rank-1],
                footprint=list(FOOTPRINT),clear_combat_size=[612,612],deck_z=DECK_Z,water_z=WATER_Z,
                wall_height=(74,68,64,72,72,64,74,68,74,76)[rank-1],roles=roles,
                review_xy=[-700 if rank%2 else 700,((rank-1)//2-2)*REVIEW_PITCH],
                entry=[0,-234,0],spawn=[0,234,0],
                entry_marker=f'challenge_11_stage_{rank:02}_entry',
                spawn_marker=f'challenge_11_stage_{rank:02}_spawn',emissive=False)
