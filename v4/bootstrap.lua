-- NIGHTSHADE V4 // Greedy Growers bootstrap
local BASE = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/v4/"
local PARTS = {
    "part-01.lua", "part-02.lua", "part-03.lua", "part-04.lua", "part-05.lua",
    "part-06.lua", "part-07.lua", "part-08.lua", "part-09.lua", "part-10.lua",
}

local chunks = table.create and table.create(#PARTS) or {}
for i, name in ipairs(PARTS) do
    local ok, body = pcall(game.HttpGet, game, BASE .. name)
    if not ok or type(body) ~= "string" or #body == 0 then
        error("[NIGHTSHADE V4] Failed to download " .. name .. ": " .. tostring(body))
    end
    chunks[i] = body
end

local source = table.concat(chunks)
local fn, compileError = loadstring(source)
if not fn then
    error("[NIGHTSHADE V4] Compile failed: " .. tostring(compileError))
end
return fn()
