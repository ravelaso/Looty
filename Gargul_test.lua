-- Looty Gargul Format Standalone Test
-- Run with: lua Gargul_test.lua
-- Prerequisites: Lua 5.1+ or LuaJIT
--
-- Decodes a softres.it "Gargul Export" string.
-- Pipeline: standard base64 → LibDeflate:DecompressZlib → JSON → Lua table
--
-- Instructions:
--   1. Get a softres.it Gargul export string
--   2. Paste it below as the value of GARGUL_STRING
--   3. Run: lua Gargul_test.lua

local GARGUL_STRING = [[
eNpVkDFuwzAMRe/CWUMSxHalrblAh6JT4YEQGVSoLAUUlaGG716pHpJu+vrk5yNXWFiRUBHcCoHAAf9Mw72CgZCKYvIMLtUYH7qA+wTN/jTAbOArEHECd8VY2IAXRmV6VXDHabKn8WxfrIF6o//fw8EeDQgGelcULd3Zx8Tsv/fKXVMoPgt9SGxwDStl5f7aDJR8VeHCcv+DWkFyjJecalMHA7dYy1viXSRcetulcvIxLNiSfMTSTCCpbfNHcltVedkT+0nOo53GZ7vhsLTUbd76BVDoiWLefgFrvG1v
]]

GARGUL_STRING = GARGUL_STRING:match("^%s*(.-)%s*$")

-- ============================================================
-- Bootstrap (same compat shim as SoftRes_test)
-- ============================================================

local script_path = (arg and arg[0]) or debug.getinfo(1, "S").source:match("^@?(.*)$")
local ROOT = script_path:match("^(.*[/\\])") or "./"

-- WoW / Lua 5.1 compat globals (no Libs/* are touched)
if not strmatch   then _G.strmatch   = string.match end
if not tinsert    then _G.tinsert    = table.insert end
if not tremove    then _G.tremove    = table.remove end
if not tsort      then _G.tsort      = table.sort end
if not tconcat    then _G.tconcat    = table.concat end
if not unpack     then _G.unpack     = table.unpack end
if not math.ldexp then math.ldexp    = function(m, e) return m * 2.0 ^ e end end
if not math.frexp then math.frexp    = function(x)
    if x == 0 then return 0, 0 end
    local e = 0
    local abs = x < 0 and -x or x
    while abs >= 1 do abs = abs / 2; e = e + 1 end
    while abs < 0.5 do abs = abs * 2; e = e - 1 end
    return x < 0 and -abs or abs, e
end end

dofile(ROOT .. "Libs/LibStub/LibStub.lua")
dofile(ROOT .. "Libs/LibDeflate/LibDeflate.lua")

local LibDeflate = LibStub("LibDeflate")

-- ============================================================
-- Standard Base64 decoder (RFC 4648)
-- ============================================================

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, 64 do
    B64_DECODE[B64_CHARS:byte(i)] = i - 1
end
B64_DECODE[string.byte("=")] = 0

local function base64Decode(str)
    str = str:gsub("[^%w%+%/%=]", "")
    local out = {}
    local outLen = 0
    local i = 1
    while i <= #str do
        local a = B64_DECODE[str:byte(i)]     or 0
        local b = B64_DECODE[str:byte(i + 1)] or 0
        local c = B64_DECODE[str:byte(i + 2)] or 0
        local d = B64_DECODE[str:byte(i + 3)] or 0
        outLen = outLen + 1; out[outLen] = string.char((a * 4 + math.floor(b / 16)) % 256)
        outLen = outLen + 1; out[outLen] = string.char((b * 16 + math.floor(c / 4)) % 256)
        outLen = outLen + 1; out[outLen] = string.char((c * 64 + d) % 256)
        i = i + 4
    end
    -- Strip padding
    local result = table.concat(out)
    if str:sub(-2) == "==" then return result:sub(1, -3)
    elseif str:sub(-1) == "=" then return result:sub(1, -2)
    else return result end
end

-- ============================================================
-- Minimal JSON decoder (enough for our known structure)
-- ============================================================

local function jsonDecode(str)
    local pos, skipSpace, parseValue, parseObject, parseArray, parseString, parseNumber

    function skipSpace()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else break end
        end
    end

    function parseValue()
        skipSpace()
        local c = str:sub(pos, pos)
        if c == "{" then return parseObject() end
        if c == "[" then return parseArray() end
        if c == '"' then return parseString() end
        if c == "t" then pos = pos + 4; return true end
        if c == "f" then pos = pos + 5; return false end
        if c == "n" then pos = pos + 4; return nil end
        return parseNumber()
    end

    function parseObject()
        pos = pos + 1; local obj = {}
        skipSpace()
        if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
            skipSpace()
            local key = parseString()
            skipSpace(); pos = pos + 1 -- colon
            local val = parseValue()
            obj[key] = val
            skipSpace()
            local c = str:sub(pos, pos)
            if c == "}" then pos = pos + 1; return obj end
            if c == "," then pos = pos + 1 end
        end
    end

    function parseArray()
        pos = pos + 1; local arr = {}
        skipSpace()
        if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        local idx = 1
        while true do
            arr[idx] = parseValue(); idx = idx + 1
            skipSpace()
            local c = str:sub(pos, pos)
            if c == "]" then pos = pos + 1; return arr end
            if c == "," then pos = pos + 1 end
        end
    end

    function parseString()
        pos = pos + 1; local parts = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(parts) end
            if c == "\\" then
                pos = pos + 1; local esc = str:sub(pos, pos)
                if esc == '"' then parts[#parts + 1] = '"'
                elseif esc == "\\" then parts[#parts + 1] = "\\"
                elseif esc == "/" then parts[#parts + 1] = "/"
                elseif esc == "b" then parts[#parts + 1] = "\b"
                elseif esc == "f" then parts[#parts + 1] = "\f"
                elseif esc == "n" then parts[#parts + 1] = "\n"
                elseif esc == "r" then parts[#parts + 1] = "\r"
                elseif esc == "t" then parts[#parts + 1] = "\t"
                elseif esc == "u" then
                    local hex = str:sub(pos + 1, pos + 4)
                    parts[#parts + 1] = string.char(tonumber(hex, 16))
                    pos = pos + 4
                end
                pos = pos + 1
            else
                parts[#parts + 1] = c; pos = pos + 1
            end
        end
        error("Unterminated string")
    end

    function parseNumber()
        local s, e = str:find("^-?[0-9]+%.?[0-9]*(e[%+%-]?[0-9]+)?", pos)
        if not s then error("Expected number at " .. pos) end
        local num = str:sub(s, e)
        pos = e + 1
        return tonumber(num)
    end

    pos = 1
    local result = parseValue()
    skipSpace()
    return result
end

-- ============================================================
-- Table printer (same as WA test)
-- ============================================================

local function printTable(t, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)
    local function kv(k)
        if type(k) == "string" then return string.format("[%q]", k)
        elseif type(k) == "number" then return string.format("[%d]", k)
        else return tostring(k) end
    end
    for k, v in pairs(t) do
        local line = indent .. kv(k) .. " = "
        if type(v) == "table" then
            print(line .. "{")
            printTable(v, depth + 1)
            print(indent .. "}")
        elseif type(v) == "string" then
            local display = #v > 200 and v:sub(1, 200) .. "..." or v
            print(line .. string.format("%q", display))
        else
            print(line .. tostring(v))
        end
    end
end

local function printStructure(data, label)
    print("")
    print("========================================")
    print("  " .. label)
    print("========================================")
    print("Type: " .. type(data))
    if type(data) == "table" then
        local keys = {}
        for k in pairs(data) do table.insert(keys, type(k) == "string" and k or tostring(k)) end
        table.sort(keys)
        print("Keys (" .. #keys .. "): " .. table.concat(keys, ", "))
        print("")
        printTable(data, 0)
    else
        print(tostring(data))
    end
    print("========================================")
    print("")
end

-- ============================================================
-- Main
-- ============================================================

if GARGUL_STRING == "" or GARGUL_STRING:find("PASTE_YOUR_GARGUL") then
    print("")
    print("=== EDIT Gargul_test.lua ===")
    print("Set GARGUL_STRING to your softres.it Gargul export string.")
    local script_name = arg and arg[0] or "Gargul_test.lua"
    print("Then run: lua " .. script_name)
    print("")
    os.exit(1)
end

-- Pipeline: base64 → zlib decompress → raw JSON text → JSON decode
local raw = base64Decode(GARGUL_STRING)
if not raw or raw == "" then
    print("BASE64 DECODE FAILED")
    os.exit(1)
end

local ok, decompressed = pcall(LibDeflate.DecompressZlib, LibDeflate, raw)
if not ok or not decompressed then
    print("ZLIB DECOMPRESS FAILED: " .. tostring(decompressed))
    os.exit(1)
end

-- Show raw decompressed text (first 3000 chars)
print("")
print("========================================")
print("  Raw decompressed JSON (" .. #decompressed .. " bytes)")
print("========================================")
if #decompressed > 3000 then
    print(decompressed:sub(1, 3000) .. "...")
    print("(truncated to 3000 chars — full length: " .. #decompressed .. ")")
else
    print(decompressed)
end
print("========================================")
print("")

-- Attempt JSON decode
local ok2, data = pcall(jsonDecode, decompressed)
if not ok2 then
    print("JSON DECODE FAILED: " .. tostring(data))
    print("See raw text above — JSON is valid, the decoder needs fixing.")
    os.exit(1)
end

printStructure(data, "Top-Level Decoded Data (Gargul format)")

-- Also show validation summary
if type(data) == "table" then
    print("--- Summary ---")
    print("metadata.id:  " .. tostring(data.metadata and data.metadata.id or "MISSING"))
    print("softreserves: " .. tostring(#(data.softreserves or {})) .. " entries")
    print("hardreserves: " .. tostring(#(data.hardreserves or {})) .. " entries")
    print("")
    if data.softreserves then
        for i, entry in ipairs(data.softreserves) do
            local items = {}
            for _, item in ipairs(entry.items or {}) do
                items[#items + 1] = tostring(item.id)
            end
            print(string.format("  [%d] %s (%s) items: [%s] note=%q plus=%s",
                i, entry.name or "?", entry.class or "?",
                table.concat(items, ","),
                entry.note or "",
                tostring(entry.plusOnes or 0)))
        end
    end
    if data.hardreserves then
        for i, entry in ipairs(data.hardreserves) do
            print(string.format("  HR[%d] item=%s for=%q note=%q",
                i, tostring(entry.id), tostring(entry["for"] or ""), tostring(entry.note or "")))
        end
    end
    print("")
end
