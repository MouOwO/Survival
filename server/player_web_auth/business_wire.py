"""Negotiated, lossless business-response representation; never a save patch.

Initial schema indexes cost O(S). Idle work is zero. A response costs
O(B + sum(K log K)) expected time and O(B+N) space, bounded by 8 MiB,
100,000 nodes and depth 64. K is the field count of an individual object.
The indexes are immutable for this process. No database, clock, gameplay/native
API, network call, timer, or account cache participates in this codec.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re

MAX_BYTES = 8 * 1024 * 1024
MAX_NODES = 100_000
MAX_DEPTH = 64
MAX_REFS = 4096
HEADER = "X-Survival-Wire"
MARKER = "_bw"
_DIGITS = re.compile(r"[0-9]+\Z")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False,
                      sort_keys=True, separators=(",", ":")).encode("utf-8")


def _unique(pairs):
    value = {}
    for key, child in pairs:
        if key in value:
            raise ValueError("business_wire_duplicate_key")
        value[key] = child
    return value


def _loads(raw):
    def reject(_):
        raise ValueError("business_wire_nonfinite_number")
    return json.loads(raw, object_pairs_hook=_unique, parse_constant=reject)


def _scalar(value):
    return value is None or type(value) in (bool, int, str) or (
        type(value) is float and math.isfinite(value))


def validate_schema(schema):
    if (type(schema) is not dict or set(schema) != {"version", "fields", "symbols", "templates"}
            or schema["version"] != 1 or type(schema["version"]) is not int):
        raise ValueError("business_wire_schema_invalid")
    for name, limit in (("fields", 4096), ("symbols", 16384)):
        values = schema[name]
        if (type(values) is not list or not 1 <= len(values) <= limit
                or any(type(x) is not str or not x or len(x) > 256 for x in values)
                or len(set(values)) != len(values)):
            raise ValueError("business_wire_schema_ids_invalid")
    templates = schema["templates"]
    if type(templates) is not list or len(templates) > 512:
        raise ValueError("business_wire_templates_invalid")
    names = set()
    fields = set(schema["fields"])
    for template in templates:
        if (type(template) is not dict or set(template) != {"name", "defaults"}
                or type(template["name"]) is not str or not template["name"]
                or template["name"] in names or type(template["defaults"]) is not dict
                or not 1 <= len(template["defaults"]) <= 256
                or any(k not in fields or not _scalar(v) for k, v in template["defaults"].items())):
            raise ValueError("business_wire_template_invalid")
        names.add(template["name"])
    return schema


SCHEMA = validate_schema(_loads(Path(__file__).with_name("business_wire_schema.json").read_bytes()))
SCHEMA_HASH = hashlib.sha256(canonical(SCHEMA)).hexdigest()
_FIELD_IDS = {value: str(index) for index, value in enumerate(SCHEMA["fields"], 1)}
_SYMBOL_IDS = {value: index for index, value in enumerate(SCHEMA["symbols"], 1)}
_KEY_SYMBOL_IDS = {value: "@" + str(index) for value, index in _SYMBOL_IDS.items()
                   if len("@" + str(index)) < len(value.encode("utf-8"))}
_ENCODED_KEY_JSON_SIZES = {key: len(key) + 2 for key in
                           (*_FIELD_IDS.values(), *_KEY_SYMBOL_IDS.values())}


def _encoded_key_json_size(key):
    # Stored aliases are ASCII IDs; unknown keys retain exact JSON escaping.
    size = _ENCODED_KEY_JSON_SIZES.get(key)
    if size is not None:
        return size
    return len(json.encoder.encode_basestring(key).encode("utf-8"))


_SYMBOL_SAVINGS = {value: len(canonical(value)) - len(canonical([1, index]))
                   for value, index in _SYMBOL_IDS.items()}
_TEMPLATES = SCHEMA["templates"]


def _typed(value):
    # Python considers False==0; default matching must preserve JSON types.
    return type(value).__name__, canonical(value)


def _template_index():
    groups = {}
    for index, template in enumerate(_TEMPLATES, 1):
        groups.setdefault(frozenset(template["defaults"]), []).append((index, template["defaults"]))
    def indexed(keys, entries, remaining):
        if len(entries) == 1:
            return (None, entries[0])
        # A fixed-depth trie selects daily key -> actual allowance. Quotas can
        # change without scanning 40/80 candidate templates on every response.
        for discriminator in remaining:
            if discriminator not in keys:
                continue
            children = {}
            for entry in entries:
                children.setdefault(_typed(entry[1][discriminator]), []).append(entry)
            if len(children) > 1:
                following = tuple(key for key in remaining if key != discriminator)
                return (discriminator, ({value: indexed(keys, subset, following)
                                         for value, subset in children.items()}, entries[-1]))
        # Pure and persisted stat projections can differ in JSON number types.
        # A changed value keeps the same type and still selects one candidate.
        for key in sorted(keys):
            by_type = {type(defaults[key]).__name__: (index, defaults)
                       for index, defaults in entries}
            if len(by_type) > 1:
                return (("type", key), (by_type, entries[-1]))
        return (None, entries[-1])

    return {keys: indexed(keys, entries, ("key", "id", "name", "limit"))
            for keys, entries in groups.items()}


def _select_template(current, group):
    # The construction above bounds this traversal to four value selectors and
    # one type selector; it is independent of schema/row/account population.
    for _ in range(6):
        discriminator, entries = group
        if discriminator is None:
            return entries
        by_value, fallback = entries
        if type(discriminator) is tuple:
            return by_value.get(type(current[discriminator[1]]).__name__, fallback)
        group = by_value.get(_typed(current[discriminator]))
        if group is None:
            return fallback
    raise ValueError("business_wire_template_index_invalid")


_TEMPLATE_INDEX = _template_index()


def _key(key):
    if type(key) is not str:
        raise ValueError("business_wire_object_key_invalid")
    known = _FIELD_IDS.get(key) or _KEY_SYMBOL_IDS.get(key)
    return known or ("~" + key if key.startswith(("~", "@")) or _DIGITS.fullmatch(key) else key)


def _original_key(key):
    if type(key) is not str:
        raise ValueError("business_wire_object_key_invalid")
    if key.startswith("~"):
        original = key[1:]
        if not (original.startswith(("~", "@")) or _DIGITS.fullmatch(original)):
            raise ValueError("business_wire_escape_invalid")
        return original
    if key.startswith("@"):
        number = key[1:]
        if not number or number[0] == "0" or not _DIGITS.fullmatch(number) or len(number) > 5:
            raise ValueError("business_wire_symbol_key_invalid")
        index = int(number)
        if not 1 <= index <= len(SCHEMA["symbols"]):
            raise ValueError("business_wire_symbol_key_invalid")
        return SCHEMA["symbols"][index - 1]
    if _DIGITS.fullmatch(key):
        if not key or key[0] == "0" or len(key) > 4:
            raise ValueError("business_wire_field_id_invalid")
        index = int(key)
        if not 1 <= index <= len(SCHEMA["fields"]):
            raise ValueError("business_wire_field_id_invalid")
        return SCHEMA["fields"][index - 1]
    # Known fields must have their numeric encoding; reject ambiguous aliases.
    if key in _FIELD_IDS:
        raise ValueError("business_wire_field_alias_invalid")
    return key


_PACK_RETAIN_BYTES = 64 * 1024


class _EncodedEnvelope:
    """One pack call's original-writer bytes; never an account/global cache."""
    __slots__ = ("value", "raw")

    def __init__(self, value, raw):
        self.value, self.raw = value, raw


def encode(value):
    return _encode(value)


def _encode(value, *, _retain=False):
    """Return a fresh versioned envelope. Input objects are never mutated."""
    count = 0
    # Exact structural identities use already-interned child IDs, rather than
    # scanning whole repeated subtrees or trusting a cryptographic collision.
    # Python's tuple dictionary resolves its hash collisions by exact equality.
    occurrences = {}
    sizes = {}
    structural_ids = {}
    scalar_cache = {}

    def intern(signature):
        identity = structural_ids.get(signature)
        if identity is None:
            identity = len(structural_ids) + 1
            structural_ids[signature] = identity
        return identity

    def visit(current, depth):
        nonlocal count
        count += 1
        if depth > MAX_DEPTH or count > MAX_NODES:
            raise ValueError("business_wire_budget_exceeded")
        if _scalar(current):
            # Preserve -0.0 independently of 0.0 and bool independently of int.
            cache_key = (type(current), current.hex() if type(current) is float else current)
            cached = scalar_cache.get(cache_key)
            if cached is not None:
                return cached
            node = current
            if type(current) is str and _SYMBOL_SAVINGS.get(current, 0) > 0:
                node = [1, _SYMBOL_IDS[current]]
            raw = canonical(node)
            result = node, intern(("scalar", type(current).__name__, raw)), len(raw)
            scalar_cache[cache_key] = result
            return result
        if type(current) is list:
            children = [visit(child, depth + 1) for child in current]
            node = [0, *(child[0] for child in children)]
            digest = intern(("array", tuple(child[1] for child in children)))
            size = 3 + sum(child[2] + 1 for child in children)
        elif type(current) is dict:
            # Dict semantics do not depend on input insertion order. Sorting
            # only K short field names yields deterministic exact duplicates.
            # Total sorting is O(sum K log K), K is bounded by input node budget.
            children = [(key, visit(child, depth + 1)) for key, child in current.items()]
            encoded, encoded_sizes = {}, {}
            for key, child in children:
                encoded_key = _key(key)
                encoded[encoded_key] = child[0]
                encoded_sizes[encoded_key] = child[2]
            node = encoded
            size = 2 + sum(_encoded_key_json_size(key) + child_size + 2
                           for key, child_size in encoded_sizes.items()) - bool(encoded)
            group = _TEMPLATE_INDEX.get(frozenset(current))
            if group:
                entry = _select_template(current, group)
                if entry:
                    index, defaults = entry
                    patch = {_key(key): child[0] for key, child in children
                             if not (type(current[key]) is type(defaults[key]) and current[key] == defaults[key])}
                    patch_size = 2 + sum(_encoded_key_json_size(key) + encoded_sizes[key] + 2
                                         for key in patch) - bool(patch)
                    template_size = 5 + len(str(index)) + patch_size
                    if template_size < size:
                        node, size = [2, index, patch], template_size
            digest = intern(("object", tuple((key, child[1]) for key, child in
                                               sorted(children, key=lambda entry: entry[0]))))
        else:
            raise ValueError("business_wire_value_invalid")
        occurrences[digest] = occurrences.get(digest, 0) + 1
        sizes[id(node)] = (digest, size)
        return node, digest, size

    root, _, _ = visit(value, 0)
    references = {}
    serial = 0

    def refs(node, depth):
        nonlocal serial
        metadata = sizes.get(id(node)) if type(node) in (dict, list) else None
        definition = None
        if metadata:
            digest, size = metadata
            repeats = occurrences[digest]
            # Child-intern identity lookup is O(1) expected, with no recursive
            # equality or all-bucket scan for each occurrence.
            entry = references.get(digest)
            if entry is not None:
                return [3, entry]
            if repeats > 1 and serial < MAX_REFS and size >= 32:
                candidate_id = serial + 1
                definition_cost = 5 + len(str(candidate_id))
                reference_size = 4 + len(str(candidate_id))
                if (repeats - 1) * (size - reference_size) > definition_cost:
                    serial = candidate_id
                    definition = serial
        if type(node) is dict:
            # JSON object iteration order is not portable (notably Lua pairs).
            # Definition/reference order is defined by encoded-key UTF-8 order.
            result = {key: refs(node[key], depth + 1) for key in sorted(node)}
        elif type(node) is list:
            # Every encoded list is a protocol tag; only actual child nodes
            # recurse. Template patches are plain encoded object dictionaries.
            if node[0] == 0:
                result = [0, *(refs(child, depth + 1) for child in node[1:])]
            elif node[0] == 2:
                result = [2, node[1], refs(node[2], depth + 1)]
            else:
                result = list(node)
        else:
            result = node
        if definition is not None:
            # A parent definition is registered only after its child definitions
            # are complete. Definitions cannot form cycles or forward refs.
            references[metadata[0]] = definition
            return [4, definition, result]
        return result

    result = {MARKER: [1, SCHEMA_HASH, refs(root, 0)]}
    # Nested repeats can become unreachable when an ancestor itself is reused.
    # Compare the finished alternatives so incidental child definitions cannot
    # make the final representation larger than the no-reference candidate.
    baseline = {MARKER: [1, SCHEMA_HASH, root]}
    result_bytes = canonical(result)
    result_size = len(result_bytes)
    retained = result_bytes if _retain and result_size <= _PACK_RETAIN_BYTES else None
    del result_bytes
    baseline_bytes = canonical(baseline)
    baseline_size = len(baseline_bytes)
    if baseline_size <= result_size:
        result, result_size = baseline, baseline_size
        retained = baseline_bytes if _retain and baseline_size <= _PACK_RETAIN_BYTES else None
    del baseline_bytes
    if result_size > MAX_BYTES:
        raise ValueError("business_wire_output_budget_exceeded")
    return _EncodedEnvelope(result, retained) if _retain else result


def decode(value):
    return _decode(value)


def _decode(value, *, _writer=None):
    """Public decode recomputes; only pack's exact writer can reuse its bytes."""
    if (type(_writer) is _EncodedEnvelope and _writer.value is value
            and _writer.raw is not None):
        input_size = len(_writer.raw)
    else:
        input_size = len(canonical(value))
    if input_size > MAX_BYTES:
        raise ValueError("business_wire_input_budget_exceeded")
    if (type(value) is not dict or set(value) != {MARKER}
            or type(value[MARKER]) is not list or len(value[MARKER]) != 3
            or type(value[MARKER][0]) is not int or value[MARKER][0] != 1
            or value[MARKER][1] != SCHEMA_HASH):
        raise ValueError("business_wire_envelope_invalid")
    count = 0
    references = {}
    defining = set()

    def budget(depth):
        nonlocal count
        count += 1
        if depth > MAX_DEPTH or count > MAX_NODES:
            raise ValueError("business_wire_budget_exceeded")

    def copy_reference(current, depth):
        budget(depth)
        if type(current) is dict:
            return {key: copy_reference(child, depth + 1) for key, child in current.items()}
        if type(current) is list:
            return [copy_reference(child, depth + 1) for child in current]
        return current

    def object_fields(node, depth):
        result = {}
        for key in sorted(node):
            child = node[key]
            original = _original_key(key)
            if original in result:
                raise ValueError("business_wire_field_collision")
            result[original] = visit(child, depth + 1)
        return result

    def integer_id(value, limit):
        if type(value) is not int or not 1 <= value <= limit:
            raise ValueError("business_wire_id_invalid")
        return value

    def visit(node, depth):
        budget(depth)
        if _scalar(node):
            return node
        if type(node) is dict:
            return object_fields(node, depth)
        if type(node) is not list or not node or type(node[0]) is not int:
            raise ValueError("business_wire_node_invalid")
        tag = node[0]
        if tag == 0:
            return [visit(child, depth + 1) for child in node[1:]]
        if tag == 1 and len(node) == 2:
            return SCHEMA["symbols"][integer_id(node[1], len(SCHEMA["symbols"])) - 1]
        if tag == 2 and len(node) == 3 and type(node[2]) is dict:
            defaults = _TEMPLATES[integer_id(node[1], len(_TEMPLATES)) - 1]["defaults"]
            patch = object_fields(node[2], depth)
            if set(patch) - set(defaults):
                raise ValueError("business_wire_template_patch_invalid")
            result = copy_reference(defaults, depth)
            result.update(patch)
            return result
        if tag == 3 and len(node) == 2:
            identity = integer_id(node[1], MAX_REFS)
            if identity not in references:
                raise ValueError("business_wire_reference_unknown")
            return copy_reference(references[identity], depth)
        if tag == 4 and len(node) == 3:
            identity = integer_id(node[1], MAX_REFS)
            if identity in references or identity in defining or len(references) + len(defining) >= MAX_REFS:
                raise ValueError("business_wire_reference_duplicate")
            defining.add(identity)
            result = visit(node[2], depth + 1)
            defining.remove(identity)
            references[identity] = result
            return result
        raise ValueError("business_wire_tag_invalid")

    result = visit(value[MARKER][2], 0)
    # Expansion (including reference copies) is bounded independently of input.
    if len(canonical(result)) > MAX_BYTES:
        raise ValueError("business_wire_expansion_budget_exceeded")
    return result


def pack_bytes(body, advertised_hash):
    """Return original bytes unless exact negotiation and a smaller valid pack.

    A transport failure must not turn a committed reward into a failed business
    transaction. This function never retries or modifies a business request.
    """
    if (type(body) is not bytes or len(body) > MAX_BYTES
            or type(advertised_hash) is not str or advertised_hash != SCHEMA_HASH):
        return body
    try:
        value = _loads(body)
        if type(value) is not dict or MARKER in value:
            return body
        writer = _encode(value, _retain=True)
        envelope = writer.value
        # An optional pack must never produce a representation that exceeds
        # the consumer's expansion/depth budget. This one local pass also
        # verifies exact default types and reference reconstruction.
        if canonical(_decode(envelope, _writer=writer)) != canonical(value):
            return body
        packed = writer.raw if writer.raw is not None else canonical(envelope)
        return packed if len(packed) < len(body) else body
    except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError):
        return body
