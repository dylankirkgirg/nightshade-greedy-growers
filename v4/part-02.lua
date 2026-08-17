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

--========================================================
-- GAME DATA
--========================================================

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

--========================================================
-- SETTINGS
--========================================================

local Settings = {
    Master = false,

    AutoHarvest = false,
    HarvestAtMultiplier = 1,
    AutoCollectFruit = false,
    UseCollectAll = true,
    AutoClearDead = false,
    DeadSweepMaxPasses = 8,
    DeadSweepMaxActions = 32,
    DeadConfirmTimeout = 1.0,
    DeadRescanDelay = 0.08,
    DeadRetryBackoff = 2.5,
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

local CONFIG_FILE = "nightshade_gg_v4.json"

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

--========================================================
-- WINDUI // CROSS-DEVICE UI
--========================================================

local UIS = UserInputService
local touch = UIS.TouchEnabled
local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()
ENV.NIGHTSHADE_WINDUI = WindUI

local function viewportSize()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function deviceLayout()
    local vp = viewportSize()
    local phone = touch and math.min(vp.X, vp.Y) < 600
    local tablet = touch and not phone

    local marginX = phone and 18 or 30
    local marginY = phone and 54 or 70

    local width
    local height
    local sidebar

    if phone then
        width = math.clamp(vp.X - marginX, 340, 560)
        height = math.clamp(vp.Y - marginY, 285, 470)
