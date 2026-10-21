"""Inventory-derived combat bonuses for immutable account/match projections.

The Lua runtime uses the same archive_stackable_items rows. Pure matches need
the signed difference of full account bonuses, rather than bonuses computed
from their inventory difference: a single new copy can cross a threshold.
"""
from __future__ import annotations

from decimal import Decimal
from .unique_points import integer, MAX_INTEGER


def _legacy_ember_growth(save):
    state=save.get('archive', {}).get('stackable_items', {})
    marker=state.get('legacy_ember_growth')
    if marker is not None:
        if isinstance(marker,bool):
            raise ValueError('stackable_legacy_marker_invalid')
        try:
            result=Decimal(str(marker))
        except Exception as error:
            raise ValueError('stackable_legacy_marker_invalid') from error
        if not result.is_finite() or not 0<=result<=Decimal('.1'):
            raise ValueError('stackable_legacy_marker_invalid')
        return result
    return (Decimal('.1') if save.get('lottery_applied_item_effects', {}).get(
        'lottery_ember_of_legacy') is True else Decimal(0))


def _project(save,bundle):
    definitions=bundle.tables.get('archive_stackable_items', {})
    inventory=save.get('content_inventory', {})
    per_item={}
    for row in definitions.values():
        if row.get('enabled') is False:
            continue
        identity=row['item_id']
        count=integer(inventory.get(identity,0))
        maximum=integer(row['max_owned'])
        if maximum:
            count=min(count,maximum)
        contribution,highest=per_item.setdefault(identity,({},{}))
        field=row['effect_id'];value=Decimal(str(row['effect_value']))
        if row['mode']=='per_copy':
            contribution[field]=contribution.get(field,Decimal(0))+count*value
        elif count>row['threshold']:
            previous=highest.get(field)
            if previous is None or row['threshold']>previous[0]:
                highest[field]=(row['threshold'],value)
    result={}
    for identity,(contribution,highest) in per_item.items():
        for field,(_,value) in highest.items():
            contribution[field]=contribution.get(field,Decimal(0))+value
        if identity=='lottery_ember_of_legacy':
            field='hero_basic_attack_growth'
            contribution[field]=max(Decimal(0),contribution.get(field,Decimal(0))-_legacy_ember_growth(save))
        for field,value in contribution.items():
            if value:
                result[field]=result.get(field,Decimal(0))+value
    return result


def _plain(value):
    if not value.is_finite() or abs(value)>MAX_INTEGER:
        raise ValueError('stackable_effect_limit')
    return int(value) if value==value.to_integral_value() else float(value)


def project(save,bundle):
    """Read-only full account contribution, matching the Lua projection."""
    return {field:_plain(value) for field,value in _project(save,bundle).items()}


def difference(current,baseline,bundle):
    """Signed delta; e.g. ember's 600→601 highest tier changes 100 to 40."""
    after,before=_project(current,bundle),_project(baseline,bundle)
    return {field:_plain(value) for field in after.keys()|before.keys()
            if (value:=after.get(field,Decimal(0))-before.get(field,Decimal(0)))}
