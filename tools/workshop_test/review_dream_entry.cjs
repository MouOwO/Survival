"use strict";
// Static selected-resource review; no addon execution, decryption or network.
// Default reads only. --write-report writes the one fixed review JSON.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const WORKSHOP_ID = "3616205610";
const PACKAGE = "D:/SteamLibrary/steamapps/workshop/content/570/3616205610/3616205610.vpk";
const REPORT = path.resolve(__dirname, "../../publishing/workshop/dream_island_entry_review_20261024.json");
const SELECTED = [
    "addoninfo.txt",
    "scripts/vscripts/addon_game_mode.lua",
    "scripts/vscripts/addon_game_mode_client.lua",
    "scripts/vscripts/server/core/http.lua",
    "scripts/vscripts/server/core/request.lua",
    "scripts/vscripts/server/player_auth/playerauthapi.lua",
    "scripts/vscripts/modules/player_auth/playerauthgateway.lua",
    "panorama/layout/custom_game/hud_loading/script.vjs_c",
];
const PROTECTED = SELECTED.slice(3, 7);
const sha = raw => crypto.createHash("sha256").update(raw).digest("hex");
function need(value, code) { if (!value) throw new Error(code); }
function crc32(raw) {
    let crc = 0xffffffff;
    for (const value of raw) {
        crc ^= value;
        for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    return (crc ^ 0xffffffff) >>> 0;
}
function readExactly(fd, position, length) {
    need(Number.isSafeInteger(position) && position >= 0 && Number.isSafeInteger(length)
        && length >= 0 && length <= 16 * 1024 * 1024, "reference_read_out_of_bounds");
    const raw = Buffer.alloc(length);
    let completed = 0;
    while (completed < length) {
        const amount = fs.readSync(fd, raw, completed, length - completed, position + completed);
        need(amount > 0, "reference_read_truncated");
        completed += amount;
    }
    return raw;
}
function openDirectory(file) {
    need(path.basename(file) === WORKSHOP_ID + ".vpk", "reference_package_identity_invalid");
    const fd = fs.openSync(file, "r");
    try {
        const size = fs.fstatSync(fd).size;
        const header = readExactly(fd, 0, 28);
        const version = header.readUInt32LE(4), treeSize = header.readUInt32LE(8);
        need(header.readUInt32LE(0) === 0x55aa1234 && (version === 1 || version === 2)
            && treeSize > 0 && treeSize <= 16 * 1024 * 1024, "reference_vpk_header_invalid");
        const headerSize = version === 2 ? 28 : 12;
        need(headerSize + treeSize <= size, "reference_vpk_tree_truncated");
        const tree = readExactly(fd, headerSize, treeSize), entries = new Map();
        let cursor = 0;
        function string() {
            const terminator = tree.indexOf(0, cursor);
            need(terminator >= cursor, "reference_vpk_tree_string_invalid");
            const value = tree.toString("utf8", cursor, terminator);
            cursor = terminator + 1;
            return value;
        }
        for (let extension; (extension = string());) {
            for (let directory; (directory = string());) {
                for (let name; (name = string());) {
                    need(cursor + 18 <= tree.length, "reference_vpk_tree_record_invalid");
                    const crc = tree.readUInt32LE(cursor), preloadSize = tree.readUInt16LE(cursor + 4);
                    const archive = tree.readUInt16LE(cursor + 6), offset = tree.readUInt32LE(cursor + 8);
                    const length = tree.readUInt32LE(cursor + 12), terminator = tree.readUInt16LE(cursor + 16);
                    cursor += 18;
                    need(terminator === 0xffff && cursor + preloadSize <= tree.length,
                        "reference_vpk_tree_record_invalid");
                    const resource = (directory === " " ? "" : directory + "/") + name + "." + extension;
                    need(!entries.has(resource), "reference_vpk_duplicate_resource");
                    entries.set(resource, {crc, archive, offset, length,
                        preload: tree.subarray(cursor, cursor + preloadSize)});
                    cursor += preloadSize;
                }
            }
        }
        need(cursor === tree.length, "reference_vpk_tree_tail_invalid");
        return {
            entries,
            size,
            readSelected(resource) {
                need(SELECTED.includes(resource), "unreviewed_resource_read_forbidden");
                const entry = entries.get(resource);
                need(entry && entry.length + entry.preload.length <= 4 * 1024 * 1024,
                    "selected_resource_absent_or_oversized");
                let body;
                if (entry.archive === 0x7fff) {
                    const start = headerSize + treeSize + entry.offset;
                    const dataEnd = version === 2 ? headerSize + treeSize + header.readUInt32LE(12) : size;
                    need(start + entry.length <= dataEnd && dataEnd <= size, "selected_resource_payload_invalid");
                    body = readExactly(fd, start, entry.length);
                } else {
                    const archiveName = WORKSHOP_ID + "_" + String(entry.archive).padStart(3, "0") + ".vpk";
                    const archiveFd = fs.openSync(path.join(path.dirname(file), archiveName), "r");
                    try {
                        need(entry.offset + entry.length <= fs.fstatSync(archiveFd).size, "selected_resource_payload_invalid");
                        body = readExactly(archiveFd, entry.offset, entry.length);
                    } finally { fs.closeSync(archiveFd); }
                }
                const raw = Buffer.concat([entry.preload, body]);
                need(crc32(raw) === entry.crc, "selected_resource_crc_mismatch");
                return raw;
            },
            close() { fs.closeSync(fd); },
        };
    } catch (error) { fs.closeSync(fd); throw error; }
}
function mapMaximum(info, name) {
    for (const match of info.matchAll(/\{[^{}]*\bmap\s*=\s*"([^"]+)"[^{}]*\}/g)) {
        if (match[1] !== name) continue;
        const maximum = /\bMaxPlayers\s*=\s*(\d+)/.exec(match[0]);
        if (maximum) return Number(maximum[1]);
    }
    return null;
}
function review() {
    const archive = openDirectory(PACKAGE);
    try {
        const selected = new Map(SELECTED.map(resource => [resource, archive.readSelected(resource)]));
        const text = resource => selected.get(resource).toString("utf8");
        const info = text(SELECTED[0]), server = text(SELECTED[1]), client = text(SELECTED[2]);
        const ui = text(SELECTED[7]);
        need(/\bDefaultMap\s*=\s*"neverland_launcher"/.test(info)
            && mapMaximum(info, "neverland_launcher") === 1 && mapMaximum(info, "dota_mhd_solo") === 4,
            "reviewed_map_layout_changed");
        need(client.includes('_G.NEVERLAND_LAUNCHER_WORKSHOP_ID = "3616205610"')
            && client.includes('SendToConsole(("dota_launch_custom_game " .. workshopId) .. " dota_mhd_solo")'),
            "reviewed_entry_route_changed");
        need(PROTECTED.every(resource => /^\s*return\s+\(?\s*GameRules\.XDecrypt\s*\(/.test(text(resource))),
            "reviewed_protected_resource_shape_changed");
        const rows = SELECTED.map(resource => ({path: resource, bytes: selected.get(resource).length,
            sha256: sha(selected.get(resource)),
            crc32: archive.entries.get(resource).crc.toString(16).padStart(8, "0"), crc_verified: true,
            protected_wrapper_observed: PROTECTED.includes(resource)}));
        return {
            schema: 1,
            review_date: "2026-10-24",
            workshop_id: WORKSHOP_ID,
            installed_title: "Dota: Island of Dreams",
            local_vpk_name: WORKSHOP_ID + ".vpk",
            package_bytes: archive.size,
            package_entry_count: archive.entries.size,
            selected_resources: rows,
            observations: {
                default_entry_map: "neverland_launcher",
                entry_map_max_players: 1,
                real_map: "dota_mhd_solo",
                real_map_max_players: 4,
                client_uses_fixed_same_workshop_id: true,
                client_uses_standard_dota_launch_custom_game: true,
                client_relaunches_real_map_from_entry: true,
                launcher_server_calls_force_game_start: server.includes("GameRules:ForceGameStart()"),
                gameplay_modules_are_in_other_map_branch: server.includes('require("modules.index")')
                    && server.includes("ActivateModules()"),
                ui_mount_ready_event_present: ui.includes("c2s_nv_meta_hud_loading_ready"),
                ui_game_password_submission_event_present: ui.includes("c2s_nv_meta_hud_loading_send_validate_password"),
                ui_clears_password_after_submission: /send_validate_password['"],\s*\{ password \}\);\s*clearPassword\(\)/.test(ui),
                ui_opens_server_supplied_https_browser_link: ui.includes("s2c_nv_meta_hud_loading_open_url")
                    && ui.includes("data.url.startsWith('https://')") && ui.includes("ExternalBrowserGoToURL"),
                ui_offline_without_cloud_event_present: ui.includes("c2s_nv_meta_hud_loading_continue_offline"),
                readable_login_ui_has_engine_game_in_progress_gate: /GameRules|Game\.GetState|DOTA_GAMERULES_STATE_GAME_IN_PROGRESS/.test(ui),
                readable_http_constructor_observed: /\b(?:CreateHTTPRequestScriptVM|CreateHTTPRequest)\s*\(/.test(server + "\n" + client + "\n" + ui),
                http_and_auth_core_protected_by: "GameRules.XDecrypt",
            },
            boundaries: {
                protected_modules_decrypted: false,
                third_party_scripts_executed: false,
                third_party_business_code_copied: false,
                third_party_business_endpoints_contacted: false,
                credentials_or_keys_extracted: false,
                full_package_payload_read: false,
                backend_auth_protocol_verified: false,
                session_persistence_verified: false,
                http_constructor_api_verified: false,
                http_engine_phase_requirement_verified: false,
            },
            method: "Stream only the VPK directory and eight explicitly selected resources; verify each selected CRC and SHA256; inspect readable entry and UI structure without executing or decrypting code.",
            application: "Independent implementation of a lightweight default entry that relaunches the same Workshop item's own gameplay map. No third-party authentication, transport or game business implementation is copied.",
            limitations: [
                "The visible launcher ForceGameStart call does not establish that HTTP requires GAME_IN_PROGRESS.",
                "The protected transport and authentication implementation does not reveal its actual HTTP constructor or timing.",
                "Readable UI game-password events do not verify the external site's authentication or credential-storage behavior.",
                "Reference routing observations do not prove our original Workshop lobby, cloud login or multiplayer behavior.",
            ],
            sources: ["https://steamcommunity.com/sharedfiles/filedetails/?id=" + WORKSHOP_ID],
        };
    } finally { archive.close(); }
}
function main() {
    const args = process.argv.slice(2);
    need(args.length === 0 || args.length === 1 && args[0] === "--write-report", "review_argument_invalid");
    const report = review();
    if (args.length) fs.writeFileSync(REPORT, JSON.stringify(report, null, 2) + "\n", "utf8");
    process.stdout.write(JSON.stringify({ok: true, workshop_id: WORKSHOP_ID,
        selected_resources: report.selected_resources.length, crc_verified: true,
        report_written: args.length === 1, third_party_execution: false, decryption: false,
        default_entry_map: report.observations.default_entry_map,
        real_map: report.observations.real_map, fixed_same_workshop_relaunch: true}) + "\n");
}
if (require.main === module) {
    try { main(); }
    catch (error) {
        const code = error && /^[a-z][a-z0-9_]{1,95}$/.test(error.message) ? error.message : "dream_entry_review_failed";
        process.stdout.write(JSON.stringify({ok: false, error: code}) + "\n");
        process.exitCode = 1;
    }
}
module.exports = {review};
