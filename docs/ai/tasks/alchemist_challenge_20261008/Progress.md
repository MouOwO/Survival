# 炼金挑战怪缺头修复

## 原因

`challenge_monster_05` 使用炼金主体，但未声明 `default_wearable_asset_id`，因此召唤链路中的 `monster_hero_visual_service.apply` 返回 `default_wearable_not_declared`。Valve 的炼金地精头、食人魔头以及地精身体都是独立穿戴模型，主体本身不能呈现完整角色。

## 修改

- 挑战配置声明 `monster_default_alchemist`，保留原有数值、缩放、奖励和冷却。
- 新默认资源包包含 Valve ItemDef 117–125 的完整九件模型，使用现有 `prop_dynamic` 与 `bone_merge` 挂载流程。
- 包纳入现有 `monster_default_wearables` 同步预加载组；新增原生异步代理也声明完整模型。
- 原生挑战单位出生模型改为炼金；命名同步工具读取建筑挑战的模型声明，避免再次生成时回退到尸王。
- 使用现有 `build_lottery_configs.ps1` 的 CSV 序列化函数单独生成三个表；与修复前工作区逐行比较，其他已有资源数据保持一致。
- 更新资源契约，区分正式波次默认资源和建筑挑战默认资源；新增生命周期回归，并在 `.gitignore` 中允许该测试进入后续正常提交。

## 验证

- 新回归：修复前准确失败，修复后验证九件模型及两颗头的挂载、重复应用无重复生成、尸体保留、最终清理、延迟回调安全及初始预加载。
- 十罪外观、模型挂载成本/生命周期、挑战头像外观、入口预加载回归通过。
- 本机 Dota 2 `pak01_dir.vpk` 核对 ItemDef 117–125 与 CSV 中的模型和槽位一致；主体及九件组件的 `.vmdl_c` 均存在，原生代理声明完整。
- 生成 Lua、测试 Lua 和同步脚本语法检查通过。
- `tools/test_monster_hero_wearable_contract.py` 仅更新本次新增挑战资源的约束；未运行其整套 Python 检查，本机没有可用 Python 解释器。
- 当前测试游戏控制台未返回探测结果，未获得修复后的实机截图。重载地图后由正常生成链路加载新配置；没有强制重启或干预当前对局。

## 检查点

`output/alchemist_challenge_20261008/before/` 保存修改前目标文件，`checkpoint/` 保存修复后的目标文件、验证脚本及测试。验证记录位于 `validation/20261008/alchemist_challenge_heads.json`。

这次没有提交或推送，也没有改动其他任务的业务代码。后续提交按项目要求执行 stash → pull → pop → commit → push；恢复时先比较检查点与当前文件，避免覆盖并行任务的更晚修改。
