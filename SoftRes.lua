-- Looty SoftRes Decoder (Gargul format)
--
-- Decodes softres.it "Gargul Export" strings.
-- Pipeline: standard base64 → LibDeflate:DecompressZlib → JSON → Lua table
--
-- References Looty global at call time (never at load time).
-- Must load AFTER LibStub, LibDeflate.

local LibDeflate = LibStub("LibDeflate")
local floor = math.floor

local SoftRes = {}
LootySoftRes = SoftRes

-- ============================================================
-- Standard Base64 decoder (RFC 4648)
-- ============================================================

local B64_DECODE = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do
        B64_DECODE[chars:byte(i)] = i - 1
    end
    B64_DECODE[string.byte("=")] = 0
end

local function base64Decode(str)
    str = str:gsub("[^%w%+%/%=]", "")
    local out = {}
    local n = 0
    local i = 1
    while i <= #str do
        local a = B64_DECODE[str:byte(i)]     or 0
        local b = B64_DECODE[str:byte(i + 1)] or 0
        local c = B64_DECODE[str:byte(i + 2)] or 0
        local d = B64_DECODE[str:byte(i + 3)] or 0
        n = n + 1; out[n] = string.char((a * 4 + floor(b / 16)) % 256)
        n = n + 1; out[n] = string.char((b * 16 + floor(c / 4)) % 256)
        n = n + 1; out[n] = string.char((c * 64 + d) % 256)
        i = i + 4
    end
    local result = tconcat(out)
    if str:sub(-2) == "==" then return result:sub(1, -3) end
    if str:sub(-1) == "="  then return result:sub(1, -2) end
    return result
end

-- ============================================================
-- Minimal JSON decoder
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
        pos = pos + 1
        local obj = {}
        skipSpace()
        if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
            skipSpace()
            local key = parseString()
            skipSpace(); pos = pos + 1 -- colon
            local val = parseValue()
            if val ~= nil then obj[key] = val end
            skipSpace()
            local c = str:sub(pos, pos)
            if c == "}" then pos = pos + 1; return obj end
            if c == "," then pos = pos + 1 end
        end
    end

    function parseArray()
        pos = pos + 1
        local arr = {}
        skipSpace()
        if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        local idx = 1
        while true do
            local val = parseValue()
            if val ~= nil then arr[idx] = val end
            idx = idx + 1
            skipSpace()
            local c = str:sub(pos, pos)
            if c == "]" then pos = pos + 1; return arr end
            if c == "," then pos = pos + 1 end
        end
    end

    function parseString()
        pos = pos + 1
        local parts = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1; return tconcat(parts) end
            if c == "\\" then
                pos = pos + 1
                local esc = str:sub(pos, pos)
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
                parts[#parts + 1] = c
                pos = pos + 1
            end
        end
        error("Unterminated string")
    end

    function parseNumber()
        local s, e = str:find("^-?[0-9]+", pos)
        if not s then error("Expected number at " .. pos) end
        -- optional fractional part
        local de = str:find("^%.[0-9]*", e + 1)
        if de then e = de end
        -- optional exponent (Lua patterns: can't make groups optional with `?`)
        local es, ee = str:find("^[eE][%+%-]?[0-9]+", e + 1)
        if es then e = ee end
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
-- Public API
-- ============================================================

--- Decode a Gargul-format softres.it string into a Lua table.
-- @param importString The raw Gargul export string (base64).
-- @return table on success, nil + error message on failure.
function SoftRes.Decode(importString)
    if type(importString) ~= "string" or importString == "" then
        return nil, "Invalid input: expected non-empty string"
    end

    local ok, raw = pcall(base64Decode, importString)
    if not ok or raw == "" then
        return nil, "Base64 decode failed: " .. tostring(raw)
    end

    local ok2, decompressed = pcall(LibDeflate.DecompressZlib, LibDeflate, raw)
    if not ok2 or not decompressed then
        return nil, "Zlib decompress failed: " .. tostring(decompressed)
    end

    local ok3, data = pcall(jsonDecode, decompressed)
    if not ok3 or type(data) ~= "table" then
        return nil, "JSON decode failed: " .. tostring(data)
    end

    -- Validate expected structure
    if type(data.softreserves) ~= "table" then
        return nil, "Missing or invalid 'softreserves' field"
    end
    if type(data.metadata) ~= "table" or not data.metadata.id then
        return nil, "Missing or invalid 'metadata.id' field"
    end

    return data
end

--- Build index by item ID.
-- Returns { [itemID] = { players = {"Name1",...}, hardReservedFor = "Name"|nil } }
function SoftRes.IndexByItem(data)
    local idx = {}
    for _, entry in ipairs(data.softreserves) do
        local playerName = entry.name
        for _, item in ipairs(entry.items or {}) do
            local id = item.id
            if not idx[id] then idx[id] = { players = {} } end
            tinsert(idx[id].players, playerName)
        end
    end
    for _, entry in ipairs(data.hardreserves or {}) do
        local id = entry.id
        if not idx[id] then idx[id] = { players = {} } end
        idx[id].hardReservedFor = entry["for"]
    end
    return idx
end

--- Build index by player name (lowercase).
-- Returns { [name:lower] = { class, items = {...}, plusOnes } }
function SoftRes.IndexByPlayer(data)
    local idx = {}
    for _, entry in ipairs(data.softreserves) do
        local name = strlower(entry.name or "")
        if name ~= "" then
            local record = {
                class    = entry.class,
                items    = {},
                plusOnes = entry.plusOnes or 0,
                note     = entry.note or "",
            }
            for _, item in ipairs(entry.items or {}) do
                tinsert(record.items, item.id)
            end
            idx[name] = record
        end
    end
    return idx
end

--- Print decoded data to chat for debugging.
function SoftRes.DebugPrint(importString)
    local data, err = SoftRes.Decode(importString)
    if not data then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7B2D8E[Looty]|r SoftRes error: " .. tostring(err))
        return
    end

    Looty:Print("=== SoftRes (Gargul) ===")
    Looty:Print("metadata.id: " .. tostring(data.metadata.id))
    Looty:Print("softreserves: " .. #data.softreserves .. " entries")
    Looty:Print("hardreserves: " .. #(data.hardreserves or {}) .. " entries")

    for i, entry in ipairs(data.softreserves) do
        local ids = {}
        for _, item in ipairs(entry.items or {}) do
            tinsert(ids, tostring(item.id))
        end
        Looty:Print(string.format("  [%d] %s (%s) items=[%s] +%d note=%s",
            i, entry.name or "?", entry.class or "?",
            tconcat(ids, ","),
            entry.plusOnes or 0,
            entry.note or ""))
    end
    for _, entry in ipairs(data.hardreserves or {}) do
        Looty:Print(string.format("  HR item=%d for=%s note=%s",
            entry.id or 0, tostring(entry["for"] or ""), entry.note or ""))
    end
    Looty:Print("=== End ===")
end
