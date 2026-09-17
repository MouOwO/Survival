# 本批工作记录（已收尾，2026-09-11）

最新状态：本批 **331 / 331** 新图完成，连同原有四张，共 **335 张**已映射并部署到 `survival_ui_handoff_v1`，版本 **2e781d8614**。audit 的 pending / issues 均为空，670 张 BGRA8888 纹理编译完成。生成 cell 381 已结束，**不要重新启动整批任务**。

积分与秘法最后各页、每日奖励、实际金币木材商店和共用奖池图已经实机检查。原资源审阅页、分类实机索引均已更新；图标试览不代表玩家持有或奖励发放。

本轮 UI 状态修正和剩余阻塞见 [最新交接](../../ui_state_completion_v1/README.md)，截图与录屏见 [证据索引](../../ui_state_completion_v1/evidence/index.html)。后续从新对局 BOSS 实机验证、真实付费接口和待配置额外装备继续，不重复生成已完成图。

---

以下是制作过程历史，不是当前待办：

阶段记录：已部署 `ab35e63403`，270 张映射（266 新图 + 原四张）。好友、前女友、瑞兽均已各 40 张齐全并实机检查；鱼类 26、神兵 12、建筑 9、商店 10 也已整组检查。内置生成任务在当前会话 cell `381` 中继续，从第 149 项延续到 331；不要在它运行时重复启动。PNG 文件是实时完成依据。

原 cell 301 在 friend_20 的记录写入步骤失败，原图已恢复，错误记录移为 `friend_20.recovery.json`。云界旗、两位角色与小舞做过修订，当前有效来源在 receipts，修订提示词在 revisions。`tools/audit_archive_art.py` 检查来源原始字节、Alpha、主体触边与重复图片；角落允许一个 1/255 的量化残点并记录原值。

最终还需：等待生成全部结束；审阅最后的积分/秘法图；audit → import → prepare → verify（等待进程真正完成）→ deploy_test → 实机检查积分/秘法及奖池共享图 → build_bulk_art_evidence.cjs → verify_artifacts。最后更新本文件和 README 完成状态。

目标为已启用配置中的 331 项新图，加上原先已认可的 4 张虚空之影图。项目业务表不改。

`prompts.json` 是逐图任务来源，`receipts/<item_id>.json` 记录内置生成器原始保存路径。每张图完成后立即复制到项目 `panorama/src/images/custom_game/archive_items_v2/`，可以按文件存在性继续；不要重复生成已有图。若有 `.error.json`，先检查生成器返回错误，不自动切换收费 API。

接入与验收顺序：

1. `tools/import_archive_art.py` 登记已完成资源。
2. `tools/build_archive_art_review.py` 更新资源审阅页与各分类联系表；这些不是游戏截图。
3. `node art/ui/development/remaining_ui_handoff_v1/prepare.cjs`。
4. `node art/ui/development/remaining_ui_handoff_v1/verify.cjs`。
5. `pwsh -NoProfile -File art/ui/development/remaining_ui_handoff_v1/deploy_test.ps1` 部署已存在的隔离测试地图，需要其 content/runtime 写权限。
6. 存档实际分类与「图标试览」检查；抽奖详情、现有金币木材商店检查共享图片映射。

运行纹理注意：`prepare.cjs` 生成两套原生 `.vtex` 编译配方，`build.json.textureInputs` 必须在布局之前显式编译，不能只依赖预加载 XML 对 `s2r://` 的依赖扫描。运行时使用 BGRA8888；先前的 DXT5 试验画面颜色错误，不可回用。配方由母图构建，RGBA 原图保持字节一致。

UI 试览每页 8 项，分类切换与翻页只重建当前页；层级为 20，高于原抽奖操作栏 10，避免底部按钮被盖住。真实存档卡片依旧由原服务端列表决定数量和解锁状态。

Python 使用 `C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe`，系统 `py -3` 不可用。

本轮开始前的 UI 适配器、表格和校验器备份位于 `before/`；旧正式 UI 及已有隔离测试 HUD/存档控制器受部署脚本哈希保护。

范围说明：配置中的商店可授予内容共 10 项，挑战/转生操作不作为商品图标任务。U 币/积分付费商城适配器当前没有真实商品目录，已接上同一个图片查找接口，不编造商品、金额或支付结果。积分道具表中的抽奖/兑换物品全部进入本批清单。
