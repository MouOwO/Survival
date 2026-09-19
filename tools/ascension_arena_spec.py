"""Approved ascension art direction; first modeling pass in Source units."""
NAMESPACE = 'ascension_arenas'
REVISION = 'ascension_arenas_v2_1000x550'
FOOTPRINT = (1000, 550)
REVIEW_COLUMN_OFFSET = 650
REVIEW_ROW_PITCH = 800
LAYER_HEIGHT = 14.0
LAYER_INSET = 1.5
NAMES = ('夯土试武台', '木垒练武台', '青石比武台', '砌石演武台', '白石晋阶台',
         '青玉试炼台', '玄晶登阶台', '天玉凌空台', '流云登仙台', '太虚云擂')
PALETTE = {
    'earth': (.48,.35,.215), 'earth_edge': (.38,.285,.18), 'mortar': (.34,.34,.30),
    'wood': (.49,.345,.205), 'wood_light': (.62,.46,.28), 'wood_end': (.66,.49,.30),
    'stone': (.58,.61,.59), 'stone_light': (.69,.70,.63), 'stone_dark': (.39,.45,.46),
    'dressed_stone': (.66,.65,.59), 'ivory': (.80,.775,.67), 'jade': (.40,.63,.53),
    'jade_light': (.67,.78,.67), 'crystal': (.235,.43,.60), 'mineral_stone': (.54,.62,.67),
    'iron': (.30,.335,.32), 'bronze': (.58,.44,.25), 'gold': (.82,.67,.36),
    'silver': (.70,.73,.70), 'moss': (.29,.36,.15),
    'cloud': (.88,.92,.97), 'cloud_shadow': (.62,.735,.84), 'cloud_pearl': (.94,.955,.95),
}


def stage(rank):
    assert 1 <= rank <= 10
    inset=(rank-1)*LAYER_INSET
    return dict(rank=rank,name=f'arena_{rank:02}',label=NAMES[rank-1],layers=rank,
                layer_height=LAYER_HEIGHT,deck_z=rank*LAYER_HEIGHT,
                footprint=list(FOOTPRINT),deck_size=[size-2*inset for size in FOOTPRINT],
                clear_combat_size=[size-2*inset-64 for size in FOOTPRINT],
                review_xy=[-REVIEW_COLUMN_OFFSET if rank%2 else REVIEW_COLUMN_OFFSET,
                           ((rank-1)//2-2)*REVIEW_ROW_PITCH],
                float_preview_offset=0 if rank<8 else (rank-7)*10,
                emissive=False)
