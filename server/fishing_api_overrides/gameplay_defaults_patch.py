"""Exact-parent gameplay-default validation/SQL-construction experiment.

Preparation only: never connects to PostgreSQL. Preserve the outer NULL guard,
players insert order, type conversion, dynamic EXECUTE, conflict rule and full-row
return. Two set SQL statements replace only the original per-key loop. This
reduces statement-boundary count; field work/sorting is not O(1).
"""
from __future__ import annotations
import hashlib

SCHEMA_PATH = 'database/10_schema.sql'
BASELINE_SHA256 = '56467cf615c01615adf1f8dbe885a8135f236ef820e1beb2551895245fa3475b'
OUTPUT_SHA256 = '600eb5d3fa430e57a369e0ed4724e29f279fd268d47b36dcd938f4ecec007f57'
MARKER = '-- SURVIVAL_GAMEPLAY_DEFAULTS_SET_V1'
OLD_BLOCK = " for key in select jsonb_object_keys(p_gameplay_stats) order by 1 loop\n  if key !~ '^[a-z][a-z0-9_]*$' or key in ('player_id','created_at','updated_at') or not exists (\n   select 1 from pg_attribute where attrelid='public.player_gameplay_stats'::regclass and attname=key and not attisdropped\n  ) then raise exception 'gameplay_schema_mismatch'; end if;\n  columns_sql:=columns_sql||format(',%I',key);\n  values_sql:=values_sql||format(',x.%I',key);\n end loop;\n"
NEW_BLOCK = " -- SURVIVAL_GAMEPLAY_DEFAULTS_SET_V1\n if exists (\n  select 1 from jsonb_object_keys(p_gameplay_stats) as k(key)\n  where k.key !~ '^[a-z][a-z0-9_]*$'\n   or k.key in ('player_id','created_at','updated_at')\n   or not exists (\n    select 1 from pg_attribute a\n    where a.attrelid='public.player_gameplay_stats'::regclass\n     and a.attname=k.key and not a.attisdropped\n   )\n ) then raise exception 'gameplay_schema_mismatch'; end if;\n select 'player_id'||coalesce(string_agg(format(',%I',k.key),'' order by k.key),''),\n        '$1'||coalesce(string_agg(format(',x.%I',k.key),'' order by k.key),'')\n  into columns_sql,values_sql\n  from jsonb_object_keys(p_gameplay_stats) as k(key);\n"


def _normalized(source):
    if type(source) is not str:
        raise ValueError('gameplay_defaults_schema_invalid')
    source = source.replace('\r\n', '\n')
    if '\r' in source:
        raise ValueError('gameplay_defaults_schema_invalid')
    return source


def _sha(source):
    return hashlib.sha256(source.encode('utf8')).hexdigest()


def _replace(source, before, after):
    if source.count(before) != 1:
        raise ValueError('gameplay_defaults_anchor_invalid')
    return source.replace(before, after, 1)


def restore_schema(source):
    source = _normalized(source)
    if _sha(source) != OUTPUT_SHA256 or source.count(MARKER) != 1:
        raise ValueError('gameplay_defaults_output_changed')
    restored = _replace(source, NEW_BLOCK, OLD_BLOCK)
    if _sha(restored) != BASELINE_SHA256:
        raise ValueError('gameplay_defaults_parent_changed')
    return restored


def patch_schema(source):
    source = _normalized(source)
    if MARKER in source:
        restore_schema(source)
        return source
    if _sha(source) != BASELINE_SHA256:
        raise ValueError('gameplay_defaults_baseline_mismatch')
    result = _replace(source, OLD_BLOCK, NEW_BLOCK)
    if _sha(result) != OUTPUT_SHA256 or restore_schema(result) != source:
        raise ValueError('gameplay_defaults_unrelated_change')
    return result


def patch_sources(sources):
    if type(sources) is not dict or set(sources) != {SCHEMA_PATH}:
        raise ValueError('gameplay_defaults_source_set_invalid')
    return {SCHEMA_PATH: patch_schema(sources[SCHEMA_PATH])}
