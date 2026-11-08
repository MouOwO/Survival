# 武器成长成功提示使用中文名称（2026-11-08）

仅本地更新。后台未改，SDK0；正式仍2026110104 / Steam manifest 7025356658517360342。新完整签包、原生显示和原游廊交付仍待。

用户截图的“武器成长完成：weapon_frost_blade_04”来自 systems/weapon_growth_service.lua 的 upgrade_if_ready：库存升级成功后直接拼接 next_content_id。现改为按既有 weapons.by_id 索引读取目标武器 display_name，截图场景实际输出“武器成长完成：霜之剑刃Lv4”。此共享入口覆盖其他按普攻次数成长的武器。配置名称缺失/空值时使用中文“新武器”，避免退回英文ID。

本轮仅改变成功提示名称，库存事务、升级门槛、进度结转、成长属性、玩家归属和通知级别保持。没有改生成配置、本地化表、素材或Panorama；content无配套Lua源。效率为一次成功升级O(1)索引和名称检查；初始化/普通未升级攻击/稳定帧新增工作0，无新循环、计时器、原生或网络调用，使用原有一条通知。

复用树外 test_weapon_growth_inputs.lua 的真实服务夹具：原1000次满级攻击/5000次读取、输入缓存、双玩家、锻造锤、升级门槛与失败结转回归通过；同一夹具实际将霜之剑刃Lv3升为Lv4，断言唯一通知文本、player_id=0、level=info通过。Lua5.1语法与git diff --check通过。属于模拟服务验证，尚无新版原生截图；不热重载或中止用户Tools对局。

树外证据：D:/Survival_本地工具/runs/20261108_weapon_growth_chinese_name/，verification.json记录服务摘要及验证范围，verification.stdout.txt保存实际中文消息，git_sync.json记录唯一stash与双仓同步。第一次命令行中文字节比较和一次Lua UTF-8中文路径读取不兼容均在正式验证前失败；最终使用UTF-8脚本、以Windows命令参数传入夹具路径后通过，没有改生产代码规避测试。

改动前核实当前Dota为-tools/offline局，无联网keeper，lineage pending=null；不属于联网签包冻结。game/dev按stash→pull→精确pop恢复，content/master在干净状态pull、不创建空提交；既有本地提交与两边其他任务改动保留，只提交本轮源码和知识记录。精确提交与推送结果见树外git_sync.json。

全部待发通过 release_pending_inventory.py 相对实际签名0104父基线重新收集，包含双仓源码、编译、素材、删除及历史未发布项，完整结果保存于同一树外目录 pending_inventory.json。旧0803绑定不含本次提示修复；生产转换/编译来源/映射尚未全部闭合，用户Tools也仍在运行，本轮未改authority、签包、正式安装或上传，后续须完整同源构建和新原生准入后统一发行。
