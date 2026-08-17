-- NIGHTSHADE // Greedy Growers
-- Obsidian Edition bootstrap
-- Keeps the existing chunked core, but swaps the UI layer to Obsidian before execution.

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

local combined = table.concat(source, "\n")

local function replaceLiteral(input, old, new)
    local startPos, endPos = string.find(input, old, 1, true)

    while startPos do
        input = string.sub(input, 1, startPos - 1) .. new .. string.sub(input, endPos + 1)
        startPos, endPos = string.find(input, old, startPos + #new, true)
    end

    return input
end

-- Obsidian is intentionally API-compatible with the Linoria-style layout NIGHTSHADE uses,
-- while adding maintained native Mobile + PC support.
combined = replaceLiteral(
    combined,
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/",
    "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
)

combined = replaceLiteral(combined, "ENV.NIGHTSHADE_LINORIA", "ENV.NIGHTSHADE_OBSIDIAN")
combined = replaceLiteral(combined, "NIGHTSHADE // Linoria", "NIGHTSHADE // Obsidian")
combined = replaceLiteral(combined, "100% Linoria", "100% Obsidian")
combined = replaceLiteral(combined, "Linoria adapter", "Obsidian adapter")
combined = replaceLiteral(combined, "Linoria calls", "Obsidian calls")

-- Use only documented Obsidian CreateWindow options.
combined = replaceLiteral(
    combined,
    [[local LinoriaWindow = Library:CreateWindow({
    Title = "NIGHTSHADE // Greedy Growers",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.18,
})]],
    [[local LinoriaWindow = Library:CreateWindow({
    Title = "NIGHTSHADE // Greedy Growers",
    Footer = "NIGHTSHADE • Greedy Growers",
    Center = true,
    AutoShow = true,
    Size = UDim2.fromOffset(620, 500),
    NotifySide = "Right",
    ShowCustomCursor = false,
    CornerRadius = 7,
})]]
)

-- Let Obsidian's ThemeManager own the theme instead of mutating old Linoria fields.
combined = replaceLiteral(
    combined,
    [[-- Dark/Ouroboros-ish defaults
pcall(function()
    Library.AccentColor = Color3.fromRGB(85, 170, 255)
    Library.AccentColorDark = Color3.fromRGB(55, 110, 165)
    Library.MainColor = Color3.fromRGB(18, 18, 20)
    Library.BackgroundColor = Color3.fromRGB(13, 13, 15)
    Library.OutlineColor = Color3.fromRGB(45, 45, 50)
end)]],
    [[pcall(function()
    ThemeManager:ApplyTheme("Dracula")
end)]]
)

local fn, compileError = loadstring(combined)

if not fn then
    error("[NIGHTSHADE] Obsidian compile failed: " .. tostring(compileError))
end

return fn()
