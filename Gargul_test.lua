-- Looty Gargul Format Integration Test
-- Uses LootySoftRes (SoftRes.lua) to decode and inspect a Gargul export string.
--
-- Instructions:
--   1. Get a softres.it Gargul export string
--   2. Paste it below as the value of GARGUL_STRING
--   3. Run: lua Gargul_test.lua

local GARGUL_STRING = [[
eNpVkDFuwzAMRe/CWUMSxHalrblAh6JT4YEQGVSoLAUUlaGG716pHpJu+vrk5yNXWFiRUBHcCoHAAf9Mw72CgZCKYvIMLtUYH7qA+wTN/jTAbOArEHECd8VY2IAXRmV6VXDHabKn8WxfrIF6o//fw8EeDQgGelcULd3Zx8Tsv/fKXVMoPgt9SGxwDStl5f7aDJR8VeHCcv+DWkFyjJecalMHA7dYy1viXSRcetulcvIxLNiSfMTSTCCpbfNHcltVedkT+0nOo53GZ7vhsLTUbd76BVDoiWLefgFrvG1v
]]

GARGUL_STRING = GARGUL_STRING:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")

-- ============================================================
-- Bootstrap
-- ============================================================

local script_path = (arg and arg[0]) or debug.getinfo(1, "S").source:match("^@?(.*)$")
local ROOT = script_path:match("^(.*[/\\])") or "./"

-- WoW / Lua 5.1 compat globals (SoftRes.lua relies on these)
if not strmatch   then _G.strmatch   = string.match end
if not strlower   then _G.strlower   = string.lower end
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

-- Minimal WoW mocks so SoftRes.lua can load outside WoW
if not Looty then Looty = { Print = function(...) print("|cff7B2D8E[Looty]|r", ...) end } end
if not DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME = { AddMessage = print } end

dofile(ROOT .. "Libs/LibStub/LibStub.lua")
dofile(ROOT .. "Libs/LibDeflate/LibDeflate.lua")
dofile(ROOT .. "SoftRes.lua")  -- registers LootySoftRes

-- ============================================================
-- Table printer
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

if GARGUL_STRING == "" or GARGUL_STRING:find("PASTE_YOUR") then
    print("")
    print("=== EDIT Gargul_test.lua ===")
    print("Set GARGUL_STRING to your softres.it Gargul export string.")
    local name = arg and arg[0] or "Gargul_test.lua"
    print("Then run: lua " .. name)
    print("")
    os.exit(1)
end

-- ---- Decode with our production SoftRes module ----
-- NOTE: SoftRes methods are stateless (no `self`), must use DOT syntax.
local data, err = LootySoftRes.Decode(GARGUL_STRING)
if not data then
    print("DECODE FAILED: " .. tostring(err))
    os.exit(1)
end

printStructure(data, "Decoded Data (via LootySoftRes:Decode)")

-- ---- Summary ----
print("--- Summary ---")
print("metadata.id:  " .. tostring(data.metadata.id))
print("softreserves: " .. #data.softreserves .. " entries")
print("hardreserves: " .. #(data.hardreserves or {}) .. " entries")
print("")

for i, entry in ipairs(data.softreserves) do
    local items = {}
    for _, item in ipairs(entry.items or {}) do
        items[#items + 1] = tostring(item.id)
    end
    print(string.format("  [%d] %s (%s) items=[%s] +%d note=%s",
        i, entry.name or "?", entry.class or "?",
        table.concat(items, ","),
        entry.plusOnes or 0,
        entry.note or ""))
end
for _, entry in ipairs(data.hardreserves or {}) do
    print(string.format("  HR item=%d for=%q note=%q",
        entry.id or 0, tostring(entry["for"] or ""), entry.note or ""))
end

-- ---- Index tests ----
print("")
print("--- IndexByItem ---")
local byItem = LootySoftRes.IndexByItem(data)
for id, info in pairs(byItem) do
    print(string.format("  Item %d → players=[%s] hardReservedFor=%s",
        id, table.concat(info.players, ","),
        info.hardReservedFor or "(none)"))
end

print("")
print("--- IndexByPlayer ---")
local byPlayer = LootySoftRes.IndexByPlayer(data)
for name, info in pairs(byPlayer) do
    print(string.format("  %s (class=%s) items=[%s] +%d note=%s",
        name, info.class, table.concat(info.items, ","),
        info.plusOnes, info.note))
end

print("")
print("DONE")
