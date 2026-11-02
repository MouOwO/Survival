# 四档普通抽奖券兑换码增量

此目录只准备10／50／100／200张普通券的服务器奖励定义，不包含有效码，也不自动部署、注册或修改已有128项定义。

权威库存ID为`lottery_ticket`，用于`map`地图奖池（当前单抽1、十连10）。`special_lottery_ticket`是另外三池的金色券，本任务不发放。定义克隆既有`lottery_ticket_single`零价兑换叶，仅替换本码冻结的券数量和说明；商品价格、客户端目录和抽卡概率不变。既有`pay_lottery_ticket_single`次数标记仍按每次成功兑换加1，不是可花费的券，也不生成支付订单或VIP成长。

`tiers.json`是四项公开运营参数；`definitions.py`只接受精确四个SHA256，不接收明文、不生成随机码。原`normalize`规则为去首尾空白、转大写、去连字符；登记hash必须是`SHA256(normalize(code).encode('ascii'))`。有效明文仅由获准运营人员在私有交付中管理，不能放入Git、客户端或公开回执。尚未在本轮生成有效码。

无参数运行只显示静态计划，0文件写入、0网络、0数据库：

```powershell
python -B tools/redemption_ticket_codes_20261102/definitions.py
```

获准后由Root准备私有hash输入，JSON键严格为`10`、`50`、`100`、`200`（字符串），值为各自64位小写hash。以下命令只生成一个NEW的hash-only注册文件，不能覆盖旧文件，不会连接服务器：

```powershell
python -B tools/redemption_ticket_codes_20261102/definitions.py --hashes PRIVATE_HASH_INPUT.json --output output/redemption_ticket_codes_20261102/private/server_codes.json
```

实际登记必须使用WS4专用、insert-only的增量事务：先核对现役release/bundle/RPC，完整服务器备份及本机仅DPAPI密文；持既有WS4锁／advisory锁，只插4个新`code_id`/`code_hash`，遇任何冲突拒绝，旧定义／claims／attempts保持。默认每账号每码一次，继承现有SQL主键；全服总次数0、无新增截止日期，沿用现有码默认规则。保留已接受奖励快照，不重启支付，不改存档配置，不需客户端新包。旧`tools/redemption_codes/register.py`指向旧部署库且会更新冲突定义，不能直接用于此次WS4新增。

隔离回归使用当前真实Lua兑换reducer、商城发放和抽卡投影；数据库为既有测试替身，并非生产或真实PostgreSQL并发证明。只用固定合成码／账号和系统临时bundle，不读取真实128项码或玩家记录：

```powershell
$env:LUA_EXECUTABLE='C:/Program Files/lua/bin/lua5.1.exe'
python -B -X utf8 -m unittest discover -s tools/redemption_ticket_codes_20261102 -p test_definitions.py -v
```

验证四档精确到账、仅地图池券数变化、余额／属性不变、重复与不同账号、并发／丢回包、客户端篡改及库存上限。沿用既有通用兑换政策：若券库存已逼近2147483647上限，整项跳过且该码被使用；本任务未改这条规则。

一次运营编译读取既有目录O(P)，再生成4个固定规格O(4)；空间O(P+4)，0数据库／网络调用。游戏稳定阶段新增工作0，兑换仍走既有prepare→真实Lua→commit；遇revision冲突沿用原最多4轮重试。测试调用计数不能写成游戏FPS改善。

## 新四码的私有生成（与旧128码隔离）

`generate_private.py`无参数只显示静态计划，不读取旧运营表、不取随机数、不写文件、不连服务器。仅Root显式执行`--generate`才一次生成4个新码，每码的随机部分为`secrets.token_hex(12)`（96位熵），规范化后计算SHA256并调用已审的四档定义编译器。明文只进入NEW私有中文Excel，初始状态为“待登记”；hashes、registry及可恢复manifest不含明文。此脚本不登记、不自动改状态、不复制桌面或对外分发。

已核本机既有`C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe`包含openpyxl3.1.5；安全venv没有该依赖。无需向全局或venv安装新包。

```powershell
& 'C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe' -B tools/redemption_ticket_codes_20261102/generate_private.py
# Root审阅后执行一次；本轮工具开发/测试未执行此生产生成命令：
& 'C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe' -B tools/redemption_ticket_codes_20261102/generate_private.py --generate
```

固定目录为`output/redemption_ticket_codes_20261102/private`，输出`普通抽奖券四档兑换码_20261102.xlsx`、`ticket_hashes.json`、`server_codes.json`、`generation_manifest.json`及两份hash-only意图/中间记录。任何已有同名目标或意图都拒绝重新生成，不覆盖旧码。中途失败时保留全部文件；若原Excel完整，可显式`--resume`核对源工具、四hash和冻结奖励后补齐同一批hash/registry/manifest，全程不再取随机数。若Excel缺失或损坏，工具停止并保留现场，不能从hash找回明文，也不会偷偷生成替代码。

Excel明确标注“本文件不是旧128码Excel，不用旧register.py导入”。Root确认实际WS4登记成功后，另行更新登记状态并复制桌面；不能把本地生成成功写成服务器已经生效。生成/恢复均为一次运营O(P+4)，稳定游戏成本和网络调用仍为0。对应12项隔离生成测试仅使用系统临时目录和固定合成熵，不创建有效生产码。
