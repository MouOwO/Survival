# Wave Model Resource Lifecycle

## Final target

Each formal wave must eventually declare its own approved final model resources. Formal preload, developer jump-wave preload, `SetModel`/`SetOriginalModel`, and lifecycle accounting must all consume the same resolved wave-model list. A wave must never depend on an earlier wave having loaded a shared model.

## Temporary compatibility

`monster_archetypes.normal_flying_model_path` currently maps formal `normal + flying` members to Visage while final per-wave models are still incomplete. Shared model-path leases also support this temporary overlap.

`TODO(FINAL_WAVE_MODELS)` may be removed only after:

1. every enabled formal wave member has an approved final model mapping;
2. every mapped model has an asset-catalog entry and a valid exact-model async proxy or startup preload route;
3. local VPK/resource validation passes for every final path;
4. formal preload, developer preload, and spawn resolution tests use those mappings; and
5. the shared `normal_flying_model_path` field and its compatibility tests can be deleted together.

## Wave sessions and leases

Each wave generation creates a unique resource session containing:

- wave number and generation token;
- resolved, deduplicated model paths;
- planned and pending monster counts;
- alive monster count; and
- generation-completed and released state.

Spawned units retain their owning session identity. Death settles only that session, so overlapping waves cannot release one another's resources. A normal release is allowed only after generation is complete and both `pending == 0` and `alive == 0`. Shared paths use reference-counted session leases; releasing one completed wave cannot remove another wave's lease.

Starting a later wave closes stale pending generation from an older token but preserves leases for any older monsters still alive. Forced wave cleanup and initialization explicitly settle all sessions after their project-owned entities and visual state are cleaned.

Developer jump waves release their per-run session identity but retain model leases as developer-resident resources. Repeated `monster<N>` commands can therefore reuse loaded models. Entity, attachment, particle, corpse, and scheduler cleanup remain active and independent from model lease retention.

## Preload timing

The first formal wave continues to use startup preload. A later target wave is requested when its countdown starts, then reviewed idempotently at `formal_wave_preload_lead_seconds` (currently four seconds). This changes resource preparation only; it must not alter the countdown, first spawn time, member count, order, or interval.

Urgent wave assets start their exact-model proxy request immediately and may run alongside the single minute-based tower/wall background request. Per-asset state still deduplicates repeated requests.

Developer jump waves retain the configured rendering buffer. READY is diagnostic rather than proof that every client can render immediately; failure and timeout remain developer-only fail-open behavior.

## Release is not engine unload

Current release removes project-controlled Lua session references and leases. Entity removal, visual attachment cleanup, particle destruction/release, corpse lifecycle, and scheduler cancellation are handled by their existing owners.

Dota 2 Workshop Lua has no confirmed safe runtime `UnloadModel` or equivalent API. `asset_preload.retire()` only marks project Lua state as `RETIRED`; it does not prove that Source 2 unloaded a `.vmdl`, and it prevents later requests from reloading that asset. Wave lifecycle code must not call it.

`TODO(SOURCE2_MODEL_UNLOAD)` may be replaced only if Valve exposes a documented safe runtime unload API, or the project adopts independently unloadable resource packages with verified reference and client-rendering semantics. Until then, no documentation or log may describe Lua lease release as deleting or force-unloading a model.

## Required regression coverage

- `monster12` queues `monster_visage`, matching the normal flying spawn model.
- Formal preload, developer preload, and spawn resolution share one model collector.
- Pending or alive sessions reject release.
- Overlapping sessions sharing a model retain the path until the final formal lease ends.
- Developer sessions end without retiring or dropping developer-resident models.
- Urgent requests do not wait behind the background stream.
- Wave lifecycle production code contains no `asset_preload.retire()` call.
- Visage authoritative and generated `first_use_wave` metadata remains 8 while the temporary compatibility mapping exists.