const fs = require('node:fs'), zlib = require('node:zlib'), assert = require('node:assert/strict');
const {build, alphaAt} = require('./build_grid_mask.cjs');
const file = 'panorama/src/images/custom_game/survival_grid/range_mask.png';
const png = fs.readFileSync(file);
assert.deepEqual(png, build(), 'checked-in mask must match the deterministic build');
const chunks = [];
let width, height;
for (let offset = 8; offset < png.length;) {
    const size = png.readUInt32BE(offset), kind = png.toString('ascii', offset + 4, offset + 8);
    const data = png.subarray(offset + 8, offset + 8 + size);
    if (kind === 'IHDR') {
        width = data.readUInt32BE(0); height = data.readUInt32BE(4);
        assert.equal(data[8], 8); assert.equal(data[9], 6, 'opacity mask requires RGBA alpha');
    }
    if (kind === 'IDAT') chunks.push(data);
    offset += size + 12;
}
const pixels = zlib.inflateSync(Buffer.concat(chunks));
assert.equal(pixels.length, height * (width * 4 + 1));
const alpha = (x, y) => pixels[y * (width * 4 + 1) + 1 + x * 4 + 3];
assert.equal(alpha(256, 256), 255, 'center must reveal the white grid');
assert.equal(alpha(0, 256), 0); assert.equal(alpha(511, 511), 0);
assert.equal(alpha(420, 256), 255, 'large perspective circles must retain a readable interior');
assert(alpha(475, 256) > 0 && alpha(475, 256) < 255, 'edge must feather, not binary clip');
for (let x = 257; x < width; x++) assert(alpha(x, 256) <= alpha(x - 1, 256));
for (let y = 0; y < height; y += 17) for (let x = 0; x < width; x += 17) {
    assert.equal(alpha(x,y), alpha(width - 1 - x,y));
    assert.equal(alpha(x,y), alpha(x,height - 1 - y));
}
assert.equal(alphaAt(1, 0), 0);
const css = fs.readFileSync('panorama/src/styles/custom_game/survival_grid_placement.css', 'utf8');
assert(css.includes('opacity-mask: url("file://{images}/custom_game/survival_grid/range_mask.png")'),
    'use a native texture for opacity-mask, never the SVG that hid the complete subtree');
console.log('GRID_MASK_PASS: deterministic RGBA / opaque center / symmetric monotonic feather / texture reference');
