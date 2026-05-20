-- Looty SoftRes Decoder
-- Decodes softres.it export strings in WeakAuras format.
-- Pipeline:
--   "!WA:2!" + base64 → LibDeflate:DecodeForPrint
--     → LibDeflate:DecompressDeflate → LibSerialize:Deserialize → Lua table
--
-- References Looty global at call time (never at load time).
-- Must load AFTER LibStub, LibDeflate, LibSerialize.

local LibDeflate = LibStub("LibDeflate")
local LibSerialize = LibStub("LibSerialize")

local SoftRes = {}
LootySoftRes = SoftRes

--- Decode a WeakAuras-format string into a Lua table.
-- @param importString The full string including "!WA:N!" prefix.
-- @return table on success, nil + error message on failure.
function SoftRes.Decode(importString)
    if type(importString) ~= "string" or importString == "" then
        return nil, "Invalid input: expected non-empty string"
    end

    local _, _, encodeVersion, encoded = importString:find("^(!WA:%d+!)(.+)$")
    if not encodeVersion then
        -- Try legacy format (version 1 — just "!" prefix)
        encoded, encodeVersion = importString:gsub("^%!", "")
        if encodeVersion == 0 then
            return nil, "Missing !WA:N! prefix"
        end
    else
        encodeVersion = tonumber(encodeVersion:match("%d+"))
    end

    local decoded
    if encodeVersion > 0 then
        decoded = LibDeflate:DecodeForPrint(encoded)
    else
        return nil, "Version 0 not supported (LibCompress format). Upgrade to softres.it Gargul export."
    end

    if not decoded then
        return nil, "LibDeflate:DecodeForPrint failed — invalid base64 data"
    end

    local decompressed
    if encodeVersion > 0 then
        decompressed = LibDeflate:DecompressDeflate(decoded)
        if not decompressed then
            return nil, "LibDeflate:DecompressDeflate failed — corrupted or invalid data"
        end
    else
        return nil, "Version 0 decompression not supported"
    end

    local success, deserialized
    if encodeVersion < 2 then
        return nil, "Version 1 not supported (AceSerializer format)"
    else
        success, deserialized = LibSerialize:Deserialize(decompressed)
    end

    if not success then
        return nil, "LibSerialize:Deserialize failed — data is not valid serialized table"
    end

    return deserialized
end

--- Decode and print the full table structure to chat for inspection.
-- @param importString The full "!WA:N!" softres string.
function SoftRes.DebugPrint(importString)
    local data, err = SoftRes.Decode(importString)
    if not data then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7B2D8E[Looty]|r SoftRes error: " .. tostring(err))
        return
    end

    Looty:Print("=== SoftRes Decoded Data ===")
    PrintTable(data, 0)
    Looty:Print("=== End ===")
end

-- Recursive table printer (internal)
local function PrintTable(t, depth)
    local indent = string.rep("  ", depth)
    for k, v in pairs(t) do
        local kStr
        if type(k) == "string" then
            kStr = string.format("[%q]", k)
        elseif type(k) == "number" then
            kStr = string.format("[%d]", k)
        else
            kStr = tostring(k)
        end

        local line = indent .. kStr .. " = "
        if type(v) == "table" then
            Looty:Print(line .. "{")
            PrintTable(v, depth + 1)
            Looty:Print(indent .. "}")
        elseif type(v) == "string" then
            local display = #v > 100 and v:sub(1, 100) .. "..." or v
            Looty:Print(line .. string.format("%q", display))
        elseif type(v) == "number" then
            Looty:Print(line .. tostring(v))
        elseif type(v) == "boolean" then
            Looty:Print(line .. tostring(v))
        else
            Looty:Print(line .. tostring(v) .. " (" .. type(v) .. ")")
        end
    end
end
