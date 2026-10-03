'use strict';
// Read-only audit of installed Valve weapon cosmetics requested for hero equipment.
// Writes evidence under output/weapon_hero_cosmetics_20261002; does not compile or start a map.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const assert = require('assert');
const { Vpk, endOf } = require('./map_c6/lib.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output/weapon_hero_cosmetics_20261002');
const packs = { dota: new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk')),
    core: new Vpk(path.resolve(root, '../../core/pak01_dir.vpk')) };
const schemaBytes = packs.dota.read('scripts/items/items_game.txt');
const localizationBytes = packs.dota.read('resource/localization/items_schinese.txt');
const schema = schemaBytes.toString('utf8');
const localization = Object.fromEntries([...localizationBytes.toString('utf8')
    .matchAll(/"([^"\r\n]+)"\s+"([^"\r\n]*)"/g)].map(m => [m[1], m[2]]));
const requested = [
    ['npc_dota_hero_monkey_king', 'none|growth_sword', 609, '齐天大圣武器'],
    ['npc_dota_hero_monkey_king', 'frost_blade', 13546, '伏魔行者战棍'],
    ['npc_dota_hero_monkey_king', 'ice_blade', 9212, '鲧禹之钺'],
    ['npc_dota_hero_monkey_king', 'epic_icefire', 9453, '纯金鲧禹之钺'],
    ['npc_dota_hero_monkey_king', 'legend_abyss', 29347, '鲧禹之钺十周年'],
    ['npc_dota_hero_juggernaut', 'none|growth_sword', 7, '主宰武器'],
    ['npc_dota_hero_juggernaut', 'frost_blade', 23327, '霜望好战者武器'],
    ['npc_dota_hero_juggernaut', 'ice_blade', 13185, '暴风领主的血统'],
    ['npc_dota_hero_juggernaut', 'epic_icefire', 9984, '奇门之风'],
    ['npc_dota_hero_juggernaut', 'legend_abyss', 12417, '猩红奇门之风'],
];
const report = { status: 'FAIL', checked_at: new Date().toISOString(),
    source: 'Fresh installed official Valve dota/core VPK schema, Chinese localization and compiled resources',
    map_started: false, compiled_new_resources: false, live_visual_verified: false,
    checks: [], warnings: [], items: [], resources: [] };
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const records = new Map();
function check(label, action) { action(); report.checks.push(label); }
function blockFor(key, text = schema) {
    const match = text.match(new RegExp('(?:^|\\r?\\n)\\t\\t"' + key + '"\\s*\\{'));
    assert(match, 'Missing official schema block: ' + key);
    return text.slice(match.index, endOf(text, text.indexOf('{', match.index)));
}
function property(raw, key) {
    return raw.match(new RegExp('"' + key + '"\\s+"([^"\\r\\n]*)"'))?.[1];
}
function nested(raw, key) {
    const match = raw.match(new RegExp('"' + key + '"\\s*\\{'));
    if (!match) return '';
    return raw.slice(match.index, endOf(raw, raw.indexOf('{', match.index)));
}
function assetModifiers(raw) {
    return [...raw.matchAll(/"asset_modifier\d*"\s*\{/g)].map(match => {
        const block = raw.slice(match.index, endOf(raw, raw.indexOf('{', match.index)));
        return { type: property(block, 'type'), asset: property(block, 'asset') || null,
            modifier: property(block, 'modifier'), style: property(block, 'style') || null,
            ability_effects_slot: property(block, 'apply_when_equipped_in_ability_effects_slot') === '1',
            original_kv: block };
    });
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
function inspect(resource) {
    if (records.has(resource)) return records.get(resource);
    const compiled = resource + '_c', origin = Object.keys(packs).find(key => packs[key].entries.has(compiled));
    assert(origin, 'Missing compiled official resource: ' + compiled);
    const bytes = packs[origin].read(compiled);
    const record = { resource, compiled, origin, bytes: bytes.length, sha256: hash(bytes),
        dependencies: references(bytes) };
    records.set(resource, record);
    record.dependencies.forEach(inspect);
    return record;
}
function dump(resource) {
    const record = inspect(resource);
    const file = path.join(output, 'native_dump', record.compiled);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, packs[record.origin].read(record.compiled));
    const dumpBlocks = resource.endsWith('.vmdl') ? ['MDAT', 'DATA'] : ['all'];
    const text = dumpBlocks.map(block => cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
        ['-i', file, ...(block === 'all' ? ['-all'] : ['-b', block])],
        { encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024 })).join('\n');
    record.dump_blocks = dumpBlocks;
    fs.writeFileSync(file + '.txt', text);
    record.dump = path.relative(root, file + '.txt').replace(/\\/g, '/');
    if (resource.endsWith('.vpcf')) {
        record.embedded_snapshots = [...new Set([...text.matchAll(/m_hSnapshot = resource:"([^"]+)"/g)].map(match => match[1]))];
        record.serialized_snapshot_control_point = Number(text.match(/\bm_nSnapshotControlPoint = (\d+)/)?.[1] || 0);
        record.serialized_attach_type = text.match(/m_iAttachType = "([^"]+)"/)?.[1] || null;
        record.attachment_names = [...new Set([...text.matchAll(/m_attachmentName = "([^"]+)"/g)]
            .map(match => match[1]))];
        record.children = [...new Set([...text.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(match => match[1]))];
        record.control_point_configuration = [...text.matchAll(/m_controlPointConfigurations =\s*\[/g)]
            .map(match => text.slice(match.index, endOf(text, text.indexOf('[', match.index), '[', ']')));
        record.preview_control_point_drivers = [];
        const driversMatch = text.match(/m_drivers =\s*\[/);
        if (driversMatch) {
            const start = text.indexOf('[', driversMatch.index), drivers = text.slice(start, endOf(text, start, '[', ']'));
            for (let cursor = drivers.indexOf('{'); cursor >= 0;) {
                const stop = endOf(drivers, cursor), block = drivers.slice(cursor, stop);
                const value = key => block.match(new RegExp(key + ' = "([^"\r\n]*)"'))?.[1] || null;
                record.preview_control_point_drivers.push({ cp: Number(block.match(/m_iControlPoint = (\d+)/)?.[1] || 0),
                    attachment_type: value('m_iAttachType'), attachment_name: value('m_attachmentName'),
                    entity: value('m_entityName'),
                    offset: block.match(/m_vecOffset = \[ ([^\]]+) \]/)?.[1].split(',').map(Number) || null,
                    omitted_fields_use_native_defaults: true });
                cursor = drivers.indexOf('{', stop);
            }
        }
    } else if (resource.endsWith('.vmdl')) {
        record.model_attachment_names = [];
        for (const match of text.matchAll(/m_attachments =\s*\[/g)) {
            const start = text.indexOf('[', match.index), block = text.slice(start, endOf(text, start, '[', ']'));
            record.model_attachment_names.push(...[...block.matchAll(/m_name = "([^"]+)"/g)].map(m => m[1]));
        }
        record.model_attachment_names = [...new Set(record.model_attachment_names)];
        record.material_groups = [];
        for (const match of text.matchAll(/m_materialGroups =\s*\[/g)) {
            const start = text.indexOf('[', match.index), block = text.slice(start, endOf(text, start, '[', ']'));
            record.material_groups.push(...[...block.matchAll(/m_name = "([^"]+)"/g)].map(m => m[1]));
        }
        record.material_groups = [...new Set(record.material_groups)];
    }
    return text;
}
try {
    fs.mkdirSync(output, { recursive: true });
    report.schema = { resource: 'scripts/items/items_game.txt', sha256: hash(schemaBytes),
        localization: 'resource/localization/items_schinese.txt', localization_sha256: hash(localizationBytes),
        weapon_slot_prefabs: Object.fromEntries(['wearable', 'default_item'].map(key => [key, blockFor(key)])) };
    for (const [hero, series, id, userName] of requested) {
        const raw = blockFor(id), prefab = property(raw, 'prefab'), prefabRaw = blockFor(prefab);
        const usedBy = nested(raw, 'used_by_heroes'), visuals = nested(raw, 'visuals');
        const model = property(raw, 'model_player'), modifiers = assetModifiers(visuals);
        const item = { hero, series, item_def: id, user_name: userName,
            official_name: property(raw, 'name'), official_chinese_name: localization[property(raw, 'item_name').replace(/^#/, '')],
            name_token: property(raw, 'item_name'), prefab,
            item_slot: property(raw, 'item_slot') || property(prefabRaw, 'item_slot'),
            rarity: property(raw, 'item_rarity') || property(prefabRaw, 'item_rarity'),
            model, skin: Number(property(visuals, 'skin') || 0), modifiers,
            ambient_particles: modifiers.filter(m => m.type === 'particle_create').map(m => m.modifier),
            particle_replacements: modifiers.filter(m => m.type === 'particle'),
            snapshot_replacements: modifiers.filter(m => m.type === 'particle_snapshot'),
            activity_modifiers: modifiers.filter(m => m.type === 'activity'),
            projectile_modifiers: modifiers.filter(m => /projectile/.test(m.type)),
            missing_schema_snapshots: [],
            raw_schema_sha256: hash(raw), raw_schema_file: 'output/weapon_hero_cosmetics_20261002/items/' + id + '.txt' };
        fs.mkdirSync(path.join(output, 'items'), { recursive: true });
        fs.writeFileSync(path.join(output, 'items', id + '.txt'), raw);
        check(id + ': official record is the requested hero weapon only', () => {
            assert(usedBy.includes('"' + hero + '"')); assert.equal(item.item_slot, 'weapon'); assert(model);
        });
        inspect(model);
        for (const modifier of modifiers) {
            if (!/\.v(?:pcf|snap|mdl|mat|tex)$/.test(modifier.modifier || '')) continue;
            if (modifier.type === 'particle_snapshot'
                && !Object.values(packs).some(pack => pack.entries.has(modifier.modifier + '_c'))) {
                item.missing_schema_snapshots.push(modifier.modifier);
                report.warnings.push(id + ': Official schema snapshot replacement is absent from installed dota/core packs: ' + modifier.modifier);
            } else inspect(modifier.modifier);
        }
        report.items.push(item);
    }
    const roots = new Set(report.items.flatMap(item => [item.model, ...item.ambient_particles,
        ...item.snapshot_replacements.filter(m => !item.missing_schema_snapshots.includes(m.modifier)).map(m => m.modifier),
        ...item.particle_replacements.map(m => m.modifier)]));
    const parentModels = { npc_dota_hero_monkey_king: 'models/heroes/monkey_king/monkey_king.vmdl',
        npc_dota_hero_juggernaut: 'models/heroes/juggernaut/juggernaut_arcana.vmdl' };
    const catalogPath = 'data/csv/资源系统/asset_catalog.csv', catalogBytes = fs.readFileSync(path.join(root, catalogPath));
    const catalog = catalogBytes.toString('utf8');
    check('current authoritative hero body catalog matches audited parent model attachments', () => {
        assert(catalog.split(/\r?\n/).some(line => line.startsWith('hero_permanent_hero_monkey_king,')
            && line.split(',')[3] === parentModels.npc_dota_hero_monkey_king));
        assert(catalog.split(/\r?\n/).some(line => line.startsWith('hero_permanent_hero_blademaster,')
            && line.split(',')[3] === parentModels.npc_dota_hero_juggernaut));
    });
    report.current_hero_body_catalog = { path: catalogPath, sha256: hash(catalogBytes), models: parentModels };
    Object.values(parentModels).forEach(model => roots.add(model));
    const stormAmbient = 'particles/econ/items/juggernaut/jugg_ti10_cache/jugg_ti10_cache_weapon.vpcf';
    const stormParticles = [], stormVisited = new Set();
    function collectStormParticles(resource) {
        if (stormVisited.has(resource)) return;
        stormVisited.add(resource); stormParticles.push(resource); roots.add(resource);
        records.get(resource).dependencies.filter(dependency => dependency.endsWith('.vpcf')).forEach(collectStormParticles);
    }
    collectStormParticles(stormAmbient);
    for (const resource of roots) dump(resource);
    const stormSnapshotParticles = stormParticles.filter(resource => records.get(resource).embedded_snapshots.length > 0);
    check('storm weapon trace children internally bind native authored snapshots to CP6', () => {
        assert.equal(stormSnapshotParticles.length, 6);
        assert(stormSnapshotParticles.every(resource => records.get(resource).serialized_snapshot_control_point === 6));
        assert.equal(new Set(stormSnapshotParticles.flatMap(resource => records.get(resource).embedded_snapshots)).size, 3);
        assert(stormSnapshotParticles.every(resource => !records.get(resource).embedded_snapshots
            .some(snapshot => snapshot.endsWith('susano_os_descendant_weapon_fx.vsnap'))));
    });
    report.storm_snapshot_contract = { ambient: stormAmbient,
        embedded_snapshots: [...new Set(stormSnapshotParticles.flatMap(resource => records.get(resource).embedded_snapshots))],
        trace_particles: stormSnapshotParticles, native_snapshot_cp: 6,
        external_snapshot_override_required: false, extra_snapshot_precache_type_required: false,
        schema_fx_snapshot_is_an_ambient_dependency: false,
        scope: 'Native m_hSnapshot and m_nSnapshotControlPoint authoring are serialized in the child particle resources; no claim of a live engine call.' };
    const mapping = report.items.map(item => {
        const model = records.get(item.model), unsupported = item.missing_schema_snapshots.length > 0;
        return { hero: item.hero, series_id: item.series, item_def: item.item_def,
            display_name: item.official_chinese_name, model: item.model, skin: item.skin,
            material_group: model.material_groups[item.skin] || '', native_model_material_groups: model.material_groups,
            native_model_attachment_names: model.model_attachment_names,
            native_parent_model: parentModels[item.hero],
            native_parent_attachment_names: records.get(parentModels[item.hero]).model_attachment_names,
            ambient: unsupported ? [] : item.ambient_particles.map(particle => ({ particle,
                control_point_drivers: records.get(particle).preview_control_point_drivers,
                native_authoring_configuration_only: true })),
            native_activity: item.activity_modifiers.map(m => ({ asset: m.asset, modifier: m.modifier })),
            snapshot: unsupported ? '' : item.snapshot_replacements[0]?.modifier || '',
            snapshot_is_schema_replacement_only: true,
            notes: unsupported ? 'Native weapon-specific snapshot is missing from installed official packs. Keep exact requested weapon model and existing frost hand glow; do not use generic ambient with the default sword snapshot.'
                : 'Use exact native model/skin and weapon ambient; activity/skill/projectile replacement is separate from the requested weapon appearance.' };
    });
    fs.writeFileSync(path.join(output, 'weapon_mapping.json'), JSON.stringify(mapping, null, 2) + '\n');
    check('ten requested weapon models, ambient particles and all their mounted compiled dependencies resolve', () => {
        assert.equal(report.items.length, 10); assert([...records.values()].every(record => record.origin === 'dota' || record.origin === 'core'));
    });
    check('gold and anniversary monkey weapons and crimson juggernaut use their official distinct skins', () => {
        assert.equal(report.items.find(item => item.item_def === 9453).skin, 2);
        assert.equal(report.items.find(item => item.item_def === 29347).skin, 3);
        assert.equal(report.items.find(item => item.item_def === 12417).skin, 2);
    });
    const serverBinaryPath = path.resolve(root, '../../dota/bin/win64/server.dll');
    const binary = fs.readFileSync(serverBinaryPath);
    report.script_api_binary_name_probe = { path: '../../dota/bin/win64/server.dll', bytes: binary.length,
        sha256: hash(binary), scope: 'Literal name availability in installed binary, not a live script API invocation or definitive ABI proof.',
        names: Object.fromEntries(['SetParticleControlOffset', 'SetParticleControlEntWithOffset',
            'SetParticleControlTransform', 'SetParticleControlTransformOrientation', 'SetParticleControlEnt',
            'SetParticleControlSnapshot', 'SetControlPointSnapshot', 'SetParent', 'SetLocalOrigin']
            .map(name => [name, binary.includes(Buffer.from(name))])) };
    report.script_api_binary_name_probe.notes = [
        'SetParent / SetLocalOrigin appear together with ScriptSetParent / ScriptSetLocalOrigin and entity API help text.',
        'SetParticleControlSnapshot is absent. SetControlPointSnapshot appears in CUserMsg_ParticleManager protobuf protocol strings; that presence is not evidence of a Lua method.',
        'No unsupported PrecacheResource type is inferred from these names. Native particles already carry their snapshots through their compiled RERL graph.',
    ];
    report.warnings.push('User calls Edge of the Lost Order 奇门之风; official localization is 奇门之锋, and 猩红奇门之锋 for Crimson. ItemDefs are unambiguous.');
    report.warnings.push('Schema item-slot defaults to weapon through wearable/default_item prefabs. Missing explicit item_slot is not a missing weapon tag.');
    report.warnings.push('resourceinfo control-point configurations describe native authoring/model preview defaults; this audit does not assert engine wearable APIs reproduce them in a live match.');
    report.resources = [...records.values()];
    report.counts = { item_definitions: report.items.length, distinct_models: new Set(report.items.map(i => i.model)).size,
        particle_systems: report.resources.filter(r => r.resource.endsWith('.vpcf')).length,
        compiled_dependencies: records.size, root_dumps: roots.size };
    report.status = 'PASS';
} catch (error) { report.error = error.stack || String(error); process.exitCode = 1; }
fs.writeFileSync(path.join(output, 'native_resources.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ status: report.status, counts: report.counts, error: report.error || null,
    evidence: 'output/weapon_hero_cosmetics_20261002/native_resources.json' }, null, 2));
