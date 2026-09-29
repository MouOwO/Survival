# 微信与支付宝共用 HTTPS 支付入口

更新：2026-09-28。支付域名和 HTTPS 入口已部署并通过外网检查；独立微信支付服务现已部署，微信通知路径已接入验签、解密和原子发奖。首笔 0.10 元真实付款、真实通知解密与“齐天大圣”×1 发奖已通过验收。测试账号名单控制入口。操作及证据见 [游戏内微信支付测试](game_payment_test.md)。支付宝通知路径仍返回 503。

最新部署：用户已添加 pay 的 A 记录，公网和 ECS 均解析到 `47.110.238.248`。已在该 ECS 从现有发行版软件仓库安装 Nginx、Certbot，申请 Let's Encrypt 域名证书，启用 HTTPS 和自动续期。证书有效期至 2026-12-27，续期演练成功。外网 [连接检查](https://pay.xiaofengnet.com/connection-check) 返回 HTTP 200，正常验证证书链与域名，没有关闭 TLS 校验。原游戏后台与数据库未重启，后台健康检查仍为 200。

部署脚本：[payment_https.py](../../server/aliyun/deploy/payment_https.py)；完整验证结果：[payment_https_deployment_20260928.json](payment_https_deployment_20260928.json)。下方早期只读报告保留为历史证据，当前 HTTPS 状态以本段和最新部署报告为准。

08:19 最新补充：用户已找回并保存 APIv3 密钥，`D:/magic and love/wechatpay/api_v3_key.txt` 的 32 位格式检查通过，不需要为此重新设置密钥；实际回调解密尚待验证。域名由用户同伴的阿里云账号管理，当前用户自己的账号看不到该域名。最简操作是由同伴添加下述 pay 的 A 记录；若需用户长期管理，可在管理域名的账号下创建带相应 DNS 权限的 RAM 用户。域名与 ECS 可以属于不同阿里云账号，解析只需填写目标服务器的公网 IP。

## 已检查的实际状态

| 项目 | 检查结果 |
| --- | --- |
| 游戏后台 ECS | 已通过严格主机指纹校验的 SSH 只读连接确认 `47.110.238.248`，`goufayu-api.service` 为 active |
| 后台监听 | `127.0.0.1:8765`，本机 `/health` 返回 HTTP 200 |
| HTTPS 入口 | Nginx 已启用；HTTPS 外网验证通过，域名证书及自动续期已配置，续期演练通过 |
| 官网 | `www.xiaofengnet.com` 解析到另一台服务器 `47.116.11.179` |
| 支付域名 | `pay.xiaofengnet.com` 已解析到 `47.110.238.248` |
| 微信 | Native 首笔真实下单、0.10 元付款与存档发奖成功，AppID 绑定已通过该笔请求验证 |
| 微信 APIv3 密钥 | 真实付款通知解密及验签通过，回调返回 HTTP 204 |
| 支付宝 | 密钥已移至 `D:/magic and love/alipay`；本次重新查单，生产响应验签通过，仍为 `40003 / isv.not-online-app` |
| 项目支付实现 | 独立 `goufayu-payment.service` 承担订单、微信通知及发奖；原游戏后台的 PAYMENT_MODE=test 保持原义，未放宽其权限 |

部署前的脱敏只读检查记录：[payment_https_readiness_20260928.json](payment_https_readiness_20260928.json)。后续已完成 HTTPS 和独立微信支付服务部署，微信私钥、公钥及 APIv3 密钥通过验证主机指纹的 SSH 上传至服务端受限目录。支付宝密钥未上传。真实支付订单与付款结果以最新首单验收记录为准。

## 地址安排

建议使用一个支付域名和覆盖该域名的一张 HTTPS 证书，微信、支付宝分别使用独立的通知路径：

| 用途 | 拟用地址 |
| --- | --- |
| 支付入口 | `https://pay.xiaofengnet.com` |
| 微信付款通知 | `https://pay.xiaofengnet.com/v1/payments/wechat/notify` |
| 支付宝付款通知 | `https://pay.xiaofengnet.com/v1/payments/alipay/notify` |

HTTPS 域名证书已部署在 ECS 的 Nginx 上。微信通知由支付服务处理：验签、解密、核对订单和金额、事务落库成功后才返回 204；伪造通知返回 401。支付宝路径暂时保持 503。微信商户 API 证书和支付宝 RSA 密钥用于支付签名，不是网站 HTTPS 证书。

两条完整通知 URL 由后端分别填入微信 Native 下单请求和支付宝支付请求的 `notify_url`。支付宝的页面返回地址用于展示结果，不能作为发奖依据；应用网关的设置也不能替代支付请求里的通知参数。公司官网域名本身不会自动成为支付接口。

流程：游戏选择商品和支付渠道 → 后台按固定商品配置保存订单与账号 → 微信返回二维码地址 / 支付宝返回电脑网站收银台 → 用户付款 → 对应通知路径验签核对金额 → 持久化支付结果 → 对同一订单只发奖一次 → 游戏刷新存档。

## 第一步：在阿里云添加支付子域名（已完成）

登录管理 `xiaofengnet.com` 的阿里云账号，进入“云解析 DNS → 公网权威解析 → xiaofengnet.com → 解析设置 → 添加记录”。

| 字段 | 填写值 |
| --- | --- |
| 记录类型 | A |
| 主机记录 | pay |
| 解析请求来源 / 线路 | 默认 |
| 记录值 | 47.110.238.248 |
| TTL | 默认 |

这里只填写 `pay`，不填写完整 URL、路径、端口或 `https://`。用户已在有权限的账号中完成新增，无需再操作；现有官网和根域名解析无需迁移。

依据：[阿里云添加公网解析记录](https://help.aliyun.com/zh/dns/pubz-add-parsing-record)。

## 第二步：在游戏后台服务器配置 HTTPS（已完成）

域名解析到 ECS 后，部署可信 Nginx、为 `pay.xiaofengnet.com` 申请受信任 CA 签发的 TLS 证书，配置 443 HTTPS 监听并安排证书续期。按证书域名验证方式设置必要的 DNS 或 HTTP 验证。安全组和系统防火墙允许 443 入站；如使用 HTTP-01 验证，再开放其所需的 80。

证书必须覆盖 `pay.xiaofengnet.com`。只覆盖 `www.xiaofengnet.com` 的证书不能直接用于支付子域名。Nginx 在内部转发到支付后端；现有游戏后端与数据库继续使用私网或本机入口。现有 `nginx-https.conf.example` 是未启用的游戏接口模板，不含支付通知路由，不应直接当成已完成的支付配置。

本次已验证 TLS 证书链、域名匹配、公网连通性、HTTP 跳转、ACME 验证路径；对两条付款通知路径发送无签名 POST，均按当前配置返回 503。原有内部 `/v1/rewards/grant` 在支付域名返回 404，未公开游戏发奖接口。仅浏览器能打开连接检查页不足以说明支付通知已可处理。

运维文件：Nginx 配置为 `/etc/nginx/nginx.conf`，原始包配置备份为 `/etc/goufayu-payment-https/nginx.original.conf`。证书目录为 `/etc/letsencrypt/live/pay.xiaofengnet.com`，证书私钥留在服务器上。`goufayu-payment-cert-renew.timer` 已启用，每日两次检查续期并加入随机延迟，成功续期后执行 Nginx 配置检查及 reload。`certbot renew --cert-name pay.xiaofengnet.com --dry-run --no-random-sleep-on-renew` 已成功。部署脚本检查受管配置以避免覆盖后续人工修改；若后续接入真实支付，需要先更新脚本和对应配置。

回退入口配置时，应先检查是否已有真实支付订单，再停止/禁用这次新增的 Nginx 服务和 `goufayu-payment-cert-renew.timer`；原游戏 API、数据库不依赖这个入口，无需停止。不要为入口回退而删除支付订单、游戏存档或证书私钥。本次没有执行回退。

依据：[Nginx HTTPS 配置](https://nginx.org/en/docs/http/configuring_https_servers.html)。

## 第三步：补齐渠道材料

微信：APIv3 密钥已找回并保存在项目仓库之外的 `D:/magic and love/wechatpay/api_v3_key.txt`，文件格式检查通过。本次没有生成或重置密钥，没有把密钥正文放入聊天或仓库。格式正确不代表已验证平台配置，需要后续支付通知解密确认。

微信证书、公钥、商户号及 AppID 已收到，不需要再次申请；后续下单时仍需验证 AppID 绑定及 Native 实际权限。

支付宝：完成正式应用 `2021007102660118` 的上线审核，直到只读查单不再返回 `isv.not-online-app`。另需从商户配置取得收款商户标识用于核对付款通知。

依据：[微信 APIv3 密钥配置](https://pay.wechatpay.cn/doc/v3/merchant/4012072195)。

## 第四步：实现并验证第一笔支付

第一件商品沿用已确认内容：人民币 0.10 元，存档奖励 `lottery_monkey_king`（齐天大圣）×1。服务端固定金额为 10 分；支付宝请求金额字符串为 `"0.10"`。

开发需完成以下内容，不能仅切换 PAYMENT_MODE 配置：

1. 由可信游戏服务端提供玩家身份，服务端生成并持久化唯一订单，记录商品、金额、玩家和渠道快照。
2. 微信 Native 创建二维码；支付宝电脑网站支付进入其收银台。不能假定电脑网站支付权限已经包括 `alipay.trade.precreate`。
3. 独立通知路径按各自协议验签；微信解密通知，支付宝解析表单。核对应用、商户、订单、金额和支付状态，校验失败不标为付款成功。
4. 付款确认和待发货任务可靠保存；发奖需与存档版本、库存上限和并发保存协调。同订单通知重试、查单补偿和服务重启都不重复发奖。
5. 对指定测试账号执行 0.10 元真实付款，核对订单、商户交易和游戏存档；测试重复通知不会二次发奖。已拥有道具、付后通过别的渠道得到道具、退款与测试奖励处理需在收款前确定处理方式。

公网通知路径通过平台签名验证来源，不使用游戏内部 Bearer token；游戏下单和查询继续校验身份与订单归属。原有 `/v1/rewards/grant` 不能公开当成付款通知，也不能用页面跳转“成功”或截图直接发奖。

域名解析、HTTPS、自动续期和微信本机材料已准备好，无需用户再提供这些配置。下一步技术侧实现订单、支付通知及幂等奖励发放，再进入真实收款验收；支付宝还需完成应用上线。
