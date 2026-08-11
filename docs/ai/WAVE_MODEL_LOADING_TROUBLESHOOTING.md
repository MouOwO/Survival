# 波次模型加载故障排查与防复发经验

## 文档用途

本文记录W12 Visage模型告警的排查结论和可复用处理流程，供后续Cline会话在新增、替换或排查逐波模型时直接使用。架构细节见`WAVE_MODEL_RESOURCE_LIFECYCLE.md`。

2026-08-11用户后续观察中暂未再发现加载问题。这是阶段性实测反馈，不代表未来新增模型、冷资源路径或长时间波次运行一定不会复发；再次出现同类告警时应按本文从权威CSV和三条模型解析路径开始检查。

## 原始症状与确定根因

原始引擎告警：

```text
models/heroes/visage/visage.vmdl requested is not loaded and may have been deleted
```

该文本不能直接证明模型文件被删除，也不能直接证明尸体清理卸载了模型。本次确认Visage路径、Dota资源和项目异步代理均存在，真正缺陷是模型解析不一致：

- 正式预载和怪物出生按实际角色解析到Visage；
- `monster12`开发跳波曾直接读取基础`definition.model_path`，预载了另一个模型；
- 出生时再调用`SetModel/SetOriginalModel`切换到Visage，客户端可能在模型尚未准备好时收到渲染请求。

正式流程还存在第二层风险：只在首只怪前4秒请求资源时，urgent请求可能被塔和城墙的后台资源流阻塞。两个问题必须分别处理，不能只增加等待时间掩盖解析分叉。

## 必须长期保持的规则

1. **先查CSV权威数据。** 模型资产元数据以`data/csv/资源系统/asset_catalog.csv`为基础来源；逐波成员和原型模型也必须从对应CSV进入生成流程。不得先手改`config/generated/*.lua`或在运行时代码中新增第二份模型表。
2. **三条路径只使用一个实际模型解析。** 正式预载、`monster<N>`开发预载、出生时`SetModel/SetOriginalModel`必须消费同一去重后的模型集合。任何一条直接读基础字段都可能再次制造“预载A、出生B”。
3. **每波独立，不依赖前波碰巧加载过。** 每个正式波次都要能从冷状态准备自己的实际模型；共享路径只是租约层可复用，不能成为隐式前置条件。
4. **预载时点不得改变出怪业务。** 后续波在倒计时开始立即请求，在配置的4秒提前窗口幂等复核；资源准备只能提前，不能修改倒计时、数量、顺序、首只怪时刻或生成间隔。
5. **urgent资源不能等待后台流。** 波次模型请求允许与单个塔/城墙后台请求并行，资源自身状态仍负责重复请求去重。
6. **波次资源必须有会话身份。** 每次波次运行保存独立session及`planned/pending/alive`计数。只有生成完成且`pending == 0`、`alive == 0`时才能释放该会话；重叠波次不得按全局`current_wave`互相结算。
7. **共享模型使用会话租约。** 多波同时使用同一路径时，释放一个已完成波次不能移除另一个活动波次的租约。
8. **开发跳波保留模型驻留。** dev清理仍要删除怪物、附件、粒子和调度任务，并释放本次session身份；模型租约保持developer-resident，便于连续执行`monster<N>`。
9. **Lua release不等于引擎卸载。** 当前没有已确认安全的Workshop Lua模型卸载API。`asset_preload.retire()`只把项目状态置为`RETIRED`并阻止后续请求，不会证明Source 2已卸载`.vmdl`，波次生命周期禁止调用它。

## 再次出现告警时的排查顺序

1. 完全退出并冷启动Workshop Tools，避免热加载和既有资源驻留掩盖冷资源问题。
2. 从目标波的CSV成员开始，列出出生时最终会使用的精确模型路径，不要只看基础原型字段。
3. 对比正式预载、开发预载和出生解析结果；三者的去重模型路径集合必须完全一致。
4. 检查每个模型是否有`asset_catalog.csv`条目、正确`first_use_wave`、精确异步代理，以及生成Lua与CSV逐字节一致。
5. 检查模型路径是否真实存在于当前Dota VPK或项目资源中。路径存在只能排除“文件缺失”，不能替代预载时序检查。
6. 检查正式日志是否同时出现`phase=countdown_start`和`phase=lead_review`，并确认urgent请求没有排在后台流之后。
7. 检查目标session在首只怪出生前没有被提前release；存在pending或alive怪物时release必须被拒绝。
8. 分别运行`monster<N>`和正式目标波。开发命令成功不能证明正式倒计时路径成功，正式路径成功也不能证明dev解析一致。
9. 记录首只怪是否正常渲染、精确告警文本、波次、模型路径、是否冷启动以及相关预载日志，避免只记录“红色ERROR”。

## 未来为每波替换独立模型的清单

1. 在权威CSV中配置该波成员最终模型或可解析到最终模型的字段。
2. 在`asset_catalog.csv`登记资产ID、精确路径和真实最早`first_use_wave`。
3. 为精确模型提供可用异步代理或已验证的启动预载路径。
4. 通过现有生成工具定向重建Lua，禁止手改生成文件。
5. 验证正式预载、开发预载和出生解析返回同一模型集合。
6. 验证多个重叠波共享路径时，租约直到最后一个活动session结束才消失。
7. 冷启动后分别实测`monster<N>`和正式波次的第一只怪。
8. 只有全部正式波成员完成最终模型映射后，才按`TODO(FINAL_WAVE_MODELS)`条件删除临时`normal_flying_model_path`兼容层及对应测试。

## 禁止的临时修复

- 不要因为告警含`may have been deleted`就调用`asset_preload.retire()`或虚构模型卸载API。
- 不要只把4秒改得更长，却保留正式、dev和出生三套不同解析。
- 不要依赖先运行较早波次或先执行一次开发命令来“暖模型”。
- 不要在Lua代码硬编码模型路径来绕过CSV和资产目录。
- 不要把Mock、语法检查、静态契约或热加载测试描述成冷启动引擎验收。

## 当前验证状态

- 自动验证已覆盖W12模型解析一致、session release门禁、重叠租约、dev resident、urgent并行、视觉集成、VPK/代理资源、CSV生成一致和生产代码无`asset_preload.retire()`。
- 用户在2026-08-11后续运行中暂未再观察到模型加载问题。
- 当前结论是修复有效且未见复发，不是对未来新增模型和所有长时间运行路径的永久保证。
- Source 2真实资源驻留和释放行为仍只能由引擎实测观察；项目当前只承诺释放Lua层会话与租约。

## 关键入口

- `data/csv/资源系统/asset_catalog.csv`
- `scripts/vscripts/config/generated/asset_catalog.lua`
- `scripts/vscripts/systems/wave_system.lua`
- `scripts/vscripts/systems/asset_preload_service.lua`
- `scripts/vscripts/tests/test_wave_model_resource_lifecycle.lua`
- `scripts/vscripts/tests/test_asset_preload_urgent_parallel.lua`
- `tools/test_wave_model_resource_lifecycle_contract.ps1`
- `tools/test_wave_monster_model_resources.py`
