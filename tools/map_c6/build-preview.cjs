// Native incrementvar wraps at its limits. Explicit camera steps clamp instead.
const fs = require('fs');
const path = require('path');
const low = 1200, high = 8000, step = 400;
const camera = distance => `c6_preview_z${distance}`;
const commands = [
  'sv_cheats 1', 'r_farz 100000', 'fog_override 1', 'fog_enable 0',
  'fog_override_enable 1', 'fog_override_max_density 0',
  'dota_camera_lerp_duration 0', 'dota_camera_mousewheel_start_delay 0',
  'dota_camera_zoom_return_to_default_time 999999',
  'dota_camera_disable_zoom 0', 'dota_camera_edgemove 1',
];
for (let distance = low; distance <= high; distance += 100) {
  commands.push(`alias ${camera(distance)} "dota_camera_distance ${distance}; bind MWHEELUP ${camera(Math.max(low, distance - step))}; bind MWHEELDOWN ${camera(Math.min(high, distance + step))}"`);
}
commands.push(
  `bind F7 "${camera(1800)}; dota_camera_set_lookatpos 700 6250"`,
  `bind F8 "${camera(6500)}; dota_camera_set_lookatpos -1024 5376"`,
  camera(3200), 'dota_camera_set_lookatpos 700 6250', 'r_drawpanorama 0',
  'script_reload_code tests/map_c6_preview_hold', 'hideconsole',
);
fs.writeFileSync(path.join(__dirname, 'preview.json'), JSON.stringify([
  {name: 'console_send', arguments: {commands: commands.join('\n')}},
], null, 2) + '\n');
