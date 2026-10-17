"""Grant earned free VIP privileges through the existing durable archive reducer.

The verified payment ledger owns recharge progress. This hook reads that saved
progress only; it never credits money, purchases packages, or awards medals.
"""
from __future__ import annotations

MAX_INTEGER = 9007199254740991


def integer(value):
    return type(value) is int and 0 <= value <= MAX_INTEGER


class VipProgression:
    def __init__(self, service):
        self.service = service
        self.levels = sorted(service.bundle.tables['archive_vip_levels'].values(),
                             key=lambda row: row['level'])
        self.rewards = sorted((row for row in service.bundle.tables['archive_vip_rewards'].values()
                               if row.get('enabled') is True and row['group_id'] == 'privileges'),
                              key=lambda row: (row['level'], row['reward_id']))

    def level(self, profile):
        total = profile.get('save', {}).get('gameplay_stats', {}).get('vip_recharge_total_fen')
        if not integer(total):
            return 0
        return max((row['level'] for row in self.levels
                    if row['required_recharge_fen'] <= total), default=0)

    @staticmethod
    def owned(profile, reward_id):
        saved = profile.get('save', {})
        claimed = saved.get('archive', {}).get('vip_claimed', {})
        inventory = saved.get('content_inventory', {})
        count = inventory.get(reward_id, 0)
        return claimed.get(reward_id) is True or integer(count) and count > 0

    def reconcile(self, account, profile):
        if not isinstance(profile, dict) or profile.get('account_id') != account:
            raise ValueError('vip_profile_identity_invalid')
        # At most one receipt per configured privilege. Concurrent requests and
        # lost replies use the same ID; the reducer additionally checks ownership.
        for row in self.rewards:
            reward_id = row['reward_id']
            if self.level(profile) < row['level'] or self.owned(profile, reward_id):
                continue
            result = self.service.command({'account_id': account,
                'config_hash': self.service.bundle.hash,
                'command': {'id': 'vip:auto:' + self.service.bundle.hash + ':' + reward_id,
                            'kind': 'vip_claim', 'reward_id': reward_id}})
            if not isinstance(result, dict) or result.get('ok') is not True:
                raise TimeoutError('vip_auto_reward_pending')
            profile = result.get('profile')
            if (not isinstance(profile, dict) or profile.get('account_id') != account
                    or not self.owned(profile, reward_id)):
                raise TimeoutError('vip_auto_reward_unconfirmed')
        return profile


def install(service):
    if getattr(service, '_vip_progression', None) is not None:
        return service
    progression = VipProgression(service)
    original_profile = service.profile

    def profile(payload):
        # The loader first resumes pending archive transactions. No nested
        # profile() call is made by the existing vip_claim command path.
        value = original_profile(payload)
        return progression.reconcile(payload['account_id'], value)

    service._vip_progression = progression
    service.profile = profile
    return service
