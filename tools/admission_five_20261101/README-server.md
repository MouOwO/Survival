# 第五个获准账号：WS4 服务端维护

仅增加 `76561198296534615`（账号32为 `336268887`），保留原四个账号。获准总人数为5，一局仍最多4人。不修改支付账号、价格、订单、存档权限边界、Steam验签、密钥、凭据pin或d573合同，不创建OAuth授权或假游戏会话。

原API为 `/opt/goufayu-ws4/releases/20261031-redemption-ws4-23e3ab768478`，原web为 `/opt/goufayu-ws4-web/releases/20261031-game-diagnostics-v2`。运行前重新核对实际PID/cwd、两个unit/env的hash、六个保留服务、pin及完整源清单。新目录必须不存在；旧源码和失败产物保留。

先提交3项服务端修改和本工具，再指定完整不可变提交制作计划：

```powershell
python tools/admission_five_20261101/server_driver.py plan --source-revision <commit> --report output/admission_five_20261101/server_plan.json
python tools/admission_five_20261101/server_driver.py prepare --plan output/admission_five_20261101/server_plan.json --reviewed-plan-sha256 <sha> --report output/admission_five_20261101/server_prepared.json
```

`audit` 与 `plan` 只读。`prepare`只复制现役两套源码、应用已提交的3份验证代码，生成新清单，保存host-only 0600的两个env、两个unit和SQLite一致性备份，不切换、不重启。原env的Steam名单只精确4→精确5；API原 `FISHING_ADDON_ROOT` 若精确引用旧addon，则仅切换为逐字节相同的新副本。其他设置/认证/relay/payments值不变。

审阅实际计划后才能执行正式切换：

```powershell
python tools/admission_five_20261101/server_driver.py activate --plan output/admission_five_20261101/server_plan.json --reviewed-plan-sha256 <same-sha> --apply --report output/admission_five_20261101/server_activated.json
python tools/admission_five_20261101/server_driver.py verify --plan output/admission_five_20261101/server_plan.json --reviewed-plan-sha256 <same-sha> --report output/admission_five_20261101/server_verified.json
```

正式阶段先查未完成存档操作/订单，短停web和WS4 API后再查，记录只读PostgreSQL表/函数摘要及新的私有SQLite备份。仅修改两套启动文件和名单。API先启动，仅以零HTTP字节的本机TCP连接确认监听，web尚停时核对PostgreSQL数据/函数不变；web启动同样只作TCP就绪，再完整核对SQLite所有表和结构不变。两项完整校验通过后才请求真实HTTP健康接口；其原有限流计数正常更新，不冒称健康请求后计数也逐字节不变。若出现并发变化，保留证据、恢复自己拥有的代码/配置；永不用旧数据库覆盖新写入。

验证新PID/cwd/进程环境及新源码：4个原账号和新账号允许，第6人拒绝。正常Steam登录仍必需；不生成玩家授权、读玩家档案或创建订单。真实健康探针仅用现有web进程上游Bearer，先在host内核对既有pin，再读archive/config确认d573。密钥、env正文和数据库内容不返回本机；回执只含路径、hash、计数和布尔结论。

失败时停止这两个服务，只对仍等于自己before/after字节的文件恢复，重启原API/web并验证；外部管理员并发改动不覆盖。失败回执、源码和备份均保留，不自动重试、不恢复数据库。已完成或已失败stage不能再次activate。

成本：这是显式一次维护。F为两目录文件数（各最多4000、128MiB），文件清单/复制/完整性检查为O(F+B)，文件复制单次缓冲最多16MiB。表摘要在PostgreSQL内规范排序O(R log R)，hash和计数不含数据原文；SQLite摘要把单表规范化行载入内存并排序，时间O(R log R)、空间O(R+B)，B为该表序列化字节，仅在显式备份/验证时执行，无后台轮询。启动就绪探针采用12秒真实单调截止、250ms间隔，最后一次在途I/O最多另有2秒尾延迟；不增加应用计时器或场景遍历。运行时API membership为O(1)，web原有最多5账号的小字典为O(5)，新增网络/数据库/原生调用0。

专项检查：`python -B -m unittest discover -s tools/admission_five_20261101 -p test_server_operator.py`。它仅使用本地合成文件、SQLite、TCP/HTTP及依赖替身，不连接SSH、Steam或正式数据库。真实本地测试证明零字节TCP不改变任何SQLite表，HTTP健康请求只改变原有限流表，完整校验仍拒绝未预期的限流数据变化。
