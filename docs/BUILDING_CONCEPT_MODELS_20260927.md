# Approved building concepts: runtime model replacement (2026-09-27)

The user approved installing the remaining buildings from the 2026-09-26 concept board. The initial arrow towers LV1-LV5 had already been installed; their resources are preserved.

## Scope

- Main city: 5 visual levels.
- Population farm: 5 visual levels.
- Gold mine: 10 visual stages, keeping the existing 3 gameplay levels per stage.
- Basic/advanced research labs, hero altar and challenge arena.
- Walls: 10 visual stages, keeping the existing 30 gameplay levels and square placement footprint.

The 34 replacements use stone, dark teal slate, timber, warm windows and brass details. The concept image is an art direction reference; the delivered assets are real meshes with baked 2K color, normal and reflectance maps. Walls adapt the stone battlements to the existing square footprint. Empty idle clips are explicitly exported for native portraits and model initialization. There are no new particle effects or runtime timers.

Runtime model paths and CSV gameplay values remain unchanged. Old convex collision source geometry/import scales are retained. New selection boxes follow the new render bounds. Every building has a matching construction/reveal mesh and a fitted native 3D portrait camera.

## Authoring and rebuild

- Geometry: `tools/concept_building_geometry.py`.
- Blender authoring/export: `tools/build_concept_buildings.py`.
- Source stage, FBX/ModelDoc/materials, individual `.blend` files and real mesh renders: `output/building_models_20260927/`.
- Install: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/install_concept_buildings.ps1`.
- Portrait fit: `python tools/build_unit_portraits.py` after all models compile.
- Resource audit: `python tools/verify_concept_buildings.py`.

Blender can rebuild selected assets by passing their names after `--`. Final geometry is authored at runtime size, ModelDoc FBX scale is 0.01, entity scale stays 1.0. The export rig compensates the Source FBX +90 degree rotation so the root is identity and building entrances remain -Y. Construction-shell regeneration uses this revision's manifest in preference to the old .02 building sources.

The old reference building/wall authoring scripts describe the previous art revision. Use the concept builder for these 34 paths. Do not reinstall the old source stage over this revision.

## Validation and rollback

The stage stores original runtime files under `before/`, original installed sources under `content_before/`, and a SHA-256 gameplay/tower baseline. `verification.json` records compiled bounds, shell alignment, idle sequences, material dependencies, collision dimensions/volume, and portrait framing. Existing building upgrade lifecycle, wall quick upgrade and builder tower rebuild regressions are recorded in `runtime_regressions.json`.

This is asset/resource and regression validation. In-game lighting, camera feel and silhouette acceptance remain for the user's new match after reloading Dota 2.
