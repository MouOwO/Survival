"""Read exception metadata from a Windows minidump; no private symbols required.
Stack code pointers are candidates, not an unwound/symbolized call stack.
"""
import argparse
import json
import struct
from pathlib import Path, PureWindowsPath


def inspect(path):
    data = path.read_bytes()
    if data[:4] != b'MDMP':
        raise ValueError('Not a Windows minidump')
    count, directory = struct.unpack_from('<II', data, 8)
    streams = {}
    for i in range(count):
        kind, size, offset = struct.unpack_from('<III', data, directory + i * 12)
        streams[kind] = (size, offset)
    modules = []
    if 4 in streams:
        offset = streams[4][1]
        for i in range(struct.unpack_from('<I', data, offset)[0]):
            base, size, _, _, name = struct.unpack_from('<QIIII', data, offset + 4 + i * 108)
            length = struct.unpack_from('<I', data, name)[0]
            name = data[name + 4:name + 4 + length].decode('utf-16le')
            modules.append((base, size, PureWindowsPath(name).name))

    def location(address):
        for base, size, name in modules:
            if base <= address < base + size:
                return f'{name}+0x{address - base:x}'
        return None

    result = {'file': path.name}
    if 6 not in streams:
        return result
    offset = streams[6][1]
    thread = struct.unpack_from('<I', data, offset)[0]
    code, _, _, address, count = struct.unpack_from('<IIQQI', data, offset + 8)
    params = struct.unpack_from('<15Q', data, offset + 40)[:min(count, 15)]
    result.update(thread_id=thread, exception_code=hex(code), fault=location(address),
                  exception_parameters=[hex(v) for v in params])
    if code == 0xc0000005 and len(params) >= 2:
        result.update(access={0: 'read', 1: 'write', 8: 'execute'}.get(params[0], 'unknown'),
                      target_address=hex(params[1]))
    # CONTEXT offsets below are only defined for AMD64.
    if 7 not in streams or struct.unpack_from('<H', data, streams[7][1])[0] != 9:
        return result
    size, context = struct.unpack_from('<II', data, offset + 160)
    if size < 256:
        return result
    names = ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi',
             'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15', 'rip']
    registers = dict(zip(names, struct.unpack_from('<17Q', data, context + 120)))
    result['registers'] = {k: hex(v) for k, v in registers.items()}
    result['stack_code_pointer_candidates'] = []
    if 3 in streams:
        offset = streams[3][1]
        for i in range(struct.unpack_from('<I', data, offset)[0]):
            entry = offset + 4 + i * 48
            if struct.unpack_from('<I', data, entry)[0] != thread:
                continue
            start, size, source = struct.unpack_from('<QII', data, entry + 24)
            begin = max(0, registers['rsp'] - start)
            for j in range(begin, min(size - 7, begin + 1400), 8):
                candidate = location(struct.unpack_from('<Q', data, source + j)[0])
                if candidate:
                    result['stack_code_pointer_candidates'].append({
                        'rsp_offset': hex(start + j - registers['rsp']), 'code': candidate})
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dumps', nargs='+', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = json.dumps([inspect(p) for p in args.dumps], indent=2, ensure_ascii=False)
    if args.output:
        args.output.write_text(report + '\n', encoding='utf-8')
    else:
        print(report)
