// Deterministic opacity texture; no runtime rasterization or image dependencies.
// Panorama draws SVG backgrounds, but an SVG used as an opacity-mask can make
// the whole subtree transparent. Supply an ordinary compiled RGBA texture.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const SIZE = 512;
function alphaAt(x, y) {
    const radius = Math.hypot(x, y);
    // A world circle's perspective ellipse has a screen center displaced from
    // the projected mouse. Keep its interior opaque; feather only the rim.
    const t = Math.max(0, Math.min(1, (1 - radius) / (1 - 0.75)));
    const smooth = t * t * (3 - 2 * t);
    return Math.round(255 * smooth);
}
function crc32(data) {
    let crc = 0xffffffff;
    for (const byte of data) {
        crc ^= byte;
        for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, body) {
    const name = Buffer.from(type), header = Buffer.alloc(4), crc = Buffer.alloc(4);
    header.writeUInt32BE(body.length);
    crc.writeUInt32BE(crc32(Buffer.concat([name, body])));
    return Buffer.concat([header, name, body, crc]);
}
function build() {
    const rows = Buffer.alloc(SIZE * (1 + SIZE * 4));
    for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
        const i = y * (1 + SIZE * 4) + 1 + x * 4;
        rows[i] = rows[i + 1] = rows[i + 2] = 255;
        rows[i + 3] = alphaAt((x + 0.5 - SIZE / 2) / (SIZE / 2), (y + 0.5 - SIZE / 2) / (SIZE / 2));
    }
    const header = Buffer.alloc(13);
    header.writeUInt32BE(SIZE, 0); header.writeUInt32BE(SIZE, 4);
    header[8] = 8; header[9] = 6; // 8-bit RGBA, no interlace.
    return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header),
        chunk('IDAT', zlib.deflateSync(rows, {level:9})), chunk('IEND', Buffer.alloc(0))]);
}
if (require.main === module) {
    const target = path.resolve(__dirname, '../panorama/src/images/custom_game/survival_grid/range_mask.png');
    fs.writeFileSync(target, build());
    console.log('GRID_MASK_BUILT: 512 x 512 RGBA, opaque center / feathered transparent edge');
}
module.exports = {alphaAt, build};
