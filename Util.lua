-- Tables, a safe serializer (no code is ever run on import), LZW
-- compression and a base64 text encoding for the export strings.
--
-- Export string: "!PF1!" .. base64(lzw(adler32 .. ":" .. serialized)) .. "!"
local _, PF = ...

local U = {}
PF.Util = U

local floor, byte, char, sub = math.floor, string.byte, string.char, string.sub

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
function U.Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[U.Copy(k, seen)] = U.Copy(v, seen) end
    return out
end

-- Fills what target lacks from defaults (deeply); never overwrites
function U.Defaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = U.Copy(v)
        elseif type(v) == "table" and type(target[k]) == "table" and not v[1] then
            U.Defaults(target[k], v)
        end
    end
    return target
end

function U.Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end
U.SortedKeys = SortedKeys

-- The leaf paths that differ between two tables ("buttons.PAD1.mode"), at
-- most `limit` of them
function U.Diff(a, b, limit)
    local out = {}
    limit = limit or 200
    local function walk(x, y, path)
        if #out >= limit then return end
        if type(x) == "table" and type(y) == "table" then
            local keys = {}
            for k in pairs(x) do keys[k] = true end
            for k in pairs(y) do keys[k] = true end
            for _, k in ipairs(SortedKeys(keys)) do
                walk(x[k], y[k], path == "" and tostring(k) or (path .. "." .. tostring(k)))
            end
        elseif x ~= y then
            out[#out + 1] = path
        end
    end
    walk(a, b, "")
    return out
end

---------------------------------------------------------------------------
-- Serializer: typed tokens, strings length-prefixed (no escaping), keys in
-- a stable order. Only strings, numbers, booleans and tables.
--   ^S<len>:<bytes>  ^N<number>;  ^B (true)  ^b (false)  ^T ... ^t
---------------------------------------------------------------------------
local MAX_DEPTH = 40

local function SerializeValue(value, out, depth)
    local t = type(value)
    if t == "string" then
        out[#out + 1] = "^S" .. #value .. ":" .. value
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("can't serialize " .. tostring(value))
        end
        if value == floor(value) and value > -1e15 and value < 1e15 then
            out[#out + 1] = string.format("^N%d;", value)
        else
            out[#out + 1] = string.format("^N%.17g;", value)
        end
    elseif t == "boolean" then
        out[#out + 1] = value and "^B" or "^b"
    elseif t == "table" then
        if depth > MAX_DEPTH then error("table too deep") end
        out[#out + 1] = "^T"
        for _, k in ipairs(SortedKeys(value)) do
            local v = value[k]
            local kt, vt = type(k), type(v)
            if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                SerializeValue(k, out, depth + 1)
                SerializeValue(v, out, depth + 1)
            end
        end
        out[#out + 1] = "^t"
    else
        error("can't serialize a " .. t)
    end
end

function U.Serialize(value)
    local out = {}
    SerializeValue(value, out, 0)
    return table.concat(out)
end

-- Returns value, or nil and why
function U.Deserialize(text)
    if type(text) ~= "string" then return nil, "not text" end
    local pos, len = 1, #text

    local function fail(why) error({ why = why }, 0) end

    local readValue
    readValue = function(depth)
        if depth > MAX_DEPTH then fail("too deep") end
        if sub(text, pos, pos) ~= "^" then fail("bad token at " .. pos) end
        local tag = sub(text, pos + 1, pos + 1)
        pos = pos + 2
        if tag == "S" then
            local colon = text:find(":", pos, true)
            if not colon then fail("bad string") end
            local n = tonumber(sub(text, pos, colon - 1))
            if not n or n < 0 or colon + n > len then fail("bad string length") end
            local s = sub(text, colon + 1, colon + n)
            pos = colon + n + 1
            return s
        elseif tag == "N" then
            local semi = text:find(";", pos, true)
            if not semi then fail("bad number") end
            local n = tonumber(sub(text, pos, semi - 1))
            if not n then fail("bad number") end
            pos = semi + 1
            return n
        elseif tag == "B" then
            return true
        elseif tag == "b" then
            return false
        elseif tag == "T" then
            local t = {}
            while true do
                if pos > len then fail("unfinished table") end
                if sub(text, pos, pos + 1) == "^t" then
                    pos = pos + 2
                    return t
                end
                local k = readValue(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then fail("bad key") end
                t[k] = readValue(depth + 1)
            end
        end
        fail("unknown token " .. tag)
    end

    local ok, result = pcall(readValue, 0)
    if not ok then
        return nil, type(result) == "table" and result.why or tostring(result)
    end
    if pos <= len then return nil, "trailing data" end
    return result
end

---------------------------------------------------------------------------
-- Adler-32 (arithmetic only: no bit library needed)
---------------------------------------------------------------------------
function U.Checksum(text)
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + byte(text, i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

---------------------------------------------------------------------------
-- LZW straight into a base64 bit stream. The code width grows with the
-- dictionary: the i-th code is written with the bits its dictionary size
-- then needs, so the decoder knows each width from the count alone.
---------------------------------------------------------------------------
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local c = sub(ALPHABET, i, i)
    ENC[i - 1] = c
    DEC[byte(c)] = i - 1
end

local MAX_DICT = 65536
local POW = {}
for i = 0, 30 do POW[i] = 2 ^ i end

local function Width(size)
    local w = 1
    while POW[w] < size do w = w + 1 end
    return w
end

function U.Compress(text)
    local out, n = {}, 0
    local acc, bits = 0, 0
    local function put(code, width)
        acc = acc * POW[width] + code
        bits = bits + width
        while bits >= 6 do
            local shift = bits - 6
            local c = floor(acc / POW[shift])
            acc = acc - c * POW[shift]
            bits = shift
            n = n + 1
            out[n] = ENC[c]
        end
    end
    if #text == 0 then return "" end
    local dict, size = {}, 256
    for i = 0, 255 do dict[char(i)] = i end
    local emitted = 0
    local w = sub(text, 1, 1)
    for i = 2, #text do
        local c = sub(text, i, i)
        local wc = w .. c
        if dict[wc] then
            w = wc
        else
            emitted = emitted + 1
            put(dict[w], Width(math.min(256 + emitted - 1, MAX_DICT)))
            if size < MAX_DICT then
                dict[wc] = size
                size = size + 1
            end
            w = c
        end
    end
    emitted = emitted + 1
    put(dict[w], Width(math.min(256 + emitted - 1, MAX_DICT)))
    if bits > 0 then
        n = n + 1
        out[n] = ENC[acc * POW[6 - bits]]
    end
    return table.concat(out)
end

function U.Decompress(data)
    if data == "" then return "" end
    local dict, size = {}, 256
    for i = 0, 255 do dict[i] = char(i) end
    local acc, bits, pos, len = 0, 0, 1, #data
    local read = 0
    local function get(width)
        while bits < width do
            if pos > len then return nil end
            local v = DEC[byte(data, pos)]
            if not v then error("bad character", 0) end
            pos = pos + 1
            acc = acc * 64 + v
            bits = bits + 6
        end
        local shift = bits - width
        local code = floor(acc / POW[shift])
        acc = acc - code * POW[shift]
        bits = shift
        return code
    end
    local out = {}
    read = read + 1
    local first = get(Width(math.min(256 + read - 1, MAX_DICT)))
    if not first or not dict[first] then error("empty data", 0) end
    local w = dict[first]
    out[1] = w
    while true do
        read = read + 1
        local code = get(Width(math.min(256 + read - 1, MAX_DICT)))
        if not code then break end
        local entry
        if dict[code] then
            entry = dict[code]
        elseif code == size then
            entry = w .. sub(w, 1, 1)
        else
            error("bad code", 0)
        end
        out[#out + 1] = entry
        if size < MAX_DICT then
            dict[size] = w .. sub(entry, 1, 1)
            size = size + 1
        end
        w = entry
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Export strings
---------------------------------------------------------------------------
local PREFIX = "!PF1!"

-- payload: any serializable table
function U.Encode(payload)
    local body = U.Serialize(payload)
    return PREFIX .. U.Compress(U.Checksum(body) .. ":" .. body) .. "!"
end

-- Returns payload, or nil and a reason a person can read
function U.Decode(text)
    if type(text) ~= "string" then return nil, "Nothing to import." end
    text = text:gsub("%s+", "")
    if text == "" then return nil, "Nothing to import." end
    if sub(text, 1, #PREFIX) ~= PREFIX then
        if text:find("^!PF%d+!") then return nil, "This string is from a newer PadForge. Update the addon first." end
        return nil, "This is not a PadForge string."
    end
    local data = text:sub(#PREFIX + 1):gsub("!$", "")
    local ok, raw = pcall(U.Decompress, data)
    if not ok or not raw then return nil, "The string is damaged (it may be cut off)." end
    local sum, body = raw:match("^(%x+):(.*)$")
    if not sum or U.Checksum(body) ~= sum then return nil, "The string is damaged (checksum mismatch)." end
    local payload, why = U.Deserialize(body)
    if type(payload) ~= "table" then return nil, "The string is damaged (" .. tostring(why) .. ")." end
    return payload
end
