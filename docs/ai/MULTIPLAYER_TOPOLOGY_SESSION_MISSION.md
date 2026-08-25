# SurvivalContent Multiplayer Topology & Session Mission v1.0

## Mission Type

Architecture Verification / CTO Investigation

## Current Phase

Backend Integration

## Rule

**Do not write production code during this mission.**

The goal is to establish the factual multiplayer topology first, then decide how Session, Python HTTP, persistence, reconnect, and finalization should be designed.

---

# 1. User Intent

The project is entering real multiplayer + backend integration.

The project owner needs to personally establish the difficult foundation in the next few days so that other team members can later fill in features with AI using the same framework.

The most urgent unknown is:

> Where does the actual Dota 2 custom-game server run during a normal Arcade multiplayer session, and how is that different from local development?

Do not assume that the person who creates the lobby is the machine running the game server.

---

# 2. Project Context

SurvivalContent is:

- Dota 2 Arcade
- small tower-defense + hero-growth game
- not an MMO
- not an ARPG
- core single-player gameplay is substantially complete
- current bottleneck is multiplayer/backend integration

Current known backend shape:

Dota Lua
→ local HTTP client
→ Python HTTP server
→ Supabase RPC/PostgreSQL

Current Python stack documented by the project must be treated as authoritative unless code inspection proves otherwise.

Do not replace the existing Python architecture merely because another framework is more familiar.

---

# 3. Required Investigation

Determine, with evidence, the actual topology for:

## Scenario A — Local development

Examples may include Workshop Tools / local launch / local listen server.

Determine:

- who runs Dota game server
- where Lua runs
- where Python runs
- where `127.0.0.1` points
- how another player can or cannot join

## Scenario B — Normal Custom Lobby / Arcade

Determine:

- who owns the lobby
- whether lobby owner is the game host
- whether a dedicated/allocated Dota game server is created
- whether all players connect to that server
- where Lua GameMode executes
- whether Python can still be assumed to be on `127.0.0.1`
- whether the custom game server exposes a usable environment for the project's Python server

## Scenario C — If multiple hosting models exist

Document:

- Local Host
- user-hosted / listen-server style
- Dota/Valve allocated game server
- relay/P2P concepts only when relevant

Do not force SurvivalContent into a model that is not proven to apply.

---

# 4. Evidence Rules

Use evidence in this priority:

1. Current SurvivalContent code
2. Current project test records / console logs / Workshop evidence
3. Current Dota 2 / Steam official documentation
4. Valve issue tracker or current technical reports
5. Community sources only when primary sources do not answer the question

For every important topology claim, record:

- Claim
- Evidence
- Confidence
- Source
- What remains unknown

Current official Steam documentation says a lobby has one lobby owner for lobby arbitration, and when launching, users join the game server OR connect to a user nominated to host the game. Therefore, **Lobby Owner and Game Server should not be treated as automatically identical.**

Also verify how this applies specifically to Dota 2 Custom Games rather than general Steam matchmaking.

---

# 5. Mandatory Report

Create:

`ai/architecture/MULTIPLAYER_TOPOLOGY_REPORT.md`

The report must contain:

## 5.1 Executive Summary

One paragraph:

- current development topology
- expected production topology
- biggest uncertainty
- immediate recommendation

## 5.2 Topology Matrix

| Scenario | Lobby Owner | Game Server | Lua Execution | Python Location | Supabase | Confidence |
|---|---|---|---|---|---|---|

## 5.3 Diagrams

Produce simple ASCII diagrams for:

### Local Development

### Normal Arcade Multiplayer

### If Production Differs From Development

## 5.4 Identity Mapping

Define the relationship among:

- Steam Account ID
- PlayerID
- Lobby ID
- Match ID
- Session ID
- Trace ID

For every identifier:

- origin
- scope
- lifetime
- persistence
- can it be trusted by backend?

## 5.5 Python Placement

Answer:

### Can Python safely stay on 127.0.0.1?

For each topology:

- YES
- NO
- UNKNOWN

Explain why.

Do not redesign this until topology is verified.

## 5.6 Session Implications

Determine whether:

- Session belongs to a player
- Session belongs to a game server
- one Match has many Sessions
- reconnect creates a new Session or restores the old one
- a game server restart invalidates all Sessions

## 5.7 Finalization Implications

Determine whether finalization should be attached to:

- player disconnect
- match end
- game server shutdown
- Dota game-state transition
- multiple signals with idempotent finalization

Do not implement.

## 5.8 Security / Trust Boundary

Identify:

- game server authority
- player client authority
- Python authority
- database authority

## 5.9 Open Questions

Anything not proven must be listed as:

`UNKNOWN — DO NOT GUESS`

---

# 6. Very Important Distinction

Do not confuse:

- Lobby
- Match
- Game Server
- Player Client
- Player Session
- Backend Session

They are separate concepts unless evidence proves otherwise.

The report must define them separately.

---

# 7. Project-Specific Questions

Inspect current `ai/` and current code to answer:

1. Does current Python bind only to `127.0.0.1`?
2. Which process starts Python?
3. Which machine is expected to start Python in current integration tests?
4. Does the current Lua HTTP client run from the Dota server process?
5. Is the current Session code assuming one player per process?
6. Does current finalization assume the Dota process and Python process are colocated?
7. What happens when two players enter the same match?
8. What happens when the lobby owner leaves?
9. What happens when a non-owner leaves?
10. What happens if the Dota game server ends before a final HTTP request completes?
11. Does a reconnect go through the same game server?
12. What identifies a single match?
13. What identifies a single player within that match?
14. What prevents player A data from being written to player B?
15. What prevents two matches from sharing state?

---

# 8. Decision Gate

After the report, classify the project into one of these:

### MODEL-A

Game server and Python are colocated.

### MODEL-B

Game server and Python are not colocated.

### MODEL-C

Development is A, production is B.

### MODEL-D

Topology is still unknown and must be experimentally verified.

If Model-D:

Do not implement Session architecture yet.

Create a small topology verification experiment instead.

---

# 9. Required Experimental Verification

If documentation cannot prove the topology, design the smallest possible test.

Example categories:

- two PCs
- one creates lobby
- second joins
- observe Dota console
- observe Lua logs
- observe Python logs
- record local IPs / ports only where appropriate
- identify which machine executes Lua
- identify which machine can reach `127.0.0.1:8765`
- record Match ID / player identity

The test must have:

- setup
- exact steps
- expected result
- observation points
- interpretation of outcomes

---

# 10. Do Not Code Until This Report Is Complete

No:

- Session refactor
- HTTP refactor
- Database refactor
- Reconnect implementation
- Purchase implementation

until the topology report establishes the deployment boundary.

---

# 11. After Verification

Only after the report is complete, propose the next architecture layer:

## Session Foundation

Match
→ Player
→ Session
→ Connection
→ Checkpoint
→ Finalization
→ Reconnect

Then determine:

- where state lives
- what lives in Lua
- what lives in Python
- what is persisted in Supabase
- what is temporary
- what is authoritative

This second phase may be implemented only after human review of the topology report.

---

# 12. Output Style

Keep the final report concise.

Prefer:

- tables
- short paragraphs
- diagrams
- explicit UNKNOWN labels

Do not repeat project history from `ai/`.

Do not duplicate existing Registry content.

Link/reference existing docs instead.

---

# 13. Success Criteria

This mission succeeds only when a human can answer:

> “When three players enter one SurvivalContent Arcade match, exactly which machine/process runs the Dota game server, where Lua runs, where Python must run, what `127.0.0.1` means, and how a player reconnects.”

If any of those remain unknown, the mission is not complete.
