'use strict';
// Inspect the original PNGs, generated pixels and shipped Source2 DATA/mip payloads.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {textureInfo} = require('./test_construction_grid_resources.cjs');
const {decodePng} = require('./collection_gw2/opaque_probe.cjs');
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const categories = ['ex', 'friend', 'wife', 'beast'];
const expectedIds = categories.flatMap(category => Array.from({length: 40}, (_, index) => category + '_' + String(index + 1).padStart(2, '0')));
function localFile(root, relative) {
    assert.equal(typeof relative, 'string');
    assert(!path.isAbsolute(relative) && !relative.split(/[\\/]/).includes('..'), 'manifest paths stay within their declared root');
    return path.join(root, relative);
}
function runtimeFile(root, uri) {
    assert(uri.startsWith('s2r://panorama/images/'), 'native Panorama texture URI');
    return localFile(root, uri.slice('s2r://'.length) + '_c');
}
function alphaSummary(image) {
    let minimum = 255, maximum = 0, transparent = 0, partial = 0;
    for (let i = 0; i < image.width * image.height; i++) {
        const alpha = image.channels === 4 ? image.pixels[i * 4 + 3] : 255;
        minimum = Math.min(minimum, alpha); maximum = Math.max(maximum, alpha);
        if (!alpha) transparent++; else if (alpha < 255) partial++;
    }
    return {minimum, maximum, transparent_pixels: transparent, partial_pixels: partial};
}
function payloadSize(info) {
    let bytes = 0;
    for (let level = 0; level < info.mipLevels; level++) bytes += Math.max(1, info.width >> level) * Math.max(1, info.height >> level) * 4;
    return bytes;
}
function audit(options = {}) {
    const assetRoot = path.resolve(options.assetsRoot || process.cwd());
    const sourceRoot = path.resolve(options.root || assetRoot);
    const manifestPath = path.join(assetRoot, 'data/ui/collection_portraits_compact_v1.json');
    const manifestBytes = fs.readFileSync(manifestPath), manifest = JSON.parse(manifestBytes);
    assert.equal(manifest.schema_version, 1);
    assert.equal(manifest.asset_set, 'collection_portraits_compact_v1');
    assert.equal(manifest.usage, 'collection_grid_only');
    assert.deepEqual(manifest.dimensions, [128, 128]);
    assert.equal(manifest.pixel_format, 'RGBA');
    assert.equal(manifest.texture.output_format, 'BGRA8888');
    assert.equal(manifest.texture.no_lod, true);
    assert.equal(manifest.texture.mip_algorithm, 'Box');
    assert.equal(manifest.texture.mip_levels, 8);
    assert.equal(manifest.texture.payload_bytes_per_texture, 87380);
    assert.equal(manifest.count, 160); assert.equal(manifest.items.length, 160);
    assert.deepEqual(manifest.items.map(item => item.id).sort(), expectedIds.slice().sort(), 'all four formal pools have exactly 01 through 40');
    for (const field of ['source', 'png', 'texture', 'runtime_uri', 'legacy_runtime_uri']) {
        assert.equal(new Set(manifest.items.map(item => item[field])).size, 160, 'each item retains a distinct ' + field + ' mapping');
    }
    const records = [];
    let totalBytes = 0, legacyBytes = 0, generatedPngBytes = 0, originalPngBytes = 0;
    for (const item of manifest.items) {
        const id = item.id, prefix = 'panorama/src/images/custom_game/collection_portraits_compact_v1/' + id;
        assert.equal(item.category_id, id.split('_')[0], id + ': original collection pool');
        assert.equal(item.png, prefix + '.png'); assert.equal(item.texture, prefix + '.vtex');
        assert.equal(item.runtime_uri, 's2r://panorama/images/custom_game/collection_portraits_compact_v1/' + id + '.vtex');
        const originalBytes = fs.readFileSync(localFile(sourceRoot, item.source));
        assert.equal(sha256(originalBytes), item.source_sha256, id + ': original source hash remains unchanged');
        const original = decodePng(originalBytes), originalAlpha = alphaSummary(original);
        assert.deepEqual([original.width, original.height], item.source_dimensions, id + ': original dimensions match the receipt');
        const pngBytes = fs.readFileSync(localFile(assetRoot, item.png));
        assert.equal(sha256(pngBytes), item.png_sha256, id + ': generated PNG matches manifest');
        const png = decodePng(pngBytes), alpha = alphaSummary(png);
        assert.deepEqual([png.width, png.height, png.channels], [128, 128, 4], id + ': actual decoded thumbnail is 128px RGBA');
        assert(alpha.maximum > 0, id + ': portrait is not accidentally transparent');
        if (originalAlpha.minimum === 255) assert.equal(alpha.minimum, 255, id + ': opaque source stays opaque');
        else assert(alpha.minimum < 255, id + ': authored transparency survives resampling');
        const recipeBytes = fs.readFileSync(localFile(assetRoot, item.texture)), recipe = recipeBytes.toString('utf8');
        assert.equal(sha256(recipeBytes), item.texture_sha256, id + ': source recipe matches manifest');
        assert(recipe.includes('"' + item.png.replace('panorama/src/', 'panorama/') + '"'), id + ': recipe references this item PNG');
        assert.match(recipe, /"m_outputFormat"\s+"string"\s+"BGRA8888"/);
        assert.match(recipe, /"m_bNoLod"\s+"bool"\s+"1"/);
        assert.match(recipe, /"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+"Box"/);
        const compiledBytes = fs.readFileSync(runtimeFile(assetRoot, item.runtime_uri)), info = textureInfo(compiledBytes);
        assert.deepEqual([info.width, info.height, info.depth, info.format, info.mipLevels, info.flags & 8],
            [128, 128, 1, 28, 8, 8], id + ': actual native texture has the full resident BGRA8888 mip chain');
        assert.equal(info.payload.length, 87380, id + ': all eight native mip payloads exist');
        assert.equal(info.payload.length, payloadSize(info));
        // Source2 stores smallest mips first. The 128px base level is the final 65536 bytes.
        const baseMip = info.payload.subarray(info.payload.length - 128 * 128 * 4);
        for (let pixel = 0; pixel < 128 * 128; pixel++) {
            assert.equal(baseMip[pixel * 4 + 3], png.pixels[pixel * 4 + 3], id + ': compiled base-level alpha matches PNG pixel ' + pixel);
        }
        const oldBytes = fs.readFileSync(runtimeFile(sourceRoot, item.legacy_runtime_uri)), old = textureInfo(oldBytes);
        assert.equal(old.format, 28, id + ': comparison uses the existing BGRA8888 resource');
        assert.equal(old.depth, 1); assert.equal(old.payload.length, payloadSize(old), id + ': existing mip payload is complete');
        assert.equal(old.payload.length, item.legacy_payload_bytes, id + ': legacy payload receipt matches actual native bytes');
        totalBytes += info.payload.length; legacyBytes += old.payload.length;
        generatedPngBytes += pngBytes.length; originalPngBytes += originalBytes.length;
        records.push({id, source_sha256: item.source_sha256, png_sha256: item.png_sha256,
            compiled_sha256: sha256(compiledBytes), width: info.width, height: info.height,
            format: info.format, mip_levels: info.mipLevels, payload_bytes: info.payload.length,
            legacy_payload_bytes: old.payload.length, alpha, native_alpha_matches_png: true});
    }
    assert.equal(totalBytes, 160 * 87380); assert.equal(totalBytes, manifest.target_payload_bytes);
    assert.equal(legacyBytes, manifest.legacy_payload_bytes);
    assert(totalBytes < legacyBytes, 'actual native payload total decreases');
    return {result: 'COLLECTION_PORTRAIT_THUMBNAILS_PASS', count: records.length,
        source_root: sourceRoot, asset_root: assetRoot, manifest_sha256: sha256(manifestBytes),
        original_sources_unchanged: true, native_alpha_matches_png: true,
        payload_bytes: totalBytes, legacy_payload_bytes: legacyBytes, bytes_saved: legacyBytes - totalBytes,
        reduction_percent: Number(((1 - totalBytes / legacyBytes) * 100).toFixed(2)),
        generated_png_bytes: generatedPngBytes, original_png_bytes: originalPngBytes, records};
}
module.exports = {audit};
if (require.main === module) {
    const options = {};
    for (let i = 2; i < process.argv.length; i++) {
        const flag = process.argv[i], value = process.argv[++i];
        assert(value && ['--root', '--output'].includes(flag), 'usage: node tools/audit_collection_portrait_thumbnails.cjs [--root original-repo] [--output report.json]');
        options[flag.slice(2)] = value;
    }
    const report = audit(options);
    if (options.output) {fs.mkdirSync(path.dirname(path.resolve(options.output)), {recursive: true}); fs.writeFileSync(options.output, JSON.stringify(report, null, 2) + '\n');}
    const {records, ...summary} = report;
    console.log(JSON.stringify(summary, null, 2));
}
