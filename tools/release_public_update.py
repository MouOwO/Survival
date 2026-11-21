"""Public content updates through the existing guarded release pipeline."""
from pathlib import Path
from types import FunctionType
import hashlib

MODE = 'EXPLICIT_PUBLIC_CONTENT_UPDATE_NATIVE_PENDING'
AUTHORIZATION_KIND = 'EXPLICIT_CURRENT_USER_PUBLIC_CONTENT_UPDATE_AUTHORIZATION'
AUTHORIZATION_TEXT = '可以更新到游廊上了'
PUBLIC_STATUS = 'SUBMITTED_PUBLIC_PENDING_DOWNLOAD_AND_NATIVE_TEST'
UNLISTED_STATUS = 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
SOURCE = 'tools/release_public_update.py'
SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()


def is_public_upload(journal):
    return journal.get('status') == PUBLIC_STATUS and type(journal.get('visibility_requested')) is int and journal['visibility_requested'] == 0


def supported_parent(journal):
    return is_public_upload(journal) or (
        journal.get('status') == UNLISTED_STATUS and journal.get('visibility_requested') == 3)


def require_prior_public_launch(state, parent, authority):
    from release_lineage_20261101 import guard
    pin = state.get('last_public_launch_receipt')
    guard.need(isinstance(pin, dict), 'verified_permanent_public_launch_required')
    receipt, raw = guard.read_json(pin['path'], 65536)
    guard.need(guard.sha(raw) == pin['sha256']
        and receipt.get('status') == 'PUBLIC_LAUNCH_VERIFIED_OFFICIAL'
        and receipt.get('final_visibility') == 0
        and receipt.get('package_bytes_changed') is False
        and receipt.get('both_languages_verified') is True
        and type(receipt.get('release_sequence')) is int
        and receipt['release_sequence'] <= parent['release_sequence'],
        'verified_public_launch_receipt_changed')
    if not is_public_upload(parent):
        from release_packager.core import baseline
        current = baseline(Path(authority.policy['repositories']['game']))['baseline']
        guard.need(receipt['release_sequence'] == current['parent_sequence'] == parent['release_sequence']
            and receipt.get('steam_manifest') == current['official_parent_manifest'],
            'public_launch_receipt_must_bind_first_public_parent')


def bind_public_download(protocol):
    """Retain the frozen query ABI and all checks while expecting public visibility."""
    def public_check(check, item, total):
        protocol.need(type(item.get('visibility')) is int and item['visibility'] == 0,
                      'official_item_must_remain_public')
        # The historical check also examines ownership, freshness, size and tags.
        check({**item, 'visibility': 3}, total)

    prior = protocol.previous.SHOP02Steam.fresh_item
    prior_globals = {**prior.__globals__}
    prior_check = prior_globals['validate_remote']
    prior_globals['validate_remote'] = lambda item, total: public_check(prior_check, item, total)
    fresh = FunctionType(prior.__code__, prior_globals, prior.__name__, prior.__defaults__, prior.__closure__)
    check = protocol.validate_remote

    def fresh_public_item(self):
        snapshot = fresh(self)
        public_check(check, snapshot, self.total)
        return snapshot

    protocol.RefreshSteam.fresh_item = fresh_public_item
