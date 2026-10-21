# 发布保护、校验与外部备份 · 2026-10-21

本轮已完成引用隔离、生产作弊门禁、完整文件校验、Lua 数据保护和加密源包。完整候选在 `D:\Survival_发布候选\20261021_secure_release_01`，状态为 **READY_FOR_NATIVE_SMOKE_ONLY**，`ready_for_upload=false`。尚未进行 Dota 实机验收或工坊上传。

| 内容 | 实际结果 |
| --- | --- |
| design_refs | 21 个零引用产出、61,300,079 字节移到项目外；引用文件继续保留 |
| 生产作弊门禁 | 默认 production 拒绝；开发命令必须同时满足 development、服务器端、Tools 模式 |
| 发布文件 | 6,619 个，3,776,907,831 字节；逐个 MD5、SHA256、清单签名均校验通过 |
| 原始 CSV | 180 张记录双摘要；原表不进入客户端发布包 |
| 运行 Lua 数据 | 176 个生成表、4 个规则模块已保护；176 表所有值和4个规则探针通过 |
| 其他 Lua | 605 个模块仍为原始可读 Lua；没有宣称全部代码已加密 |
| Lua 语法 | 完整候选 785 个运行 Lua 均通过 Lua5.1 语法检查 |
| 加密源文件包 | 10,500 个文件，原始874,857,070字节 → 密文805,565,629字节；完整解密验包通过 |

原始 CSV、开发 Lua 和美术源文件继续保留，便于正常编辑和生成。源文件 AES 保密备份与可运行的 Lua 混淆是两种不同机制；没有把客户端可解码的常量编码当作密码学保密。

**你需要做的事：**

1. 备份 `D:\Survival_密钥\20261021_release_01` 到独立安全介质。`data-key.bin` 用于恢复 AES 源包，`signing-key.pem` 用于签署后续版本；缺少对应密钥就不能恢复/签名。不要随客户端分发，不要加入 Git，也不要把它与加密包一起公开传输。当前目录仅允许本机当前 Windows 账户和 SYSTEM；ACL 是账户访问控制，不代替离线密钥保管。
2. 对完整候选做独立 Dota Tools 实机测试：进入地图与等待流程、主城/建造、波次/野怪/练功房、商城/抽奖/收藏/福利，以及生产配置下原作弊命令不增加资源、不解锁数据。检查字符串、数值、报错和加载耗时。候选未覆盖开发目录；验证前不要把保护产物复制回开发源码。
3. 实机通过后，按现有工坊发布流程发布新候选。以后每次发布使用新的序号，例如本次 `2026102101`、下次 `2026102102`；核验方的最低序号来自可信本地配置/发布记录，不能相信下载包自己声明的最低号。CSV、Lua 或资源改变后重新生成、保护、校验和签名，不要沿用旧清单。

以下是本轮采取的规则和复现入口。

**引用隔离与还原。** 扫描两个仓库的代码、工具、文档、相对链接、设计目录内部引用及动态目录锚点。被动盘点记录不当成会打开文件的依赖；实际代码/工具/文档引用均保留，内部互引岛也保留。R5 参考稿仍供当前工具读取，因此保留；R1–R4 HTML 和其余零引用文件移入 `D:\Survival_待删除\20261021_security_01`。5 个原有访问受限的历史目录未动。

外部批次包含原路径、大小、SHA256、双仓 HEAD 和追加操作日志。移动前后逐项校验；恢复不覆盖已修改的同名文件，备份继续保留。

```powershell
$securityPython = 'D:\Survival_安全工具\venv\Scripts\python.exe'
# 先查看将还原什么；此命令不修改游戏。
& $securityPython -B tools/quarantine_design_refs.py --restore 'D:/Survival_待删除/20261021_security_01/quarantine_manifest.json'
# 确有需要时加 --apply 执行还原。
```

**作弊规则。** `scripts/vscripts/config/release_profile.lua` 默认 `channel = "production"`。`core/release_policy.lua` 统一判断，只有显式 development 且 `IsServer()==true`、`IsInToolsMode()==true` 才放行。`sv_cheats`、房主身份、聊天指令和客户端 debug 字段不能把生产包改成开发包。聊天监听的注册、执行入口、调试事件处理器和延迟回调均有门禁；正常购买、档案和常规游戏请求保留。

本地开发如确需原作弊命令，明确使用 development 的本地配置并在 Tools 运行。发布工具严格解析 production 配置，缺失、development、重复/可执行字段或注释伪装都拒绝；不能靠编辑注释绕过发布检查。

**哈希、更新和签名。** `tools/build_runtime_release.py` 生成 schema2 清单，覆盖发布白名单内的全部文件，包含路径、大小、MD5、SHA256 和整体内容 ID。MD5 用于兼容现有变化索引；文件完整性使用 SHA256，发布者身份使用固定可信公钥验证 Ed25519。SHA256 属于 NIST 列出的 SHA-2 算法族；不要把 MD5 相同当作攻击下的真实性证明。[NIST Hash Functions](https://csrc.nist.gov/Projects/hash-functions)

验包会报告缺失、修改、意外运行文件、清单路径越界和非生产配置；失败返回非零，不写游戏文件。与上轮本地清单的实际差异为新增7、修改237、移除0，仅用于对比，不代表线上版本已更新。

```powershell
# 在项目根目录执行。真实候选已经这样核验通过。
& $securityPython -B tools/build_runtime_release.py --root 'D:/Survival_发布候选/20261021_secure_release_01' --verify 'D:/Survival_发布候选/20261021_secure_release_01/_release_manifest.json' --report output/runtime_verify.json
& $securityPython -B tools/release_security/protect_data.py verify-signature --manifest 'D:/Survival_发布候选/20261021_secure_release_01/_release_manifest.json' --signature 'D:/Survival_发布候选/20261021_secure_release_01/_release_signature.json' --public-key tools/release_security/trusted_public_key.pem --minimum-sequence 2026102101

# 后续对比：生成新清单，并列出新增/修改/移除，不直接应用更新。
& $securityPython -B tools/build_runtime_release.py --manifest output/runtime_new.json --baseline output/runtime_previous.json --diff output/runtime_diff.json
```

签名绑定完整运行文件清单和发布序号。验证签名后仍必须核对实际文件，不能只相信包内的 READY 标记或随包替换的公钥。可信公钥及其指纹固定在仓库保护策略中，私钥不进入发布包。[Ed25519 官方接口](https://cryptography.io/en/latest/hazmat/primitives/asymmetric/ed25519/)

这里的全量文件校验是发布/离线验包入口，不是假装 Panorama 能遍历并改写任意本地磁盘。现有奖池登录 MD5 比较、本地缓存和服务端更新广播继续使用；静态 Lua、图片、模型和地图通过工坊版本更新。没有新增绕过工坊、自行替换代码或资源的客户端加载器，也未发布新的云端服务。

180 张源 CSV 的 MD5/SHA256 与对应生成模块摘要在 `validation/20261021/source_csv_integrity.json`。快照不声称重新运行了所有业务生成器；修改原 CSV 后，应先按其现有数据流程生成运行模块，再进行发布保护。后台商城导入表、图标表等由独立生成器消费，不是每张原表都对应同名 Lua。

**Lua 保护。** 使用固定版本、离线运行的 Prometheus，锁定 commit `a4efc5f381c50ae2a111bdbb9272fa3203685be3`、83份依赖源文件的整体SHA256及许可证SHA256。转换不上传游戏源码，绕开上游在线更新入口，不执行其安装器。策略在 `tools/lua_protection_policy.json`，以 Lua51 为目标，保留原模块路径、返回数据和业务规则；工具与文档保留上游署名。Prometheus 本身是 AST 混淆工具，不是提供密码学保密的运行时保险箱。[Prometheus 官方文档](https://prometheus-lua.github.io/Prometheus/docs/)

Based on Prometheus by Elias Oelschner, https://github.com/prometheus-lua/Prometheus . 固定版本许可证保留在项目外依赖目录中，摘要记录在策略内。

176 个纯表模块采用常量池去重、字符串编码、数值表达式和局部改名；字符串解码使用词法局部的 math 副本与私有 PRNG，不消耗游戏随机数。4 个规则模块使用基线变换。禁止 AntiTamper、Vmify 和依赖调试库的步骤；发布 profile 保持明文，供发布前严格检查。`item_resources.lua` 的可执行解析器与 `index.lua` 注册入口保持原样；605个其他模块没有被悄悄标成已保护。

数值精度逐项验证：曾拦下一次上游输出把 `0.33333333333333331` 缩短的失败构建，随后使用仅影响构建进程的17位数值格式适配并重新校验。增强字符串配置曾因重复字符串造成超时，失败候选明确禁发；先去重再转换的最终04候选全部通过。没有失败后回退到明文的路径。

最终180模块本机单轮 Lua5.1 解析加载约0.071秒→0.821秒；这是本机离线测量，不是 Dota 帧率或实机加载承诺。保护后的相关源码体积约7.51MB→14.85MB。

**真正的保密加密。** 原始180张CSV、Lua/Panorama源码、服务端与工具代码、美术原图保存在 `D:\Survival_加密备份\20261021_source_01\survival_sources.svault`。采用 cryptography 的 AES-256-GCM：32字节随机密钥、每包独立12字节随机nonce、认证头和16字节tag；加密ZIP中的完整路径、大小、MD5/SHA256清单也被认证。密钥不与密文一起发布。GCM nonce不能重复；库文档也明确强调这一约束。[cryptography AEAD 文档](https://cryptography.io/en/latest/hazmat/primitives/aead/)

该源包不是 Dota 能直接运行的文件。运行时图像/模型/声音继续使用原生编译格式，并由全文件校验与签名保护；本项目没有经过引擎验证的资源密文加载器，所以没有把纹理、KV或模型直接替换成AES密文。分发给客户端、需要由客户端解码显示的数据，不能宣称永久无法提取。重要结算、扣费和发奖继续以服务端既有权威结果为准。

```powershell
# 只验证和解密校验，不写回开发目录。
& $securityPython -B tools/release_security/protect_data.py verify-vault --vault 'D:/Survival_加密备份/20261021_source_01/survival_sources.svault' --key 'D:/Survival_密钥/20261021_release_01/data-key.bin'
# 若需恢复源包，加 --restore 指向一个项目外、尚不存在的新目录。
```

源包恢复先完成认证与逐文件核验，再写私有临时目录，全部成功后发布为新恢复目录；错误、错误密钥、尾部/头部篡改或磁盘写入失败都不会覆盖开发文件或留下可误用的最终半成品。路径拒绝链接、越界、Windows设备名、尾点和尾空格；超过8GiB源数据或8MiB清单时需分卷。

专用工具环境是 `D:\Survival_安全工具\venv`，不在游戏内。cryptography 50.0.2及依赖从PyPI下载，逐wheel与PyPI官方SHA256核对后离线安装；Windows/Python3.14锁文件在 `tools/release_security/requirements-win-py314.lock`。服务器支付环境和它现有的依赖锁未修改。

**重新构建。** 更新数据并通过相关测试后，先构建新的外部 Lua 保护树，再用完整组装器；不要覆盖旧候选，输出使用新目录，序号按可信发布记录递增：

```powershell
# Prometheus根目录和本机Lua路径可在工具帮助中查看；先完成保护构建。
& $securityPython -B tools/protect_runtime_lua.py --help
& $securityPython -B tools/release_security/assemble_release.py --protected-lua 'D:/Survival_发布候选/<新的已验证Lua树>' --destination 'D:/Survival_发布候选/<新的完整候选>' --signing-key 'D:/Survival_密钥/20261021_release_01/signing-key.pem' --sequence 2026102102
```

组装器复制完整原生运行包，只覆盖通过策略与源哈希检查的保护模块，重新执行完整Lua语法、数据/规则/随机数探针、全部MD5/SHA256和签名验证，最后原子发布外部目录。失败不覆盖旧候选、不替换源码、不上传，也不把选中模块回退为明文。

验证记录在 `validation/20261021/release_security.json` 和本机 `output/release_security_20261021/`。本轮通过：250种门禁组合、89个真实调试入口检查、32项相关游戏回归、13项隔离恢复测试、发布清单20个用例（1项Windows创建链接权限跳过）、7项Lua构建测试、7项完整组装测试、11项加密签名测试及16项独立复查。源包10,500文件已完整解密认证核验，最终6,619文件在发布目录改名后再次全量核验通过。

未完成的验收是 Dota 实机冒烟与正式工坊发布。未修改服务器支付代码；额外Python支付全套测试因专用工具环境未装psycopg而未运行，正常游戏支付桥的相关Lua回归已通过。
