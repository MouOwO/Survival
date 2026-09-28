# Lumberjack fusion selection queue — 2026-09-28

Selecting multiple owned lumberjacks now orders ordinary workers by fusion readiness, level, and entity ID. Recipe quantities come from the server runtime snapshot (including five materials at LV1), never a frontend constant. Incomplete levels stay at the end. Supers are identified by their missing fusion ability, including supers that retain the ordinary unit entity name.

Each Q/button press sends one authoritative request. Pending requests suppress duplicate input. The service restricts materials to the current selection for queue casts and returns every consumed material ID, including the caster transformed in place. Successful merges remove those IDs and select the next eligible group. Multiple groups at the same level are exhausted before higher levels. An incomplete final group stays scoped; a completed queue selects its final product. Failed resource/city/material checks retain the group for deliberate retry. Single-unit legacy casts keep the previous material search.

Manual selection of unrelated units while awaiting a response is preserved. Reload generations invalidate stale handlers. The queue uses selection events and the existing managed ability input; it does not replace the shared mouse callback.

Validation:
- tools/test_lumberjack_fusion_queue.cjs: 10 selection/cast lifecycle scenarios.
- tests/test_lumberjack_fusion.lua: eight tiers, spending/refund, ownership, selected-only materials, deduplication, consumed-ID response.
- tests/test_lumberjack_fusion_ui.lua: router scope and response metadata; legacy dispatch.
- tools/test_lumberjack_fusion_runtime.lua: eight recipe runtime snapshots.
- Existing box-selection, minimap shortcut and tower-level regressions passed.
- Resource compiler: 13 compiled, zero failed. Source mirrored to the content addon.
- Console connection refused at 127.0.0.1:29000; in-game interaction has not been verified. Start a new test session/map to load the server Lua changes as well as compiled Panorama resources.
