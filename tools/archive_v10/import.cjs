'use strict';
// Import the approved original components and geometry. Preview data never enters runtime.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {csv} = require('../shop_ui_12h/catalog.cjs');

const repo = path.resolve(__dirname, '../..');
const pack = path.join(repo, 'design_refs/archive_v10/package/archive_ui_final_v1');
const work = path.join(repo, 'design_refs/archive_v10/work');
const read = file => JSON.parse(fs.readFileSync(path.join(pack, file), 'utf8'));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const layout = read('layout.json');
const manifest = read('asset_manifest.json');
const tooltip = read('tooltip_layout.json');
const catalogSource = 'data/csv/存档系统/archive_shadow_items.csv';
const catalog = csv(path.join(repo, catalogSource)).filter(row => row.enabled === '1').map(row => ({
    id: row.item_id,
    name: row.display_name,
    description: row.description,
    quality: row.quality,
    icon_style: row.icon_style,
    max_owned: Number(row.max_owned) > 0 ? Number(row.max_owned) : undefined
}));
const records = [];
const assets = {};

// Check every packaged file, including the excluded reference and editable masters.
for (const entry of manifest.assets) {
    if (!/^(?:assets\/(?:backgrounds|common|items|tooltip|preview_only)\/[a-z0-9_]+\.(?:png|svg)|fonts\/(?:SourceHanSansSC-Regular\.otf|LICENSE-SourceHanSans\.txt))$/.test(entry.file)) {
        throw new Error('Unexpected packaged asset path: ' + entry.file);
    }
    const bytes = fs.readFileSync(path.join(pack, entry.file));
    if (hash(bytes) !== entry.sha256) throw new Error('Packaged asset checksum differs: ' + entry.id);
    const specified = layout.assets[entry.id];
    if (!specified || specified.file !== entry.file || specified.sha256 !== entry.sha256 || specified.runtime_use !== entry.runtime_use) {
        throw new Error('Layout / manifest asset mismatch: ' + entry.id);
    }
    if (!entry.runtime_use || !entry.file.endsWith('.png')) continue;
    const actualSize = [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
    if (!Buffer.from([137,80,78,71,13,10,26,10]).equals(bytes.subarray(0,8)) || actualSize[0] !== specified.size[0] || actualSize[1] !== specified.size[1]) {
        throw new Error('PNG dimensions differ from the approved layout: ' + entry.id);
    }
    const relative = 'images/custom_game/archive_v10/' + entry.file.slice('assets/'.length);
    const destination = path.join(repo, 'panorama/src', relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, bytes);
    if (hash(fs.readFileSync(destination)) !== entry.sha256) throw new Error('Imported bytes differ: ' + entry.id);
    assets[entry.id] = {
        file: 'file://{images}/' + relative.slice('images/'.length),
        size: specified.size,
        sha256: entry.sha256,
        role: entry.role
    };
    records.push({id: entry.id, source: entry.file, relative, destination: path.relative(repo, destination).replaceAll('\\', '/'), bytes: bytes.length, size: actualSize, sha256: entry.sha256});
}

const fontSource = layout.assets.source_han_sans;
const fontPaths = ['panorama/src/fonts/Radiance-Survival-SourceHanSansSC-Regular.otf', 'panorama/fonts/Radiance-Survival-SourceHanSansSC-Regular.otf'];
for (const font of fontPaths) {
    if (hash(fs.readFileSync(path.join(repo, font))) !== fontSource.sha256) {
        throw new Error('The already registered font does not match the V10 font: ' + font);
    }
}

const staticLabels = /^(?:project_title|top_[0-5]|sidebar_\d{2}|filter_(?:all|owned|unowned)_text)$/;
const layers = layout.layers.filter(layer => !layer.item_id && layer.scope !== 'preview_only').map(layer => {
    const copy = {...layer};
    if (copy.kind === 'text' && !staticLabels.test(copy.id || '')) delete copy.text;
    // Retain the approved static label. Data values are supplied by the existing controller.
    delete copy.data_field;
    return copy;
});
const data = {
    canvas: layout.canvas,
    assets,
    layers,
    sidebar_toggles: layout.sidebar_toggles.map(({preview_data_available, runtime_configuration_supplied, ...toggle}) => toggle),
    shared_regions: layout.shared_regions,
    grid_template: layout.grid_template,
    catalog,
    tooltip: {layout: tooltip.layout, text_colors: tooltip.text_colors, interaction: tooltip.interaction,
        assets: Object.fromEntries(Object.entries(tooltip.assets).map(([id, entry]) => [id, {...entry, file: assets['tooltip_' + id].file}]))},
    shadow_icons: Object.fromEntries(catalog.map(item => {
        const match = /^shadow_(\d+)$/.exec(item.id);
        const asset = match && assets['virtual_' + match[1].padStart(2, '0')];
        return asset ? [item.id, asset.file] : null;
    }).filter(Boolean)),
    font_family: 'Source Han Sans SC'
};
const dataFile = 'scripts/custom_game/archive_v10_data.js';
const assetLayout = 'layout/custom_game/archive_v10_assets.xml';
fs.mkdirSync(path.join(repo, 'panorama/src/layout/custom_game'), {recursive: true});
fs.mkdirSync(path.dirname(path.join(repo, 'panorama/src', dataFile)), {recursive: true});
fs.writeFileSync(path.join(repo, 'panorama/src', dataFile), '// Generated by tools/archive_v10/import.cjs. Geometry and approved components only; no preview counts, limits, or effects.\n(function(){GameUI.CustomUIConfig().ArchiveV10Data=' + JSON.stringify(data) + ';})();\n');
fs.writeFileSync(path.join(repo, 'panorama/src', assetLayout), '<root><Panel hittest="false" hittestchildren="false">\n' + Object.values(assets).map(entry => '  <Image src="' + entry.file + '" visible="false" style="visibility:collapse; width:0px; height:0px;" />').join('\n') + '\n</Panel></root>\n');

fs.mkdirSync(work, {recursive: true});
fs.writeFileSync(path.join(work, 'import.json'), JSON.stringify({at: new Date().toISOString(), success: true, package: path.relative(repo, pack).replaceAll('\\', '/'), manifestAssetCount: manifest.assets.length,
    runtimeBitmapCount: records.length, originalBytesPreserved: true, records, catalogSource, configuredItemCount: catalog.length, font: {family: data.font_family, sha256: fontSource.sha256, policy: 'Reuse byte-identical, already registered project font', paths: fontPaths},
    excluded: ['assets/preview_only/**', 'previews/**', '*.svg masters', 'data_preview.json', 'tooltip_preview_data.json'],
    dataPolicy: 'No preview item layers, sample numbers, limits or descriptions imported. Shadow icons keyed by official shadow_01..shadow_23 IDs; other categories keep their original project icons.'}, null, 2));
fs.writeFileSync(path.join(__dirname, 'compile_scope.json'), JSON.stringify(records.map(record => record.relative).concat([dataFile, 'scripts/custom_game/archive_v10_semantics.js', 'scripts/custom_game/archive_v10_icons.js', 'scripts/custom_game/archive_purple.js', 'scripts/custom_game/archive_handoff_180de7e38b.js', 'scripts/custom_game/archive_v10.js', 'styles/custom_game/archive_v10.css', 'scripts/custom_game/archive_180de7e38b_titles_compact_v6.js', assetLayout, 'layout/custom_game/archive.xml']), null, 2));
console.log('ARCHIVE_V10_IMPORT_PASS ' + records.length + ' original runtime PNGs; ' + manifest.assets.length + ' manifest checksums verified; registered font identical.');
