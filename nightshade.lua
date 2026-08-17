-- NIGHTSHADE V4 // Greedy Growers
-- Stable public loader.

local URL = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/v4/bootstrap.lua"
local ok, source = pcall(game.HttpGet, game, URL)

if not ok or type(source) ~= "string" or #source == 0 then
    error("[NIGHTSHADE V4] Failed to download bootstrap: " .. tostring(source))
end

local fn, compileError = loadstring(source)
if not fn then
    error("[NIGHTSHADE V4] Bootstrap compile failed: " .. tostring(compileError))
end

return fn()
