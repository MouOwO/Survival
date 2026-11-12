-- RFC 8439 ChaCha20 for PUBLIC, signed local configuration only.
-- The packaged key is deliberately local-readable: this is encrypted storage,
-- not a secret from the player. Authenticity comes from the release manifest.
-- No executable plaintext, loadstring, gameplay RNG, IO, timers or native calls.
-- One require decrypts O(B/64 * 20) work / O(B) space, B <= 256 KiB; idle O(1).
local M = {}
local floor, char, byte = math.floor, string.char, string.byte
local MOD, MAX_BYTES = 4294967296, 262144

-- Native bit operations are optional. A 256-entry nibble table keeps the Lua
-- 5.1 fallback bounded, without a 65,536-entry byte table or foreign modules.
local native = rawget(_G, 'bit') or rawget(_G, 'bit32')
local xor
if type(native) == 'table' and type(native.bxor) == 'function' then
    xor = function(a, b) return native.bxor(a, b) % MOD end
else
    local nibbles = {}
    for a = 0, 15 do
        for b = 0, 15 do
            local x, y, result, weight = a, b, 0, 1
            for _ = 1, 4 do
                if x % 2 ~= y % 2 then result = result + weight end
                x, y, weight = floor(x / 2), floor(y / 2), weight * 2
            end
            nibbles[a * 16 + b] = result
        end
    end
    xor = function(a, b)
        local result, weight = 0, 1
        for _ = 1, 8 do
            result = result + nibbles[(a % 16) * 16 + b % 16] * weight
            a, b, weight = floor(a / 16), floor(b / 16), weight * 16
        end
        return result
    end
end

local function rotate(value, bits)
    local high = 2 ^ (32 - bits)
    return (value % high) * 2 ^ bits + floor(value / high)
end

local function quarter(state, a, b, c, d)
    state[a] = (state[a] + state[b]) % MOD
    state[d] = rotate(xor(state[d], state[a]), 16)
    state[c] = (state[c] + state[d]) % MOD
    state[b] = rotate(xor(state[b], state[c]), 12)
    state[a] = (state[a] + state[b]) % MOD
    state[d] = rotate(xor(state[d], state[a]), 8)
    state[c] = (state[c] + state[d]) % MOD
    state[b] = rotate(xor(state[b], state[c]), 7)
end

local function unhex(value, expected)
    if type(value) ~= 'string' or #value % 2 ~= 0
        or (expected and #value ~= expected * 2)
        or #value > MAX_BYTES * 2 or value:find('[^0-9a-f]') then
        error('local_config_cipher_invalid_hex', 0)
    end
    return (value:gsub('..', function(pair) return char(tonumber(pair, 16)) end))
end

local function word(value, offset)
    return byte(value, offset) + byte(value, offset + 1) * 256
        + byte(value, offset + 2) * 65536 + byte(value, offset + 3) * 16777216
end

function M.decrypt_hex(ciphertext, key_hex, nonce_hex, counter)
    local input = unhex(ciphertext)
    local key, nonce = unhex(key_hex, 32), unhex(nonce_hex, 12)
    counter = counter == nil and 1 or counter
    if type(counter) ~= 'number' or counter ~= floor(counter) or counter < 0
        or counter >= MOD or counter + math.ceil(#input / 64) > MOD then
        error('local_config_cipher_invalid_counter', 0)
    end
    local initial = { 1634760805, 857760878, 2036477234, 1797285236 }
    for index = 1, 8 do initial[index + 4] = word(key, (index - 1) * 4 + 1) end
    initial[14], initial[15], initial[16] = word(nonce, 1), word(nonce, 5), word(nonce, 9)
    local blocks = {}
    for offset = 1, #input, 64 do
        initial[13] = counter
        local state = {}
        for index = 1, 16 do state[index] = initial[index] end
        for _ = 1, 10 do
            quarter(state, 1, 5, 9, 13); quarter(state, 2, 6, 10, 14)
            quarter(state, 3, 7, 11, 15); quarter(state, 4, 8, 12, 16)
            quarter(state, 1, 6, 11, 16); quarter(state, 2, 7, 12, 13)
            quarter(state, 3, 8, 9, 14); quarter(state, 4, 5, 10, 15)
        end
        local out, position = {}, offset
        for index = 1, 16 do
            local value = (state[index] + initial[index]) % MOD
            for _ = 1, 4 do
                if position <= #input and position < offset + 64 then
                    out[#out + 1] = char(xor(byte(input, position), value % 256))
                    position = position + 1
                end
                value = floor(value / 256)
            end
        end
        blocks[#blocks + 1] = table.concat(out)
        counter = counter + 1
    end
    return table.concat(blocks)
end

function M.catalog(ciphertext, key, nonce, expected_hash)
    if type(expected_hash) ~= 'string' or #expected_hash ~= 64
        or expected_hash:find('[^0-9a-f]') then error('local_config_cipher_invalid_hash', 0) end
    local plaintext = M.decrypt_hex(ciphertext, key, nonce, 1)
    local value = require('core/json_decoder').decode(plaintext)
    if type(value) ~= 'table' or value.hash ~= expected_hash or type(value.schema) ~= 'table' then
        error('local_config_cipher_catalog_invalid', 0)
    end
    return value
end

return M
