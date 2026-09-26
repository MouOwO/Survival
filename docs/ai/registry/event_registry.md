# Event Registry

Status: REFERENCE
Last Reviewed: 2026-08-25

| Event | Producer | Consumer | Payload |
| --- | --- | --- | --- |
| `HERO_READY` | Hero lifecycle | Player profile / online session startup | UNKNOWN — verify in code |
| `HERO_COMBAT_STATS_GET_REQUEST` | Combat stat requester | Hero combat stat service | Request/response table — verify in code |
| `FISHING_REWARD_GRANTED` | Validated permanent/immediate reward path | Reward notification / downstream subscribers | Whitelisted gameplay fields; verify exact payload in code |
| `UI_NOTIFICATION` | Server gameplay/UI routing | Panorama notification UI | `message`, `level`, audience routing |
| `TECHNOLOGY_STATS_CHANGED` | Technology stat manager | Tower/stat refresh consumers | UNKNOWN — verify in code |

本表只索引文档中反复出现且仍适用的关键事件。新增或修改事件前必须从当前事件总线注册与调用方核对精确 payload。
## 2026-09-26 建筑生产与研究队列

| Event | Producer | Consumer | Payload |
| --- | --- | --- | --- |
| `WORKER_TRAINING_GET_REQUEST` | Production UI service | Worker system | `{player_id, source_entindex}` → options、active_job、queued、queue_count、queue_capacity |
| `TECHNOLOGY_STATE_GET_REQUEST` | Production UI / runtime projection | Shop system | `{player_id, source_entindex}` → 私有 research 队列、reserved_levels、auto_research、next_start_at |
| `TECHNOLOGY_RESEARCH_STATE_CHANGED` | Shop research lane | Private selected-building refresh | `player_id, source_entindex` 及当前研究、等待队列、自动状态和服务端时间戳 |
| `TECHNOLOGY_PURCHASE_NEXT_REQUEST` | `ui_research_queue_request` / existing research intents | Shop queue admission | `{player_id, technology_group, source_entindex, request_id, source}` → 入队结果，开始时扣费 |
| `SHOP_AUTO_RESEARCH_TOGGLE_REQUEST` | Validated right-click route | Shop research lane | `{player_id, technology_group, source_entindex}` → 切换自动；每次完成后等待 1 秒 |

客户端事件和完整行为见 `docs/BUILDING_PRODUCTION.md`；只信引擎注入 `PlayerID`，不接受客户端费用或免费来源。

## 2026-09-26 小地图回程入口（复用原事件）

| Event | Producer | Consumer | Payload |
| --- | --- | --- | --- |
| `ui_return_home_request` | F2 / 小地图回程按钮的统一 Request | UI request router | 客户端 `{}`；仅信引擎 `PlayerID`，服务器找本人正式英雄并施放原回程技能 |
| `ui_return_home_result` | UI request router | 请求者客户端 | `success`, `error`；成功表示正常施法请求已提交，落点成功由服务另行通知 |
| `HERO_RETURNED_HOME` | Hero return home service（实际移动成功后） | 挑战生命周期 | `player_id`, `hero`, `position`；本人主城安全落点，无同队主城回退 |

参见 `docs/MINIMAP_SHORTCUTS.md`。空格选建造师是本地选择操作，身份来自已有 `survival_builder_identity/player_N`，不新增玩法请求事件。

## 2026-09-26 建造师天赋常驻状态

`ROGUE_REWARD_CHANGED` 仍由 `rogue_reward_service` 发布 `{player_id, snapshot}`；snapshot 新增 `builder_talent`（card_id/name/description/icon_name）与 `talent_pending`（0/1），并写入既有 `survival_rogue_reward[player_id]`。`ability_runtime_service` 据此刷新该玩家的技能展示，`builder_progression_system` 保留 G 键入口。领取、重开、失败及不同玩家不改变原发奖幂等边界；Boss奖励历史不会覆盖开局天赋。
