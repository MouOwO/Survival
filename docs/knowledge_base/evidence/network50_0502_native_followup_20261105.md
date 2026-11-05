# 2026-11-05｜0502实测、恢复与暂停发送根因

仍仅本地更新，未上传0502。原游廊为2026110104，Steam manifest `7025356658517360342`。后台 `20261104-ws4-worker-cache-3f53908aaea0` 保持 ACTIVE_VERIFIED，本轮未改后台。支付目录约88KB仍按用户决定另做，不阻断本轮高频优化。

0502源码Game/operator `524e40e2ba33b57b959d69b819836bc8160bcc17`、Content `35b5152b8585d99793a7d76bdf827e8a7052bac2` 均已推送。完整包7032资源、3,806,468,865字节、390变更及7删除；151项官方编译、186项保护均有真实原生产者绑定。签包报告SHA `9abf69fd63376fd6af9164fb97e35d42d6267bb6dd22d16067a90de7a0b290a5`，内容SHA `303705cc4a4b58ae62185dfef7330108d1c02aa5b1c43f9510926e9f15d0d844`，签名manifest SHA `1056493a694af4d080d4de512abe40dc63674e88032e3056338d1ae667195551`。控制及原始证据位于 `output/complete_delivery_release_20261105_v02`；候选在树外独立0502目录，不覆盖0501或0104。

普通排演 `complete0502_run01`，PID9524、创建UTC `2026-11-05T08:18:33.1040190Z`。起止inspect均确认4数据卷实际使用；Root正常WM_CLOSE，keeper正常结束，restore exit0明确 `ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`。最终闭合日志2,650,915字节、SHA `dd9177c5ed43af6a433d35653a493ca00aed685f23093c06f02fef9f60ccf848`。Root仍未消耗授权30券中的任何券；观察到实际券数141及已拥有标记，但三次真实十连和四池电影仍未验收。先前map_preview01因模态焦点吞掉控制台键，未执行preview命令，四张静态照片不能当电影证据。

0502有效前台N1开局采样29.9146643秒、2939个接受帧，平均98.246130 FPS，P95 11.66286ms、P99 15.442824ms、最大21.6381ms，超过25ms为0；这是原生ETW样本，只覆盖该段场景，不是整体发布或多人长局通过。第一次opening01失去前台，保留为无效样本。游戏是否运行必须核对实际画面及日志，不能用暂停局FPS代替。

实机发现两处真实代码问题：Panorama不支持 `PanelDeleted` 事件，抛错后旧owner清理未安装；另暂停时94帧奖池数据仅同步发出首8帧，恢复游戏才继续。目录刷新也有约1秒及更长样本，不能宣布所有请求小于1秒。owner修复改用有效root、匿名隐藏子面板和代际token，入口O(1)检查，无新增轮询；真实销毁时O(V)清理已创建视图，旧回调及重入不能发包，正常活跃view关闭仍发Close。Node/Lua回归不冒称原生通过。

5名工人各自1秒训练完成，被旧网络门禁当成同内容高频广播。新门禁须使用服务器接受的action8、唯一intent token及实际job入队/开始/成功完成生命周期一对一匹配；不按名称豁免，不扣除原始流量。每真实任务最多3条本机诊断，空闲无新增工作或网络；取消、失败、重复token及缺失证据不获例外。`train_lumberjack_auto` 只是技能选择训练级别，不代表持续自动生产。旧router研究缓存断言在S23实际旧服务亦失败，未改规则或隐藏失败。

独立原生暂停实验已正常关闭及移除自身junction，LAB完整保留在 `D:/Survival_本地排演/network50_probe_20261105/paused_think01`。仅最小Tools addon `svt_paused_think0503`，不加载项目/后台/玩家交易，正常地图副本不改正式资源。实际build `10938:11200340`；4.980147秒窗口内GameTime不变、暂停始终为true：mode/target的SetContextThink和SetThink在delay/return=0时各执行32次，0.05时各0次。闭合日志SHA `d771a5815b93758321abe49cce44eccadafa65962379a8491ad4e12d4da231e2`，结果在 `output/paused_dispatch_0503/native01/result.json`。这证明引擎调度差异，不是普通版本新补丁验收。

下一版独立2026110503：使用按需零间隔UI发送回调，保留8帧/16ms/2ms限额及空闲停止，不改变全局游戏计时器；修复后重新冻结双仓、生成目录、完整编译/保护/签名，再普通客户端验证全部UI、真实电影及解码失败兜底、连续三十连（累计最多30张普通券）、实际网络和FPS。只有canonical SDK回执与官方下载逐文件相同、待发清单为空，才可写已同步游廊。前序0502照片及Tools实验不能替代该验收。

0503源码冻结前回归：owner/core共38项及13个适配层套件通过；训练门禁71项Python及5个Lua套件通过。按需发送driver/原transport/bulk/disconnect/deadline scheduler/replacement共6个Lua回归通过。真实transport+codec合成四接收者各96帧，一次原生think安装完成队列，同优先级按job轮换，总计每16ms不超过8帧；1000次稳定更新零发包、零安装。另覆盖2ms预算、关闭、冷bus加载、换实体、换局、current/after/codec/clock失败及发送/完成回调重入。初始化及稳定检查O(1)，空闲无原生think；变化按实际消息帧数有界推进，队列内存按现有每视图最多8事务限制。上述合成计数不等于新候选普通实机网络或FPS。
