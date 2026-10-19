'use strict';

// Preserve the approved forest background as an unused source asset only.
// The installed texture contains a native JPEG bitstream: copying it retains
// exact Valve bytes; renaming or re-encoding it as PNG would obscure that fact.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const sourcePath = 'panorama/images/loadout_backgrounds/loadout_bg_forest_003_jpg.vtex_c';
const assetPath = 'art/ui/sources/custom_game/lottery_optional_v1/forest_emerald.jpeg';
const manifestPath = 'art/ui/sources/custom_game/lottery_optional_v1/manifest.json';
const sourceFile = path.join(root, 'design_refs/official_ui_catalog_20261019/assets/panorama/images/loadout_backgrounds/loadout_bg_forest_003_jpg.jpeg');
const official = {
    id: 'UI04024',
    resourceSha256: '9aa3a5a260b7d8ad189be0438ea695f50d8bf67e485ed0b9ef6b9134548f0ef3',
    jpegSha256: '89d56ab661c1a19b464d90790253ba1b53eec7eef3bfd8e6caaa40312bf8c058',
    width: 3840,
    height: 2160,
    embeddedJpegOffset: 2052,
};
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
function assert(condition, message) { if (!condition) throw new Error(message); }

function jpegSize(bytes) {
    assert(bytes[0] === 0xff && bytes[1] === 0xd8, 'Expected a real JPEG file, not a renamed image');
    let offset = 2;
    while (offset < bytes.length - 9) {
        assert(bytes[offset++] === 0xff, 'Malformed JPEG marker');
        while (bytes[offset] === 0xff) offset++;
        const marker = bytes[offset++];
        if (marker === 0xd9 || marker === 0xda) break;
        if (marker === 0x01 || marker >= 0xd0 && marker <= 0xd8) continue;
        const length = bytes.readUInt16BE(offset);
        assert(length >= 2 && offset + length <= bytes.length, 'Malformed JPEG segment');
        if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
            return { width: bytes.readUInt16BE(offset + 5), height: bytes.readUInt16BE(offset + 3) };
        }
        offset += length;
    }
    throw new Error('JPEG size marker not found');
}

function verifyBytes(bytes) {
    assert(sha(bytes) === official.jpegSha256, 'Forest JPEG differs from the official embedded source');
    const dimensions = jpegSize(bytes);
    assert(dimensions.width === official.width && dimensions.height === official.height, 'Forest JPEG dimensions changed');
    return dimensions;
}

function officialEvidence(bytes) {
    const archive = path.resolve(root, '../../dota/pak01_dir.vpk');
    if (!fs.existsSync(archive)) return { available: false };
    const vpk = require('../vpk_inspect.cjs').open(archive);
    const entry = vpk.entries.find((row) => row.path === sourcePath);
    assert(entry, 'Official forest VTEX is missing from installed VPK');
    const compiled = vpk.read(entry);
    assert(sha(compiled) === official.resourceSha256, 'Installed official forest resource identity changed');
    assert(compiled.indexOf(bytes) === official.embeddedJpegOffset, 'Export is not the exact official embedded JPEG bitstream');
    return { available: true, compiledBytes: compiled.length, embeddedJpegOffset: official.embeddedJpegOffset };
}

function productionReferences() {
    const needles = ['lottery_optional_v1', 'forest_emerald', 'loadout_bg_forest_003'];
    const found = [];
    function walk(directory) {
        if (!fs.existsSync(directory)) return;
        for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
            const file = path.join(directory, entry.name);
            if (entry.isDirectory()) walk(file);
            else if (/\.(?:js|css|xml)$/.test(entry.name)) {
                const text = fs.readFileSync(file, 'utf8');
                for (const needle of needles) if (text.includes(needle)) found.push({ file: path.relative(root, file).replaceAll('\\', '/'), needle });
            }
        }
    }
    walk(path.join(root, 'panorama/src'));
    return found;
}

function check() {
    const file = path.join(root, assetPath);
    const manifest = JSON.parse(fs.readFileSync(path.join(root, manifestPath), 'utf8'));
    const bytes = fs.readFileSync(file);
    const dimensions = verifyBytes(bytes);
    assert(manifest.currentlyDisabled === true && manifest.runtimeUri === null, 'Optional background must stay disabled for this integration');
    assert(manifest.asset.path === assetPath && manifest.asset.sha256 === sha(bytes), 'Optional manifest identity mismatch');
    assert(manifest.source.resource === sourcePath && manifest.source.resourceSha256 === official.resourceSha256, 'Optional manifest source mismatch');
    const references = productionReferences();
    assert(!references.length, 'Disabled forest background has production references: ' + JSON.stringify(references));
    const compiledDirectory = path.join(root, 'panorama/images/custom_game/lottery_optional_v1');
    assert(!fs.existsSync(compiledDirectory), 'Disabled optional background unexpectedly has runtime compilation output');
    const evidence = officialEvidence(bytes);
    if (fs.existsSync(sourceFile)) assert(fs.readFileSync(sourceFile).equals(bytes), 'Stored optional image is not an exact copy of the decoded original');
    return { status: 'PASS_DISABLED_EXACT_OFFICIAL_ASSET', file: assetPath, bytes: bytes.length, sha256: sha(bytes), ...dimensions, currentlyDisabled: true, runtimeReferences: references, officialEvidence: evidence };
}

function importAsset(input = sourceFile) {
    const bytes = fs.readFileSync(input);
    verifyBytes(bytes);
    const evidence = officialEvidence(bytes);
    assert(evidence.available, 'Import requires installed VPK evidence');
    const target = path.join(root, assetPath);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    if (fs.existsSync(target)) assert(fs.readFileSync(target).equals(bytes), 'Refusing to overwrite a different existing optional background');
    else fs.writeFileSync(target, bytes);
    const manifest = {
        schemaVersion: 1,
        name: '幽林翡翠 forest003 备用背景',
        currentlyDisabled: true,
        runtimeUri: null,
        compileRequiredForThisChange: false,
        asset: { path: assetPath, format: 'JPEG', width: official.width, height: official.height, bytes: bytes.length, sha256: sha(bytes) },
        source: {
            catalogId: official.id,
            archive: 'game/dota/pak01_dir.vpk',
            resource: sourcePath,
            resourceUri: 's2r://panorama/images/loadout_backgrounds/loadout_bg_forest_003_jpg.vtex',
            resourceSha256: official.resourceSha256,
            embeddedJpegOffset: official.embeddedJpegOffset,
            extraction: 'Exact native JPEG bitstream from official VTEX, copied without re-encoding or visual edits.',
        },
        usage: 'Stored for a possible future background option. The current lottery uses the existing four pool scenes; no production layout, script, stylesheet or runtime texture references this optional image.',
    };
    fs.writeFileSync(path.join(root, manifestPath), JSON.stringify(manifest, null, 2) + '\n');
    return check();
}

module.exports = { importAsset, check, jpegSize, productionReferences };
if (require.main === module) {
    const at = process.argv.indexOf('--source');
    const result = process.argv.includes('--check') ? check() : importAsset(at >= 0 ? path.resolve(process.argv[at + 1]) : sourceFile);
    console.log(JSON.stringify(result, null, 2));
}
