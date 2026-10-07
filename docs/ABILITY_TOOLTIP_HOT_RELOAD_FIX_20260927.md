# 技能图标悬停说明修复（2026-09-27）

## 原因

实机日志显示 `SURVIVAL_TOOLTIP_ERROR stage=proxy_mouseover ... Underlying panel is deleted!`。只读诊断进一步确认 CustomAbilityFields.__fieldRows 保留旧 JS 引用，而 row、left、right、iconHost 的 IsValid() 全部为 false。Panorama 热更新删除动态子节点后，面板上的缓存属性仍存在。再次悬停时，render 直接对已删除 row 写 visible，抛出异常，说明面板无法显示。

## 修改

ability_tooltip.js 增加 resetFieldRows：复用前检查行、文字节点、图标容器与图标有效性；任一失效则清理旧子节点和缓存，重新创建说明字段。正常悬停继续复用有效节点，不每次重建。错误日志增加 stack，并保留仅 Tools 可用、名称带时间戳的只读 inspect 命令，方便后续定位。

## 验证

- test_ability_tooltip_stability.cjs：覆盖整个字段行删除、部分文字节点删除、图标删除后的恢复，以及连续悬停不会反复重建。
- test_ability_tooltip_recovery.cjs：全部通过，覆盖延迟 HUD、节点替换、快速选择、停止回调、原生空技能等。
- 编译 1 项成功、0 失败；源码同步 content，编译资源已更新 game。
- 实机确认修复前缓存 valid=false；修复后真实鼠标悬停多重攻击LV5，tooltipHidden=false，显示伤害说明。
- 实机研究所 entity=856：研究伐木工攻速、研究高级伐木效率均 tooltipHidden=false，完整当前/下一级效果和扣费时机，7 个字段行 invalidRows=0。
- 验收时用户同时切换单位和移动鼠标，未宣称六格逐项全部实机通过；其余技能共用同一修复路径，自动化测试通过。
- 不改技能数值、鼠标点击或科技发放逻辑。

## 全局影响范围复核

用户进一步指出建筑和英雄技能均受影响。补充 test_ability_tooltip_recovery.cjs 集成回归：主城、农场、金矿、普通研究所、高级研究所、箭塔、城墙、英雄祭坛、建造师、Doom 英雄技能，共 10 类入口。测试实际执行生产 onmouseover/render，模拟引擎删除动态字段但保留 JS 缓存，再次悬停验证重建、文本及无异常。

同一组新增测试在 HEAD 旧版本下 10 项全部失败（Underlying panel is deleted），当前修复版本 10 项全部通过。原有 11 项恢复测试继续通过。只读实机检查额外确认主城升级 tooltipHidden=false、全部字段有效；后续读取到训练高级修理工的完整说明。修复位于共用 render 路径，无研究所或单位类型限定。
