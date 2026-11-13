"""Common SDK boundary: old publishers cannot mutate without a release lease.

Only explicit publication operations consult the guard. Query/download tools
and noncanonical diagnostic journals keep their existing behavior. Validation
cost is bounded control metadata per mutation, never a per-frame operation.
"""
from pathlib import Path
import hashlib
import importlib
ROOT = Path(__file__).resolve().parents[1]
CANONICAL_JOURNAL = ROOT / 'output/four_accounts_20261022/steam_upload_state.json'
AUTHORITY_FILE = ROOT / 'publishing/workshop/packager_pack_2026111302_2f448589_authority.json'
AUTHORITY_SHA256 = '168e975bdbefbc844989a24bd016fdb4dbbd0d1a1ba6db50e3bc59ce88b23e2e'
_QUERY_AND_DOWNLOAD = frozenset({'SendQueryUGCRequest', 'ReleaseQueryUGCRequest', 'DownloadItem', 'SubscribeItem', 'UnsubscribeItem', 'SetAllowCachedResponse', 'SetLanguage', 'SetSearchText', 'SetCloudFileNameFilter', 'SetMatchAnyTag', 'SetRankedByTrendDays', 'SetTimeCreatedDateRange', 'SetTimeUpdatedDateRange', 'AddRequiredTag', 'AddExcludedTag', 'AddRequiredKeyValueTag', 'AddRequiredTagGroup'})
_UGC = 'SteamAPI_ISteamUGC_'

def _guard():
    if not isinstance(AUTHORITY_SHA256, str) or len(AUTHORITY_SHA256) != 64:
        raise RuntimeError('release_authority_not_configured_publication_refused')
    guard = importlib.import_module('release_lineage_20261101.guard')
    return guard

def publication_suffix(name):
    if not name.startswith(_UGC):
        return None
    suffix = name[len(_UGC):]
    if suffix.startswith(('Get', 'CreateQuery', 'SetReturn')) or suffix in _QUERY_AND_DOWNLOAD:
        return None
    return suffix

def wrap_sdk_function(name, native):
    suffix = publication_suffix(name)
    if suffix is None:
        return native

    def guarded(*values):
        if not values:
            raise RuntimeError('release_sdk_interface_missing')
        permit = _guard().require_sdk_mutation(suffix, tuple(values[1:]), authority_sha256=AUTHORITY_SHA256)
        if permit is None or not callable(getattr(permit, 'observe_result', None)):
            raise RuntimeError('unregistered_ugc_publication_primitive_refused')
        result = native(*values)
        permit.observe_result(result)
        return result
    return guarded

def before_journal_write(path, value):
    if Path(path).resolve() != CANONICAL_JOURNAL.resolve():
        return False
    _guard().before_journal_write(Path(path), value, authority_sha256=AUTHORITY_SHA256)
    return True

def after_journal_write(path, guarded):
    if guarded:
        raw = Path(path).read_bytes()
        _guard().after_journal_write(Path(path), hashlib.sha256(raw).hexdigest(), authority_sha256=AUTHORITY_SHA256)
