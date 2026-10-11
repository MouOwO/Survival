// Build isolated native Doom portrait cameras without changing the bottom HUD.
// Source entities follow build_juggernaut_portrait_map.ps1. No compiler/game I/O.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = path.resolve(__dirname, '..');
const DOOM_MODEL = 'models/heroes/doom/doom.vmdl';
// Confirmed default_item/model_player entries in Valve scripts/items/items_game.txt.
const WEARABLES = [
    ['head', 'doom_helm'], ['shoulder', 'shoulders'], ['back', 'wings'],
    ['arms', 'bracer'], ['belt', 'belt'], ['tail', 'tail'], ['weapon', 'doom_sword'],
].map(([slot, file]) => ({ slot, model: `models/heroes/doom/${file}.vmdl` }));

function balanced(text, start, left, right) {
    if (text[start] !== left) throw new Error(`Expected ${left} at ${start}`);
    let depth = 0, quoted = false, escaped = false;
    for (let i = start; i < text.length; i++) {
        const c = text[i];
        if (quoted) {
            if (escaped) escaped = false;
            else if (c === '\\') escaped = true;
            else if (c === '"') quoted = false;
        } else if (c === '"') quoted = true;
        else if (c === left) depth++;
        else if (c === right && --depth === 0) return i;
    }
    throw new Error(`Unbalanced ${left}${right}`);
}

function escapeRegex(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function property(block, key) {
    const match = block.match(new RegExp(`"${escapeRegex(key)}"\\s+"(?:string|vector3|qangle|int|bool)"\\s+"([^\"]*)"`));
    if (!match) throw new Error(`Missing entity property ${key}`);
    return match[1];
}
function setProperty(block, key, value) {
    const regex = new RegExp(`("${escapeRegex(key)}"\\s+"(?:string|vector3|qangle|int|bool)"\\s+")[^\"]*(")`);
    if (!regex.test(block)) throw new Error(`Missing entity property ${key}`);
    return block.replace(regex, (_, prefix, suffix) => prefix + String(value) + suffix);
}

function worldEntities(text) {
    const worldStart = text.indexOf('"world" "CMapWorld"');
    if (worldStart < 0) throw new Error('Missing world');
    const anchor = text.indexOf('"children" "element_array"', worldStart);
    const opening = text.indexOf('[', anchor);
    const closing = balanced(text, opening, '[', ']');
    let cursor = opening + 1;
    const entities = [];
    while (cursor < closing) {
        const start = text.indexOf('"CMapEntity"', cursor);
        if (start < 0 || start >= closing) break;
        const end = balanced(text, text.indexOf('{', start), '{', '}');
        entities.push(text.slice(start, end + 1));
        cursor = end + 1;
    }
    return { opening, closing, entities };
}

function namedKvBlock(text, name, start = 0) {
    const index = text.indexOf(`"${name}"`, start);
    if (index < 0) throw new Error(`Missing KV block ${name}`);
    const opening = text.indexOf('{', index);
    return text.slice(opening, balanced(text, opening, '{', '}') + 1);
}

function doomCamera(portraits) {
    const model = namedKvBlock(portraits, DOOM_MODEL);
    const cameras = namedKvBlock(model, 'cameras');
    const defaultEntry = /"default"\s*\{/i.exec(cameras);
    if (!defaultEntry) throw new Error('Missing Doom default camera');
    const opening = cameras.indexOf('{', defaultEntry.index);
    const block = cameras.slice(opening, balanced(cameras, opening, '{', '}') + 1);
    const values = Object.fromEntries([...block.matchAll(/"([^\"]+)"\s*"([^\"]*)"/g)].map(m => [m[1], m[2]]));
    for (const key of ['PortraitPosition', 'PortraitAngles', 'PortraitFOV']) {
        if (!values[key]) throw new Error(`Missing Doom ${key}`);
    }
    return values;
}

function stableIds(block, seed, nodeId) {
    block = block.replace(/"id" "elementid" "([^\"]+)"/g, (_, original) => {
        const hex = crypto.createHash('sha256').update(seed + ':' + original).digest('hex').slice(0, 32);
        return `"id" "elementid" "${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-8${hex.slice(17, 20)}-${hex.slice(20)}"`;
    });
    return setProperty(block, 'nodeID', nodeId);
}

function makeMap(template, camera, variant, margin) {
    const world = worldEntities(template);
    const find = (classname, name) => world.entities.find(block =>
        property(block, 'classname') === classname && (!name || property(block, 'targetname') === name));
    const bodySource = find('prop_dynamic', 'grass_cyclone');
    const lightSource = find('env_global_light');
    const cameraSource = find('point_camera');
    if (!bodySource || !lightSource || !cameraSource) throw new Error('Missing native template entity');
    const update = (block, values) => Object.entries(values).reduce((result, [key, value]) => setProperty(result, key, value), block);
    let body = update(bodySource, {
        targetname: 'shortcut_doom_body', parentname: '', parentAttachmentName: '',
        model: DOOM_MODEL, skin: 'default', rendercolor: '255 255 255 255',
        StartingAnim: 'idle', IdleAnim: 'idle', origin: '0 0 0', angles: '0 0 0', scales: '1 1 1',
        solid: '0', disableshadows: '1', disablereceiveshadows: '1',
        force_hidden: '0', editorOnly: '0',
    });
    const blocks = [stableIds(body, variant + ':body', 1)];
    for (const wearable of WEARABLES) {
        const block = update(body, {
            targetname: 'shortcut_doom_' + wearable.slot, parentname: 'shortcut_doom_body',
            parentAttachmentName: '!bonemerge', model: wearable.model,
        });
        blocks.push(stableIds(block, variant + ':' + wearable.slot, blocks.length + 1));
    }
    const light = update(lightSource, {
        targetname: 'shortcut_light', StartDisabled: '0', background_clear_not_required: '1',
        enableshadows: '0', groundscale: '0', height_fog_density: '0.0',
        origin: '77.29 -68.51 304.23', angles: '41.19 112.90 0',
        color: '255 224 202 255', lightscale: '2.2',
        ambientcolor1: '148 135 135 255', ambientscale1: '1.4',
        force_hidden: '0', editorOnly: '0',
    });
    blocks.push(stableIds(light, variant + ':light', blocks.length + 1));
    const nativeFov = Number(camera.PortraitFOV);
    const fov = 2 * Math.atan(Math.tan(nativeFov * Math.PI / 360) * margin) * 180 / Math.PI;
    const sceneCamera = update(cameraSource, {
        targetname: 'shortcut_camera', parentname: '', parentAttachmentName: '',
        origin: camera.PortraitPosition, angles: camera.PortraitAngles,
        FOV: fov.toFixed(4), ZNear: '4', ZFar: '5000',
        UseScreenAspectRatio: '0', aspectRatio: '1', dof_enabled: '0', fogEnable: '0',
        force_hidden: '0', editorOnly: '0',
    });
    blocks.push(stableIds(sceneCamera, variant + ':camera', blocks.length + 1));
    let text = template.slice(0, world.opening + 1) + '\n' + blocks.join(',\n') + '\n\t\t' + template.slice(world.closing);
    text = setProperty(text, 'mapUsageType', 'background');
    // Remove unused environment dependencies left by the original showcase.
    const refs = text.indexOf('"map_asset_references" "string_array"');
    if (refs >= 0) {
        const opening = text.indexOf('[', refs), closing = balanced(text, opening, '[', ']');
        text = text.slice(0, opening + 1) + '\n' + [DOOM_MODEL, ...WEARABLES.map(w => w.model)].map(m => '\t\t"' + m + '"').join(',\n') + '\n\t' + text.slice(closing);
    }
    const actual = worldEntities(text).entities;
    if (actual.length !== 10) throw new Error('Unexpected scene entity count');
    if (actual.some(block => /"classname" "string" "(?:env_fog_controller|info_particle_system|prop_static)"/.test(block))) throw new Error('Environment leaked into portrait');
    return { text, report: { variant, model: DOOM_MODEL, entityCount: actual.length, camera: {
        targetname: 'shortcut_camera', position: camera.PortraitPosition, angles: camera.PortraitAngles,
        originalFov: nativeFov, margin, fov: Number(fov.toFixed(4)),
    }, wearables: WEARABLES } };
}

function generate() {
    const template = fs.readFileSync(path.join(__dirname, 'jugg_portrait_template.vmap'), 'utf8');
    const camera = doomCamera(fs.readFileSync(path.join(ROOT, 'scripts/npc/portraits_custom.txt'), 'utf8'));
    const directory = path.join(ROOT, 'art/portraits/shortcuts');
    fs.mkdirSync(directory, { recursive: true });
    const results = [];
    for (const [variant, margin] of [['doom_soft_a', 1.65]]) {
        const { text, report } = makeMap(template, camera, variant, margin);
        const filename = path.join(directory, variant + '.vmap');
        fs.writeFileSync(filename, text, 'utf8');
        results.push({ ...report, source: filename, sha256: crypto.createHash('sha256').update(text).digest('hex') });
    }
    console.log(JSON.stringify({ result: 'SHORTCUT_DOOM_MAP_SOURCE_PASS', compiled: false, gameVerified: false, results }, null, 2));
    return results;
}

module.exports = { balanced, worldEntities, doomCamera, makeMap, generate };
if (require.main === module) generate();
