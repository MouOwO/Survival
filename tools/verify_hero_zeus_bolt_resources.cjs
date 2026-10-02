'use strict';
// Validate current hero/tower CSV contracts against fresh installed Valve assets.
// Writes only output/hero_zeus_bolt_20261002; does not compile or start a map.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const assert = require('assert');
const { Vpk, endOf } = require('./map_c6/lib.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output/hero_zeus_bolt_20261002');
const dumps = path.join(output, 'resource_validation');
const reportFile = path.join(output, 'resources_validation.json');
const lightningCsv = 'data/csv/建筑与工人系统/防御塔/tower_lightning_effects.csv';
const soundCsv = 'data/csv/英雄系统/hero_skill_sound_definitions.csv';
const nativeBolt = 'particles/units/heroes/hero_zuus/zuus_lightning_bolt.vpcf';
const nativeCast = 'particles/units/heroes/hero_zuus/zuus_lightning_bolt_castfx.vpcf';
const expectedTowerStorm = 'particles/econ/items/disruptor/disruptor_2022_immortal/disruptor_2022_immortal_static_storm.vpcf';
const particlePrefix = 'particles/econ/items/zeus/lightning_weapon_fx/';
const expectedSound = 'Hero_Zuus.LightningBolt.Righteous';
const expectedSoundResource = 'soundevents/game_sounds_heroes/game_sounds_zuus.vsndevts';
const baseline = { particle_systems: 28, resources: 41 };
const report = {
    status: 'FAIL', checked_at: new Date().toISOString(),
    source: 'Fresh installed Valve dota/core VPK and current authoritative CSVs',
    item_def: 5412, warnings: [], checks: [], in_game_visual_verified: false,
    compiled_resources: false, map_started: false,
};
function hash(bytes) { return crypto.createHash('sha256').update(bytes).digest('hex'); }
function csvRows(filename) {
    const text = fs.readFileSync(path.join(root, filename), 'utf8').replace(/^\uFEFF/, '');
    const rows = []; let row = [], value = '', quoted = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (ch === '"') {
            if (quoted && text[i + 1] === '"') { value += '"'; i++; }
            else quoted = !quoted;
        } else if (!quoted && (ch === ',' || ch === '\n' || ch === '\r')) {
            row.push(value); value = '';
            if (ch !== ',') {
                rows.push(row); row = [];
                if (ch === '\r' && text[i + 1] === '\n') i++;
            }
        } else value += ch;
    }
    assert(!quoted, 'Unclosed CSV quoted field: ' + filename);
    if (value || row.length) { row.push(value); rows.push(row); }
    const headers = rows.shift();
    return rows.filter(r => r[0] && !r[0].startsWith('#')).map(r => {
        assert.equal(r.length, headers.length, 'CSV column mismatch: ' + filename + ' / ' + r[0]);
        return Object.fromEntries(headers.map((h, i) => [h, r[i]]));
    });
}
function enabled(row) { return row && /^(1|true)$/i.test(row.enabled); }
function parseItem(raw) {
    const tokens = raw.match(/\/\/[^\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+/g)
        .filter(t => !t.startsWith('//')); let i = 0;
    const value = token => token.startsWith('"') ? token.slice(1, -1) : token;
    function block() {
        const result = {};
        while (i < tokens.length) {
            const key = tokens[i++]; if (key === '}') return result;
            const next = tokens[i++];
            result[value(key)] = next === '{' ? block() : value(next);
        }
        return result;
    }
    return block();
}
function itemDefinition(schema, id) {
    const marker = new RegExp('(?:^|\\r?\\n)\\t\\t"' + id + '"\\s*\\{');
    const match = schema.match(marker); assert(match, 'Official ItemDef missing: ' + id);
    const open = schema.indexOf('{', match.index);
    const raw = schema.slice(match.index, endOf(schema, open));
    return { raw, item: parseItem(raw)[String(id)] };
}
function classBlocks(text) {
    return [...text.matchAll(/_class = "([^"]+)"/g)].map(m => {
        const open = text.lastIndexOf('{', m.index);
        return { class: m[1], text: text.slice(open, endOf(text, open)) };
    });
}
function inputRange(text, property) {
    const match = text.match(new RegExp(property + '\\s*=\\s*\\{'));
    if (!match) return null;
    const open = text.indexOf('{', match.index), body = text.slice(open, endOf(text, open));
    const kind = body.match(/m_nType = "([^"]+)"/)?.[1];
    if (kind === 'PF_TYPE_LITERAL') {
        const value = Number(body.match(/m_flLiteralValue = ([\d.e+-]+)/)?.[1]);
        return Number.isFinite(value) ? [value, value] : null;
    }
    if (/^PF_TYPE_RANDOM_(UNIFORM|BIASED)$/.test(kind || '')) {
        const min = Number(body.match(/m_flRandomMin = ([\d.e+-]+)/)?.[1] || 0);
        const max = Number(body.match(/m_flRandomMax = ([\d.e+-]+)/)?.[1]);
        return Number.isFinite(min) && Number.isFinite(max) ? [min, max] : null;
    }
    return null;
}
function references(bytes) {
    const refs = [], header = 8 + bytes.readUInt32LE(8);
    for (let i = 0; i < bytes.readUInt32LE(12); i++) {
        const block = header + i * 12, start = block + 4 + bytes.readUInt32LE(block + 4);
        if (bytes.toString('ascii', block, block + 4) !== 'RERL') continue;
        const entries = start + bytes.readUInt32LE(start);
        for (let j = 0; j < bytes.readUInt32LE(start + 4); j++) {
            const pointer = entries + j * 16 + 8, target = pointer + Number(bytes.readBigInt64LE(pointer));
            refs.push(bytes.toString('utf8', target, bytes.indexOf(0, target)));
        }
    }
    return refs;
}
function check(name, action) { action(); report.checks.push(name); }
try {
    fs.mkdirSync(dumps, { recursive: true });
    const packs = {
        dota: new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk')),
        core: new Vpk(path.resolve(root, '../../core/pak01_dir.vpk')),
    };
    const schemaBytes = packs.dota.read('scripts/items/items_game.txt');
    const schema = schemaBytes.toString('utf8');
    const { raw: itemRaw, item } = itemDefinition(schema, 5412);
    const modifiers = Object.values(item.visuals).filter(x => x && typeof x === 'object' && x.type);
    const replacement = asset => modifiers.find(m => m.type === 'particle' && m.asset === asset)?.modifier;
    const hero = csvRows(lightningCsv).find(r => r.effect_key === 'hero_strike');
    const tower = csvRows(lightningCsv).find(r => r.effect_key === 'strike');
    check('hero_strike matches ItemDef5412 W and cast replacements', () => {
        assert(enabled(hero), 'hero_strike must be enabled');
        assert.equal(item.name, 'Righteous Thunderbolt');
        assert.equal(hero.particle_name, replacement(nativeBolt));
        assert.equal(hero.cast_particle, replacement(nativeCast));
        assert(hero.particle_name && hero.cast_particle, 'Official W/cast replacement missing');
        assert.equal(hero.impact_particle, '', 'Ground cracks are already native children; no separate impact root');
        assert.equal(hero.visual_duration, '', 'Hero W must retain its finite native tail, without early CSV duration');
    });
    check('tower strike retains Disruptor immortal R without Zeus roots', () => {
        assert(enabled(tower)); assert.equal(tower.particle_name, expectedTowerStorm);
        assert.equal(tower.impact_particle, ''); assert.equal(tower.cast_particle, '');
        assert(packs.dota.entries.has(expectedTowerStorm + '_c'), 'Tower storm native resource missing');
    });
    const records = new Map(), dataByPath = new Map();
    function packResource(resource) {
        const key = resource + '_c', origin = Object.keys(packs).find(p => packs[p].entries.has(key));
        assert(origin, 'Missing native resource: ' + key);
        return { bytes: packs[origin].read(key), origin };
    }
    function dumpResource(resource, bytes) {
        const dest = path.join(dumps, resource + '_c'); fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.writeFileSync(dest, bytes);
        const text = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
            ['-i', dest, '-all'], { encoding: 'utf8', windowsHide: true });
        fs.writeFileSync(dest + '.txt', text);
        return { text, file: path.relative(root, dest + '.txt').replace(/\\/g, '/') };
    }
    function inspect(resource) {
        if (records.has(resource)) return;
        const { bytes, origin } = packResource(resource), dependencies = references(bytes);
        const record = { resource, origin, bytes: bytes.length, sha256: hash(bytes), dependencies };
        records.set(resource, record);
        if (resource.endsWith('.vpcf')) {
            const { text, file } = dumpResource(resource, bytes), at = text.indexOf('--- vpcf block DATA');
            assert(at >= 0, 'Particle DATA block missing: ' + resource);
            const data = text.slice(at), blocks = classBlocks(data); dataByPath.set(resource, data);
            record.dump = file;
            record.children = [...new Set([...data.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m => m[1]))];
            record.continuous_emitters = blocks.filter(b => b.class === 'C_OP_ContinuousEmitter').map(b => {
                const duration = inputRange(b.text, 'm_flEmissionDuration');
                assert(duration && duration[0] >= 0 && duration[1] > 0,
                    'Unbounded/unknown continuous emission: ' + resource);
                return { duration_seconds: duration };
            });
            record.serialized_lifetimes = blocks.filter(b => b.class === 'C_INIT_InitFloat'
                && /m_nOutputField = 1\b/.test(b.text)).map(b => {
                const range = inputRange(b.text, 'm_InputValue');
                assert(range && range[0] > 0 && range[1] >= range[0], 'Nonfinite native lifetime: ' + resource);
                return range;
            });
            record.lifetime_uses_engine_default = record.serialized_lifetimes.length === 0
                && blocks.some(b => /^C_OP_(Instantaneous|Continuous)Emitter$/.test(b.class));
        }
        for (const dependency of dependencies) inspect(dependency);
    }
    inspect(hero.particle_name); inspect(hero.cast_particle);
    const crack = particlePrefix + 'zuus_lightning_bolt_groundfx_crack.vpcf';
    const fire = particlePrefix + 'zuus_lightning_bolt_groundfx_fire.vpcf';
    const light = particlePrefix + 'zuus_lightning_bolt_groundfx_crack_light.vpcf';
    function childClosure(resource, found = new Set()) {
        if (found.has(resource)) return found;
        found.add(resource); for (const child of records.get(resource).children || []) childClosure(child, found);
        return found;
    }
    check('complete W child closure includes native cracks, fire and crack light', () => {
        const children = childClosure(hero.particle_name);
        for (const resource of [crack, fire, light]) assert(children.has(resource), 'Incomplete ground layer: ' + resource);
        assert(records.get(crack).children.includes(fire)); assert(records.get(crack).children.includes(light));
        assert(records.get(crack).dependencies.includes('materials/particle/ground/crack_growth_01.vtex'));
    });
    check('native ground residue is finite and initializes on ground without position locks', () => {
        for (const resource of [crack, fire, light]) {
            const data = dataByPath.get(resource);
            assert(data.includes('C_INIT_PositionPlaceOnGround'));
            assert(!data.includes('C_OP_PositionLock') && !data.includes('C_OP_LockToBone'));
            assert(records.get(resource).serialized_lifetimes.length > 0, 'Ground lifetime must be explicit: ' + resource);
        }
        assert(dataByPath.get(crack).includes('C_OP_InstantaneousEmitter'));
    });
    check('all native particle emitters have finite serialized duration where continuous', () => {
        assert([...records.values()].some(r => r.continuous_emitters?.length), 'Expected finite ground/cast emitters missing');
    });
    const sourceFile = 'scripts/vscripts/systems/zeus_lightning_visual.lua';
    const visualSource = fs.readFileSync(path.join(root, sourceFile), 'utf8');
    check('hero presentation does not separately create literal crack/fire/light roots', () => {
        assert(!/zuus_lightning_bolt_groundfx_(crack|fire)/.test(visualSource));
    });
    const sound = csvRows(soundCsv).find(r => r.cue_id === 'hero_fury_thunder_strike');
    const nativeSound = modifiers.find(m => m.type === 'sound' && m.asset === 'Hero_Zuus.LightningBolt')?.modifier;
    check('hero sound CSV matches ItemDef5412 Righteous bolt replacement', () => {
        assert(enabled(sound)); assert.equal(sound.sound_event, expectedSound);
        assert.equal(sound.sound_event, nativeSound); assert.equal(sound.sound_resource, expectedSoundResource);
    });
    const soundAsset = packResource(sound.sound_resource), soundDump = dumpResource(sound.sound_resource, soundAsset.bytes);
    const soundData = soundDump.text.slice(soundDump.text.indexOf('--- vsndevts block DATA'));
    check('Righteous event is declared in fresh game_sounds_zuus native DATA', () => {
        assert(/^\s*Hero_Zuus\.LightningBolt\.Righteous\s*=/m.test(soundData), 'Righteous sound event missing in native resource');
    });
    const actualCounts = { particle_systems: dataByPath.size, resources: records.size };
    if (actualCounts.particle_systems !== baseline.particle_systems || actualCounts.resources !== baseline.resources) {
        report.warnings.push('Installed native graph changed from baseline 28 particles / 41 resources to '
            + actualCounts.particle_systems + ' / ' + actualCounts.resources
            + '; every fresh dependency and finite ground/emitter check was evaluated, without forcing old counts.');
    }
    report.status = 'PASS';
    report.inputs = [lightningCsv, soundCsv, sourceFile].map(file => ({ file, sha256: hash(fs.readFileSync(path.join(root, file))) }));
    report.schema_sha256 = hash(schemaBytes); report.item_record_sha256 = hash(Buffer.from(itemRaw));
    report.official_w_mapping = { particle_name: replacement(nativeBolt), cast_particle: replacement(nativeCast), sound: nativeSound };
    report.hero_strike = hero; report.tower_strike = tower;
    report.counts = actualCounts; report.baseline_counts = baseline;
    report.bolt_particle_systems = childClosure(hero.particle_name).size;
    report.cast_particle_systems = childClosure(hero.cast_particle).size;
    report.ground = [crack, fire, light].map(resource => ({ resource, lifetime_seconds: records.get(resource).serialized_lifetimes,
        continuous_emitters: records.get(resource).continuous_emitters, children: records.get(resource).children }));
    report.sound = { cue_id: sound.cue_id, sound_event: sound.sound_event, sound_resource: sound.sound_resource,
        native_sha256: hash(soundAsset.bytes), dump: soundDump.file };
    report.resources = [...records.values()];
    report.notes = ['Serialized native lifetimes and finite emitters are validated; whole-system duration is not measured in game.',
        'Particle lifetime fields omitted by native serialization are recorded as engine defaults, not invented explicit values.',
        'This tool does not consume or overwrite the older 20261001 lightning reference manifest.'];
} catch (error) { report.error = error.stack || String(error); process.exitCode = 1; }
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n');
if (report.status === 'PASS') {
    console.log('HERO_ZEUS_BOLT_RESOURCES_PASS item=5412 particles=' + report.counts.particle_systems
        + ' dependencies=' + report.counts.resources + ' native_sound=verified tower_disruptor=unchanged');
    for (const warning of report.warnings) console.log('NATIVE_GRAPH_CHANGE: ' + warning);
} else console.error(report.error);
