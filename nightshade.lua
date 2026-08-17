-- NIGHTSHADE V3 // Greedy Growers
-- Stable public loader. V3 is a clean single-source rebuild.

local URL = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/v3/part-01.lua"
local ok, source = pcall(game.HttpGet, game, URL)

if not ok or type(source) ~= "string" or #source == 0 then
    error("[NIGHTSHADE V3] Failed to download core: " .. tostring(source))
end

local fn, compileError = loadstring(source)
if not fn then
    error("[NIGHTSHADE V3] Compile failed: " .. tostring(compileError))
end

return fn()
