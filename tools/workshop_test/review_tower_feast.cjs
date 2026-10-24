'use strict';
// Read selected installed resources and report structure; never execute addon code.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {open} = require('../vpk_inspect.cjs');

const installed = process.argv[2] || 'D:/SteamLibrary/steamapps/workshop/content/570/2234335140/2234335140.vpk';
const output = process.argv[3];
const packageFile = path.resolve(installed);
const archive = open(packageFile);
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
function crc32(data) {
    let crc = 0xffffffff;
    for (const value of data) {
        crc ^= value;
        for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    return (crc ^ 0xffffffff) >>> 0;
}
const selected = [
    'addoninfo.txt', 'resource/addon_schinese.txt',
    'panorama/layout/custom_game/component/login_loading/login_loading.vxml_c',
    'panorama/layout/custom_game/component/login_loading/login_loading.vjs_c',
    'panorama/layout/custom_game/component/login_loading/login_loading.vcss_c',
    'scripts/vscripts/module/server/servertransport.lua',
    'scripts/vscripts/module/role/data/role_login_session.lua',
    'scripts/vscripts/module/role/data/player_session_auth.lua',
];
const records = selected.map(name => {
    const entry = archive.entries.find(row => row.path === name);
    if (!entry) throw new Error('selected_resource_missing');
    const bytes = archive.read(entry);
    if (crc32(bytes) !== (entry.crc >>> 0)) throw new Error('selected_resource_crc_mismatch');
    return {path: name, bytes: bytes.length, sha256: sha(bytes), crc_verified: true};
});
const ui = archive.read(archive.entries.find(row => row.path === selected[3])).toString('utf8');
const addon = archive.read(archive.entries.find(row => row.path === 'addoninfo.txt')).toString('utf8');
const report = {
    schema: 1, review_date: '2026-10-24', workshop_id: '2234335140',
    title: 'Tower Feast [Local Host Support]', package_entries: archive.entries.length,
    selected_resources: records,
    observations: {
        external_authorization_site: 'https://auth.fnightgame.com/',
        site_referenced_by_installed_ui: ui.includes('https://auth.fnightgame.com/'),
        browser_navigation: /(?:ExternalBrowserGoToURL|BrowserGoToURL)/.test(ui),
        custom_game_auth_event: ui.includes('c2s_user_auth'),
        login_ui_has_server_transfer: /SendToConsole/.test(ui),
        default_map_is_solo: /solo/.test(addon),
        max_players_one: /MaxPlayers[\s"']+1/.test(addon),
    },
    method: 'Read VPK directory, verify selected entry CRCs, inspect readable UI strings and localization; no third-party code executed.',
    protected_server_modules_decrypted: false,
    third_party_authentication_performed: false,
    third_party_business_code_copied: false,
    backend_protocol_or_password_storage_verified: false,
    application: 'Independent implementation of Steam browser approval and per-player, per-match short-lived sessions. No reusable game password is sent to a player host.',
    sources: [
        'https://steamcommunity.com/sharedfiles/filedetails/?id=2234335140',
        'https://steamcommunity.com/sharedfiles/filedetails/changelog/2234335140?p=2',
    ],
};
if (output) {
    const destination = path.resolve(output);
    const allowed = path.resolve(__dirname, '../../publishing/workshop') + path.sep;
    if (!destination.startsWith(allowed) || path.extname(destination) !== '.json') throw new Error('report_path_invalid');
    fs.writeFileSync(destination, JSON.stringify(report, null, 2) + '\n');
}
process.stdout.write(JSON.stringify({ok: true, selected_resources: records.length, crc_verified: true, observations: report.observations}));
