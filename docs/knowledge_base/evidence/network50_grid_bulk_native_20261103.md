# 网格低频 bulk：原生消息尺寸实测

仅本地更新。本证据只覆盖独立最小 Tools addon 的 `gb/d` 序列化，后台、SDK及游廊未由本探针修改。不是完整网格功能、普通客户端、四人联机或 FPS 验收。

用户当前范围是高频同步每条不超过 50B、其他按总流量优化。未知地图冷位图另获低频每条不超过 1KiB 的 bulk 范围；常态 `cw/d` 的 24 ASCII 预算保持独立，不能将本次结果称为所有消息都小于 50B。

## 实测

主操作者运行并正常关闭独立 `bulk02`，完整闭合日志由工具配对每条 `CUserMsg_CustomGameEvent [148]` 的原生 bits、实际单键 `gb/d` ASCII 值长度。没有按固定封装开销倒推。

| d 的 ASCII 字节 | 原生 bits | 向上取整字节 | 实测封装字节 |
| ---: | ---: | ---: | ---: |
| 64 | 706 | 89 | 25 |
| 128 | 1234 | 155 | 27 |
| 256 | 2258 | 283 | 27 |
| 512 | 4306 | 539 | 27 |
| 896 | 7378 | 923 | 27 |

最大 923B 小于 1024B。较大载荷的 protobuf 长度边界改变封装开销，不能把旧 `cw` 小包的 `+25B` 直接用于 bulk。这里的 native 字节是引擎消息层 bits 向上取整，不包含 UDP/IP/Steam 外层包头。

实际 Client build 为 `10938:11198969`；先前 `cw` 标定为 `10938:11175759`。两次 `networksystem.dll` 摘要相同，但不宣称 Client revision 相同，也不重新给旧客户端验收背书。

## 来源与脱敏

- 完整闭合日志：`output/network50_native_probe_20261103/bulk02/engine.log`，SHA256 `ce05e75e1373de45e37d10a9232b387d6ac49ad15089f79a9f32c0c54ff9ceac`。
- 原始测量回执：同目录 `native_budget.json`，SHA256 `9c4e2c4e13afbdcdd1986054ef7d33e3b1f9a83e2d8ee42ea9fcb895f93ad41b`。
- 安全公开证据：`data/ui/ui_grid_bulk_native_evidence_20261103.json`，SHA256 `a0abafc8316771836e4c6405cbb3e653f0c498d7aabcbc41dd49b3b630f1ae06`。仅公开尺寸、构建号和摘要，无账户、session、PID、启动 argv 或原始网络字串。
- `networksystem.dll` SHA256 `7acebae03d1c558e819963d2e552c2d1aab0487c6688b6ece21b6b659f3506e2`。
- 原样复制的正常 `maps/template_map.vpk` SHA256 `59c5856b44a75a3db5659fb15dd2038480a102c450ae5a27141e890b201bcf33`。
- 最小探针 Lua SHA256 `ac611b132b1fc4bcd073fcb05b71302bd4a8a4061fc95321f8651c54677da220`。

LAB 位于 `D:/Survival_本地排演/network50_probe_20261103/bulk02/addon`，只通过独立 `svt_network50_bulk` junction 挂载；没有在 addon 的 output 中创建裸 VPK，没有导入主项目、后台或交易逻辑。探针仅发五次合成 A 字符串。

## 工具与边界

`tools/network50_bulk_native_probe_20261103.py` 提供 plan/prepare/verify/launch/close/measure/retire。启动和正常关闭由主操作者执行；measure 要求确切 PID+created 已退出、日志包含正常关闭与完整五档 sweep。纯解析/source/退役门禁/公开证据测试为 `python -X utf8 -B tools/test_network50_bulk_native_probe.py`，不冒充 native 运行。

retire 必须全部 Dota 客户端为零，且固定 junction 精确指向已绑定外部 LAB、真实闭合测量及来源摘要均匹配；只移除该 junction，保留 LAB、map、Lua、进程/准备回执与完整日志。该动作由主操作者另行执行，本记录不预称已退役。

完整网格的 metadata、四个真实位图片段、K delta、关闭取消、owner/epoch/scope 恢复及总流量仍须以新实际项目客户端验证；本次仅标定该事件名和载荷档位的 native 上限。没有 ETW/FPS 数据，发行签名、上传与官方完整下载均不是本探针的证据范围。
