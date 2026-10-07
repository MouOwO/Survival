const record=require('./record.cjs');
const groups=[
 ['01_junction','J02',[
  {id:'J01',result:'淘汰',improvement:'减弱标题下方横带',cost:'背景过渡仍是窄带，侧栏深浅关系未改善'},
  {id:'J02',result:'保留',improvement:'暖雾衔接象牙标题与商品底，顶部接缝更连贯',cost:'比原版少一点青灰层次，仍保留山水细节'}]],
 ['02_sidebar','J04',[
  {id:'J03',result:'淘汰',improvement:'接缝更克制',cost:'仅降低透明度导致原直线边缘仍显硬'},
  {id:'J04',result:'保留',improvement:'薄雾与细线替换宽亮边，选中行光晕保持完整',cost:'深色侧栏边界仍可见，属于必要分区'}]],
 ['03_card_material','C07',[
  {id:'C05',result:'淘汰',improvement:'象牙更暖，卡体保留玉石雕刻感',cost:'原厚边框与底部双线仍过重'},
  {id:'C06',result:'淘汰',improvement:'明显扁平化，减少外边与高光',cost:'浅色物品与底板层次过弱，失去浅玉质感'},
  {id:'C07',result:'保留',improvement:'细边框与较浅浮雕平衡商品轮廓，接近风格锚点',cost:'仍有微弱云纹，非纯白平面'}]],
 ['04_card_shadow','C09',[
  {id:'C08',result:'淘汰',improvement:'投影显著减弱，网格留白更干净',cost:'卡体与窗口几乎贴平，hover层级不易察觉'},
  {id:'C09',result:'保留',improvement:'中等投影保留浅浮起，消除原版偏脏底边',cost:'卡片仍有轻微实体边界'}]],
 ['05_item_display','I10',[
  {id:'I10',result:'保留',improvement:'独立投影减弱至55%，浮空物品底部不再显脏',cost:'接触感略轻，仍能辨认投影'},
  {id:'I11',result:'淘汰',improvement:'缩小6%增加留白',cost:'缩放使示例物品细节发软，宽大物品原比例更清楚'},
  {id:'I12',result:'淘汰',improvement:'展示底改成暖色柔雾',cost:'与卡体形成额外亮色块，原环纹更自然'}]],
 ['06_name_price','N13',[
  {id:'N13',result:'保留',improvement:'名称重量减轻、字距收紧，名称和价格形成清晰层次',cost:'中文标题雕刻感比粗字稍弱'},
  {id:'N14',result:'淘汰',improvement:'柔软价格带减少下半部边缘',cost:'价格与卡体辨识不足，保留原内嵌信息底'}]],
 ['07_hover','H16',[
  {id:'H15',result:'淘汰',improvement:'遮罩横向铺开，文字更稳',cost:'边缘仍是一块深色矩形，压过物品细节'},
  {id:'H16',result:'保留',improvement:'较轻遮罩与四边渐变让物品仍可见，价格不遮挡',cost:'极亮物品须复查长描述对比度'}]],
 ['08_buy_button','B17',[
  {id:'B17',result:'保留',improvement:'减少金边及高光，青玉按钮有清楚但克制的购买反馈',cost:'比原版立体感较低'},
  {id:'B18',result:'淘汰',improvement:'亮釉提高购买按钮可见性',cost:'亮边抢商品主体，背离极简方向'}]],
 ['09_navigation','B17',[
  {id:'V19',result:'淘汰',improvement:'选中象牙材质稍暖',cost:'全图对比收益很小，原导航材质已符合参考，不叠加修改'},
  {id:'V20',result:'淘汰',improvement:'选中光晕减半，边缘更克制',cost:'底部金线与选中态弱化，保留原光晕与金线'}]]
];
const count=Number(process.argv[2]||groups.length);
const from=Number(process.argv[3]||0);
for(const g of groups.slice(from,count))record(...g);
