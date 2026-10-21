"""Optional four-account test gate; this is not Steam/server authentication.

The HTTP API already expects a trusted game server's Bearer credential. This
additional gate restricts which existing Steam account IDs that server may use.
Keep the setting in the host environment, never in an addon or a payment list.
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import wraps
import os
import re
from typing import Mapping


ENVIRONMENT_NAME = "SURVIVAL_TEST_STEAM_IDS64"
STEAM_INDIVIDUAL_BASE = 76561197960265728
MAX_ACCOUNT_ID = 4294967295


@dataclass(frozen=True)
class TestAccountPolicy:
    account_ids: frozenset[str]

    @classmethod
    def from_environment(cls, environ: Mapping[str, str]):
        value = environ.get(ENVIRONMENT_NAME, "")
        if not isinstance(value, str):
            raise ValueError("test_access_configuration_invalid")
        if not value.strip():
            return None  # Explicit opt-in: existing production access is unchanged.
        identities = [part.strip() for part in value.split(",")]
        if len(identities) != 4 or len(set(identities)) != 4:
            raise ValueError("test_access_requires_four_unique_steam_ids")
        accounts = set()
        for identity in identities:
            if not re.fullmatch(r"[0-9]{17}", identity):
                raise ValueError("test_access_steam_id_invalid")
            account = int(identity) - STEAM_INDIVIDUAL_BASE
            if not 1 <= account <= MAX_ACCOUNT_ID:
                raise ValueError("test_access_steam_id_invalid")
            accounts.add(str(account))
        return cls(frozenset(accounts))

    def permits(self, account):
        # The game uses GetSteamAccountID, not SteamID64, as the archive key.
        # Do not normalize caller input or change the existing HMAC/database key.
        return isinstance(account, str) and account in self.account_ids


def install(application, environ=None):
    """Gate the shared raw-account -> database-account boundary before any RPC.

    Profile, session, reward, online checkpoint, lottery and commerce operations
    all pass this boundary. Static config/health routes contain no account and
    retain the existing HTTP authorization behavior. Restart to change the list.
    """
    policy = TestAccountPolicy.from_environment(os.environ if environ is None else environ)
    previous = getattr(application, "_survival_test_access_policy", None)
    if previous is not None:
        if previous != policy:
            raise ValueError("test_access_policy_changed_restart_required")
        return previous
    if policy is None:
        return None
    from fishing_api.application import ApiError

    original = application._database_account_id

    @wraps(original)
    def restricted(account_id):
        if not policy.permits(account_id):
            raise ApiError("test_account_not_allowed", 403)
        return original(account_id)

    application._database_account_id = restricted
    application._survival_test_access_policy = policy
    return policy
