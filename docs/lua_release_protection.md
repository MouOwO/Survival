# Lua 发布保护

开发目录里的 Lua、CSV 保持可编辑。保护工具只创建项目外的全新候选目录，绝不覆盖开发原件，也不自动上传 Workshop。

Based on Prometheus by Elias Oelschner, https://github.com/prometheus-lua/Prometheus

本项目的离线适配器采用 [Prometheus 官方源码](https://github.com/prometheus-lua/Prometheus)，固定提交 `a4efc5f381c50ae2a111bdbb9272fa3203685be3`。官方 [library 用法](https://github.com/prometheus-lua/Prometheus/blob/a4efc5f381c50ae2a111bdbb9272fa3203685be3/doc/guides/using-as-a-library.md) 和 [配置说明](https://github.com/prometheus-lua/Prometheus/blob/a4efc5f381c50ae2a111bdbb9272fa3203685be3/doc/guides/writing-a-custom-config.md) 是接口依据。源码下载保存在 `D:/Survival_安全工具/prometheus`，不进入游戏目录；源码和 LICENSE 的实际 SHA256 锁在 `tools/lua_protection_policy.json`。其他机器若文件换行不同导致锁不匹配，应先核对明确差异，再审核更新锁，不能跳过验证。

这是增加逆向成本的 **Lua 混淆**。常量池、字符串编码、可选的字符串解码器、数值表达式和局部变量改名都不能提供 AES 的密码学保密。玩家必须使用的值在执行后仍可恢复。AES-256-GCM 用于外部私有源码备份；付款密钥、账户结算及真正保密的数据必须保留在服务器，不应分发给客户端。

默认保护 `config/generated` 下的数据表，保留 `index.lua` 注册器与独立可执行的 `item_resources.lua`。另外保护 `content_id_aliases`、`armor_balance`、`mode_progression`、`release_policy` 四个业务规则模块。`release_profile.lua` 始终保留字面量配置，发布工具必须读到明确的 `production` 才放行。

使用本机已安装的 Lua 5.1 / luac 5.1，基础候选命令如下，输出必须是尚不存在的绝对外部路径：

```powershell
python -B -X utf8 tools/protect_runtime_lua.py `
  --prometheus-root 'D:/Survival_安全工具/prometheus' `
  --output 'D:/Survival_发布候选/lua_NEW_RELEASE'
```

只对已证明返回纯数据表的生成模块增加字符串混淆：

```powershell
python -B -X utf8 tools/protect_runtime_lua.py `
  --prometheus-root 'D:/Survival_安全工具/prometheus' `
  --output 'D:/Survival_发布候选/lua_NEW_RELEASE_strings' `
  --data-string-obfuscation
```

字符串解码器的 `math.random` 被限制在词法局部的 math 副本与私有 PRNG 中，不能推进游戏的全局随机数状态；四个业务模块继续使用基础配置。没有启用 AntiTamper、Vmify、自更新入口、在线服务或 Lua 字节码。构建适配器用 17 位有效数字输出数值，避免上游 Lua 5.1 `tostring` 的默认精度损失。数值只有在精度检查通过时才改写为表达式，不能保证每一个数字从文件中消失。

每次构建都必须通过以下实际检查：所有运行 Lua 的 luac 5.1 语法检查、所有保护数据表的完整深层同值检查、四个业务模块的行为探针、无 io/os/debug 环境加载、加载时不调用游戏随机数，以及构建前后开发源码哈希一致。报告在外部候选的 `_lua_protection_report.json`，包含每个文件的前后 MD5/SHA256、大小及本机解析加载耗时。任何选中模块失败都会标记 `FAILED_DO_NOT_PUBLISH` 并停止，不允许改成明文后继续发布。

2026-10-21 的实测候选 `D:/Survival_发布候选/lua_20261021_security_04_strings` 已通过：176 个完整数据表精确同值、四个业务探针、全部 785 个运行 Lua 的语法检查。180 个选中模块在本机 Lua 5.1 的一次解析加载合计为原始 `0.071s`、保护后 `0.821s`。这只是离线加载比较，尚未在 Dota 原生环境实测，也没有上传发布。

输出是完整 Lua 树，不是完整游戏包。将通过检查的 Lua 树用于独立正式运行包候选后，必须重新生成整个正式运行包的双哈希 manifest、执行全量 verify，最后签名该最终 manifest。不能沿用混淆前的摘要或签名。依赖源码/保护工作脚本、原始 CSV、PSD、测试、服务器及密钥不能加入运行包。先通过 Dota 原生环境的进入地图、选择难度、波次、商城、抽奖、存档冒烟，再手动执行平台发布；本机 Lua 校验不等于实机验证。

`tools/release_security/assemble_release.py` 自动执行上述运行包组装和签名顺序。它读取固定的 `protection_policy.json` / 公钥和 Lua 保护策略，核对每个保护模块的原始及保护后摘要，重新执行语法、数据同值和私有随机数检查，仅覆盖选中的保护文件，其他代码来自当前最新开发目录。签名私钥必须是显式外部路径，序列号必须达到可信策略规定的最低值；序列号的递增由发布负责人管理，不能根据下载包自行降低。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  tools/release_security/assemble_release.py `
  --protected-lua 'D:/Survival_发布候选/lua_20261021_security_04_strings' `
  --destination 'D:/Survival_发布候选/runtime_NEW_RELEASE' `
  --signing-key 'D:/实际外部密钥目录/signing-key.pem' `
  --sequence 2026102101
```

完整运行资源先写入目的目录同级的唯一临时目录，所有摘要、签名和检查通过后才改名成指定新目录。成功标记是 `_RELEASE_READY_FOR_NATIVE_SMOKE.json`，只表示可以进行实机冒烟，`ready_for_upload` 仍为 false。失败会留下 `_RELEASE_FAILED.json` 和可定位的失败临时目录，不允许用明文回退后继续发布，也不覆盖旧候选。运行包包含最终 `_release_manifest.json`、`_release_signature.json` 和 `_release_verification.json`；原始 CSV、设计资料、后端、私钥均不进入运行包。

当前第三方许可证保留在外部依赖的 `LICENSE`。它允许生成结果不携带版权通知，并要求使用该工具的产品/文档保留署名；本文和适配器帮助文本均保留上方的完整署名。下载公开依赖需要网络，实际保护过程只读取本地固定源码，不上传项目源码。
