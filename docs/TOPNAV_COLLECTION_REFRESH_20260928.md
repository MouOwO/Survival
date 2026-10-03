# Collection icons and navigation windows — 2026-09-28

- Restored the original gold house SVG for the archive artifact sidebar entry; display name remains 存档神器.
- Built-in image_gen produced 26 distinct fishing illustrations and 17 welfare subjects. The 34 welfare entries map their two tiers to the same 17 recognizable subjects. No item IDs, rewards, costs, or source effects changed.
- Masters: `panorama/src/images/custom_game/archive_collection_v4/`. Prompts, original paths, SHA256 and item mappings: `data/ui/archive_collection_v4.json`. Runtime textures use explicit 256px BGRA with mipmaps; masters are byte-identical to the generator output.
- Fishing/work art displays at 88×88 instead of 72×56; card name/count/cost rows have separate vertical positions. Existing archive typography and friend/ex portraits remain intact.
- Navigation SVGs now specify fill/stroke on each drawable element to avoid black shapes from unsupported group inheritance.
- Shared `topnav_windows.css` and the window component replace old pale framing with the archive's opaque #16353e → #0b1b23 surface, light regular text, gold numeric/action roles and dark readable disabled controls. Includes treasure, daily/pass, lottery/detail/history, commerce/order and survival shop. Pool illustration changes independently of the common surface.
- Local hero corner portrait starts hidden/noninteractive, independently refreshes before bottom-HUD readiness, checks ready state, hero identity, current assigned entity and owner, and clears stale artwork. Ordinary navigation remains available as before.

Validation: 43 textures compiled; archive and HUD compiled with zero failures. Hero-corner lifecycle, portrait presentation, archive compact UI, shop behavior, and lottery cache/read/switching checks passed. Review sheets are under `output/archive_collection_v4_*_review.jpg`. Live window screenshots are under `output/map_build_c6/collection_*_final.png` (inspect actual contents before treating individual captures as evidence).

Final live review:
- `collection_fishing_final.png` and `collection_work_final.png` confirm the new art, names, counts and costs in game.
- `collection_treasure_complete.png` confirms all 20 slots in five columns; `collection_benefit_complete.png` confirms readable claim/pass controls; `collection_survival_shop_complete.png` confirms the dark shop body; `collection_lottery_polished.png` confirms the dark lottery controls and isolated pool art.
- Earlier window captures ending in `_final` did not all open successfully while the existing mandatory choice overlay was active. They are not evidence for those windows.
- The artifact SVG preload now explicitly collapses with zero size/opacity, fixing a stray gold house in the hero corner. The current match has a valid summoned Doom portrait; pre-summon hiding is covered by lifecycle tests, without restarting this match.
- Commerce is disabled by the existing production integration. Its theme is prepared but cannot be live-reviewed; no fake catalog or payment preview was enabled.
- Corrected shared action inline colors, stale daily helper references and shop-body paint overrides. Daily, survival shop and lottery regression suites pass after these changes. Source and compiled assets are synchronized to game/content; no cloud activation, purchase, reward claim or save mutation was performed for review.
