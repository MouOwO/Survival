-- Read-only public display metadata. The generator supplies fixed Git modules
-- and virtual public files, never account/session data or a wall clock.
package.path="scripts/vscripts/?.lua;"..package.path
local benefits=require("systems/archive_benefit_rewards")
local config=require("config/generated/archive_benefit_rewards")
local json=require("core/json_encoder")
local source_paths={
    "scripts/vscripts/systems/archive_benefit_rewards.lua",
    "panorama/src/scripts/custom_game/public_beta_gift.js",
}
local raw={}
for _,path in ipairs(source_paths)do
    local file=assert(io.open(path,"rb"),"immutable_beta_public_source_missing:"..path)
    raw[path]=file:read("*a");file:close()
end
local tier=assert(raw[source_paths[1]]:match('local PUBLIC_BETA_TIER%s*=%s*"([A-Za-z0-9_]+)"'),"beta_tier_source_changed")
local row=assert(config.by_id[tier],"beta_config_tier_missing")
local probe=benefits.public_beta_snapshot({revision=0,save={archive={}}},0)
assert(type(probe.ticket_id)=="string"and type(probe.ticket_name)=="string"
    and type(probe.ticket_count)=="number"and probe.ticket_count>0,"beta_public_snapshot_metadata_missing")
-- The old public DTO is a fixed single-ticket display. Reject configuration
-- drift rather than displaying two tickets while the real rule grants three,
-- another item, or an extra monthly reward. Authority remains in M.apply.
assert(row.reward_id==tier and row.period=="day","beta_reward_identity_or_period_changed")
assert(type(row.base_item_ids)=="table"and #row.base_item_ids==1
    and row.base_item_ids[1]==probe.ticket_id,"beta_reward_item_shape_changed")
assert(type(row.base_counts)=="table"and #row.base_counts==1
    and tonumber(row.base_counts[1])==probe.ticket_count,"beta_reward_count_changed")
assert((row.pass_item_ids==nil or type(row.pass_item_ids)=="table"and #row.pass_item_ids==0)
    and(row.pass_counts==nil or type(row.pass_counts)=="table"and #row.pass_counts==0),"beta_additional_reward_requires_review")
local notice=assert(raw[source_paths[2]]:match('"(领取未完成，请重试)"'),"beta_original_failure_notice_missing")
print(json.encode({format=1,ticket_id=probe.ticket_id,ticket_name=probe.ticket_name,
    ticket_count=probe.ticket_count,tier_id=tier,config=row,errors={"","claim_failed"},
    failure_notice=notice,sources=source_paths}))
