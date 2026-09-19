# 城墙摧毁：抖动后水晶爆炸

## 表现与接入

- 已建成的十阶城墙死亡时，复制当前模型、比例、朝向与世界坐标到无阻挡视觉实体，隐藏尸体。1 秒内逐渐加强横向抖动和轻微倾斜；墙顶出现白蓝蓄光与向内聚拢的光点。
- 1 秒后移除视觉墙体，同时播放白蓝闪光、地面扩散光环、44 片立体水晶碎片、余光和冰晶爆裂音效。碎片有随机速度、旋转、重力和缩小过程。属于水晶爆炸风格的原创组合，没有使用《英雄联盟》的游戏资源。
- `systems/wall_destruction_visual.lua` 管理表现生命周期。位置取实体世界坐标，视觉高度取十款模型的实际渲染尺寸，不使用较矮的物理碰撞高度。
- `building_system.lua` 的真实死亡事件调用表现；计数、人口、网格和城墙阻挡立即释放。表现不改变真实单位位置，不参与寻路或点选。
- 普通模式保留原有城墙死亡败北规则：立刻锁定败北，延至死亡后 1.45 秒调用 `SetGameWinner`，让 1 秒后的爆炸先显示。调用结算前释放服务器句柄，有限寿命粒子自然结束，避免结算冻结游戏时钟造成残留。无尽模式仍按原有规则处理。
- 重复死亡不会重复播放。未建成城墙、断线清理不播放；地图重置取消残留表现与延迟结算。死亡建筑不能因 UI 查询被重新恢复为占地建筑。

## 资源与重建

新增 6 个原生 VPCF、1 个 8 面水晶碎片模型、3 个分面材质；粒子使用 Dota 自带的光晕和光环纹理，音效使用 Crystal Nova。入口已预载粒子、碎片和音效。

```powershell
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/build_wall_destruction_assets.py
& ./tools/install_wall_destruction.ps1
& 'D:/magic and love/软件/Blender/5.2/python/bin/python.exe' -X utf8 tools/verify_wall_destruction.py
```

生成文件位于 `output/wall_destruction/source/`，安装器复制到配套 content addon 并编译到 game addon。共享纯白纹理依赖现有 `build_white_glow_color.png`。将来重建城墙并改变高度后，需重跑此生成器，更新 `config/generated/wall_destruction_models.lua`。

## 验证（2026-09-16）

- 6 粒子、碎片模型与 3 材质编译通过；审计实际编译内容的有限寿命、重力、资源依赖以及无物理/选择盒。Source 2 按 CRC 跳过未变资源，校验源文件内容与编译日志，不以文件时间判断失败。
- 7 项相关 Lua 检查通过：表现生命周期、死亡流程接入、塔死亡后重建、城墙配置、网格对齐、施工表现和流光外壳。包含 1 秒前不爆炸、只爆炸一次、尸体提前删除不影响播放、立即释放占地、结算前释放句柄、重置和资源失败降级。
- Workshop `template_map`：十阶城墙蓄光/爆炸实际可见；`charge_review.png` 和 `burst_review.png` 为暂停帧，包含暂停界面，仅用于渲染确认。连续运行采样 0.767 秒未爆炸、1.133 秒和 1.467 秒已爆炸，2.8 秒后活动表现与代理均为 0。
- 一级临时城墙经过真实 `Kill` → `entity_killed` → 建筑系统：0.167 秒时表现/代理均为 1，建筑已不可查询；1.167 秒时代理为 0、爆炸仍活动、状态仍为 10；随后进入状态 11，活动表现、代理和该城墙阻挡均为 0。实际只验证一级真实死亡与十阶视觉，未逐一摧毁所有 30 个等级。
- 该 Workshop 版本的 `ForceKill(false)` 未产生所需死亡事件；它仅用于独立表现探针。真实死亡测试使用 `Kill(nil, unit)`，没有手工发送死亡总线事件。
- `tests/manual_wall_destruction.lua` 是显式 Tools 测试入口，不由生产代码加载。`start(10, .8)` / `freeze_at(1.1)` 用于暂停帧；`trace(10)` 连续采样；`defeat_test()` 会结束当前临时测试局；`clear()` 清理样本、释放相机并解除暂停。
- 最终 `WALL_DEATH_FINAL 11 0 0 0`、`WALL_DEATH_PROBE_CLEAN 0 0`。报告分别在 `output/wall_destruction/verification.json` 和 `runtime_verification.json`。
- 额外运行的旧 `test_building_state_recovery.lua` 在第 118 行有既存玩家编号断言不匹配，禁用新增表现后仍相同失败；未修改此无关测试，也未计入 7 项通过结果。
