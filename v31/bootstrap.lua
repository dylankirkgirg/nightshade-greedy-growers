-- NIGHTSHADE V3.1 verified bootstrap
-- Loads the V3.1 core and applies two source-level correctness fixes before compile.

local CORE = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/v31/main.lua"
local ok, source = pcall(game.HttpGet, game, CORE)
if not ok or type(source) ~= "string" or #source == 0 then
    error("[NIGHTSHADE V3.1] Failed to download core: " .. tostring(source))
end

local function replacePlain(text, old, new)
    local at = string.find(text, old, 1, true)
    if not at then
        error("[NIGHTSHADE V3.1] Bootstrap patch target missing")
    end
    return string.sub(text, 1, at - 1) .. new .. string.sub(text, at + #old)
end

-- Lua patterns do not use | for alternation. Accept alphabetic compact suffixes
-- and validate them through the existing suffix multiplier table instead.
source = replacePlain(
    source,
    'local number, suffix = s:match("([%d]+%.?[%d]*)%s*([KkMmBbTt][AaIi]?|[Qq][AaIi])")',
    'local number, suffix = s:match("([%d]+%.?[%d]*)%s*([%a]*)")'
)

source = replacePlain(
    source,
    'local amount, suffix = s:match("%$%s*([%d]+%.?[%d]*)%s*([KkMmBbTt][AaIi]?|[Qq][AaIi])")',
    'local amount, suffix = s:match("%$%s*([%d]+%.?[%d]*)%s*([%a]*)")'
)

-- Prefer the nearest model around each conveyor interaction. This avoids
-- collapsing multiple seeds into one candidate when ConveyorSeeds uses a
-- nested folder/container layout.
source = replacePlain(
    source,
    'local entity = entityUnderRoot(interaction, root)',
    'local model = firstAncestorModel(interaction)\n            local entity = (model and model ~= root and underRoot(model, root)) and model or entityUnderRoot(interaction, root)'
)

local fn, compileError = loadstring(source)
if not fn then
    error("[NIGHTSHADE V3.1] Compile failed: " .. tostring(compileError))
end

return fn()
