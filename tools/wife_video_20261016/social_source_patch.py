"""Exact additive draw-availability change against the deployed social reducer."""
import hashlib

BASE_SHA256 = "6fd7eb70f4bbb2c786a1125d30e94c29d67bcb8e1d73d430601d4c7c6566ccfe"
REPLACEMENTS = (
    ('''        if item.enabled and item.pool_id == pool then
            rows[#rows+1] = { id=item.item_id, name=item.display_name, quality=item.quality,
                description=item.description .. "（每件）\\n已拥有" .. (save.social_counts[item.item_id] or 0) .. "件，效果按数量叠加", count=save.social_counts[item.item_id] or 0,''',
     '''        if item.enabled and item.pool_id == pool then
            local draw_enabled = item.draw_enabled ~= false
            rows[#rows+1] = { id=item.item_id, name=item.display_name, quality=item.quality,
                description=draw_enabled and (item.description .. "（每件）\\n已拥有" .. (save.social_counts[item.item_id] or 0) .. "件，效果按数量叠加") or item.description,
                draw_enabled=draw_enabled and 1 or 0, availability_note=item.availability_note or "", count=save.social_counts[item.item_id] or 0,'''),
    ('''    local total, remaining = 0, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.pool_id == pool then''',
     '''    local total, remaining = 0, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.draw_enabled ~= false and item.pool_id == pool then'''),
    ('''    local pool, total = {}, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.pool_id == command.pool_id then''',
     '''    local pool, total = {}, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.draw_enabled ~= false and item.pool_id == command.pool_id then'''),
    ('''    return rows
end
function M.info''',
     '''    if pool == "wife" then table.sort(rows, function(a, b) return a.id < b.id end) end
    return rows
end
function M.info'''),
)


def transform(source):
    if hashlib.sha256(source.encode("utf-8")).hexdigest() != BASE_SHA256:
        raise ValueError("social_source_baseline_changed")
    for old, new in REPLACEMENTS:
        if source.count(old) != 1:
            raise ValueError("social_source_patch_anchor_changed")
        source = source.replace(old, new, 1)
    return source
