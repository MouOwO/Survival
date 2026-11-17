"""Opt-in BW2 data-only binary frame over the existing lossless BW1 tree.

Cold: reuse O(schema) immutable BW1 indexes; no account cache. Per changed reply:
O(B + N + sum(K log K)) extra time and O(B+N) space over BW1, for K
fields per object (including UTF-8/base64 and equality checks).
Idle: zero work. No timers, scene/native/network/DB calls. Input/output <=8MiB,
nodes<=100000, depth<=64; original BW1 expansion/reference checks still apply.
The JSON/base64 transport is deliberate: raw Dota HTTP byte safety is unproven.
"""
from __future__ import annotations
import base64
import math
import struct
from . import business_wire as bw

MAGIC = b"BW\x02"
MARKER = "_bb"
ADVERTISEMENT = bw.SCHEMA_HASH + ";b2"
MAX_INT = 2**53 - 1  # exact in the Lua client; larger values retain BW1
_PREFIX = MAGIC + bytes.fromhex(bw.SCHEMA_HASH)
_FIELDS = frozenset(bw._FIELD_IDS.values())
_SYMBOL_KEYS = frozenset(bw._KEY_SYMBOL_IDS.values())


def _need(ok):
    if not ok:
        raise ValueError("business_binary_invalid")


def _uint(value, output):
    _need(type(value) is int and 0 <= value <= MAX_INT)
    while value >= 128:
        output.append((value & 127) | 128)
        value >>= 7
    output.append(value)


def _tree_bytes(root):
    output = bytearray(_PREFIX)
    nodes = 0
    strings = {}

    def room(size):
        _need(size <= bw.MAX_BYTES - len(output))

    def text(value):
        identity = strings.get(value)
        if identity is not None:
            output.append(13)
            _uint(identity, output)
            return
        raw = value.encode("utf-8")
        room(len(raw) + 9)
        output.append(5)
        _uint(len(raw), output)
        output.extend(raw)
        if len(raw) >= 8 and len(strings) < bw.MAX_REFS:
            strings[value] = len(strings) + 1

    def fields(value, depth):
        _uint(len(value), output)
        for key in sorted(value):
            if key in _FIELDS:
                _uint(int(key) * 4, output)
            elif key in _SYMBOL_KEYS:
                _uint(int(key[1:]) * 4 + 1, output)
            else:
                raw = key.encode("utf-8")
                room(len(raw) + 8)
                _uint(len(raw) * 4 + 2, output)
                output.extend(raw)
            visit(value[key], depth + 1)

    def visit(value, depth):
        nonlocal nodes
        nodes += 1
        _need(nodes <= bw.MAX_NODES and depth <= bw.MAX_DEPTH)
        room(16)
        kind = type(value)
        if value is None:
            output.append(0)
        elif kind is bool:
            output.append(2 if value else 1)
        elif kind is int:
            _need(-MAX_INT <= value <= MAX_INT)
            if 0 <= value <= 223:
                output.append(32 + value)
            else:
                output.append(3 if value >= 0 else 12)
                _uint(abs(value), output)
        elif kind is float:
            _need(math.isfinite(value))
            output.append(4)
            output.extend(struct.pack("<d", value))
        elif kind is str:
            text(value)
        elif kind is dict:
            output.append(6)
            fields(value, depth)
        elif kind is list:
            _need(value and type(value[0]) is int)
            tag = value[0]
            if tag == 0:
                output.append(7)
                _uint(len(value) - 1, output)
                for child in value[1:]:
                    visit(child, depth + 1)
            elif tag in (1, 3) and len(value) == 2:
                output.append(8 if tag == 1 else 10)
                _uint(value[1], output)
            elif tag == 2 and len(value) == 3 and type(value[2]) is dict:
                output.append(9)
                _uint(value[1], output)
                fields(value[2], depth + 1)
            elif tag == 4 and len(value) == 3:
                output.append(11)
                _uint(value[1], output)
                visit(value[2], depth + 1)
            else:
                _need(False)
        else:
            _need(False)
    visit(root, 0)
    _need(len(output) <= bw.MAX_BYTES)
    return bytes(output)


def to_envelope(raw):
    _need(type(raw) is bytes and len(_PREFIX) < len(raw) <= bw.MAX_BYTES
          and raw.startswith(_PREFIX))
    offset, nodes = len(_PREFIX), 0
    strings = []

    def take(size):
        nonlocal offset
        _need(0 <= size <= len(raw) - offset)
        value = raw[offset:offset + size]
        offset += size
        return value

    def uint():
        value = 0
        for shift in range(0, 56, 7):
            byte = take(1)[0]
            value |= (byte & 127) << shift
            if byte < 128:
                _need((shift == 0 or byte != 0) and value <= MAX_INT)
                return value
        _need(False)

    def text(size=None):
        size = uint() if size is None else size
        _need(size <= bw.MAX_BYTES)
        return take(size).decode("utf-8", errors="strict")

    def fields(depth):
        count = uint()
        _need(count <= bw.MAX_NODES - nodes)
        result = {}
        for _ in range(count):
            key = uint()
            mode, identity = key & 3, key >> 2
            if mode == 0:
                _need(str(identity) in _FIELDS)
                name = str(identity)
            elif mode == 1:
                name = "@" + str(identity)
                _need(name in _SYMBOL_KEYS)
            else:
                _need(mode == 2)
                name = text(identity)
            _need(name not in result)
            result[name] = visit(depth + 1)
        return result

    def visit(depth):
        nonlocal nodes
        nodes += 1
        _need(nodes <= bw.MAX_NODES and depth <= bw.MAX_DEPTH)
        tag = take(1)[0]
        if tag >= 32:
            return tag - 32
        if tag == 0:
            return None
        if tag in (1, 2):
            return tag == 2
        if tag in (3, 12):
            number = uint()
            _need(tag == 3 or number > 0)
            return number if tag == 3 else -number
        if tag == 4:
            number = struct.unpack("<d", take(8))[0]
            _need(math.isfinite(number))
            return number
        if tag == 5:
            length = uint()
            value = text(length)
            if length >= 8 and len(strings) < bw.MAX_REFS:
                strings.append(value)
            return value
        if tag == 13:
            identity = uint()
            _need(1 <= identity <= len(strings))
            return strings[identity - 1]
        if tag == 6:
            return fields(depth)
        if tag == 7:
            length = uint()
            _need(length <= bw.MAX_NODES - nodes)
            return [0, *(visit(depth + 1) for _ in range(length))]
        if tag in (8, 10):
            return [1 if tag == 8 else 3, uint()]
        if tag == 9:
            identity = uint()
            return [2, identity, fields(depth + 1)]
        if tag == 11:
            identity = uint()
            return [4, identity, visit(depth + 1)]
        _need(False)

    root = visit(0)
    _need(offset == len(raw))
    return {bw.MARKER: [1, bw.SCHEMA_HASH, root]}


def encode(value):
    return _tree_bytes(bw.encode(value)[bw.MARKER][2])


def decode(raw):
    return bw.decode(to_envelope(raw))


def unwrap(value):
    _need(type(value) is dict and set(value) == {MARKER})
    text = value[MARKER]
    _need(type(text) is str and len(text) <= 4 * ((bw.MAX_BYTES + 2) // 3))
    raw = base64.b64decode(text, validate=True)
    _need(base64.b64encode(raw).decode("ascii") == text)
    return to_envelope(raw)


def pack_decoded_bytes(body, value, advertised):
    """Choose actual JSON/base64 or BW1 bytes, never raw-size-only savings."""
    if (advertised != ADVERTISEMENT or type(body) is not bytes
            or len(body) > bw.MAX_BYTES or type(value) is not dict
            or bw.MARKER in value or MARKER in value):
        return body
    # Even an empty object requires 35-byte header + 2-byte tree + base64/JSON.
    if len(body) <= 62:
        return body
    try:
        writer = bw._encode(value, _retain=True)
        envelope = writer.value
        legacy = writer.raw if writer.raw is not None else bw.canonical(envelope)
        best = legacy if len(legacy) < len(body) else body
        try:
            raw = _tree_bytes(envelope[bw.MARKER][2])
            packed = bw.canonical({MARKER: base64.b64encode(raw).decode("ascii")})
            if len(packed) < len(best):
                _need(bw.canonical(decode(raw)) == bw.canonical(value))
                return packed
        except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError):
            pass
        _need(bw.canonical(bw._decode(envelope, _writer=writer)) == bw.canonical(value))
        return best
    except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError):
        return body
