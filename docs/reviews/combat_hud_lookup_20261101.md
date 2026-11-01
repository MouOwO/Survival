# HUD lookup candidate after1105 performance failure

The ordinary1105 native sample retained3000 intervals: mean100.3055FPS,
P9519.9931ms, P9925.1418ms, slowest1%35.134FPS. The P95<=16.7ms gate failed.
285 slow intervals occurred at a median105.147ms spacing. This is evidence of a
periodic CPU-side cost, not a JavaScript function attribution. The separate
native VProf report sampled1770 frames/17.53s: `$.Schedule() - run JS func`
6117 calls, self4530.459ms/25.84%, peak33.937ms; server think451.790ms/2.58%.
Profiler overhead and the earlier ETW must remain separate.

The production100ms `refreshAbilities` called24 optional HUD aliases whose
missing lookup was stored as null, then immediately retried on the next tick.
An actual production-function replay with a synthetic absent HUD produced31
root FindChildTraverse calls every stable tick. This establishes repeated work;
it does not itself measure native milliseconds or prove all P95 spikes came
from that callback. The candidate preserves outfits, renderer/cache4, main/query
portrait identity and the original timing of native-hotkey repair.

The new lookup retains positive and negative IDs. Seven native creation
boundaries (`Hud`, `HUDElements`, `lower_hud`, `center_with_stats`, `center_block`,
`QueryUnit`, `QueryContainer`) are discovered once per real HUD generation.
Requested native controls contribute their parent identity and ancestor paths.
Stable validation checks only this union K; it does not walk the entire HUD or
the avatar catalog. Root/context changes, invalid/detached known controls and
observed native-container child changes expire the cache. Actual selection and
the existing five bounded retries validate that same K, preserving late-query
recovery without treating every selection as a new full-tree discovery.

Inventory aliases remain scoped to the current inventory. One inventory
skeleton index includes empty wrappers, so a late slot beneath an existing
InventoryItems wrapper is detected even when the inventory's direct count stays
unchanged. Traversal stops at numbered item slots, excluding their artwork and
tooltip descendants. A nested inventory change rebuilds only this index. Known
visibility/hittest values are rewritten only after the native value changes.

Let N be the full HUD size, A the distinct requested native IDs, D<=48 the
ancestor path bound, K<=O((A+7)D) their union, and I the current inventory skeleton
after slot pruning. Initial lookup costs O((A+7)N+ADK+I) with O(A+K+I) memory;
native root searches happen once per requested ID/generation. Stable100ms work
is O(K+A+I), with zero recursive searches and unchanged target writes. A true
HUD rebuild pays initial lookup again; an inventory-only nested change is O(I).
The previous measured33249-node Tools census is historical, not this sample's
native N. Current native K/I and actual FPS gains still require the new package.

`node tools/test_combat_hud_lookup_lifecycle.cjs` executes the production callback
against synthetic native objects with0 and10000 unrelated nodes. Each of20
stable ticks in both fixtures records root traversals0, recursive visits0,
target writes0, GetParent53, GetChildCount13 and IsValid61. Those fixed numbers
describe this fixture, not every native HUD. Added cases cover all-missing root
then creation, late native children, same-count alive replacement, invalid leaf,
nested inventory wrapper, duplicate IDs in another scope, item artwork pruning,
new root, unchanged selection and a retained callback after shutdown. Existing
late-query/slot63/native-state restoration and eleven other related suites pass.
No simulated count is reported as native FPS improvement.

Frozen game/content source compiler-input CRLF SHA256:
`d6dbbbe8adc4d61f95ac97cc177079a080de6095af86192614657f789f70ea7a`.
Git-normalized LF SHA256:
`2b4d38b1671b0a8a6d883e66df4e90a8db97b70daf6e9a30ebf3b9ce451d18af`.
Both contain227915 bytes/4330 CRLF lines/no bare LF. The lifecycle-test SHA256 is
`854cac290332d2992cb1d828b8e3672552b23715d1bb9becab7a978536f4ecfc`.
Root owns official compilation, new signing scope, native validation and publish
gates. This source review is not a compiled artifact, performance pass or release.
