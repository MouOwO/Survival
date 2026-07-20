# Survival CSV 配置目录

此目录是项目配置的主编辑入口。不要直接修改 `scripts/vscripts/config/generated/*.lua`。

## 分类

- `英雄系统`: 英雄属性、初始技能、专属技能、技能池与召唤规则。
- `物品系统`: 内容目录、物品、武器、成长、配方与效果。
- `商店系统`: 分类、商品、条件、祭坛动作与权限。
- `建筑与工人系统`: 建筑、升级、科技、训练与 UI 解锁。
- `怪物与波次系统`: 怪物模板、遭遇、出生点和波次。
- `挑战与奖励系统`: 挑战、转生、奖励和遭遇奖励关联。
- `公共规则`: 枚举与待确认数据问题。

## 修改流程

1. 在对应分类目录修改 CSV，保留第 2 行 `#types:` 类型定义。
2. 从项目根目录执行 `build_configs.bat`。
3. 检查输出必须包含 `CONFIG_BUILD_PASS`。
4. 完全重启 Dota 2 Workshop Tools 后测试。

生成脚本递归读取所有分类目录，输出到 `scripts/vscripts/config/generated`。物品栏 Tooltip 的名称和描述来自 `物品系统/content_catalog.csv`；武器原生物品名映射来自 `物品系统/weapon_definitions.csv` 的 `engine_item_name`。

当前目录由 `Survival_V1.6_WeaponGrowthLogicalStats/data/csv` 整理而来。旧文件中存在 UTF-8 和 GB18030 混合编码，生成器会兼容读取；后续保存建议统一使用 UTF-8。
