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