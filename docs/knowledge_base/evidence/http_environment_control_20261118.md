# HTTP三层对照：电脑HTTPS可通，本地Dota VM与游廊都未创建请求

用户要求先不经游廊，按游戏代码的形式独立发送HTTP；只有确认本地脚本能发、游廊不能发，
才继续针对游廊环境差异修改。本轮完成此对照，**正式联网仍未恢复**，没有重新发游廊包。

| 环境 | 实际结果 | 能说明什么 |
| --- | --- | --- |
| 本机Python直接HTTPS，禁用环境代理、校验TLS、不跟随重定向 | 同一匿名health地址GET 200，空JSON POST 403 | 两次均收到HTTP响应；不是电脑到后台的普遍网络阻断。403不代表授权成功，也未据此判断拒绝原因 |
| 本地Dota Tools脚本VM，不通过游廊 | 同一工厂GET/POST均nn，created=false，Send 0 | 不是仅正式游廊才能复现；此本地VM也在原生创建阶段失败，尚未到网络发送 |
| 已有正式游廊实测与另一台反馈 | 本机实际F:nn/H:l；用户报告另一台也相同 | 减少单机环境解释的可能性；另一台未采集原始日志/版本摘要，不冒充独立二进制采样 |

## 同代码对照与真实边界

Python只作网络对照，不调用Dota API。实际URL固定为
`https://pay.xiaofengnet.com/ws4-web/health`，不带认证、账号、存档或交易数据。
两次耗时约0.220/0.120秒，不当作游戏VM耗时或容量验收。

本地VM通过Steam启动独立survival/ws4_entry Tools地图，未进入玩法、未启用离线逻辑。
入口分支不初始化正式地图的档案/支付服务。加载当前真实
`core/http_request_factory.lua`，SHA256
`eef6fa1ccd1fe5eb804ec482728317bccc0a92faeea4e8692a6310acb2efb712`。
使用与游戏相同的受保护Lua调用帧、先ScriptVM再legacy创建；POST设置相同
`application/json; charset=utf-8`和空JSON，原生超时上限10000ms。
它测试的是相同构造/发送写法和匿名health路由，不是玩家授权POST业务成功。

实际客户端PID6880 / FILETIME134394846445107837，Tools=true、server=true、map=ws4_entry，
GET与POST各调用一次工厂，均nn，API可用但对象为空，未调用Send；完成标记实际收到。
诊断不增加游戏帧循环/玩家扫描。固定两项初始化，时间/空间O(1)，最多四次原生创建尝试、
两次Send；只有请求真创建时才设置一个15秒截止回调。本次实际Send0、截止回调0。
七项Lua隔离安全检查覆盖Tools/生产/鉴权门禁、空工厂、异常、截止及迟到回调；模拟网络0。

第一次脚本命令因sv_cheats=0被引擎明确忽略，没有执行Lua或HTTP。
随后仅在这个诊断Tools客户端临时允许加载测试脚本，实际执行一次，再恢复sv_cheats=0；
这不是正式客户端开启作弊的修复方案。初次采集器的JSON对象字段顺序匹配也有问题，
其失败回执保留；最终改为独立完成标记，未把采集失败当HTTP超时或重试未知请求。
首份采集回执commands_sent=0仅是未取得成功返回的旧计数，不能当作线上命令从未发送；
已有控制台回放证明命令曾发送并被作弊门禁拒绝，单独错误说明保留。
探针在首次被忽略后增加完成标记，初始启动摘要和实际执行后源码摘要分开保留，不改旧回执。

## 辅助程序路线与第二台反馈

用户在call_96c6afecbfa845ad82e437cdb5396e4a批准“接受辅助程序，优先恢复完整联网”。
正式游廊、真实Steam授权和云存档要求持续有效，不能用离线内存档或关闭授权替代。
随后用户要求优先进行上述独立HTTP对照，已优先执行。

辅助通信预检查的两次普通Steam客户端分别只加-vconport，以及-vconsole/-vconport，
都未观察到该普通客户端的监听端口；没有执行任何转发、账号或云端请求。
Tools能开放VConsole不等于正式客户端支持，不能把Tools通信作为正式辅助方案已成功。
目前辅助转发仍未实现/验证；再次正式发包或开启长期公开缺乏成功依据。

GitHub官方API只读复查35497：13条评论、仍open，没有OWNER/MEMBER/COLLABORATOR关联回复，
此前获批原文评论实际存在。未另发评论、修改公开原文或冒称Valve确认/宣布政策。
当前官方Windows原生检查与实际创建失败已证实，但最早引入版本、Linux专服及官方支持的
恢复方法仍未验证。本轮结论不是“只在游廊环境不行”，也不把电脑HTTPS可通当作游戏修复。

## 恢复、产物及交付

Tools已正常退出，未强杀。诊断前运行的Hammer辅助任务已恢复原启用/运行状态。
Tools诊断端口默认监听0.0.0.0，通信前对本轮程序TCP29006施加非回环IPv4阻断；
客户端退出后已核对并移除本轮临时规则，无遗留端口开放操作。

Tools自动重编译100项UI缓存、共9380227字节。逐文件备份、SHA256核验并登记后，
仅将本轮生成缓存另存stash `32f54a4aa8ee815f2295177485aa40bc2cbefd21`，恢复原工作区版本，
不把诊断生成物混入发行。一次性原生探针正常退出后已备份并迁出到树外，保持可复核源码，
未作为正式游戏运行改动。原15项工作逐文件摘要保持；content没有改动。

证据根：`D:/Survival_本地工具/runs/login_create_failure_20261118/local_http_control01`。
主要回执：direct_pc_https_receipt、native_http_control_executed_receipt、cleanup_receipt、
http_environment_comparison_receipt（均.json）。完整对照回执SHA256
`f276dce85460e9771381e85e4f306fcf2b7cbe20afe7382ddf149f6772880423`。
实际探针源码为manual_native_http_probe.executed.lua，并有相同摘要备份。
完整对照登记e8b29577132be7ab146f347c5ca5478b43a52f3a03c7601db71c54f4ce93e324；
缓存备份登记a624536c26e72c56a470d595ac1ae2195f22d70d482ada20926f0ae372ded82c。

仅诊断工具及记录变化；后台未部署，真实交易/清档/新增UGC提交均0。
正式游廊仍为2026111806，manifest6295798134948076528，不声称已恢复完整联网。
收口完整pending_sources/dirty_runtime均空，正式Steam验签check再次READY、未重启中转。
