# Gold mine palette, 2026-09-28

The three mountain groups now use dedicated ore_gold and ore_gold_light materials in concept_building_geometry.py. Warm gold replaces stone/limestone only in those groups; timber, tracks, foliage and other buildings retain their materials. All ten visual stages (covering gameplay levels 1-30) were rebuilt using the established procedural model/texture pipeline.

Build output: output/gold_mine_gold_20260928. Stage 1 rendered preview was visually reviewed. All ten model dimensions, triangle counts and collision source files match the previous models. Installation compiled every model and construction shell without failures. All ten installed color textures changed and source/content copies match. No gameplay configuration was changed. Existing installed assets were backed up under the build output before/ and content_before/ directories.
