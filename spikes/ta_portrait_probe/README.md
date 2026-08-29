# Templar Assassin runtime wearable probe

This spike builds the isolated sibling addon `survival_ta_portrait_probe`. The playable map spawns one animated Templar Assassin body and three wearable `prop_dynamic` entities at runtime. Every wearable uses the production attachment order: `wearable:SetOwner(body)` followed by `wearable:FollowEntity(body, true)`.

The small `DOTAScenePanel` is a static **body-only** rendering baseline. It can help distinguish a body-model or lighting failure from a runtime failure, but it contains no wearables and is never bone-merge evidence.

## Data contract

- `data/csv/资源系统/asset_catalog.csv` supplies the body model, default sequence, scale, and asset identity.
- `data/csv/资源系统/asset_components.csv` supplies exactly three enabled components, including model, entity class, `bone_merge` metadata, scale, and order.
- `data/csv/建筑与工人系统/防御塔/tower_class_death.csv` proves that the death-tower rows select the same asset and body model.
- `spikes/ta_portrait_probe/data/scene.csv` supplies only probe-specific map, transform, camera, and lighting values.

- `build_ta_portrait_probe.ps1` resolves those CSV rows into `ta_portrait_probe_runtime_config.lua`; model paths are not hardcoded in runtime Lua.

Only the body receives and resets the CSV sequence. Wearables receive no `DefaultAnim`, `ResetSequence`, or other independent animation command. Successful entity creation and attachment API calls produce `ready_visual_check_required`, not an automatic visual pass.

## Build

From `D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival` run:

```powershell
pwsh -NoProfile -File .\tools\build_ta_portrait_probe.ps1
```

The playable map is `ta_portrait_probe_lab`; the optional body-only baseline scene is `ta_portrait/templar_assassin` with camera `hero_camera` and light `ta_portrait_key_light`.

## Workshop Tools validation

1. Close any running custom game and old Lua VM.
2. Select addon `survival_ta_portrait_probe` and run `ta_portrait_probe_lab`.
3. Confirm VConsole reports `BODY_ANIMATION_APPLIED`, three ordered `ATTACHED` lines, and `READY ... visual_verdict=pending`, with no runtime `FAIL` line.
4. Confirm the game camera targets one runtime TA body and all three default wearables are visible without rigid origin-stacked geometry or drift.
5. Compare multiple visibly different `idle` frames. Confirm hair, shoulder, and armor deform with their corresponding body bones; one still frame is insufficient evidence.
6. Confirm the body and upper wearables are framed and lit. Treat the small body-only panel only as a rendering comparison.
7. Click **Pass after multi-frame check** only after all three wearables pass step 5. This records `PASS` with `manual_multi_frame_runtime_observation` evidence.

A visible body with rigid or detached wearables is `PARENTING_VISIBLE_BONE_MERGE_FAIL`. Missing entities or models are `RENDER_FAIL`. Resource compilation, static contract checks, successful `SetOwner` / `FollowEntity`, and the body-only baseline are not visual proof.
