# 原生背景音乐接入与1106交付（2026-11-11）

已同步游廊2026111106，Steam manifest `6291919402900133473`。音乐功能未修改后台。完整发布由同一工作区另一窗口的固定打包任务完成，本窗口没有重复上传；普通新局完整听感、多人和FPS验收仍待。

## 已确认方案与实现

用户确认：日常经营/波间等待使用Dota原版，常规战斗和Boss使用TI10，极寒模式使用极北凛风。普通模式含3首经营、3首战斗和1首Boss；极寒含3首经营、3首战斗和1首Boss，共14个事件，只引用Dota原生vsnd，不把音频再次打入地图包。

`background_music.js`复用已有个人紧凑HUD的wave/wave_setup订阅，以模式、Boss标记、存活/待生成敌人和波次状态选择音乐。波间仍有敌人时保持战斗；仅分类真正变化才换曲，回到同类时轮换3首候选。原生dota_update_music_stereo负责循环、Music混音组、snd_musicvolume和1.25秒淡入淡出；保留用户音量，不改音乐包装备或用户设置。

只保留一个当前声音句柄和一个待切换任务，真实变化按1.25秒合并，正常相邻阶段交叉淡化。败退即时发停止，实际尾音由原生淡出处理；HUD重建清理旧实例，原生postgame退订并清理。初始化关闭常规Dota的自动战斗、选人及开局音乐控制，避免与地图配乐竞争。有效原生声音GUID带符号高位，可为负数，必须原样传回Game.StopSound；不能把“>=0”当有效条件。

## 成本与验证

初始化只登记14个固定声音事件和1个共享HUD消费者，无场景/单位扫描、新服务器计时器或音乐网络协议。稳定帧无新增Lua/Panorama轮询；每个wave通知按固定字段O(1)判断，包含面板有效性和原生阶段的常数次只读检查。相同分类不再调用播放/停止/调度；变化至多一个待切换任务，提交一次停止和一次播放；游标空间固定6项。

作者和实际官方编译JS DATA均通过51项专项：模式/阶段、波间余怪、Boss优先、极寒、去重、快速变化合并、过期回调、失败隔离、败退、换源、HUD重复加载/重建、postgame和原生负GUID。10000次同分类更新新增声音调用/任务0、网络0；此计数不包含常数次有效性/原生阶段只读查询，不能写成所有原生调用均0。编译规划工具原16项回归、音乐白名单与未知依赖拒绝、真实addon模块启动检查通过。

官方resourceinfo独立核对实际vsndevts产物14组type/Music/fade_in/fade_out/convar_min字段通过；旧版Source2Viewer未显示该产物DATA，未将其空输出当通过。实际三资源：

| 资源 | 字节 | SHA256 |
| --- | ---: | --- |
| panorama/scripts/custom_game/background_music.vjs_c | 6590 | 75eafbb41b9d987238e6e3689a2ee5e41fe96cd2bd6cfa6a707decbee113e17d |
| panorama/layout/custom_game/survival_hud.vxml_c | 20626 | 189a074578b018687530671cbb7d917273d280da5efe708903943a052a2ebeaf |
| soundevents/survival_background_music.vsndevts_c | 2489 | 0a86abb7133c63e0f56a8b038e944e67956f0941fb7f9850e70bed1d4b1f7cf7 |

隔离Tools实测观察到原生声音GUID为-2147483645等负数，最终控制器首曲playing=true及Dispose后playing=false。多阶段绝对计时测试曾因加载/调度集中而未完成有效逐阶段观察，不认定为全曲切换听感通过；一次诊断包装器脱离原生方法上下文触发V8错误，原文和退出记录保留，修正采集后继续验证。用户要求协调发布时，本窗口已经停止实机、Dota进程数0，不再重启测试或修改运行文件。

## 来源、完整发行与协作收口

音乐作者源码game/dev `2578086fb3ec5c67f69a6f421713737f3f59fa2c`，content/master `75a8b74c9178a62feacc1dd5cbf3c4279aa57bc4`已按stash→pull→精确pop→定向commit→push同步；game本轮stash `d66654c0028d2aff79f61151d87033b3e5a9077d`已恢复，其他历史stash及无关改动保留。编译工具只增加这一个声音事件源和三个原生包的14条依赖映射，不放宽任意音效来源。

首次本窗口1105完整构建在scope_author_mapping_incomplete处拒绝，保留任务`pack_2026111105_f444f0ba`，没有上传。另一窗口补齐新任务生成器的精确作者映射（cdfccfb99，未改旧冻结模板），并启动`pack_2026111106_08d18de8`的publish-test。本窗口发现后只读跟踪及独立审查音乐产物，没有重建/重复提交SDK。

1106任务所有阶段done：7资源官方编译、186保护模块、6项exact输入审查、7058运行资源完整收集/签包、SDK成功、官方下载完整核对及checkpoint均完成。最终运行/operator来源game `8086894cec8b0ca5f1726773a0666477727f415b`，content `ebe6fa24eac453b3c1ea809fd78b2c4d5129634b`；原条目3824360109。固定打包工具inspect再次返回1106、同一Steam manifest、pending_sources=[]、dirty_runtime=[]，不能再沿用“音乐未提交、Dota运行中”的旧提示。

本轮完整包还包含其他窗口已提交的抽奖等运行更新，范围由该任务全量清单记录，不能把整个包描述成只有音乐3资源。音乐无后台写入，其他窗口的后台操作以其独立回执为准。

树外证据：`D:/Survival_本地工具/runs/20261111_native_music_implementation/`内保存git_sync.json、作者/实际DATA专项日志、official_compiled_audit.json、原生失败与中断记录、最终LAB观察登记及仅卸载junction的回执。LAB实物保留在`D:/Survival_本地工具/vpk_lab/native_music_20261111_v01`，两处测试挂载已解除，不留裸VPK在addon扫描树内。正式包目录`D:/Survival_工坊输出/pack_2026111106_08d18de8`；官方下载verification与完整编译来源位于该固定打包任务的output及树外job记录，旧包和回执未为整理而改写。
