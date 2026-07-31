# Alt hero ability fix validation on origin/dev

## Revision

- Remote baseline: `f9bda67`
- Integration commit: `df07816`
- Branch: `integration/alt-fix-origin-dev`
- Runtime fingerprint: `preserve_engine_abilities_origin_dev_v1_20260731`
- Validation date: `2026-07-31`

## Production policy

- Replace only the four explicit visible Undying abilities.
- Preserve talents and hidden engine-added abilities.
- Keep `undying_flesh_golem` and hide it with `SetHidden(true)`.
- Never call `ability_utils.remove_all(hero)` during hero initialization.
- Run the policy before `HERO_READY` so the builder stage system can safely
  reduce only its own managed build abilities.

## Automated validation

- Lua 5.1 parser: `addon_game_mode.lua` passed.
- Lua 5.1 parser: `core/hero_ability_policy.lua` passed.
- Contract: `ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`.
- `git diff --check`: passed.

Lua compiler:

```text
C:\msys64\mingw64\bin\luac5.1.exe
Lua 5.1.5
```

## In-game validation

The user confirmed that the integrated `origin/dev` build does not crash and
pressing `Alt` does not exit the game.

Result:

```text
game_runtime=ok
alt_key=no_crash
```