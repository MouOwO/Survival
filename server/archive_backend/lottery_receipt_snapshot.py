"""Optional read-only projection from the profile already returned by durable commit.

No database/HTTP read, no second draw and no change to a stored receipt. Failure
leaves the successful transaction intact; old game versions ignore these fields.
"""
import logging
from time import perf_counter


def attach(service, reply, command, requested_hash):
    if command.get('kind') != 'lottery_draw' or reply.get('ok') is not True:
        return reply
    profile = reply.get('profile')
    if not (reply.get('done') is True or reply.get('terminal') is True):
        return reply
    if not isinstance(profile, dict) or not isinstance(profile.get('save'), dict):
        return reply
    started=perf_counter()
    try:
        reducer = service
        if requested_hash != service.bundle.hash:
            from .bundle import Bundle
            from .service import ArchiveService
            reducer = ArchiveService(service.app, Bundle(service.bundle.directory.parent/requested_hash), service.lua)
        projected = reducer.settle(profile, {'id':'lottery_snapshot','kind':'lottery_snapshot'}, False)
        from .unique_points import limit_snapshot_ownership
        projected = limit_snapshot_ownership(projected, service.bundle)
        snapshots = projected.get('snapshots')
        if projected.get('ok') is True and isinstance(snapshots, list) and 1 <= len(snapshots) <= 4:
            reply['lottery_snapshots'] = snapshots
            reply['snapshot_config_hash'] = requested_hash
            reply['snapshot_projection_ms'] = round((perf_counter()-started)*1000,2)
    except Exception as error:
        # Never turn a completed debit/grant into an apparent failed draw.
        # The game falls back to the existing authoritative snapshot endpoint.
        logging.getLogger(__name__).warning('lottery_receipt_projection_fallback error_type=%s',type(error).__name__)
    return reply
