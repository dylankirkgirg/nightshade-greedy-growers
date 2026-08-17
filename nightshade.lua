-- NIGHTSHADE // Greedy Growers public bootstrap
-- Loads the Linoria client from chunked source files in this repository.

local BASE = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/src/part-%02d.lua"
local source = table.create(10)

for i = 1, 10 do
    local url = string.format(BASE, i)
    local ok, body = pcall(game.HttpGet, game, url)

    if not ok or type(body) ~= "string" or #body == 0 then
        error(("[NIGHTSHADE] Failed to download source part %02d: %s"):format(i, tostring(body)))
    end

    source[i] = body
end

-- Explicit newlines make chunk boundaries safe even if GitHub strips a final newline.
local combined = table.concat(source, "\n")
local fn, compileError = loadstring(combined)

if not fn then
    error("[NIGHTSHADE] Compile failed: " .. tostring(compileError))
end

return fn()
