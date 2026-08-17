-- NIGHTSHADE // Greedy Growers public bootstrap
-- Loads the Linoria client from chunked source files, then applies the
-- cross-device compatibility layer on touch devices.

local BASE = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/src/part-%02d.lua"
local MOBILE_URL = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/mobile.lua"
local source = table.create(10)

for i = 1, 10 do
    local url = string.format(BASE, i)
    local ok, body = pcall(game.HttpGet, game, url)

    if not ok or type(body) ~= "string" or #body == 0 then
        error(("[NIGHTSHADE] Failed to download source part %02d: %s"):format(i, tostring(body)))
    end

    source[i] = body
end

local combined = table.concat(source, "\n")
local fn, compileError = loadstring(combined)

if not fn then
    error("[NIGHTSHADE] Compile failed: " .. tostring(compileError))
end

local result = fn()

-- Apply phone/tablet support after the main Linoria client has initialized.
if game:GetService("UserInputService").TouchEnabled then
    task.spawn(function()
        local ok, mobileSource = pcall(game.HttpGet, game, MOBILE_URL)

        if not ok or type(mobileSource) ~= "string" or #mobileSource == 0 then
            warn("[NIGHTSHADE] Mobile compatibility download failed:", mobileSource)
            return
        end

        local mobileFn, mobileCompileError = loadstring(mobileSource)

        if not mobileFn then
            warn("[NIGHTSHADE] Mobile compatibility compile failed:", mobileCompileError)
            return
        end

        local success, runtimeError = pcall(mobileFn)

        if not success then
            warn("[NIGHTSHADE] Mobile compatibility runtime failed:", runtimeError)
        end
    end)
end

return result
