// Preserve approved biome art while revising every arena to a 700 x 700 square.
'use strict';
const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '..');
const previous = path.join(root, 'output/ten_realm_arena_concepts_v1');
const out = path.join(root, 'output/ten_realm_arena_concepts_v2_700x700');
const original = JSON.parse(fs.readFileSync(path.join(previous, 'prompts.json'), 'utf8'));
const numerals = ['一','二','三','四','五','六','七','八','九','十'];
const common = `Use case: precise-object-edit / stylized-concept.
Asset type: revised Dota 2 inspired environment approval sheet for later Blender modeling.
Input image role: EDIT TARGET. Preserve this exact arena's biome, recognizable architecture, tactile materials, color palette, weathering, plants, lighting, visual quality and natural coast design. The user likes the environment but requires a SQUARE arena instead of the long rectangle.
Primary revision: rebuild the arena plan to exactly equal length and width: 700 x 700 GAME UNITS. This is the enclosed arena platform's outer footprint including its four boundary walls, not raster image resolution. Shoreline rocks, earth, plants and the surrounding water form an irregular decorative apron beyond that square footprint. The square arena should be proportionally wide, with four equal length sides, right-angle corners and NO remaining elongated narrow rectangular floor. The true top-down inset must visibly be a square in a 1:1 aspect ratio, NOT a rectangle. Re-space masonry, paving, medallions and plants naturally for this revised geometry; do not stretch textures. Keep all four walls physically continuous, including the front. Low walls, open sky, no roofs, no gates, no missing wall, no bridges. Retain two small unlit flat landing medallions at the centers of opposite sides. Keep the central combat floor flat and clear, with at least two-thirds unobstructed. All tall rocks, vegetation and crystal clusters stay at the perimeter or outside it.
Composition: landscape 1536 x 1024 image canvas, warm neutral art-board. Large three-quarter orthographic view on the left showing the entire SQUARE enclosed arena and its complete irregular island shore surrounded by water; the camera may foreshorten the square but must not produce a long thin arena. Upper right: a TRUE TOP-DOWN view of the identical square design, four equal sides shown clearly. Lower right: a detailed close-up of the identical ground-wall-coast-water transition. Exactly one biome per sheet; views are the same arena. Include dimension arrows along two perpendicular OUTSIDE edges of the square top-view enclosure, labelled '700' and '700'. Add the clear specification text '700 × 700 游戏单位' below the title. Numbers label the square walled platform, not the outer irregular shoreline.
Style and material invariants: polished hand-painted stylized game environment art matching the source. Keep distinctive dry material, darker damp margin, visible submerged shelf and progressive water depth, with an organic irregular island apron; no square block plunging directly into the sea. Restrained daylight reflections and surface texture; no emission, bloom, particles, characters, enemies, UI, logos or giant central obstructions.
Exact view labels: '整体' '俯视布局' '岸线衔接'. Title, dimension text and view labels should be sparse and legible. Final check: top-down arena truly square, 700 on both axes, all four walls closed, three views consistent, specific biome retained, shore natural.`;
const tiers = original.tiers.map(t => ({
  rank:t.rank, name:t.name, terrain:t.terrain, materials:t.materials, shore:t.shore,
  file:t.file, reference_image:path.join(previous,t.file), footprint_game_units:[700,700],
  prompt:common + `\nAssigned environment: ${t.rank} / 10, ${t.terrain}.\nExact title: '${String(t.rank).padStart(2,'0')} · ${numerals[t.rank-1]}戒 · ${t.name}'.\nPreserve biome materials: ${t.materials.join(', ')}.\nPreserve the shoreline sequence: ${t.shore}.\nOnly this environment; do not include the other nine arenas.`
}));
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'prompts.json'),JSON.stringify({
  generator:'built-in image_gen',version:2,status:'concepts_pending_user_approval',modeling_started:false,
  dimensions:'Enclosed arena platform including boundary walls: 700 x 700 game units; decorative natural shore apron extends outside.',
  footprint_game_units:[700,700],layout:'Square enclosed open-air arena; four equal continuous sides; organic island shore',
  predecessor:'../ten_realm_arena_concepts_v1',tiers
},null,2)+'\n');
console.log('SQUARE_REALM_PROMPTS '+tiers.length+' -> '+out);
