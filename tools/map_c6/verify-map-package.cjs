// Verify the current binary VMAP against its compiled package without rebuilding
// or converting anything. No arena manifest or installed-model assumptions.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const { crc32 } = require('./verify-arenas.cjs');

const ROOT = path.resolve(__dirname, '../..');
const SOURCE_ROOT = path.resolve(ROOT, '../../../content/dota_addons/survival');
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const assetName = name => String(name).replace(/\\/g, '/').replace(/^\.\//, '').toLowerCase();
function requireValid(condition, message) { if (!condition) throw new Error(message); }

function inspectVpk(bytes, { mapResource, readArchive } = {}) {
    requireValid(bytes.length >= 12 && bytes.readUInt32LE(0) === 0x55aa1234, 'Invalid VPK header');
    const version = bytes.readUInt32LE(4);
    requireValid(version === 1 || version === 2, 'Unsupported VPK version: ' + version);
    const headerSize = version === 2 ? 28 : 12;
    requireValid(bytes.length >= headerSize, 'Truncated VPK header');
    const treeEnd = headerSize + bytes.readUInt32LE(8);
    requireValid(treeEnd <= bytes.length, 'Truncated VPK tree');
    const inlineEnd = version === 2 ? treeEnd + bytes.readUInt32LE(12) : bytes.length;
    requireValid(inlineEnd <= bytes.length, 'Truncated VPK file data section');
    if (version === 2) {
        const sectionsEnd = inlineEnd + bytes.readUInt32LE(16) + bytes.readUInt32LE(20) + bytes.readUInt32LE(24);
        requireValid(sectionsEnd <= bytes.length, 'Truncated VPK checksum/signature sections');
    }
    let cursor = headerSize;
    let mapPayload;
    const entries = [];
    const names = new Set();
    function readString() {
        const end = bytes.indexOf(0, cursor);
        requireValid(end >= cursor && end < treeEnd, 'Invalid or unterminated VPK directory string');
        const value = bytes.toString('utf8', cursor, end);
        cursor = end + 1;
        return value;
    }
    let extension, directory, filename;
    while ((extension = readString())) while ((directory = readString())) while ((filename = readString())) {
        requireValid(cursor + 18 <= treeEnd, 'Truncated VPK directory entry');
        const expected = bytes.readUInt32LE(cursor);
        const preloadLength = bytes.readUInt16LE(cursor + 4);
        const archive = bytes.readUInt16LE(cursor + 6);
        const offset = bytes.readUInt32LE(cursor + 8);
        const length = bytes.readUInt32LE(cursor + 12);
        requireValid(bytes.readUInt16LE(cursor + 16) === 0xffff, 'Invalid VPK entry terminator');
        cursor += 18;
        requireValid(cursor + preloadLength <= treeEnd, 'Truncated VPK preload data');
        const preload = bytes.subarray(cursor, cursor + preloadLength);
        cursor += preloadLength;
        const name = assetName((directory === ' ' ? '' : directory + '/') + filename
            + (extension === ' ' ? '' : '.' + extension));
        requireValid(!names.has(name), 'Duplicate VPK entry: ' + name);
        names.add(name);
        let blob = bytes, start = treeEnd + offset, end = inlineEnd;
        if (archive !== 0x7fff && length > 0) {
            requireValid(typeof readArchive === 'function', 'External VPK archive reader required: ' + archive);
            blob = readArchive(archive);
            requireValid(Buffer.isBuffer(blob), 'Invalid external VPK archive: ' + archive);
            start = offset;
            end = blob.length;
        }
        requireValid(length === 0 || start + length <= end, 'Truncated VPK resource: ' + name);
        const payload = length ? Buffer.concat([preload, blob.subarray(start, start + length)]) : Buffer.from(preload);
        const actual = crc32(payload);
        requireValid(actual === expected, 'VPK CRC mismatch: ' + name + ' (expected ' + expected + ', actual ' + actual + ')');
        entries.push({ path: name, bytes: payload.length, archive_index: archive,
            expected_crc32: expected, actual_crc32: actual, crc_matches: true, sha256: sha256(payload) });
        if (name === assetName(mapResource)) mapPayload = payload;
    }
    requireValid(cursor === treeEnd, 'VPK tree did not consume the declared directory size');
    requireValid(entries.length > 0, 'VPK contains no resources');
    if (mapResource) requireValid(mapPayload, 'VPK missing compiled map: ' + mapResource);
    return { version, entries, mapPayload, crc_entries: entries.length,
        payload_bytes: entries.reduce((sum, entry) => sum + entry.bytes, 0) };
}

function resourceBlocks(bytes) {
    requireValid(bytes.length >= 16, 'Truncated compiled map resource header');
    const size = bytes.readUInt32LE(0);
    requireValid(size >= 16 && size <= bytes.length, 'Invalid compiled map resource size');
    const table = 8 + bytes.readUInt32LE(8), count = bytes.readUInt32LE(12);
    requireValid(table >= 16 && count <= 128 && table + count * 12 <= size, 'Invalid compiled map block table');
    const blocks = [];
    for (let index = 0; index < count; index++) {
        const entry = table + index * 12;
        const name = bytes.toString('ascii', entry, entry + 4);
        const start = entry + 4 + bytes.readUInt32LE(entry + 4), length = bytes.readUInt32LE(entry + 8);
        requireValid(start + length <= size, 'Truncated compiled map block: ' + name);
        blocks.push({ name, bytes: bytes.subarray(start, start + length) });
    }
    return blocks;
}

function parseRediDependencies(bytes) {
    // REDI's first offset/count pair describes 16-byte InputDependency records.
    // Filename and search-path pointers are relative to their own fields.
    requireValid(bytes.length >= 8, 'Truncated REDI input dependency header');
    const first = bytes.readInt32LE(0), count = bytes.readUInt32LE(4);
    requireValid(first >= 0 && first + count * 16 <= bytes.length, 'Invalid REDI input dependency array');
    function relativeString(field) {
        const start = field + bytes.readInt32LE(field);
        const end = bytes.indexOf(0, start);
        requireValid(start >= 0 && start < bytes.length && end >= start, 'Invalid REDI dependency string');
        return bytes.toString('utf8', start, end);
    }
    return Array.from({ length: count }, (_, index) => {
        const entry = first + index * 16;
        return { relative_filename: relativeString(entry), search_path: relativeString(entry + 4),
            crc32: bytes.readUInt32LE(entry + 8) };
    });
}

function parseRed2Dump(text) {
    // Restrict matches to individual objects; never pair one dependency's name
    // with a later dependency's CRC when metadata is missing or malformed.
    const dependencies = [];
    for (const object of text.matchAll(/\{[^{}]*\}/g)) {
        const filename = object[0].match(/\bm_RelativeFilename\s*=\s*"([^"\r\n]+)"/);
        if (!filename) continue;
        const checksum = object[0].match(/\bm_nFileCRC\s*=\s*(\d+)/);
        if (!checksum) continue;
        const crc = Number(checksum[1]);
        requireValid(Number.isInteger(crc) && crc >= 0 && crc <= 0xffffffff, 'Invalid RED2 source CRC');
        dependencies.push({ relative_filename: filename[1],
            search_path: object[0].match(/\bm_SearchPath\s*=\s*"([^"\r\n]*)"/)?.[1] || '', crc32: crc });
    }
    return dependencies;
}

function readCompiledDependencies(mapPayload, inspector) {
    const blocks = resourceBlocks(mapPayload);
    const redi = blocks.filter(block => block.name === 'REDI');
    const red2 = blocks.filter(block => block.name === 'RED2');
    requireValid(redi.length + red2.length === 1, 'Expected one REDI or RED2 dependency block in compiled map');
    if (redi.length) return { block: 'REDI', dependencies: parseRediDependencies(redi[0].bytes) };
    requireValid(fs.existsSync(inspector), 'RED2 requires resourceinfo.exe: ' + inspector);
    const temporaryParent = fs.realpathSync(os.tmpdir());
    const temporaryDirectory = fs.mkdtempSync(path.join(temporaryParent, 'survival-map-package-'));
    const extractedMap = path.join(temporaryDirectory, 'map.vmap_c');
    try {
        fs.writeFileSync(extractedMap, mapPayload);
        // Map resources need the game's resource schemas mounted. Bare-mode
        // block inspection works for textures but fails for this compiled map.
        const text = execFileSync(inspector, ['-game', path.resolve(ROOT, '../../dota'), '-i', extractedMap, '-all'],
            { encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024 });
        return { block: 'RED2', dependencies: parseRed2Dump(text) };
    } finally {
        requireValid(path.dirname(temporaryDirectory) === temporaryParent, 'Unexpected temporary directory parent');
        if (fs.existsSync(extractedMap)) fs.unlinkSync(extractedMap);
        fs.rmdirSync(temporaryDirectory);
    }
}

function matchSource(bytes, dependencies, sourceName) {
    const header = bytes.subarray(0, 256).toString('utf8').replace(/^\uFEFF/, '');
    requireValid(/^<!--\s*dmx\s+encoding\s+binary(?:_[a-z]+)?\s+\d+\s+format\s+vmap\s+\d+\s*-->/.test(header),
        'Source must already be a binary VMAP; no text conversion is performed');
    const matches = dependencies.filter(dependency => assetName(dependency.relative_filename) === assetName(sourceName));
    requireValid(matches.length === 1, 'Expected exactly one compiled source dependency for ' + sourceName + ', found ' + matches.length);
    const actual = crc32(bytes);
    return { source_name: sourceName, compiled_search_path: matches[0].search_path,
        raw_source_crc32: actual, compiled_source_crc32: matches[0].crc32, matches: actual === matches[0].crc32 };
}

function readStableFile(filename) {
    const before = fs.statSync(filename);
    requireValid(before.isFile(), 'Expected a regular file: ' + filename);
    const bytes = fs.readFileSync(filename);
    const after = fs.statSync(filename);
    requireValid(before.size === after.size && before.mtimeMs === after.mtimeMs && bytes.length === after.size,
        'Input changed while being read; wait for compilation to finish: ' + filename);
    return { bytes, size: after.size, mtimeMs: after.mtimeMs };
}

function verifyMapPackage(options, report = {}) {
    const inputs = new Map();
    function read(filename) {
        if (!inputs.has(filename)) inputs.set(filename, readStableFile(filename));
        return inputs.get(filename).bytes;
    }
    const sourceBytes = read(options.source), packageBytes = read(options.vpk);
    report.source = { path: options.source, bytes: sourceBytes.length, sha256: sha256(sourceBytes),
        raw_crc32: crc32(sourceBytes), converted: false };
    report.package = { path: options.vpk, bytes: packageBytes.length, sha256: sha256(packageBytes) };
    const checked = inspectVpk(packageBytes, {
        mapResource: options.mapResource,
        readArchive(index) {
            const filename = options.vpk.replace(/(?:_dir)?\.vpk$/i, '_' + String(index).padStart(3, '0') + '.vpk');
            requireValid(filename !== options.vpk, 'Cannot resolve external VPK archive filename');
            return read(filename);
        }
    });
    Object.assign(report.package, { version: checked.version, crc_entries: checked.crc_entries,
        payload_bytes: checked.payload_bytes, entries: checked.entries });
    const compiled = readCompiledDependencies(checked.mapPayload, options.inspector);
    report.compiled_map = { path: options.mapResource, bytes: checked.mapPayload.length,
        sha256: sha256(checked.mapPayload), dependency_block: compiled.block };
    report.source_match = matchSource(sourceBytes, compiled.dependencies, options.sourceName);
    requireValid(report.source_match.matches, 'Compiled map source CRC does not match the raw binary VMAP: expected '
        + report.source_match.compiled_source_crc32 + ', actual ' + report.source_match.raw_source_crc32);
    // Also catch an input being replaced while another archive or RED2 was read.
    for (const [filename, original] of inputs) {
        const current = fs.statSync(filename);
        requireValid(current.size === original.size && current.mtimeMs === original.mtimeMs,
            'Input changed during verification; wait for compilation to finish: ' + filename);
    }
    report.external_archives = [...inputs].filter(([filename]) => filename !== options.source && filename !== options.vpk)
        .map(([filename, input]) => ({ path: filename, bytes: input.size, sha256: sha256(input.bytes) }));
    report.status = 'PASS';
    report.compiled_verified = true;
    report.runtime_verified = false;
    report.note = 'All VPK entry CRCs and the raw binary VMAP source CRC match. Engine behavior and map layout were not tested.';
    return report;
}

function selfTest() {
    const assert = require('node:assert/strict');
    assert.equal(crc32(Buffer.from('123456789')), 0xcbf43926);
    const source = Buffer.concat([Buffer.from('<!-- dmx encoding binary 9 format vmap 39 -->\n\0'), Buffer.from([0, 255, 128, 1])]);
    const sourceName = 'maps/template_map.vmap';
    const strings = Buffer.from(sourceName + '\0dota_addons/survival\0');
    const redi = Buffer.alloc(96 + strings.length);
    redi.writeInt32LE(80, 0); redi.writeUInt32LE(1, 4);
    redi.writeInt32LE(16, 80); redi.writeInt32LE(12 + sourceName.length + 1, 84);
    redi.writeUInt32LE(crc32(source), 88); strings.copy(redi, 96);
    const compiled = Buffer.alloc(28 + redi.length);
    compiled.writeUInt32LE(compiled.length, 0); compiled.writeUInt16LE(12, 4);
    compiled.writeUInt32LE(8, 8); compiled.writeUInt32LE(1, 12);
    compiled.write('REDI', 16); compiled.writeUInt32LE(8, 20); compiled.writeUInt32LE(redi.length, 24);
    redi.copy(compiled, 28);
    function fixture(version) {
        const preload = compiled.subarray(0, 7), rest = compiled.subarray(7);
        const entry = Buffer.alloc(18);
        entry.writeUInt32LE(crc32(compiled), 0); entry.writeUInt16LE(preload.length, 4);
        entry.writeUInt16LE(0x7fff, 6); entry.writeUInt32LE(rest.length, 12); entry.writeUInt16LE(0xffff, 16);
        const tree = Buffer.concat([Buffer.from('vmap_c\0maps\0template_map\0'), entry, preload, Buffer.alloc(3)]);
        const header = Buffer.alloc(version === 2 ? 28 : 12);
        header.writeUInt32LE(0x55aa1234, 0); header.writeUInt32LE(version, 4); header.writeUInt32LE(tree.length, 8);
        if (version === 2) header.writeUInt32LE(rest.length, 12);
        return Buffer.concat([header, tree, rest]);
    }
    for (const version of [1, 2]) {
        const valid = fixture(version);
        const result = inspectVpk(valid, { mapResource: sourceName + '_c' });
        assert.equal(result.crc_entries, 1);
        assert(result.mapPayload.equals(compiled), 'VPK preload must be included in CRC and extracted data');
        const damaged = Buffer.from(valid); damaged[damaged.length - 1] ^= 1;
        assert.throws(() => inspectVpk(damaged, { mapResource: sourceName + '_c' }), /VPK CRC mismatch/);
        assert.throws(() => inspectVpk(valid.subarray(0, valid.length - 1)), /Truncated VPK/);
    }
    const dependencies = parseRediDependencies(resourceBlocks(compiled)[0].bytes);
    assert(matchSource(source, dependencies, sourceName).matches);
    const changed = Buffer.from(source); changed[changed.length - 1] ^= 1;
    assert.equal(matchSource(changed, dependencies, sourceName).matches, false, 'Raw binary changes must fail source matching');
    assert.throws(() => matchSource(source, dependencies, 'maps/another_map.vmap'), /exactly one compiled source/);
    assert.throws(() => matchSource(Buffer.from('<!-- dmx encoding keyvalues2 1 format vmap 39 -->'), dependencies, sourceName), /already be a binary/);
    const decoded = parseRed2Dump('{ m_RelativeFilename = "wrong.vmap" }\n{ m_RelativeFilename = "'
        + sourceName + '" m_SearchPath = "dota_addons/survival" m_nFileCRC = ' + crc32(source) + ' }');
    assert.equal(decoded.length, 1, 'Do not borrow a following dependency CRC for a missing field');
    assert(matchSource(source, decoded, sourceName).matches);
    console.log('MAP_PACKAGE_SELF_TEST_PASS: VPK v1/v2, preload CRC, corruption, truncation, REDI, RED2, source mismatch, text rejection');
}

function main(args = process.argv.slice(2)) {
    if (args.includes('--help')) {
        console.log('Usage: node tools/map_c6/verify-map-package.cjs [--map binary.vmap] [--vpk map.vpk] [--report report.json]\n'
            + 'Optional: --source-name maps/name.vmap --map-resource maps/name.vmap_c --resourceinfo executable\n'
            + 'Defaults: current content/maps/template_map.vmap and game/maps/template_map.vpk. --self-test uses in-memory fixtures only.');
        return;
    }
    if (args.length === 1 && args[0] === '--self-test') { selfTest(); return; }
    const values = {};
    const accepted = new Set(['--map', '--source', '--vpk', '--report', '--source-name', '--map-resource', '--resourceinfo']);
    for (let index = 0; index < args.length; index += 2) {
        requireValid(accepted.has(args[index]) && args[index + 1] && !args[index + 1].startsWith('--'), 'Invalid argument: ' + args[index]);
        requireValid(values[args[index]] === undefined, 'Duplicate argument: ' + args[index]);
        values[args[index]] = args[index + 1];
    }
    requireValid(!(values['--map'] && values['--source']), 'Use only one of --map and --source');
    const source = path.resolve(values['--map'] || values['--source'] || path.join(SOURCE_ROOT, 'maps/template_map.vmap'));
    const sourcePath = source.replace(/\\/g, '/'), mapStart = sourcePath.toLowerCase().lastIndexOf('/maps/');
    const sourceName = assetName(values['--source-name'] || (mapStart >= 0 ? sourcePath.slice(mapStart + 1) : 'maps/' + path.basename(source)));
    const options = { source, sourceName,
        vpk: path.resolve(values['--vpk'] || path.join(ROOT, 'maps/template_map.vpk')),
        mapResource: assetName(values['--map-resource'] || sourceName + '_c'),
        inspector: path.resolve(values['--resourceinfo'] || path.resolve(ROOT, '../../bin/win64/resourceinfo.exe')) };
    const reportPath = values['--report'] ? path.resolve(values['--report']) : null;
    if (reportPath) {
        requireValid(path.extname(reportPath).toLowerCase() === '.json', 'Report filename must end in .json');
        requireValid(![options.source, options.vpk, options.inspector].some(input => input.toLowerCase() === reportPath.toLowerCase()),
            'Report must not overwrite an input');
    }
    const report = { status: 'FAIL', compiled_verified: false, runtime_verified: false,
        checked_at: new Date().toISOString(), source_path: options.source, package_path: options.vpk };
    try { verifyMapPackage(options, report); }
    catch (error) { report.error = String(error.message || error); process.exitCode = 1; }
    if (reportPath) {
        fs.mkdirSync(path.dirname(reportPath), { recursive: true });
        fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
        console.log(JSON.stringify({ status: report.status, report: reportPath, error: report.error,
            crc_entries: report.package?.crc_entries, source_match: report.source_match,
            source_sha256: report.source?.sha256, package_sha256: report.package?.sha256 }));
    } else console.log(JSON.stringify(report, null, 2));
}

module.exports = { inspectVpk, resourceBlocks, parseRediDependencies, parseRed2Dump, matchSource, verifyMapPackage, selfTest };
if (require.main === module) {
    try { main(); }
    catch (error) { console.error('MAP_PACKAGE_VERIFY_FAIL: ' + String(error.message || error)); process.exitCode = 1; }
}
