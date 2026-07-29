local ground_reward_claim = require("items/challenge_ground_reward_claim")

item_survival_challenge_reward = class({})

function item_survival_challenge_reward:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_PASSIVE
end

function item_survival_challenge_reward:Claim(caster)
    return ground_reward_claim.claim(self, caster)
end

return item_survival_challenge_reward