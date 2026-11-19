"""Exact reviewed public-admission projection for newly rendered families.

No old family, signed parent, source tree or admission receipt is rewritten.
The unchanged production recipe still verifies constants, protection and all
resource origins; this extension admits only the reviewed policy and roster.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import re

EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
ACCESS = 'scripts/vscripts/config/test_access.lua'
POLICY = 'scripts/vscripts/core/test_access_policy.lua'
POLICY_SHA = 'e6f38329a4176dc860849bde64f3391318fea9ace1541e27c37daf7ab3175590'
PARENT_POLICY_SHA = 'd9461fe18ae9f1083616d4e99a75704b1478dd45ee3c4f62f8b153532d8dcc9b'
IDS = ('76561198424163156', '76561198845461206', '76561198104787442',
       '76561198974301984', '76561198296534615')
PROBE = 'tools/public_launch/production_policy_probe.lua'
PRIVATE_PROBE = 'tools/admission_five_20261101/test_projected_policy.lua'


def need(value, reason):
    if not value:
        raise ValueError(reason)


def fingerprint(raw):
    return hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest()


def roster(raw):
    text = raw.decode('utf-8-sig')
    text = re.sub(r'--[^\n]*', '', text)
    text = re.sub(r'\s+', '', text)
    found = re.fullmatch(r'return\{enabled=true,(?:public_release=(true|false),)?'
                         r'allowed_steamids=\{((?:"[0-9]{17}",)+)\},\}', text)
    need(found is not None, 'exact_public_roster_literal_grammar_required')
    identities = tuple(re.findall(r'"([0-9]{17})"', found[2]))
    need(identities == IDS, 'reviewed_fallback_roster_must_remain_exact')
    return found[1] == 'true', identities


def requested(source):
    return roster(source[ACCESS])[0]


def validate_roster(source, parent):
    _, source_ids = roster(source)
    _, parent_ids = roster(parent)
    need(source_ids == parent_ids, 'public_launch_cannot_rewrite_fallback_identities')
    return True


def validate_admission(source, parent):
    validate_roster(source[ACCESS], parent[ACCESS])
    need(fingerprint(source[POLICY]) == POLICY_SHA, 'reviewed_public_policy_bytes_required')
    need(fingerprint(parent[POLICY]) in (PARENT_POLICY_SHA, POLICY_SHA),
         'reviewed_public_policy_parent_required')
    return True


def probe_path(source):
    return PROBE if requested(source) else PRIVATE_PROBE


def configured_ids(api, candidate, approved):
    """Read the explicit mode; five fallback IDs do not imply private access."""
    path = api.protect_data.source_path(candidate, ACCESS)
    need(path.stat().st_size <= 8192, 'bounded_public_access_config_required')
    public, identities = roster(path.read_bytes())
    need(sorted(identities) == approved, 'public_candidate_fallback_roster_changed')
    if public:
        policy = api.protect_data.source_path(candidate, POLICY)
        need(fingerprint(policy.read_bytes()) == POLICY_SHA, 'public_candidate_policy_not_reviewed')
    return sorted(identities)


def review(source, parent):
    public = requested(source)
    changed = fingerprint(source[POLICY]) != fingerprint(parent[POLICY])
    if public or changed:
        validate_admission(source, parent)
    return dict(path=POLICY,
                kind='CURRENT_IMMUTABLE_PUBLIC_ADMISSION' if public else
                     'CURRENT_REVIEWED_PRIVATE_ADMISSION_WITH_PUBLIC_SUPPORT' if changed else
                     'CURRENT_SOURCE_WITH_PREVIEW_DEPENDENCY_REMOVED',
                public_release=public, approved_account_count=5,
                approved_count_is_restricted_admission=not public,
                original_non_preview_logic_identical=not changed,
                public_native_identity_probe_required=public,
                removed_dependency='scripts/vscripts/debug/offline_onboarding_test.lua')
