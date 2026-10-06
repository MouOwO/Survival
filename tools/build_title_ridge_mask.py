"""Bake the mountain silhouette that lets the real dragon wrap the peak.

The ascent draws one dragon copy behind the mountains (so only the part above
the ridge shows) and one in front masked by this silhouette. The two copies tile
each other exactly, which reads as a body passing behind the rock instead of a
flat sticker sliding over it.

The mask is emitted at the panel's own 224x96 aspect with the mountain
letterboxed exactly the way the runtime letterboxes it, so stretch-to-fill
aligns without depending on mask sizing behaviour.

Run from the addon root:  python tools/build_title_ridge_mask.py
"""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/ui/sources/custom_game/titles/peak_mountain_clean/mountains.png"
MASTER = SOURCE.with_name("ridge.png")
RUNTIME = ROOT / "panorama/src/images/custom_game/titles/peak_clean_ridge.png"

PANEL_WIDTH, PANEL_HEIGHT = 224.0, 96.0
OUT_WIDTH, OUT_HEIGHT = 672, 288
SUPERSAMPLE = 2


def decode_alpha(path):
    """Decode an 8-bit PNG far enough to read its alpha channel."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError("not a PNG: " + str(path))
    position, chunks, header = 8, [], None
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            chunks.append(payload)
        elif kind == b"IEND":
            break
        position += 12 + length
    width, height, depth, colour, _, _, interlace = header
    if interlace or depth != 8 or colour != 6:
        raise RuntimeError("expected non-interlaced 8-bit RGBA, got depth %d colour %d" % (depth, colour))
    raw = zlib.decompress(b"".join(chunks))
    stride = width * 4
    out = bytearray(height * stride)
    previous = bytearray(stride)
    cursor = 0
    for row in range(height):
        filter_type = raw[cursor]
        cursor += 1
        line = bytearray(raw[cursor:cursor + stride])
        cursor += stride
        if filter_type == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 255
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif filter_type == 4:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                up = previous[i]
                corner = previous[i - 4] if i >= 4 else 0
                pa, pb, pc = abs(up - corner), abs(left - corner), abs(left + up - 2 * corner)
                guess = left if (pa <= pb and pa <= pc) else (up if pb <= pc else corner)
                line[i] = (line[i] + guess) & 255
        elif filter_type != 0:
            raise RuntimeError("unknown PNG filter %d" % filter_type)
        out[row * stride:(row + 1) * stride] = line
        previous = line
    return width, height, bytes(out[3::4])


def write_rgba(path, width, height, alpha):
    raw = bytearray()
    for row in range(height):
        raw.append(0)
        for column in range(width):
            raw += bytes((255, 255, 255, alpha[row * width + column]))
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                     + chunk(b"IEND", b""))


def main():
    width, height, alpha = decode_alpha(SOURCE)
    scale = min(PANEL_WIDTH / width, PANEL_HEIGHT / height)
    offset_x = (PANEL_WIDTH - width * scale) / 2.0
    offset_y = (PANEL_HEIGHT - height * scale) / 2.0

    def source_at(pixel_x, pixel_y):
        image_x = (pixel_x - offset_x) / scale
        image_y = (pixel_y - offset_y) / scale
        if image_x < 0 or image_y < 0 or image_x >= width - 1 or image_y >= height - 1:
            return 0.0
        x0, y0 = int(image_x), int(image_y)
        fx, fy = image_x - x0, image_y - y0
        top = alpha[y0 * width + x0] * (1 - fx) + alpha[y0 * width + x0 + 1] * fx
        bottom = alpha[(y0 + 1) * width + x0] * (1 - fx) + alpha[(y0 + 1) * width + x0 + 1] * fx
        return top * (1 - fy) + bottom * fy

    baked = bytearray(OUT_WIDTH * OUT_HEIGHT)
    step = 1.0 / SUPERSAMPLE
    for row in range(OUT_HEIGHT):
        for column in range(OUT_WIDTH):
            total = 0.0
            for sub_y in range(SUPERSAMPLE):
                pixel_y = (row + (sub_y + 0.5) * step) / OUT_HEIGHT * PANEL_HEIGHT
                for sub_x in range(SUPERSAMPLE):
                    pixel_x = (column + (sub_x + 0.5) * step) / OUT_WIDTH * PANEL_WIDTH
                    total += source_at(pixel_x, pixel_y)
            baked[row * OUT_WIDTH + column] = int(round(total / (SUPERSAMPLE * SUPERSAMPLE)))

    covered = sum(1 for value in baked if value > 24)
    fraction = 100.0 * covered / len(baked)
    if not 25.0 < fraction < 70.0:
        raise RuntimeError("silhouette covers %.1f%% of the panel; expected a mountain" % fraction)

    write_rgba(MASTER, OUT_WIDTH, OUT_HEIGHT, baked)
    write_rgba(RUNTIME, OUT_WIDTH, OUT_HEIGHT, baked)
    print("Ridge mask baked: %dx%d, silhouette covers %.1f%%" % (OUT_WIDTH, OUT_HEIGHT, fraction))
    print("  master  " + str(MASTER.relative_to(ROOT)))
    print("  runtime " + str(RUNTIME.relative_to(ROOT)))


if __name__ == "__main__":
    main()
