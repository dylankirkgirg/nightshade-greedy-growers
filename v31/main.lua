--[[
    NIGHTSHADE V3.1 // Greedy Growers
    PlaceId: 74102906764176

    Rebuild goals:
      - Greedy Growers-specific automation, not generic prompt walking
      - distance-free seed conveyor buying when executor supports it
      - strict affordability / price-source guards before any seed purchase
      - no direct gameplay FireServer / InvokeServer calls
      - cached interaction index to avoid repeated Workspace-wide scans
      - mobile-first WindUI
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
    },
    LastAction = "Idle",
    LastError = "None",
    BestRiverSeed = "Scanning...",
    CurrentWeather = "Unknown",
    SeedCandidates = 0,
}
ENV.NIGHTSHADE_GG_V31 = Runtime

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

    local amount, suffix = s:match("%$%s*([%d]+%.?[%d]*)%s*([KkMmBbTt][AaIi]?|[Qq][AaIi])")
    if not amount then
        amount = s:match("%$%s*([%d]+%.?[%d]*)")
        suffix = ""
    end
    if amount then
        local n = tonumber(amount)
        return n and n * (SUFFIX_MULT[lower(suffix)] or 1) or nil
    end

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

    for _, node in ipairs(nodes) do
        for _, key in ipairs(keys) do
            local v = safeAttr(node, key)
            if v ~= nil then return v, node end
            local child = node:FindFirstChild(key)
            if child and child:IsA("ValueBase") then return child.Value, child end
        end
    end
    return nil, nil
end

local RARITY_RANK = {
    Common = 1, Rare = 2, Epic = 3, Legendary = 4,
    Mythic = 5, Celestial = 6, Secret = 7, Divine = 8,
}

local RARITIES = {"Common", "Rare", "Epic", "Legendary", "Mythic", "Celestial", "Secret", "Divine"}

local SEEDS = {
    ["Oak"]          = {Rarity="Common",    Cost=0},
    ["Pine"]         = {Rarity="Common",    Cost=25},
    ["Apple"]        = {Rarity="Rare",      Cost=200},
    ["Peach"]        = {Rarity="Rare",      Cost=350},
    ["Fig"]          = {Rarity="Rare",      Cost=500},
    ["Orange"]       = {Rarity="Epic",      Cost=10000},
    ["Lemon"]        = {Rarity="Epic",      Cost=15000},
    ["Avocado"]      = {Rarity="Epic",      Cost=20000},
    ["Cherry"]       = {Rarity="Legendary", Cost=2500000},
    ["Mango"]        = {Rarity="Legendary", Cost=5000000},
    ["Coconut"]      = {Rarity="Legendary", Cost=10000000},
    ["Banana"]       = {Rarity="Mythic",    Cost=3000000000},
    ["Starfruit"]    = {Rarity="Mythic",    Cost=4500000000},
    ["Dragon Fruit"] = {Rarity="Mythic",    Cost=7000000000},
    ["Glowing"]      = {Rarity="Celestial", Cost=500000000000},
    ["Blooming"]     = {Rarity="Celestial", Cost=750000000000},
    ["Magic"]        = {Rarity="Secret",    Cost=500000000000000},
    ["Pizza"]        = {Rarity="Secret",    Cost=850000000000000},
    ["Diamond"]      = {Rarity="Divine",    Cost=1000000000000000},
    ["Void"]         = {Rarity="Divine",    Cost=1750000000000000},
}

local SEED_NAMES = {}
for name in pairs(SEEDS) do table.insert(SEED_NAMES, name) end
table.sort(SEED_NAMES, function(a, b)
    local ar = RARITY_RANK[SEEDS[a].Rarity] or 0
    local br = RARITY_RANK[SEEDS[b].Rarity] or 0
    if ar ~= br then return ar < br end
    return SEEDS[a].Cost < SEEDS[b].Cost
end)

local MUTATIONS = {
    Dewy = {Multiplier=2, Weather="Misty"},
    Shocked = {Multiplier=2.5, Weather="Lightning"},
    Radioactive = {Multiplier=5, Weather="Acid Rain"},
    Charged = {Multiplier=7.5, Weather="Lightning"},
    Golden = {Multiplier=25, Weather="Rainbow"},
    Cosmic = {Multiplier=100, Weather="Meteor Shower"},
    Infested = {Weather="Pet"}, Huge = {Weather="Pet"},
    Slimy = {Weather="Pet"}, Scaled = {Weather="Pet"},
}

local EGG_COSTS = {Common=100, Rare=200, Epic=500, Legendary=1000, Mythic=2000}

local Settings = {
    Master = false,
    AutoHarvest = false,
    HarvestAtMultiplier = 1,
    AutoCollectFruit = false,
    UseCollectAll = true,
    AutoClearDead = false,
    AutoPlant = false,
    AutoPlantGrownTrees = false,
    AutoOrganiseTrees = false,
    AutoSellFruits = false,
    AutoSellAll = false,
    AutoSellAtMax = true,
    MinimumFruitsToSell = 1,
    AutoEquipSeed = true,
    OwnPlotOnly = true,
    AutoBuySeeds = false,
    BuyMode = "Highest Affordable",
    PreferredSeed = "Oak",
    MinimumRarity = "Common",
    BuyMutatedOnly = false,
    PreferMutated = true,
    MaxSeedCost = 0,
    KeepCoinReserve = 0,
    SkipIfCashUnknown = true,
    SkipIfPriceUnknown = true,
    RequireFreshAffordability = true,
    SeedDryRun = false,
    RareSeedNotify = true,
    PlantDuringWeatherOnly = false,
    WeatherMisty = true,
    WeatherAcidRain = true,
    WeatherRainbow = true,
    WeatherMeteor = true,
    WeatherUnknown = false,
    NotifyWeather = true,
    AutoGiveMarketFruits = false,
    AutoClaimMarketTickets = false,
    AutoBuyPetEggs = false,
    EggTier = "Rare",
    KeepTicketReserve = 0,
    AutoPlaceEggs = false,
    AutoHatchEggs = false,
    AutoCompostSeeds = false,
    CompostMaxRarity = "Common",
    AutoBuyGear = false,
    AutoBuyWorms = false,
    AutoBuyFurniture = false,
    AutoClaimIndexReward = false,
    AutoRebirth = false,
    StrictRebirthReady = true,
    FarmLoopDelay = 0.18,
    BuyLoopDelay = 0.12,
    MarketLoopDelay = 0.8,
    SupportLoopDelay = 1.25,
    ActionCooldown = 0.22,
    SeedCooldown = 0.35,
    AntiAFK = true,
    Debug = false,
}

local CONFIG_FILE = "nightshade_gg_v31.json"

local function loadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if ok and type(decoded) == "table" then
        for k, v in pairs(decoded) do
            if Settings[k] ~= nil and type(v) == type(Settings[k]) then
                Settings[k] = v
            end
        end
    end
end

local function saveConfig()
    if not writefile then return false, "writefile unavailable" end
    local ok, err = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(Settings))
    end)
    return ok, err
end

loadConfig()

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
local touch = UserInputService.TouchEnabled
local width = touch and math.clamp(viewport.X - 24, 350, 560) or 720
local height = touch and math.clamp(viewport.Y - 60, 310, 500) or 540

local Window = WindUI:CreateWindow({
    Title = "NIGHTSHADE V3.1",
    Icon = "sprout",
    Author = "Greedy Growers",
    Folder = "NightshadeGGV31",
    Size = UDim2.fromOffset(width, height),
    Transparent = false,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = touch and 125 or 175,
    HideSearchBar = touch,
    ScrollBarEnabled = true,
    NewElements = true,
    User = {Enabled=false, Anonymous=true},
})

pcall(function()
    Window:Tag({Title="V3.1", Color=Color3.fromHex("#37D67A")})
    Window:Tag({Title=touch and "MOBILE" or "PC", Color=Color3.fromHex("#309BFF")})
end)

local function notify(title, content, duration)
    pcall(function()
        WindUI:Notify({Title=tostring(title), Content=tostring(content), Duration=duration or 4, Icon="bell"})
    end)
end

local function readNumber(names)
    local wanted = {}
    for _, name in ipairs(names) do wanted[lower(name)] = true end
    local roots = {
        Player:FindFirstChild("leaderstats"), Player:FindFirstChild("Data"), Player:FindFirstChild("Stats"),
        Player:FindFirstChild("Currencies"), Player:FindFirstChild("Inventory"),
    }
    for _, root in ipairs(roots) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if wanted[lower(d.Name)] and (d:IsA("NumberValue") or d:IsA("IntValue")) then
                    return d.Value, safeFullName(d)
                end
            end
        end
    end
    for _, key in ipairs(names) do
        local value = safeAttr(Player, key)
        if type(value) == "number" then return value, "Player." .. key end
    end
    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                local context = d.Name .. " " .. (d.Parent and d.Parent.Name or "")
                if containsAny(context, names) then
                    local parsed = parseCompactNumber(d.Text)
                    if parsed then return parsed, safeFullName(d) .. " (text)" end
                end
            end
        end
    end
    return nil, nil
end

local function cash() return readNumber({"Cash", "Coins", "Money", "Currency", "CASH"}) end
local function tickets() return readNumber({"Tickets", "Ticket", "TICKETS"}) end
local function inventoryCount() return readNumber({"InventoryCount", "InventorySize", "FruitCount", "Storage", "STORAGE_SIZE", "Fruits"}) end
local function inventoryMax() return readNumber({"STORAGE_MAX_SIZE", "StorageMaxSize", "InventoryMax", "MaxInventory", "StorageLimit"}) end

local function character()
    local c = Player.Character
    if not c then return nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or not r or h.Health <= 0 then return nil end
    return c, h, r
end

local function isInteraction(inst)
    return inst and (inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector"))
end

for _, d in ipairs(Workspace:GetDescendants()) do
    if isInteraction(d) then Runtime.InteractionSet[d] = true end
end
connect(Workspace.DescendantAdded, function(d) if isInteraction(d) then Runtime.InteractionSet[d] = true end end)
connect(Workspace.DescendantRemoving, function(d) Runtime.InteractionSet[d] = nil Runtime.LastInteract[d] = nil end)

local function underRoot(inst, root)
    if not root then return true end
    if inst == root then return true end
    local ok, result = pcall(inst.IsDescendantOf, inst, root)
    return ok and result or false
end

local function findInteractions(words, root)
    local out = {}
    for inst in pairs(Runtime.InteractionSet) do
        if isAlive(inst) and underRoot(inst, root) and containsAny(buildText(inst, 5), words) then
            table.insert(out, inst)
        end
    end
    return out
end

local function directPrompt(prompt)
    if not prompt or not isAlive(prompt) or not prompt.Enabled then return false, "invalid prompt" end
    if fireproximityprompt then
        local ok, err = pcall(fireproximityprompt, prompt)
        return ok, err
    end
    local _, _, root = character()
    local parent = prompt.Parent
    local pos
    if parent and parent:IsA("Attachment") then pos = parent.WorldPosition
    elseif parent and parent:IsA("BasePart") then pos = parent.Position
    elseif parent and parent:IsA("Model") then
        local ok, pivot = pcall(parent.GetPivot, parent)
        if ok then pos = pivot.Position end
    end
    if not root or not pos or (root.Position - pos).Magnitude > prompt.MaxActivationDistance + 1 then
        return false, "fireproximityprompt unavailable / out of range"
    end
    local ok, err = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration, 0.03) + 0.03)
        prompt:InputHoldEnd()
    end)
    return ok, err
end

local function directClick(click)
    if not click or not isAlive(click) then return false, "invalid click" end
    if not fireclickdetector then return false, "fireclickdetector unavailable" end
    local ok, err = pcall(fireclickdetector, click)
    return ok, err
end

local function interact(inst, label, customCooldown)
    if not isInteraction(inst) then return false end
    local cooldown = customCooldown or Settings.ActionCooldown
    local last = Runtime.LastInteract[inst] or 0
    if os.clock() - last < cooldown then return false end
    Runtime.LastInteract[inst] = os.clock()
    local ok, err
    if inst:IsA("ProximityPrompt") then ok, err = directPrompt(inst) else ok, err = directClick(inst) end
    if ok then
        Runtime.Stats.Actions = Runtime.Stats.Actions + 1
        Runtime.LastAction = label or "Interact"
        Runtime.LastError = "None"
        return true
    end
    Runtime.LastError = tostring(err)
    return false
end

local function ownState(inst)
    local node = inst
    for _ = 1, 10 do
        if not node or node == Workspace then break end
        if lower(node.Name) == lower(Player.Name) then return true end
        for _, key in ipairs({"OwnerUserId", "OwnerId", "PlayerUserId", "UserId", "Owner"}) do
            local v = safeAttr(node, key)
            if v ~= nil then
                if tonumber(v) == Player.UserId or lower(v) == lower(Player.Name) then return true end
                return false
            end
            local child = node:FindFirstChild(key)
            if child and child:IsA("ValueBase") then
                local cv = child.Value
                if cv == Player or tonumber(tostring(cv)) == Player.UserId or lower(cv) == lower(Player.Name) then return true end
                return false
            end
        end
        node = node.Parent
    end
    return nil
end

local function findNamedRoot(names)
    for _, name in ipairs(names) do
        local root = Workspace:FindFirstChild(name, true)
        if root then return root end
    end
    return nil
end
local function conveyorRoot() return findNamedRoot({"ConveyorSeeds", "SeedConveyor", "Conveyor Seeds"}) end
local function fruitRoot() return findNamedRoot({"FruitSpawns", "Fruits", "Fruit Spawns"}) end
local function marketRoot() return findNamedRoot({"Farmers Market", "FarmersMarket", "MarketRows"}) end

local WEATHER_ALIASES = {
    ["misty"]="Misty", ["mist"]="Misty", ["acid rain"]="Acid Rain", ["acid"]="Acid Rain",
    ["rainbow"]="Rainbow", ["meteor shower"]="Meteor Shower", ["meteor"]="Meteor Shower",
}

local function currentWeather()
    for _, root in ipairs({Workspace, ReplicatedStorage, game}) do
        for _, key in ipairs({"CurrentWeather", "Weather", "ActiveWeather", "WeatherType"}) do
            local v = safeAttr(root, key)
            if v ~= nil then
                for alias, name in pairs(WEATHER_ALIASES) do if contains(v, alias) then return name end end
            end
        end
    end
    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible then
                for alias, name in pairs(WEATHER_ALIASES) do if contains(d.Text, alias) then return name end end
            end
        end
    end
    return "Unknown"
end

local function weatherAllowed()
    if not Settings.PlantDuringWeatherOnly then return true end
    local w = currentWeather()
    if w == "Misty" then return Settings.WeatherMisty end
    if w == "Acid Rain" then return Settings.WeatherAcidRain end
    if w == "Rainbow" then return Settings.WeatherRainbow end
    if w == "Meteor Shower" then return Settings.WeatherMeteor end
    return Settings.WeatherUnknown
end

local function mutationList(inst)
    local found = {}
    local text = buildText(inst, 4)
    for name in pairs(MUTATIONS) do if contains(text, name) then found[name] = true end end
    local raw = readAny(inst, {"Mutation", "Mutations", "Modifiers", "Variant"})
    if raw ~= nil then for name in pairs(MUTATIONS) do if contains(raw, name) then found[name] = true end end end
    local out = {}
    for name in pairs(found) do table.insert(out, name) end
    table.sort(out)
    return out
end

local function isMutated(inst)
    if #mutationList(inst) > 0 then return true end
    local raw = readAny(inst, {"IsMutated", "Mutated"})
    return raw == true
end

local function explicitDisplayedPrice(inst)
    if not inst then return nil, "unknown" end
    local raw = readAny(inst, {"Price", "price", "Cost", "cost", "SeedCost", "PurchasePrice"})
    if type(raw) == "number" then return raw, "replicated" end
    if type(raw) == "string" then
        local parsed = parseCompactNumber(raw)
        if parsed then return parsed, "replicated" end
    end
    local model = firstAncestorModel(inst) or inst
    local inspected = 0
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            inspected = inspected + 1
            if inspected > 40 then break end
            if d.Visible then
                local context = lower(d.Name .. " " .. (d.Parent and d.Parent.Name or ""))
                if containsAny(context, {"price", "cost", "buy"}) or contains(d.Text, "$") then
                    local parsed = parseExplicitCurrency(d.Text)
                    if parsed then return parsed, "display" end
                end
            end
        elseif d:IsA("NumberValue") or d:IsA("IntValue") then
            if containsAny(d.Name, {"price", "cost"}) then return d.Value, "replicated-value" end
        end
    end
    return nil, "unknown"
end

local function seedNameFrom(inst)
    local raw = readAny(inst, {"Seed", "SeedName", "Type", "ItemName"})
    if raw ~= nil then for name in pairs(SEEDS) do if contains(raw, name) then return name end end end
    local text = buildText(inst, 4)
    for name in pairs(SEEDS) do if contains(text, name) then return name end end
    return nil
end

local function seedRarity(inst, seedName)
    local raw = readAny(inst, {"Rarity", "Tier"})
    if raw ~= nil then for _, rarity in ipairs(RARITIES) do if contains(raw, rarity) then return rarity end end end
    if seedName and SEEDS[seedName] then return SEEDS[seedName].Rarity end
    return nil
end

local function seedPrice(inst, seedName)
    local live, source = explicitDisplayedPrice(inst)
    if live ~= nil then return live, source end
    if seedName and SEEDS[seedName] then return SEEDS[seedName].Cost, "database" end
    return nil, "unknown"
end

local function entityUnderRoot(inst, root)
    if not inst or not root then return nil end
    local node = inst
    local last = inst
    while node and node ~= root and node.Parent do
        last = node
        if node.Parent == root then return node end
        node = node.Parent
    end
    return last
end

local function seedCandidates()
    local root = conveyorRoot()
    if not root then Runtime.SeedCandidates = 0 return {} end
    local entities, seen = {}, {}
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, root) then
            local entity = entityUnderRoot(interaction, root)
            if entity and not seen[entity] then
                local name = seedNameFrom(entity)
                if name or contains(buildText(entity, 3), "seed") then
                    seen[entity] = true
                    table.insert(entities, entity)
                end
            end
        end
    end
    Runtime.SeedCandidates = #entities
    return entities
end

local function seedInteraction(entity)
    local best, fallback
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, entity) then
            fallback = fallback or interaction
            if containsAny(buildText(interaction, 3), {"buy", "purchase", "get seed", "seed"}) then best = interaction break end
        end
    end
    return best or fallback
end

local function affordability(entity)
    local name = seedNameFrom(entity)
    local rarity = seedRarity(entity, name)
    local price, source = seedPrice(entity, name)
    local money = cash()
    if money == nil and Settings.SkipIfCashUnknown then return false, "cash unknown", name, rarity, price, source, money end
    if price == nil and Settings.SkipIfPriceUnknown then return false, "price unknown", name, rarity, price, source, money end
    if price and Settings.MaxSeedCost > 0 and price > Settings.MaxSeedCost then return false, "over max cost", name, rarity, price, source, money end
    if money ~= nil and price ~= nil and (money - price) < Settings.KeepCoinReserve then return false, "unaffordable", name, rarity, price, source, money end
    if Settings.BuyMutatedOnly and not isMutated(entity) then return false, "not mutated", name, rarity, price, source, money end
    if Settings.BuyMode == "Specific Seed" and lower(name) ~= lower(Settings.PreferredSeed) then return false, "wrong seed", name, rarity, price, source, money end
    if Settings.BuyMode == "Minimum Rarity" then
        local got = RARITY_RANK[rarity] or 0
        local needed = RARITY_RANK[Settings.MinimumRarity] or 1
        if got < needed then return false, "below rarity", name, rarity, price, source, money end
    end
    return true, "allowed", name, rarity, price, source, money
end

local function candidateScore(entity)
    local ok, _, _, rarity, price = affordability(entity)
    if not ok then return -math.huge end
    if Settings.BuyMode == "Any Affordable" or Settings.BuyMode == "Specific Seed" then return 1 end
    local score = (RARITY_RANK[rarity] or 0) * 1e12 + math.min(price or 0, 9e11)
    if Settings.PreferMutated and isMutated(entity) then score = score + 1e11 end
    return score
end

local RareNotice = setmetatable({}, {__mode="k"})

local function selectRiverSeed()
    local candidates = seedCandidates()
    local best, bestScore
    for _, entity in ipairs(candidates) do
        local ok, reason, name, rarity, price, source = affordability(entity)
        if Settings.RareSeedNotify and rarity and (RARITY_RANK[rarity] or 0) >= 4 and not RareNotice[entity] then
            RareNotice[entity] = true
            notify("River Seed // " .. rarity, (name or entity.Name) .. " • $" .. abbreviate(price) .. " • " .. source .. " • " .. (ok and "eligible" or reason), 5)
        end
        if ok then
            if Settings.BuyMode == "Any Affordable" then best = entity break end
            local score = candidateScore(entity)
            if not bestScore or score > bestScore then best, bestScore = entity, score end
        end
    end
    if best then
        local _, _, name, rarity, price, source = affordability(best)
        Runtime.BestRiverSeed = (name or best.Name) .. " • " .. (rarity or "?") .. " • $" .. abbreviate(price) .. " • " .. source
        return best
    end
    Runtime.BestRiverSeed = #candidates > 0 and "No eligible seed" or "No conveyor seeds detected"
    return nil
end

local function buyBestSeed()
    local entity = selectRiverSeed()
    if not entity then return false end
    local last = Runtime.LastSeedTry[entity] or 0
    if os.clock() - last < Settings.SeedCooldown then return false end
    Runtime.LastSeedTry[entity] = os.clock()
    local ok, reason, name, rarity, price, source = affordability(entity)
    if not ok then
        Runtime.Stats.SeedsSkipped = Runtime.Stats.SeedsSkipped + 1
        Runtime.LastError = reason
        return false
    end
    if Settings.RequireFreshAffordability then
        task.wait()
        local ok2, reason2, name2, rarity2, price2, source2 = affordability(entity)
        if not ok2 then
            Runtime.Stats.SeedsSkipped = Runtime.Stats.SeedsSkipped + 1
            Runtime.LastError = "fresh-check: " .. reason2
            return false
        end
        name, rarity, price, source = name2, rarity2, price2, source2
    end
    local interaction = seedInteraction(entity)
    if not interaction then Runtime.LastError = "eligible seed had no interaction" return false end
    if Settings.SeedDryRun then Runtime.LastAction = "DRY RUN: " .. (name or entity.Name) Runtime.LastError = "None" return true end
    if interact(interaction, "Buy Seed // " .. (name or entity.Name), Settings.SeedCooldown) then
        Runtime.Stats.SeedsBought = Runtime.Stats.SeedsBought + 1
        if Settings.RareSeedNotify and rarity and (RARITY_RANK[rarity] or 0) >= 4 then
            notify("Seed Sniped", (name or "Seed") .. " • " .. rarity .. " • $" .. abbreviate(price) .. " • " .. source, 4)
        end
        return true
    end
    return false
end

local function seedTools()
    local out = {}
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and (contains(t.Name, "seed") or seedNameFrom(t)) then table.insert(out, t) end
        end
    end
    scan(Player.Character)
    scan(Player:FindFirstChildOfClass("Backpack"))
    return out
end

local function bestSeedTool()
    local best, bestScore
    for _, tool in ipairs(seedTools()) do
        local name = seedNameFrom(tool)
        local rarity = seedRarity(tool, name)
        local score = (RARITY_RANK[rarity] or 0) * 1e12 + (name and SEEDS[name] and math.min(SEEDS[name].Cost, 9e11) or 0)
        if name == Settings.PreferredSeed then score = score + 1e13 end
        if isMutated(tool) then score = score + 1e11 end
        if not bestScore or score > bestScore then best, bestScore = tool, score end
    end
    return best
end

local function equipBestSeed()
    if not Settings.AutoEquipSeed then return true end
    local c, h = character()
    if not h then return false end
    local tool = bestSeedTool()
    if not tool then return false end
    if tool.Parent == c then return true end
    pcall(h.EquipTool, h, tool)
    task.wait(0.05)
    return tool.Parent == c
end

local function treeCandidates()
    local out, seen = {}, {}
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and containsAny(buildText(interaction, 4), {"treebaseprompt", "harvest", "tree", "dead tree"}) then
            local model = firstAncestorModel(interaction)
            if model and not seen[model] then
                local own = ownState(model)
                if not Settings.OwnPlotOnly or own ~= false then seen[model] = true table.insert(out, model) end
            end
        end
    end
    return out
end

local function treeMultiplier(tree)
    local v = readAny(tree, {"HarvestMultiplier", "Multiplier", "GrowthMultiplier"})
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v:match("[%d%.]+")) or 0 end
    for _, d in ipairs(tree:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible then
            local m = d.Text:match("[xX]%s*([%d%.]+)") or d.Text:match("([%d%.]+)%s*[xX]")
            if m then return tonumber(m) or 0 end
        end
    end
    return 0
end

local function treeDead(tree)
    local v = readAny(tree, {"IsDead", "Dead", "Destroyed"})
    if v == true then return true end
    return containsAny(buildText(tree, 2), {"dead tree", "withered", "isdead"})
end

local function actionIn(root, words)
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, root) and containsAny(buildText(interaction, 3), words) then return interaction end
    end
    return nil
end

local function harvestOne()
    local best, bestMult
    for _, tree in ipairs(treeCandidates()) do
        if not treeDead(tree) then
            local mult = treeMultiplier(tree)
            if mult >= Settings.HarvestAtMultiplier and (not bestMult or mult > bestMult) then best, bestMult = tree, mult end
        end
    end
    if not best then return false end
    local action = actionIn(best, {"harvest", "treebaseprompt", "chop"})
    if action and interact(action, "Harvest x" .. tostring(bestMult)) then Runtime.Stats.Harvests = Runtime.Stats.Harvests + 1 return true end
    return false
end

local function clearDeadOne()
    for _, tree in ipairs(treeCandidates()) do
        if treeDead(tree) then
            local action = actionIn(tree, {"dead", "clear", "remove", "collect", "chop"})
            if action and interact(action, "Clear Dead Tree") then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
        end
    end
    return false
end

local function plantOne()
    if not weatherAllowed() or not equipBestSeed() then return false end
    for _, interaction in ipairs(findInteractions({"plant", "seedplot", "plant seed", "dirt"})) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then
            if interact(interaction, "Plant Seed") then Runtime.Stats.Plants = Runtime.Stats.Plants + 1 return true end
        end
    end
    return false
end

local function plantGrownTreeOne()
    for _, interaction in ipairs(findInteractions({"plant grown tree", "grown tree", "replant tree"})) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then
            if interact(interaction, "Plant Grown Tree") then Runtime.Stats.Plants = Runtime.Stats.Plants + 1 return true end
        end
    end
    return false
end

local function organiseOne()
    for _, interaction in ipairs(findInteractions({"organise", "organize", "arrange tree"})) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then if interact(interaction, "Organise Trees") then return true end end
    end
    return false
end

local function collectOneFruit()
    if Settings.UseCollectAll then
        for _, interaction in ipairs(findInteractions({"collect all"})) do
            local own = ownState(interaction)
            if not Settings.OwnPlotOnly or own ~= false then
                if interact(interaction, "Collect All Fruits") then Runtime.Stats.Fruits = Runtime.Stats.Fruits + 1 return true end
            end
        end
    end
    local root = fruitRoot()
    if root then
        for interaction in pairs(Runtime.InteractionSet) do
            if isAlive(interaction) and underRoot(interaction, root) then
                local own = ownState(interaction)
                if not Settings.OwnPlotOnly or own ~= false then
                    if interact(interaction, "Collect Fruit") then Runtime.Stats.Fruits = Runtime.Stats.Fruits + 1 return true end
                end
            end
        end
    end
    return false
end

local function storageFull()
    local used, maximum = inventoryCount(), inventoryMax()
    return used ~= nil and maximum ~= nil and maximum > 0 and used >= maximum
end

local function sell(kind)
    local stand = findNamedRoot({"SellStand", "Sell Stand"})
    local words = kind == "all" and {"sell all", "sell everything"} or {"sell fruits", "sell fruit", "sell"}
    for _, interaction in ipairs(findInteractions(words, stand)) do
        if interact(interaction, kind == "all" and "Sell All" or "Sell Fruits") then Runtime.Stats.Sells = Runtime.Stats.Sells + 1 return true end
    end
    return false
end

local function marketGive()
    local root = marketRoot()
    if not root then return false end
    for _, interaction in ipairs(findInteractions({"give", "submit", "turn in", "deliver"}, root)) do
        if interact(interaction, "Give Market Fruits") then Runtime.Stats.Market = Runtime.Stats.Market + 1 return true end
    end
    return false
end

local function marketClaim()
    local root = marketRoot()
    if not root then return false end
    for _, interaction in ipairs(findInteractions({"claim", "ticket", "reward"}, root)) do
        if interact(interaction, "Claim Market Tickets") then Runtime.Stats.Market = Runtime.Stats.Market + 1 return true end
    end
    return false
end

local function eggTierFrom(inst)
    local raw = readAny(inst, {"Rarity", "Tier", "EggTier"})
    if raw ~= nil then for tier in pairs(EGG_COSTS) do if contains(raw, tier) then return tier end end end
    local text = buildText(inst, 5)
    for tier in pairs(EGG_COSTS) do if contains(text, tier) and containsAny(text, {"egg", "pet"}) then return tier end end
    return nil
end

local function buyEgg()
    local root = findNamedRoot({"Pet Shop", "PetShop", "Eggs"})
    if not root then return false end
    local balance = tickets()
    if balance == nil then return false end
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, root) then
            local tier = eggTierFrom(interaction)
            if tier == Settings.EggTier then
                local live = explicitDisplayedPrice(interaction)
                local cost = live or EGG_COSTS[tier]
                if cost and balance - cost >= Settings.KeepTicketReserve then
                    if interact(interaction, "Buy " .. tier .. " Egg") then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
                end
            end
        end
    end
    return false
end

local function eggAction(words, label)
    for _, interaction in ipairs(findInteractions(words)) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then
            if interact(interaction, label) then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
        end
    end
    return false
end

local function rarityAtMost(tool, maxRarity)
    local name = seedNameFrom(tool)
    local rarity = seedRarity(tool, name)
    return rarity and (RARITY_RANK[rarity] or 99) <= (RARITY_RANK[maxRarity] or 1)
end

local function compostOne()
    local bin = findNamedRoot({"CompostBin", "Compost Bin", "Compost"})
    if not bin then return false end
    local _, h = character()
    if not h then return false end
    local chosen
    for _, tool in ipairs(seedTools()) do if rarityAtMost(tool, Settings.CompostMaxRarity) then chosen = tool break end end
    if not chosen then return false end
    pcall(h.EquipTool, h, chosen)
    task.wait(0.05)
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, bin) then
            if interact(interaction, "Compost Seed") then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
        end
    end
    return false
end

local function shopAction(shopNames, words, label)
    local root = findNamedRoot(shopNames)
    if not root then return false end
    local money = cash()
    if money == nil then return false end
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, root) and containsAny(buildText(interaction, 4), words) then
            local cost = explicitDisplayedPrice(interaction)
            if cost ~= nil and money - cost >= Settings.KeepCoinReserve then
                if interact(interaction, label) then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
            end
        end
    end
    return false
end

local function claimIndex()
    for _, interaction in ipairs(findInteractions({"claim index", "index reward", "claim reward"})) do
        if interact(interaction, "Claim Index Reward") then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
    end
    return false
end

local function rebirthReady()
    for _, key in ipairs({"CanRebirth", "RebirthReady", "ReadyToRebirth"}) do if safeAttr(Player, key) == true then return true end end
    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible and containsAny(d.Text, {"rebirth ready", "ready to rebirth", "rebirth available"}) then return true end
        end
    end
    return not Settings.StrictRebirthReady
end

local function rebirth()
    if not rebirthReady() then return false end
    for _, interaction in ipairs(findInteractions({"rebirth"})) do
        if interact(interaction, "Rebirth") then Runtime.Stats.Support = Runtime.Stats.Support + 1 return true end
    end
    return false
end

local function enabled(toggle) return Runtime.Running and Settings.Master and toggle end

task.spawn(function()
    while Runtime.Running do
        local acted = false
        if enabled(Settings.AutoClearDead) then acted = clearDeadOne() end
        if enabled(Settings.AutoSellAtMax) and not acted and storageFull() then acted = sell(Settings.AutoSellAll and "all" or "fruits") end
        if enabled(Settings.AutoHarvest) and not acted then acted = harvestOne() end
        if enabled(Settings.AutoCollectFruit) and not acted then acted = collectOneFruit() end
        if enabled(Settings.AutoPlant) and not acted then acted = plantOne() end
        if enabled(Settings.AutoPlantGrownTrees) and not acted then acted = plantGrownTreeOne() end
        if enabled(Settings.AutoOrganiseTrees) and not acted then acted = organiseOne() end
        if enabled(Settings.AutoSellFruits) and not acted then
            local used = inventoryCount()
            if not used or used >= Settings.MinimumFruitsToSell then acted = sell("fruits") end
        end
        if enabled(Settings.AutoSellAll) and not acted then acted = sell("all") end
        task.wait(acted and Settings.ActionCooldown or Settings.FarmLoopDelay)
    end
end)

task.spawn(function()
    while Runtime.Running do
        if enabled(Settings.AutoBuySeeds) then pcall(buyBestSeed) else pcall(selectRiverSeed) end
        task.wait(Settings.BuyLoopDelay)
    end
end)

task.spawn(function()
    while Runtime.Running do
        if Settings.Master then
            if Settings.AutoGiveMarketFruits then pcall(marketGive) end
            if Settings.AutoClaimMarketTickets then pcall(marketClaim) end
            if Settings.AutoBuyPetEggs then pcall(buyEgg) end
            if Settings.AutoPlaceEggs then pcall(eggAction, {"place egg", "set egg"}, "Place Egg") end
            if Settings.AutoHatchEggs then pcall(eggAction, {"hatch egg", "hatch"}, "Hatch Egg") end
        end
        task.wait(Settings.MarketLoopDelay)
    end
end)

task.spawn(function()
    while Runtime.Running do
        if Settings.Master then
            if Settings.AutoCompostSeeds then pcall(compostOne) end
            if Settings.AutoBuyGear then pcall(shopAction, {"Gear Shop"}, {"buy", "gear", "fertilizer"}, "Buy Gear") end
            if Settings.AutoBuyWorms then pcall(shopAction, {"Worm Shop"}, {"buy", "worm", "can of worms"}, "Buy Worms") end
            if Settings.AutoBuyFurniture then pcall(shopAction, {"Furniture Shop", "Decor"}, {"buy", "furniture", "decor"}, "Buy Furniture") end
            if Settings.AutoClaimIndexReward then pcall(claimIndex) end
            if Settings.AutoRebirth then pcall(rebirth) end
        end
        task.wait(Settings.SupportLoopDelay)
    end
end)

local lastWeather
task.spawn(function()
    while Runtime.Running do
        local w = currentWeather()
        Runtime.CurrentWeather = w
        if Settings.NotifyWeather and w ~= lastWeather then
            lastWeather = w
            if w ~= "Unknown" then
                local msg = "Weather active"
                if w == "Misty" then msg = "Dewy mutation opportunity"
                elseif w == "Acid Rain" then msg = "Radioactive mutation opportunity"
                elseif w == "Rainbow" then msg = "Golden mutation opportunity"
                elseif w == "Meteor Shower" then msg = "Cosmic mutation opportunity" end
                notify("Weather // " .. w, msg, 5)
            end
        end
        task.wait(0.7)
    end
end)

if Settings.AntiAFK then
    connect(Player.Idled, function()
        if not Settings.AntiAFK then return end
        pcall(function()
            local camera = Workspace.CurrentCamera
            VirtualUser:Button2Down(Vector2.new(0, 0), camera and camera.CFrame or CFrame.new())
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0, 0), camera and camera.CFrame or CFrame.new())
        end)
    end)
end

local Home = Window:Tab({Title="Home", Icon="house"})
local Farm = Window:Tab({Title="Farm", Icon="sprout"})
local SeedsTab = Window:Tab({Title="Seeds", Icon="package"})
local Weather = Window:Tab({Title="Weather", Icon="cloud-lightning"})
local Market = Window:Tab({Title="Market", Icon="store"})
local Pets = Window:Tab({Title="Pets", Icon="paw-print"})
local Utility = Window:Tab({Title="Utility", Icon="wrench"})
local Diagnostics = Window:Tab({Title="Diagnostics", Icon="scan-search"})

local Status = Home:Paragraph({Title="NIGHTSHADE V3.1", Desc="Loading snapshot...", Image="sprout"})

local function snapshot()
    local money, moneySource = cash()
    local tix, ticketSource = tickets()
    local used, maximum = inventoryCount(), inventoryMax()
    return table.concat({
        "Place: " .. tostring(game.PlaceId) .. (game.PlaceId == EXPECTED_PLACE_ID and " ✓" or " ⚠"),
        "Cash: $" .. abbreviate(money) .. " • " .. tostring(moneySource or "unknown source"),
        "Tickets: " .. abbreviate(tix) .. " • " .. tostring(ticketSource or "unknown source"),
        "Storage: " .. tostring(used or "?") .. "/" .. tostring(maximum or "?"),
        "Weather: " .. Runtime.CurrentWeather,
        "River candidates: " .. tostring(Runtime.SeedCandidates),
        "Best river seed: " .. Runtime.BestRiverSeed,
        "Last: " .. Runtime.LastAction,
        "Last error: " .. Runtime.LastError,
        "Actions: " .. Runtime.Stats.Actions .. " • Seeds: " .. Runtime.Stats.SeedsBought .. " • Harvests: " .. Runtime.Stats.Harvests,
        "fireproximityprompt=" .. tostring(fireproximityprompt ~= nil) .. " • fireclickdetector=" .. tostring(fireclickdetector ~= nil),
    }, "\n")
end

local function refreshStatus() pcall(function() Status:SetDesc(snapshot()) end) end

Home:Toggle({Title="MASTER AUTOMATION", Desc="Global kill switch.", Value=Settings.Master, Callback=function(v) Settings.Master=v end})
Home:Button({Title="Refresh Status", Icon="refresh-cw", Callback=refreshStatus})
Home:Button({Title="Save Settings", Icon="save", Callback=function() local ok, err=saveConfig() notify(ok and "Saved" or "Save failed", ok and CONFIG_FILE or tostring(err), 3) end})
Home:Button({Title="Panic Stop", Icon="octagon", Callback=function() Settings.Master=false notify("Automation stopped", "Master switch is OFF.", 3) end})
Home:Paragraph({Title="V3.1 buyer guard", Desc="The river buyer reads an explicit live Price/Cost first, falls back to the seed database only for recognized seeds, checks affordability, then checks it again immediately before the interaction.", Image="shield-check"})

Farm:Toggle({Title="Auto Harvest", Value=Settings.AutoHarvest, Callback=function(v) Settings.AutoHarvest=v end})
Farm:Slider({Title="Harvest At Multiplier", Value={Min=1,Max=100,Default=Settings.HarvestAtMultiplier}, Step=0.5, Callback=function(v) Settings.HarvestAtMultiplier=v end})
Farm:Toggle({Title="Auto Collect Fruit", Value=Settings.AutoCollectFruit, Callback=function(v) Settings.AutoCollectFruit=v end})
Farm:Toggle({Title="Use Collect All First", Value=Settings.UseCollectAll, Callback=function(v) Settings.UseCollectAll=v end})
Farm:Toggle({Title="Auto Clear Dead Trees", Value=Settings.AutoClearDead, Callback=function(v) Settings.AutoClearDead=v end})
Farm:Toggle({Title="Auto Plant", Value=Settings.AutoPlant, Callback=function(v) Settings.AutoPlant=v end})
Farm:Toggle({Title="Auto Plant Grown Trees", Value=Settings.AutoPlantGrownTrees, Callback=function(v) Settings.AutoPlantGrownTrees=v end})
Farm:Toggle({Title="Auto Equip Best Seed", Value=Settings.AutoEquipSeed, Callback=function(v) Settings.AutoEquipSeed=v end})
Farm:Toggle({Title="Own Plot Only", Value=Settings.OwnPlotOnly, Callback=function(v) Settings.OwnPlotOnly=v end})
Farm:Toggle({Title="Auto Organise Trees", Value=Settings.AutoOrganiseTrees, Callback=function(v) Settings.AutoOrganiseTrees=v end})
Farm:Toggle({Title="Auto Sell Fruits", Value=Settings.AutoSellFruits, Callback=function(v) Settings.AutoSellFruits=v end})
Farm:Toggle({Title="Auto Sell All", Value=Settings.AutoSellAll, Callback=function(v) Settings.AutoSellAll=v end})
Farm:Toggle({Title="Auto Sell At Max Inventory", Value=Settings.AutoSellAtMax, Callback=function(v) Settings.AutoSellAtMax=v end})
Farm:Slider({Title="Minimum Fruits To Sell", Value={Min=1,Max=200,Default=Settings.MinimumFruitsToSell}, Step=1, Callback=function(v) Settings.MinimumFruitsToSell=v end})

SeedsTab:Toggle({Title="Auto Buy Seeds — NO MOVEMENT", Desc="Directly uses the conveyor seed interaction when supported.", Value=Settings.AutoBuySeeds, Callback=function(v) Settings.AutoBuySeeds=v end})
SeedsTab:Dropdown({Title="Buy Mode", Values={"Highest Affordable","Any Affordable","Specific Seed","Minimum Rarity"}, Value=Settings.BuyMode, Callback=function(v) Settings.BuyMode=v end})
SeedsTab:Dropdown({Title="Preferred / Specific Seed", Values=SEED_NAMES, Value=Settings.PreferredSeed, SearchBarEnabled=true, Callback=function(v) Settings.PreferredSeed=v end})
SeedsTab:Dropdown({Title="Minimum Rarity", Values=RARITIES, Value=Settings.MinimumRarity, Callback=function(v) Settings.MinimumRarity=v end})
SeedsTab:Toggle({Title="Only Mutated Seeds", Value=Settings.BuyMutatedOnly, Callback=function(v) Settings.BuyMutatedOnly=v end})
SeedsTab:Toggle({Title="Prefer Mutated When Choosing", Value=Settings.PreferMutated, Callback=function(v) Settings.PreferMutated=v end})
SeedsTab:Input({Title="Max Cost Per Seed (0 = off)", Value=tostring(Settings.MaxSeedCost), Placeholder="0", Callback=function(v) Settings.MaxSeedCost=tonumber(v) or 0 end})
SeedsTab:Input({Title="Keep Coin Reserve", Value=tostring(Settings.KeepCoinReserve), Placeholder="0", Callback=function(v) Settings.KeepCoinReserve=tonumber(v) or 0 end})
SeedsTab:Toggle({Title="Skip If Cash Unknown", Desc="Recommended ON.", Value=Settings.SkipIfCashUnknown, Callback=function(v) Settings.SkipIfCashUnknown=v end})
SeedsTab:Toggle({Title="Skip If Price Unknown", Desc="Recommended ON.", Value=Settings.SkipIfPriceUnknown, Callback=function(v) Settings.SkipIfPriceUnknown=v end})
SeedsTab:Toggle({Title="Fresh Affordability Re-check", Desc="Checks cash and price again immediately before buying.", Value=Settings.RequireFreshAffordability, Callback=function(v) Settings.RequireFreshAffordability=v end})
SeedsTab:Toggle({Title="Dry Run", Desc="Selects/logs seeds but never presses Buy.", Value=Settings.SeedDryRun, Callback=function(v) Settings.SeedDryRun=v end})
SeedsTab:Toggle({Title="Rare Seed Notifications", Value=Settings.RareSeedNotify, Callback=function(v) Settings.RareSeedNotify=v end})
SeedsTab:Button({Title="Scan River Now", Icon="scan-search", Callback=function() selectRiverSeed() notify("River scan", Runtime.BestRiverSeed, 5) end})
SeedsTab:Button({Title="Buy Best Eligible Seed Once", Icon="shopping-cart", Callback=function() local ok=buyBestSeed() notify("Seed buyer", ok and (Settings.SeedDryRun and "Dry-run target selected." or "Purchase interaction sent.") or ("Skipped • " .. Runtime.LastError), 4) end})

Weather:Toggle({Title="Only Plant During Selected Weather", Value=Settings.PlantDuringWeatherOnly, Callback=function(v) Settings.PlantDuringWeatherOnly=v end})
Weather:Toggle({Title="Misty / Dewy", Value=Settings.WeatherMisty, Callback=function(v) Settings.WeatherMisty=v end})
Weather:Toggle({Title="Acid Rain / Radioactive", Value=Settings.WeatherAcidRain, Callback=function(v) Settings.WeatherAcidRain=v end})
Weather:Toggle({Title="Rainbow / Golden", Value=Settings.WeatherRainbow, Callback=function(v) Settings.WeatherRainbow=v end})
Weather:Toggle({Title="Meteor Shower / Cosmic", Value=Settings.WeatherMeteor, Callback=function(v) Settings.WeatherMeteor=v end})
Weather:Toggle({Title="Allow Unknown Weather", Value=Settings.WeatherUnknown, Callback=function(v) Settings.WeatherUnknown=v end})
Weather:Toggle({Title="Weather Notifications", Value=Settings.NotifyWeather, Callback=function(v) Settings.NotifyWeather=v end})
Weather:Button({Title="Current Weather", Callback=function() notify("Weather", currentWeather(), 4) end})
Weather:Paragraph({Title="Known mutation signals", Desc="Dewy, Shocked, Radioactive, Charged, Golden, Cosmic, Infested, Huge, Slimy and Scaled are recognized when exposed in replicated attributes/UI.", Image="sparkles"})

Market:Toggle({Title="Auto Give Market Fruits", Value=Settings.AutoGiveMarketFruits, Callback=function(v) Settings.AutoGiveMarketFruits=v end})
Market:Toggle({Title="Auto Claim Market Tickets", Value=Settings.AutoClaimMarketTickets, Callback=function(v) Settings.AutoClaimMarketTickets=v end})
Market:Button({Title="Give Market Fruit Once", Callback=function() notify("Market", marketGive() and "Submitted." or "No eligible interaction found.", 3) end})
Market:Button({Title="Claim Market Tickets Once", Callback=function() notify("Market", marketClaim() and "Claimed." or "Nothing claimable found.", 3) end})

Pets:Toggle({Title="Auto Buy Pet Eggs", Value=Settings.AutoBuyPetEggs, Callback=function(v) Settings.AutoBuyPetEggs=v end})
Pets:Dropdown({Title="Egg Tier", Values={"Common","Rare","Epic","Legendary","Mythic"}, Value=Settings.EggTier, Callback=function(v) Settings.EggTier=v end})
Pets:Input({Title="Keep Ticket Reserve", Value=tostring(Settings.KeepTicketReserve), Placeholder="0", Callback=function(v) Settings.KeepTicketReserve=tonumber(v) or 0 end})
Pets:Toggle({Title="Auto Place Eggs", Value=Settings.AutoPlaceEggs, Callback=function(v) Settings.AutoPlaceEggs=v end})
Pets:Toggle({Title="Auto Hatch Eggs", Value=Settings.AutoHatchEggs, Callback=function(v) Settings.AutoHatchEggs=v end})
Pets:Paragraph({Title="Ticket-safe egg buyer", Desc="Reads a live displayed egg price when available; otherwise uses the selected tier's known ticket cost, and skips if your reserve would be crossed.", Image="egg"})

Utility:Toggle({Title="Auto Compost Low-Rarity Seeds", Value=Settings.AutoCompostSeeds, Callback=function(v) Settings.AutoCompostSeeds=v end})
Utility:Dropdown({Title="Compost Up To Rarity", Values=RARITIES, Value=Settings.CompostMaxRarity, Callback=function(v) Settings.CompostMaxRarity=v end})
Utility:Toggle({Title="Auto Buy Gear (live price only)", Value=Settings.AutoBuyGear, Callback=function(v) Settings.AutoBuyGear=v end})
Utility:Toggle({Title="Auto Buy Worms (live price only)", Value=Settings.AutoBuyWorms, Callback=function(v) Settings.AutoBuyWorms=v end})
Utility:Toggle({Title="Auto Buy Furniture (live price only)", Value=Settings.AutoBuyFurniture, Callback=function(v) Settings.AutoBuyFurniture=v end})
Utility:Toggle({Title="Auto Claim Index Reward", Value=Settings.AutoClaimIndexReward, Callback=function(v) Settings.AutoClaimIndexReward=v end})
Utility:Toggle({Title="Auto Rebirth", Value=Settings.AutoRebirth, Callback=function(v) Settings.AutoRebirth=v end})
Utility:Toggle({Title="Strict Rebirth Ready Check", Value=Settings.StrictRebirthReady, Callback=function(v) Settings.StrictRebirthReady=v end})
Utility:Toggle({Title="Anti AFK", Value=Settings.AntiAFK, Callback=function(v) Settings.AntiAFK=v end})
Utility:Button({Title="Save Settings", Icon="save", Callback=function() local ok, err=saveConfig() notify("Settings", ok and "Saved." or tostring(err), 3) end})

Diagnostics:Button({Title="Executor Capability Check", Callback=function()
    notify("Capabilities", "fireproximityprompt: " .. tostring(fireproximityprompt ~= nil) .. "\nfireclickdetector: " .. tostring(fireclickdetector ~= nil) .. "\nclipboard: " .. tostring(setclipboard ~= nil) .. "\nfiles: " .. tostring(writefile ~= nil), 7)
end})

Diagnostics:Button({Title="Print Greedy Growers Surfaces", Callback=function()
    local names = {"ConveyorSeeds", "FruitSpawns", "SellStand", "CompostBin", "Worm Shop", "Gear Shop", "Pet Shop", "Farmers Market", "SeedPlot"}
    print("========== NIGHTSHADE V3.1 // SURFACES ==========")
    for _, name in ipairs(names) do local obj=Workspace:FindFirstChild(name, true) print(name, obj and safeFullName(obj) or "NOT FOUND") end
    print("==================================================")
    notify("Diagnostics", "Printed surface scan to console.", 4)
end})

Diagnostics:Button({Title="Print River Candidates", Callback=function()
    print("========== NIGHTSHADE V3.1 // RIVER ==========")
    for i, entity in ipairs(seedCandidates()) do
        local ok, reason, name, rarity, price, source, money = affordability(entity)
        print(i, safeFullName(entity), "|", name, rarity, price, source, "cash", money, ok and "ELIGIBLE" or reason)
    end
    print("==============================================")
    notify("Diagnostics", tostring(Runtime.SeedCandidates) .. " river candidates printed.", 4)
end})

Diagnostics:Button({Title="Print All Prompts / Clicks", Callback=function()
    print("========== NIGHTSHADE V3.1 // INTERACTIONS ==========")
    local count = 0
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) then
            count = count + 1
            if interaction:IsA("ProximityPrompt") then print(count, safeFullName(interaction), "|", interaction.ActionText, "|", interaction.ObjectText)
            else print(count, safeFullName(interaction), "| ClickDetector") end
        end
    end
    print("Total:", count)
    print("======================================================")
    notify("Diagnostics", tostring(count) .. " interactions printed.", 4)
end})

Diagnostics:Button({Title="Copy Snapshot", Callback=function()
    local s = snapshot()
    if setclipboard then pcall(setclipboard, s) notify("Snapshot", "Copied.", 3) else print(s) notify("Snapshot", "Clipboard unavailable; printed.", 4) end
end})
Diagnostics:Toggle({Title="Debug Logging", Value=Settings.Debug, Callback=function(v) Settings.Debug=v end})

function Runtime.Stop()
    Runtime.Running = false
    Settings.Master = false
    pcall(saveConfig)
    for _, c in ipairs(Runtime.Connections) do pcall(c.Disconnect, c) end
    Runtime.Connections = {}
    pcall(function() Window:Destroy() end)
end

task.delay(0.8, refreshStatus)
task.spawn(function() while Runtime.Running do task.wait(2) refreshStatus() end end)

if game.PlaceId ~= EXPECTED_PLACE_ID then
    notify("Place warning", "Expected Greedy Growers " .. EXPECTED_PLACE_ID .. ", current " .. tostring(game.PlaceId), 7)
end

notify("NIGHTSHADE V3.1 loaded", touch and "Mobile WindUI • strict seed sniper ready" or "WindUI • strict seed sniper ready", 5)
print("[NIGHTSHADE V3.1] Loaded")
print("[NIGHTSHADE V3.1] fireproximityprompt:", fireproximityprompt ~= nil)
print("[NIGHTSHADE V3.1] fireclickdetector:", fireclickdetector ~= nil)
