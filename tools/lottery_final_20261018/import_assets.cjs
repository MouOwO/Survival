'use strict';
// Copy only reviewed decoration PNGs, byte for byte. No UI/text/background composite is imported.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const folder = 'lottery_final_v1';
const ids = [
  'window_frame', 'header_rule', 'sidebar_rule', 'footer_rule', 'header_back_divider',
  'back_arrow', 'close_frame', 'close_cross', 'pool_1_frame', 'pool_2_frame',
  'treasure_1_frame', 'treasure_2_frame', 'treasure_3_frame', 'treasure_4_frame',
  'draw_one_frame', 'draw_ten_frame', 'footer_divider_1', 'footer_divider_2',
  'skip_checkbox_frame',
];
const digest = raw => crypto.createHash('sha256').update(raw).digest('hex');
function child(base, relative) {
  if (path.isAbsolute(relative) || relative.split(/[\\/]/).includes('..')) throw Error('Expected relative child path');
  const target = path.resolve(base, relative);
  if (!target.startsWith(path.resolve(base) + path.sep)) throw Error('Path escapes selected root');
  for (let cursor = target; cursor !== path.resolve(base); cursor = path.dirname(cursor)) {
    if (fs.existsSync(cursor) && fs.lstatSync(cursor).isSymbolicLink()) throw Error('Linked import path is not supported');
  }
  return target;
}
function pngSize(raw) {
  if (raw.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' || raw.toString('ascii', 12, 16) !== 'IHDR') throw Error('Invalid PNG');
  if (raw[24] !== 8 || raw[25] !== 6) throw Error('Expected original 8-bit RGBA decoration');
  return [raw.readUInt32BE(16), raw.readUInt32BE(20)];
}
function run(argv) {
  const apply = argv.includes('--apply'), check = argv.includes('--check');
  if (apply === check || argv.some((x, i) => !['--apply', '--check', '--source'].includes(x) && argv[i - 1] !== '--source')) throw Error('Use --apply or --check, optionally --source <package directory>');
  const sourceIndex = argv.indexOf('--source');
  const source = path.resolve(sourceIndex < 0 ? path.join(root, 'output/lottery_final_20261018/package/lottery_layered') : argv[sourceIndex + 1]);
  const manifestRaw = fs.readFileSync(child(source, 'manifest.json'));
  const manifest = JSON.parse(manifestRaw.toString('utf8').replace(/^\uFEFF/, ''));
  if (manifest.canvas.width !== 1672 || manifest.canvas.height !== 941 || manifest.layers.length !== 77) throw Error('Unexpected accepted package');
  const layers = new Map(manifest.layers.map(row => [row.id, row]));
  if (layers.size !== manifest.layers.length) throw Error('Duplicate package layer ids');
  const generated = new Map(), assets = [];
  for (const id of ids) {
    const layer = layers.get(id);
    if (!layer || !['frame', 'icon'].includes(layer.kind) || layer.path !== 'assets/' + id + '.png') throw Error('Non-decoration layer rejected: ' + id);
    const raw = fs.readFileSync(child(source, layer.path)), size = pngSize(raw);
    if (size[0] !== layer.width || size[1] !== layer.height) throw Error('PNG geometry mismatch: ' + id);
    const destinations = ['art/ui/sources/custom_game/', 'panorama/src/images/custom_game/'].map(base => base + folder + '/' + id + '.png');
    for (const destination of destinations) generated.set(destination, raw);
    assets.push({id, source: layer.path, source_kind: layer.kind, usage: layer.name, size,
      bounds: [layer.left, layer.top, layer.width, layer.height], z: layer.z, sha256: digest(raw),
      destinations, runtime_uri: 'file://{images}/custom_game/' + folder + '/' + id + '.png'});
  }
  generated.set('tools/lottery_final_20261018/asset_manifest.json', Buffer.from(JSON.stringify({
    version: 1, source_package: 'lottery_all.zip/lottery_layered', source_manifest_sha256: digest(manifestRaw),
    canvas: [1672, 941], ui_bounds: manifest.ui_bounds, geometry: manifest.geometry,
    policy: 'Original PNG bytes only. Native labels, native RGBA surfaces and existing four pool backgrounds remain separate.',
    excluded: 'RGB repaired bases, backplates, scene/game reference, raster text, concept prize icons, composite artwork, and unused repeated frames.',
    assets,
  }, null, 2) + '\n'));
  for (const [relative, raw] of generated) {
    const target = child(root, relative);
    if (apply) { fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, raw); }
    else if (!fs.existsSync(target) || !fs.readFileSync(target).equals(raw)) throw Error('Imported bytes differ: ' + relative);
  }
  const xmlPath = child(root, 'panorama/src/layout/custom_game/lottery_gw2_assets.xml');
  const xml = fs.readFileSync(xmlPath, 'utf8');
  const block = '    <!-- Lottery final: independent decorations only; no repaired bases or raster text. -->\n' + assets.map(asset =>
    '    <Image id="LotteryFinalPreload_' + asset.id + '" src="' + asset.runtime_uri + '" visible="false" hittest="false" style="visibility:collapse; width:0px; height:0px;" />').join('\n') + '\n';
  const normal = xml.replace(/\r\n/g, '\n');
  if (!normal.includes(block)) {
    if (!apply) throw Error('Final decoration preloads are missing or differ');
    if (normal.includes('LotteryFinalPreload_') || !normal.includes('  </Panel>')) throw Error('Existing final preload block changed; review before overwriting');
    const finalXml = normal.replace('  </Panel>', block + '  </Panel>');
    if (fs.readFileSync(xmlPath, 'utf8') !== xml) throw Error('Shared XML changed during import');
    fs.writeFileSync(xmlPath, finalXml);
  }
  console.log('LOTTERY_FINAL_ASSETS_PASS ' + assets.length + ' original RGBA PNGs; ' + generated.size + ' generated source files; preload references verified');
}
if (require.main === module) run(process.argv.slice(2));
module.exports = {ids, pngSize, run};
