-- Minimal .cfg (ini-style) reader, shared by defaults.cfg and the
-- per-game info.cfg files. The format is aimed at hand-editing:
--
--   # full-line comment (";" works too)
--   key = value
--   [section]
--   key = value
--
-- Rules:
--   * Only whole lines can be comments (a "#" inside a value is kept,
--     so game names and hex colors survive).
--   * Values are plain text - no quoting or escaping needed.
--   * A key with an empty value ("bg = ") is treated as absent, so
--     files can list every field as a template.
--   * Everything parses as a string; callers coerce types as needed.

local Cfg = {}

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Parses cfg text into:
--   { root = { key = value, ... },              -- pairs before any [section]
--     sections = { { name = "...", values = { ... } }, ... } }
-- Sections keep file order and may repeat (info.cfg uses one [game]
-- section per title).
function Cfg.parse(text)
    local root, sections = {}, {}
    local current = root
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        line = trim(line)
        if line ~= "" and not line:match("^[#;]") then
            local section = line:match("^%[(.-)%]$")
            if section then
                current = {}
                table.insert(sections, { name = trim(section), values = current })
            else
                local key, value = line:match("^([^=]+)=(.*)$")
                if key then
                    key, value = trim(key), trim(value)
                    if key ~= "" and value ~= "" then
                        current[key] = value
                    end
                end
            end
        end
    end
    return { root = root, sections = sections }
end

-- Folds a parse result into one nested table: root pairs at the top
-- level, section pairs under the section name. Dotted section names
-- nest further ([ext_launchers.psp] -> t.ext_launchers.psp).
function Cfg.toTable(parsed)
    local out = {}
    for k, v in pairs(parsed.root) do out[k] = v end
    for _, sec in ipairs(parsed.sections) do
        local node = out
        for part in sec.name:gmatch("[^%.]+") do
            if type(node[part]) ~= "table" then node[part] = {} end
            node = node[part]
        end
        for k, v in pairs(sec.values) do node[k] = v end
    end
    return out
end

return Cfg
