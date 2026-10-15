"use strict";
const assert = require("node:assert/strict");
const { createHarness } = require("./tests/fixtures/menus_v10_harness.cjs");
const h = createHarness(), { cfg, nodes } = h, effects = [], owners = [];
cfg.ArchiveHandoff = { Icon() {}, Init() {}, Observe() {} };
cfg.SurvivalUI.RewardFX = { Create(canvas, options) {
    assert.equal(canvas.id, "CollectionGW2Canvas");
    assert.equal(options.channel, "collection");
    const owner = { cleared: 0, disposed: false, Play(event) {
        assert(!this.disposed);
        assert(event.anchor.IsValid(), "Feedback uses the newly rendered card, never a retired card");
        effects.push(event);
    }, Clear() { this.cleared++; }, Dispose() { this.disposed = true; } };
    owners.push(owner); return owner;
} };
["ui_snapshot_cache.js", "archive_parchment_data.js", "archive_v10_semantics.js",
 "common/archive_tooltip.js", "collection_gw2_data.js", "collection_gw2.js"].forEach(h.load);
let api = cfg.SurvivalCollection, sequence = 0;
const rows = { ex: [{ id: "ex_01", name: "胡桃", count: 0, target: 60, description: "效果" }],
    friend: [{ id: "friend_01", name: "哆啦A梦", count: 0, target: 60, description: "效果" }] };
function send(pool, extras = {}) {
    h.emit("survival_archive_snapshot", { ok: 1, category_id: pool, sequence: ++sequence,
        chunk: 1, chunks: 1, rows: rows[pool].map(row => ({ ...row })), pending: 0,
        social: { tickets: 99, draw_cost: 1, remaining: 99, total: rows[pool][0].count }, ...extras });
}
function begin(pool) { api.Open(pool); h.click(nodes.CollectionGW2Draw); return api.Inspect().pending; }
function ack(intent, extras = {}) {
    h.emit("survival_archive_social_result", { pool_id: intent.pool_id, request_id: intent.request_id,
        ok: true, terminal: true, ...extras });
}
function finish(intent, extras = {}) {
    rows[intent.pool_id][0].count++;
    send(intent.pool_id, { last_draw: { id: "game:social_draw:" + intent.request_id,
        pool_id: intent.pool_id, name: rows[intent.pool_id][0].name }, ...extras });
}
send("ex"); send("friend"); api.Open("ex");
assert.equal(effects.length, 0, "Initial ownership and opening never play reward feedback");

const first = begin("ex"), oldCard = nodes.CollectionGW2Item_ex_01;
ack(first, { revision: 10 });
assert.equal(effects.length, 0, "An ACK alone waits for the committed inventory");
finish(first, { revision: 10 });
assert.equal(effects.length, 1); assert.equal(api.Inspect().pending, null);
assert(!oldCard.IsValid()); assert.equal(effects[0].anchor, nodes.CollectionGW2Item_ex_01);
assert.equal(effects[0].key, first.request_id); assert.equal(effects[0].text, "胡桃");
ack(first, { duplicate: true, revision: 10 });
send("ex", { revision: 10, last_draw: { id: "game:social_draw:" + first.request_id, pool_id: "ex", name: "胡桃" } });
assert.equal(effects.length, 1, "Duplicate ACKs and newer snapshots of one result never replay");

const second = begin("friend"); finish(second, { revision: 11 });
assert.equal(effects.length, 2, "A committed snapshot can precede its ACK");
ack(second, { revision: 11 }); assert.equal(effects.length, 2);
assert.equal(effects[1].anchor, nodes.CollectionGW2Item_friend_01);
assert.equal(effects[1].text, "哆啦A梦");

const failure = begin("friend");
ack(failure, { ok: false, terminal: false, pending: true, error: "暂时离线" });
assert(api.Inspect().pending); assert.equal(effects.length, 2);
ack(failure, { ok: false, terminal: true, error: "义帖不足" });
assert.equal(api.Inspect().pending, null); assert.equal(effects.length, 2, "Failures never play a reward effect");

const closed = begin("ex"), beforeClose = owners.at(-1).cleared;
api.Close(); assert(owners.at(-1).cleared > beforeClose);
finish(closed); assert.equal(api.Inspect().pending, null); assert.equal(effects.length, 2);
api.Open("ex"); assert.equal(effects.length, 2, "A result committed while hidden is not replayed on open");

const switched = begin("ex"), beforeSwitch = owners.at(-1).cleared;
api.Select("friend"); assert(owners.at(-1).cleared > beforeSwitch);
finish(switched); assert.equal(api.Inspect().pending, null); assert.equal(effects.length, 2);
assert(nodes.CollectionGW2Draw.enabled, "Finishing the other pool releases the shared draw gate");
api.Select("ex"); assert.equal(effects.length, 2, "Returning to a completed pool does not replay");

const reloaded = begin("friend"), previous = owners.at(-1);
h.load("collection_gw2.js"); api = cfg.SurvivalCollection;
assert(previous.disposed); api.Open("friend");
assert.equal(api.Inspect().pending.request_id, reloaded.request_id, "Reload preserves the original purchase nonce");
ack(reloaded, { revision: 20 }); finish(reloaded, { revision: 20 });
assert.equal(effects.length, 3); assert.equal(effects[2].key, reloaded.request_id);
h.load("collection_gw2.js"); api = cfg.SurvivalCollection; api.Open("friend");
ack(reloaded, { revision: 20, duplicate: true }); send("friend", { revision: 20 });
assert.equal(effects.length, 3, "Reloading a completed transaction cannot replay feedback");

const covered = begin("ex");
ack(covered, { revision: 30 });
finish(covered, { revision: 30, last_draw: { id: "later-other-pool", pool_id: "beast", name: "其他奖励" } });
assert.equal(api.Inspect().pending, null); assert.equal(effects.length, 4);
assert.equal(effects[3].text, "收藏奖励已到账", "An overwritten last_draw cannot display another transaction's item");
assert.equal(effects[3].anchor, nodes.CollectionGW2Result);

const filtered = begin("ex");
nodes.CollectionGW2Search.text = "没有匹配"; nodes.CollectionGW2Search.events.ontextentrychange();
finish(filtered);
assert.equal(effects.length, 5); assert.equal(effects[4].anchor, nodes.CollectionGW2Result,
    "A filtered reward uses the result area instead of a deleted or unrelated card");
assert.equal(effects[4].text, "胡桃");

const lastOwner = owners.at(-1); h.assertCleanDispose(api); assert(lastOwner.disposed);
console.log("COLLECTION_REWARD_FEEDBACK_PASS: authoritative ACK/snapshot orders, rebuilt anchors, both pools, failures, duplicate results, closure/category changes, hot reload and safe fallback");
