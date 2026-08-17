--[[
    NIGHTSHADE V4 // Greedy Growers
    PlaceId: 74102906764176

    Rebuild goals:
      - Greedy Growers-specific automation, not generic prompt walking
      - distance-free seed conveyor buying when executor supports it
      - strict affordability / price-source guards before any seed purchase
      - no direct gameplay FireServer / InvokeServer calls
      - cached interaction index to avoid repeated Workspace-wide scans
      - Linoria UI with a game-aware action layer
      - no server protection / honeypot code
]]

local EXPECTED_PLACE_ID = 74102906764176

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local Player = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

if ENV.NIGHTSHADE_GG_V4 and ENV.NIGHTSHADE_GG_V4.Stop then
    pcall(ENV.NIGHTSHADE_GG_V4.Stop)
end
if ENV.NIGHTSHADE_GG_V31 and ENV.NIGHTSHADE_GG_V31.Stop then
    pcall(ENV.NIGHTSHADE_GG_V31.Stop)
end
if ENV.NIGHTSHADE_GG_V3 and ENV.NIGHTSHADE_GG_V3.Stop then
    pcall(ENV.NIGHTSHADE_GG_V3.Stop)
end

local Runtime = {
    Running = true,
    Connections = {},
    InteractionSet = setmetatable({}, {__mode = "k"}),
    LastInteract = setmetatable({}, {__mode = "k"}),
    LastSeedTry = setmetatable({}, {__mode = "k"}),
    DeadTreeBackoff = setmetatable({}, {__mode = "k"}),
    DeadSweep = {
        Scans = 0,
        Found = 0,
        Cleared = 0,
        Failed = 0,
        Remaining = 0,
        Last = "Idle",
    },
    Stats = {
        Actions = 0,
        SeedsBought = 0,
        SeedsSkipped = 0,
        Harvests = 0,
        Fruits = 0,
        Plants = 0,
        Sells = 0,
        Market = 0,
        Support = 0,
        DeadTrees = 0,
    },
    LastAction = "Idle",
    LastError = "None",
    BestRiverSeed = "Scanning...",
    CurrentWeather = "Unknown",
    SeedCandidates = 0,
}
ENV.NIGHTSHADE_GG_V4 = Runtime

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Runtime.Connections, c)
    return c
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, needle)
    return string.find(lower(text), lower(needle), 1, true) ~= nil
end

local function containsAny(text, needles)
    local t = lower(text)
    for _, needle in ipairs(needles) do
        if string.find(t, lower(needle), 1, true) then
            return true
        end
    end
    return false
end

local function safeAttr(inst, key)
    if not inst then return nil end
    local ok, value = pcall(inst.GetAttribute, inst, key)
    return ok and value or nil
end

local function safeFullName(inst)
    if not inst then return "nil" end
    local ok, value = pcall(inst.GetFullName, inst)
    return ok and value or tostring(inst)
end

local function isAlive(inst)
    return inst and inst.Parent ~= nil
end

local function abbreviate(n)
    n = tonumber(n)
    if not n then return "?" end
    local units = {
        {1e18, "Qi"}, {1e15, "Qa"}, {1e12, "T"},
        {1e9, "B"}, {1e6, "M"}, {1e3, "K"},
    }
    for _, u in ipairs(units) do
        if math.abs(n) >= u[1] then
            return string.format("%.2f%s", n / u[1], u[2])
        end
    end
    return tostring(math.floor(n))
end

local SUFFIX_MULT = {
    k = 1e3, m = 1e6, b = 1e9, t = 1e12,
    qa = 1e15, qi = 1e18,
}

local function parseCompactNumber(text)
    local s = tostring(text or ""):gsub(",", "")
    local number, suffix = s:match("([%d]+%.?[%d]*)%s*([KkMmBbTt][AaIi]?|[Qq][AaIi])")
    if not number then
        number = s:match("([%d]+%.?[%d]*)")
        suffix = ""
    end
    local n = tonumber(number)
    if not n then return nil end
    return n * (SUFFIX_MULT[lower(suffix)] or 1)
end

local function parseExplicitCurrency(text)
    local s = tostring(text or ""):gsub(",", "")

    -- Dollar-prefixed text is the strongest UI signal.
    local amount, suffix = s:match("%$%s*([%d]+%.?[%d]*)%s*([KkMmBbTt][AaIi]?|[Qq][AaIi])")
    if not amount then
        amount = s:match("%$%s*([%d]+%.?[%d]*)")
        suffix = ""
    end
    if amount then
        local n = tonumber(amount)
        return n and n * (SUFFIX_MULT[lower(suffix)] or 1) or nil
    end

    -- Price/cost-labelled text is also safe enough to parse.
    if containsAny(s, {"price", "cost"}) then
        return parseCompactNumber(s)
    end

    return nil
end

local function firstAncestorModel(inst)
    if not inst then return nil end
    if inst:IsA("Model") then return inst end
    return inst:FindFirstAncestorWhichIsA("Model")
end

local function buildText(inst, depth)
    if not inst then return "" end
    depth = depth or 4
    local out = {}

    if inst:IsA("ProximityPrompt") then
        table.insert(out, inst.Name)
        table.insert(out, inst.ActionText)
        table.insert(out, inst.ObjectText)
    elseif inst:IsA("ClickDetector") then
        table.insert(out, inst.Name)
    else
        table.insert(out, inst.Name)
    end

    if not inst:IsA("ProximityPrompt") and not inst:IsA("ClickDetector") then
        local count = 0
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                if d.Visible then
                    table.insert(out, d.Text)
                    count = count + 1
                    if count >= 20 then break end
                end
            elseif d:IsA("StringValue") then
                table.insert(out, tostring(d.Value))
                count = count + 1
                if count >= 20 then break end
            end
        end
    end

    local node = inst
    for _ = 1, depth do
        node = node.Parent
        if not node or node == game then break end
        table.insert(out, node.Name)
    end

    return lower(table.concat(out, " "))
end

local function readAny(inst, keys)
    if not inst then return nil end
    local nodes = {inst}
    local model = firstAncestorModel(inst)
    if model and model ~= inst then table.insert(nodes, model) end
    if model and model.Parent then table.insert(nodes, model.Parent) end

