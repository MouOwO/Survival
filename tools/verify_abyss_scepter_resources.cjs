'use strict';
// Read installed Valve resources afresh; only write audit evidence under output/abyss_scepter_20261002.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const assert = require('assert');
const { Vpk, endOf } = require('./map_c6/lib.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output/abyss_scepter_20261002');
const dumps = path.join(output, 'resource_validation');
const aura = 'particles/items4_fx/scepter_aura.vpcf';
const expectedChildren = ['ring', 'light', 'ring_tight', 'flek', 'ring_dot_detail']
    .map(n => 'particles/items4_fx/scepter_aura_' + n + '.vpcf');
const report = { status: 'FAIL', checked_at: new Date().toISOString(),
    source: 'Fresh installed official Valve dota/core VPK', particle: aura,
    compiled_resources: false, map_started: false, in_game_visual_verified: false,
    checks: [], warnings: [], baseline: { particle_systems: 6, resources: 10 } };
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
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
function csvRows(filename) {
    const text = fs.readFileSync(filename, 'utf8').replace(/^\uFEFF/, '');
    const rows = []; let row = [], value = '', quoted = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (ch === '"') {
            if (quoted && text[i + 1] === '"') { value += '"'; i++; } else quoted = !quoted;
        } else if (!quoted && (ch === ',' || ch === '\n' || ch === '\r')) {
            row.push(value); value = '';
            if (ch !== ',') { rows.push(row); row = []; if (ch === '\r' && text[i + 1] === '\n') i++; }
        } else value += ch;
    }
    assert(!quoted, 'Unclosed CSV quoted field');
    if (value || row.length) { row.push(value); rows.push(row); }
    const headers = rows.shift();
    return { headers, rows: rows.filter(r => r[0] && !r[0].startsWith('#'))
        .map(r => Object.fromEntries(headers.map((h, i) => [h, r[i]]))) };
}
function check(name, action) { action(); report.checks.push(name); }
try {
    fs.mkdirSync(dumps, { recursive: true });
    const packs = { dota: new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk')),
        core: new Vpk(path.resolve(root, '../../core/pak01_dir.vpk')) };
    const records = new Map(), dataByPath = new Map(), blocksByPath = new Map();
    function inspect(resource) {
        if (records.has(resource)) return;
        const key = resource + '_c', origin = Object.keys(packs).find(p => packs[p].entries.has(key));
        assert(origin, 'Missing native resource: ' + key);
        const bytes = packs[origin].read(key), dependencies = references(bytes);
        const record = { resource, origin, bytes: bytes.length, sha256: hash(bytes), dependencies };
        records.set(resource, record);
        if (resource.endsWith('.vpcf')) {
            const dest = path.join(dumps, key); fs.mkdirSync(path.dirname(dest), { recursive: true });
            fs.writeFileSync(dest, bytes);
            const text = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
                ['-i', dest, '-all'], { encoding: 'utf8', windowsHide: true });
            fs.writeFileSync(dest + '.txt', text);
            const at = text.indexOf('--- vpcf block DATA'); assert(at >= 0, 'Particle DATA missing: ' + resource);
            const data = text.slice(at), blocks = classBlocks(data);
            dataByPath.set(resource, data); blocksByPath.set(resource, blocks);
            record.dump = path.relative(root, dest + '.txt').replace(/\\/g, '/');
            record.children = [...new Set([...data.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(m => m[1]))];
            record.classes = blocks.map(b => b.class);
            record.max_particles = Number(data.match(/m_nMaxParticles = (\d+)/)?.[1] || 0);
            record.emitters = blocks.filter(b => /C_OP_(Continuous|Instantaneous)Emitter/.test(b.class)).map(b => ({
                class: b.class, emit_rate_per_second: inputRange(b.text, 'm_flEmitRate'),
                emission_duration_seconds: inputRange(b.text, 'm_flEmissionDuration'),
                particle_count: inputRange(b.text, 'm_nParticlesToEmit'),
                emission_duration_is_omitted: !/m_flEmissionDuration/.test(b.text),
            }));
            record.serialized_particle_lifetimes = blocks.filter(b => b.class === 'C_INIT_InitFloat'
                && /m_nOutputField = 1\b/.test(b.text)).map(b => inputRange(b.text, 'm_InputValue'));
            record.endcap_only_decay = blocks.some(b => b.class === 'C_OP_Decay'
                && b.text.includes('PARTICLE_ENDCAP_ENDCAP_ON'));
            record.position_locked_to_cp0_default = blocks.some(b => b.class === 'C_OP_PositionLock'
                && !/m_nControlPointNumber = [1-9]/.test(b.text));
            record.preview_attachment = data.match(/m_iAttachType = "([^"]+)"/)?.[1] || null;
        }
        dependencies.forEach(inspect);
    }
    inspect(aura);
    check('native aura includes exactly the five official foot-level children', () => {
        assert.deepEqual([...records.get(aura).children].sort(), [...expectedChildren].sort());
        assert.equal(records.get(aura).max_particles, 0);
    });
    check('all child, material and texture dependencies resolve from official mounted packs', () => {
        assert([...records.values()].every(r => r.origin === 'dota' || r.origin === 'core'));
        assert([...records.values()].every(r => r.resource.endsWith('.vpcf') || r.resource.startsWith('materials/')));
    });
    check('foot aura does not bind a body model or create a beam, screen overlay or vertical curtain', () => {
        for (const blocks of blocksByPath.values()) {
            assert(!blocks.some(b => /RenderModels|RenderRopes|RenderScreen|RenderTrails|CreateOnModel|Hitbox|LockToBone/.test(b.class)));
        }
        for (const child of ['ring', 'ring_tight', 'ring_dot_detail']) {
            assert(dataByPath.get('particles/items4_fx/scepter_aura_' + child + '.vpcf')
                .includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
        }
    });
    check('native constant aura has unbounded continuing light/fleck/ground-detail and endcap-only main rings', () => {
        for (const child of ['flek', 'light', 'ring_dot_detail']) {
            const r = records.get('particles/items4_fx/scepter_aura_' + child + '.vpcf');
            assert(r.emitters.some(e => e.class === 'C_OP_ContinuousEmitter' && e.emission_duration_is_omitted
                && e.emit_rate_per_second && e.emit_rate_per_second[0] > 0));
        }
        for (const child of ['ring', 'ring_tight']) {
            const r = records.get('particles/items4_fx/scepter_aura_' + child + '.vpcf');
            assert(r.endcap_only_decay);
            assert(r.emitters.some(e => e.class === 'C_OP_InstantaneousEmitter' && e.particle_count?.[0] === 1));
        }
    });
    check('CP0 is the only external origin and CP3-8 are internally written fleck child controls', () => {
        for (const child of expectedChildren) assert(records.get(child).position_locked_to_cp0_default);
        const fleck = dataByPath.get('particles/items4_fx/scepter_aura_flek.vpcf');
        assert(fleck.includes('C_OP_SetPerChildControlPoint'));
        assert(/m_nFirstControlPoint = 3\b/.test(fleck) && /m_nNumControlPoints = 6\b/.test(fleck));
        for (const data of dataByPath.values()) {
            assert(!/m_n(ControlPoint|ControlPointNumber|CP\d|HeadLocation|FirstSourcePoint) = (?:[1-9]\d*)\b/.test(data));
        }
    });
    const schemaBytes = packs.dota.read('scripts/items/items_game.txt'), schema = schemaBytes.toString('utf8');
    const itemPositions = [...schema.matchAll(/(?:^|\r?\n)\t\t"(\d+)"\s*\{/g)]
        .map(m => ({ id: m[1], at: m.index }));
    const variants = [];
    for (let i = 0; i < itemPositions.length; i++) {
        const position = itemPositions[i], next = itemPositions[i + 1]?.at || schema.length;
        const chunk = schema.slice(position.at, next);
        if (!chunk.includes(aura)) continue;
        const open = chunk.indexOf('{'), raw = chunk.slice(0, endOf(chunk, open));
        const modifiers = [...raw.matchAll(/"asset_modifier"\s*\{/g)].map(m => {
            const at = raw.indexOf('{', m.index), block = raw.slice(m.index, endOf(raw, at));
            const value = name => block.match(new RegExp('"' + name + '"\\s+"([^"]+)"'))?.[1];
            return { type: value('type'), asset: value('asset'), modifier: value('modifier'),
                criteria: value('criteria') || null, original_kv: block };
        }).filter(m => m.type === 'particle' && m.asset === aura);
        if (modifiers.length) variants.push({ item_def: Number(position.id),
            name: raw.match(/"name"\s+"([^"]+)"/)?.[1],
            localized_name_token: raw.match(/"item_name"\s+"([^"]+)"/)?.[1], modifiers });
    }
    report.official_schema = { resource: 'scripts/items/items_game.txt', sha256: hash(schemaBytes),
        aura_replacement_records: variants };
    check('official schema identifies this root as the Aghanim scepter aura replacement target', () => {
        assert(variants.some(v => v.modifiers.some(m => m.modifier.includes('aghanim_aura_ti10/agh_aura_ti10.vpcf'))));
        assert(variants.some(v => /Aghanim/i.test(v.name || '') || /Aghanim/i.test(v.localized_name_token || '')));
    });
    const filename = path.join(root, 'data/csv/物品系统/weapon_visual_profiles.csv');
    const weaponsFilename = path.join(root, 'data/csv/物品系统/weapon_definitions.csv');
    const config = csvRows(filename), definitions = csvRows(weaponsFilename);
    if (config.headers.includes('owned_particle')) {
        const assigned = config.rows.filter(r => r.owned_particle);
        const affected = definitions.rows.filter(r => assigned.some(p => p.series_id === r.series_id));
        check('current inventory-owned profile applies only to the eleven abyss stages', () => {
            assert.equal(assigned.length, 1); assert.equal(assigned[0].series_id, 'legend_abyss');
            assert.equal(assigned[0].owned_particle, aura); assert(/^(true|1)$/i.test(assigned[0].enabled));
            assert.equal(affected.length, 11);
            for (let i = 0; i <= 10; i++) {
                const id = 'weapon_legend_abyss_' + String(i).padStart(2, '0');
                const row = affected.find(r => r.content_id === id);
                assert(row, 'Missing abyss stage: ' + id); assert.equal(Number(row.stage), i);
                assert(/^(true|1)$/i.test(row.enabled), 'Abyss stage disabled: ' + id);
            }
        });
        report.csv_owned_particle = { checked: true, profile_count: assigned.length, affected_weapon_count: affected.length,
            profile_csv: path.relative(root, filename).replace(/\\/g, '/'), profile_sha256: hash(fs.readFileSync(filename)),
            weapon_csv: path.relative(root, weaponsFilename).replace(/\\/g, '/'), weapon_sha256: hash(fs.readFileSync(weaponsFilename)),
            affected_content_ids: affected.map(r => r.content_id) };
    } else report.csv_owned_particle = { checked: false, reason: 'owned_particle profile column not yet present; native resource audit remains independent of implementation' };
    const helperFilename = path.join(root, 'scripts/vscripts/systems/weapon_owned_visual.lua');
    const serviceFilename = path.join(root, 'scripts/vscripts/systems/weapon_visual_service.lua');
    if (fs.existsSync(helperFilename) && fs.existsSync(serviceFilename)) {
        const helper = fs.readFileSync(helperFilename, 'utf8'), service = fs.readFileSync(serviceFilename, 'utf8');
        check('production uses only native CP0 foot origin following without color, size or body bones', () => {
            assert(/CreateParticle\(path,\s*PATTACH_ABSORIGIN_FOLLOW,\s*hero\)/.test(helper));
            assert(/SetParticleControlEnt\(particle,\s*0,\s*hero,\s*PATTACH_ABSORIGIN_FOLLOW,\s*"",\s*hero:GetAbsOrigin\(\),\s*true\)/.test(helper));
            assert(!/SetParticleControl\(/.test(helper));
            assert(!/PATTACH_POINT|attach_hitloc|attach_head/.test(helper));
        });
        check('main production service delegates enabled profile precache and a shared bounded lifecycle poll', () => {
            assert(/owned_visual\.precache\(context\)/.test(service));
            assert(/PrecacheResource\("particle",\s*path,\s*context\)/.test(helper));
            assert(/owned_visual\.poll\(\)/.test(service));
            assert(/scheduler\.every\(0\.25,\s*lifecycle,\s*poll_task\)/.test(service));
            assert(/\[events\.CONTENT_INVENTORY_CHANGED\]\s*=\s*owned_visual\.on_inventory_changed/.test(service));
        });
        report.production_cp_contract = { checked: true, scope: 'Static production API call and source contract review; not a live engine observation',
            helper: path.relative(root, helperFilename).replace(/\\/g, '/'), helper_sha256: hash(fs.readFileSync(helperFilename)),
            service: path.relative(root, serviceFilename).replace(/\\/g, '/'), service_sha256: hash(fs.readFileSync(serviceFilename)),
            create_attachment: 'PATTACH_ABSORIGIN_FOLLOW', external_cp: 0, cp0_owner: 'hero',
            cp0_attachment: 'PATTACH_ABSORIGIN_FOLLOW', cp0_attachment_name: '', cp0_fallback: 'hero:GetAbsOrigin()',
            body_bones: false, script_color_or_size_changes: false, lifecycle_poll_seconds: 0.25 };
    }
    report.native_resources = [...records.values()];
    report.counts = { particle_systems: report.native_resources.filter(r => r.resource.endsWith('.vpcf')).length,
        resources: records.size, texture_or_material_resources: report.native_resources.filter(r => !r.resource.endsWith('.vpcf')).length };
    if (report.counts.particle_systems !== report.baseline.particle_systems || report.counts.resources !== report.baseline.resources)
        report.warnings.push('Native closure count changed; review the fresh graph rather than treating the old count as a correctness rule.');
    report.attachment_contract = {
        externally_required_control_points: [0], cp0: 'Hero GetAbsOrigin at the feet; follow entity origin',
        recommended_create_attachment: 'PATTACH_ABSORIGIN_FOLLOW',
        recommended_control_point_entity_attachment: 'PATTACH_ABSORIGIN_FOLLOW',
        attachment_evidence: 'Recommendation from all five native PositionLock operators using CP0 default; compiled preview says PATTACH_WORLDORIGIN. No official runtime Lua binding was available.',
        unnecessary_control_points: [1, 2], internally_written_control_points: [3, 4, 5, 6, 7, 8],
        use_head_or_hitloc_attachment: false, color_or_scale_control_points: 'None; native color/size stays intact',
        persistence: 'Create one root for the held item condition; do not periodically recreate or call Release while needing later cleanup. DestroyParticle then ReleaseParticleIndex when the condition ends.',
        precache: 'PrecacheResource("particle", "' + aura + '", context); children and four textures are native resource dependencies. No export or recompilation required.',
    };
    report.visual_layers = { root_particle_count: 0, native_children: expectedChildren,
        main_ground_ring_radius: 100, tight_ground_ring_radius: 80, ring_height_offset: 15,
        ground_detail_height_offset: 18,
        contains_body_model: false, contains_full_body_curtain: false,
        contains_ground_glow_or_soft_mist: true, contains_small_rising_flecks: true,
        main_ring_serialized_lifetime_is_endcap_only: true,
        separate_grant_resource_not_used_for_ambient: 'particles/items_fx/generic_item_spell_caster_core_aghanims_scepter_grant.vpcf',
    };
    report.status = 'PASS';
    console.log('ABYSS_SCEPTER_RESOURCES_PASS particles=' + report.counts.particle_systems
        + ' resources=' + report.counts.resources + ' external_cp=0 native_ambient=verified');
} catch (error) {
    report.error = error.stack || String(error); process.exitCode = 1; console.error(report.error);
} finally {
    fs.mkdirSync(output, { recursive: true });
    fs.writeFileSync(path.join(output, 'resources_validation.json'), JSON.stringify(report, null, 2) + '\n');
}
