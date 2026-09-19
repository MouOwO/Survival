"""Shared wall stage naming and three-level visual mapping."""
NAMES=['原木','木石','青石','青铜','苍蓝','碧玉','赤铜','紫晶','白金','天辉晶冠']
ROMANS=['Ⅰ','Ⅱ','Ⅲ']
HEIGHT_MULTIPLIER=2.5
# Heavy weathering gives way to maintained dressed stone and polished trim.
WEATHERING=[1.0,.88,.76,.64,.53,.43,.34,.25,.16,.08]

def stage_for(level):
    assert 1<=level<=30
    return (level-1)//3+1

def name_for(level):
    return NAMES[stage_for(level)-1]+'城墙·'+ROMANS[(level-1)%3]

def mesh_for(level):return f'wall_lv{stage_for(level):02}'
def model_for(level):return 'models/survival_buildings/'+mesh_for(level)+'.vmdl'
