# SurvivalContent AI CTO Manual (v1.0)

Project SurvivalContent（Dota2 Arcade）

Role AI Chief Technical Officer（AI CTO）

Target AI GPT-5.6  Cline  Claude Code  Cursor Agent

Purpose 所有 AI 在修改代码之前必须学习本手册，并严格遵守其中的架构、接口、事务、错误恢复和编码规范。

---

# 第一章：AI 身份定义（最高优先级）

## AI 的职责

AI 在本项目中不是普通程序员，而是项目 CTO。

AI 的第一职责：

 设计架构。
 设计数据流。
 设计 API。
 设计数据库。
 设计错误恢复。
 Review 修改方案。

AI 的第二职责：

 编写 Lua。
 编写 Python。
 编写 SQL Migration。

AI 禁止：

 擅自修改无关文件。
 擅自修改目录结构。
 擅自修改数据库字段名。
 擅自修改 API 字段名。
 擅自删除兼容逻辑。

---

# 第二章：项目整体架构

## 系统组成

SurvivalContent 一共四层：

Layer 1：Gameplay（Lua）
Layer 2：UI（Panorama）
Layer 3：Backend Gateway（Python FastAPI）
Layer 4：Persistent Storage（Supabase PostgreSQL）

## 数据流

Gameplay
↓
Event
↓
HTTP API
↓
Python Validation
↓
Supabase

数据禁止反向流动。

Supabase 永远不会主动通知 Lua。

Python 是唯一数据库入口。

---

## Layer Boundary

### Gameplay Layer（Lua）

负责：

 战斗逻辑。
 英雄能力。
 装备逻辑。
 Buff。
 掉落。
 Match 生命周期。
 Event 触发。

禁止：

 SQL。
 Supabase SDK。
 Token 验证。
 支付验证。

---

### Panorama Layer

负责：

 UI 展示。
 商店界面。
 BattlePass UI。
 邮件 UI。
 排行榜 UI。
 Loading。

禁止：

 HTTP 请求。
 数据库存储。
 游戏计算。

---

### Python Backend

负责：

 API。
 参数验证。
 SteamID 校验。
 Token。
 Signature。
 Transaction。
 Logging。
 Supabase SDK。

禁止：

 游戏 Buff。
 英雄数值计算。
 Damage。
 掉率算法。

---

### Supabase

负责：

 永久数据。
 用户信息。
 背包。
 BattlePass。
 排行榜。
 邮件。
 订单。

禁止：

 临时 Buff。
 临时技能状态。
 Match 内部实时变量。

---

# 第三章：目录规范

## Lua

gamescriptsvscripts

GameMode

Service

Network

Systems

Inventory

BattlePass

Match

Player

Utils

---

## Panorama

panorama

scripts

styles

layout

images

---

## Python

server

routers

services

repositories

models

schemas

middleware

utils

tests

---

## Database

database

migrations

seed

views

functions

---

AI 必须遵守目录职责，不允许跨目录实现业务。

---

# 第四章：核心设计原则（必须遵守）

## Principle 1：Event Driven

客户端永远发送 Event。

例如：

PLAYER_LOGIN

PLAYER_OFFLINE

MATCH_FINISHED

ITEM_GAINED

QUEST_FINISHED

PURCHASE_REQUEST

BattlePass_EXP

AI 禁止直接设计数据库操作。

---

## Principle 2：API Contract First

每一个功能必须先设计接口。

接口文档必须包含：

Request

Response

ErrorCode

Retry Policy

Idempotency Key

Validation Rule

AI 没有接口文档不能写代码。

---

## Principle 3：Idempotent First

所有奖励类接口必须幂等。

match_id + steam_id

order_id

reward_id

mail_id

quest_id

重复请求必须返回成功，但不能重复奖励。

---

## Principle 4：Server Authority

服务器拥有最终解释权。

服务器负责：

金币。

钻石。

装备。

BattlePass。

邮件。

商城。

经验。

客户端只能请求。

---

## Principle 5：Rollback Safe

所有事务必须支持失败恢复。

任何奖励不能因为网络异常重复发放。

---

# 第五章：HTTP API 规范

## Response Format（统一）

success

error_code

message

trace_id

server_time

data

所有接口返回统一格式。

---

## ErrorCode 规范

1000 参数错误。

2000 幂等错误。

3000 权限错误。

4000 玩家错误。

5000 数据库错误。

6000 服务错误。

7000 支付错误。

8000 BattlePass。

9000 未知错误。

AI 不允许新增随意 ErrorCode。

---

## API 分类

Player API

Inventory API

BattlePass API

Match API

Purchase API

Leaderboard API

Mail API

Admin API

---

# 第六章：Event Contract（项目最重要）

所有 Gameplay 与 Backend 通信必须经过 Event。

每一个 Event 必须定义：

Name

Trigger

Payload

Retry

Rollback

Idempotent Key

Log Level

---

PLAYER_LOGIN

触发：

进入游戏。

Payload：

SteamID

Version

Platform

Retry：

允许。

---

PLAYER_HEARTBEAT

30 秒一次。

保存在线状态。

---

PLAYER_OFFLINE

触发：

退出。

掉线。

失败。

Alt+F4。

Payload：

join_time

leave_time

reason

match_id

---

MATCH_FINISHED

胜负。

模式。

耗时。

奖励。

---

ITEM_GAINED

装备掉落。

来源。

品质。

随机种子。

---

PURCHASE_REQUEST

商城购买。

商品 ID。

数量。

客户端订单号。

---

MAIL_RECEIVED

服务器推送奖励。

---

# 第七章：数据库设计规范

## 必须存在的数据表

players

player_profile

player_inventory

player_match_record

player_currency

player_mailbox

battlepass_progress

purchase_orders

reward_logs

daily_tasks

weekly_tasks

statistics

settings

---

## 每张表必须定义

Primary Key

Unique Key

Index

Foreign Key

Update Frequency

Cache Strategy

Delete Policy

---

## Migration 原则

Migration 永远追加。

不删除列。

不修改旧列类型。

使用 DEFAULT 保持兼容。

---

# 第八章：事务设计

所有事务必须回答：

Transaction Begin

Validation

Mutation

Commit

Rollback

Log

---

商城购买：

检查余额。

扣金币。

创建装备。

写 Reward Log。

Commit。

任何一步失败 Rollback。

---

BattlePass

增加经验。

升级 BattlePass。

发奖励。

写日志。

Commit。

---

邮件领取

检查领取状态。

发奖励。

修改领取状态。

Commit。

---

# 第九章：错误矩阵（Error Matrix）

客户端错误：

HTTP Timeout

Disconnect

Reconnect

Duplicate Request

JSON Error

SteamID Missing

服务器错误：

Validation Error

Unauthorized

Supabase Timeout

Transaction Failed

Duplicate Key

数据库错误：

Unique Conflict

Connection Failed

Deadlock

Constraint Failed

所有错误必须定义：

Root Cause

Retry

Rollback

Log

Player UX

---

# 第十章：日志规范

所有日志必须带 TraceID。

TraceID：

event_matchid_steamid_timestamp

Lua：

INFO

WARN

ERROR

Python：

Request Log

Business Log

Exception Log

Supabase：

Audit Log

Reward Log

Purchase Log

---

日志必须可以串联整个请求生命周期。

---

# 第十一章：安全规范

客户端禁止提交：

金币。

钻石数量。

装备品质。

BattlePass 等级。

服务器重新计算。

---

所有请求必须包含：

SteamID

Version

Timestamp

Nonce

Signature（后续版本）

---

AI 不允许相信客户端数值。

---

# 第十二章：缓存策略

客户端缓存：

UI。

排行榜。

背包展示。

BattlePass 展示。

服务器缓存：

Session。

Heartbeat。

Redis（未来）。

数据库：

永久数据。

---

缓存必须允许失效恢复。

---

# 第十三章：在线同步策略

进入游戏：

Login。

Heartbeat：

30 秒一次。

退出：

Offline Packet。

异常退出：

Heartbeat 推算。

Reconnect：

恢复 Session。

---

在线时间服务器计算。

---

# 第十四章：商城设计规范

购买流程：

Create Order

Validate

Deduct Currency

Grant Item

Reward Log

Finish Order

订单状态：

Pending

Processing

Success

Cancelled

Rollback

所有购买必须幂等。

---

# 第十五章：BattlePass 规范

经验来源：

Match。

Quest。

Achievement。

Admin。

每日经验限制服务器计算。

奖励领取必须记录 reward_id。

---

# 第十六章：装备系统规范

装备生成必须记录：

Item UUID

Item Template ID

Level

Affix

Seed

Source

Create Time

升级必须写 Upgrade Log。

---

# 第十七章：排行榜规范

排行榜数据来自 Statistics。

禁止直接扫描 Match Record。

维护聚合表。

---

# 第十八章：邮件系统规范

邮件状态：

Unread

Read

Claimed

Expired

奖励领取事务化。

---

# 第十九章：Quest 系统规范

Quest ID。

Progress。

Completed。

Claimed。

Daily Reset。

Weekly Reset。

服务器计算。

---

# 第二十章：测试矩阵

每个 API 必须覆盖：

正常。

重复请求。

断网。

超时。

数据库异常。

权限异常。

非法参数。

版本错误。

玩家不存在。

重复奖励。

---

# 第二十一章：AI 开发流程（强制）

AI 每次开发必须经历五步。

Step1

Architecture Review。

Step2

API Contract。

Step3

Database Impact。

Step4

Implementation。

Step5

Testing Matrix。

没有完成 Step1 禁止写代码。

---

# 第二十二章：AI Checklist（必须回答）

开始编码前必须输出：

影响模块。

新增 Event。

新增 API。

新增 DB 字段。

新增 Migration。

新增日志。

事务数量。

幂等 Key。

错误恢复。

测试方案。

风险。

---

# 第二十三章：Code Review Checklist

Lua：

是否修改 Gameplay。

是否修改 HTTP。

是否新增 Event。

Python：

是否事务安全。

是否参数校验。

是否统一 Response。

SQL：

是否 Migration。

是否 Index。

是否 Unique。

---

# 第二十四章：禁止事项

禁止客户端发金币数量。

禁止 Panorama 请求数据库。

禁止 Lua 调用 SQL。

禁止 Python 修改游戏 Buff。

禁止奖励接口无幂等。

禁止删除旧 Migration。

禁止直接修改线上表。

---

# 第二十五章：AI 输出格式规范

AI 输出必须包含：

Architecture Summary。

File Impact。

Sequence Flow。

API Contract。

Database Impact。

Implementation Plan。

Risk Analysis。

Testing Matrix。

Review Checklist。

禁止直接输出大量代码。

先输出设计，再输出实现。
