--[[
    NIGHTSHADE // Greedy Growers
    Research-informed local mechanics QA / automation harness

    IMPORTANT:
      * Normal automation contains no direct gameplay FireServer()/InvokeServer() calls.
      * Protection Lab optionally calls ONLY the dedicated NightshadeSecurity test remotes.
      * "Mechanics" mode uses normal local character movement + ProximityPrompt input.
        Your game may still process those normal interactions on the server, as Roblox normally does.
      * "Pure Local" mode never activates prompts; it only simulates/logs what it WOULD do locally.
      * No currency spawning, inventory cloning, teleport farming, remote spam, or direct server state edits.

    Target experience:
      Greedy Growers (PlaceId 74102906764176)

    UI:
      Linoria (https://sirius.menu/rayfield)

    Public game data incorporated:
      20 seed tiers (Common -> Divine)
      6 core weather/lightning mutations
      18 pets across 5 egg tiers
      Farmer's Market / tickets
      Gear / worms / composting / rebirth / dead-tree handling

    Generated: 2026-08-17
]]

--========================================================
-- BOOT / SERVICES
--========================================================

local EXPECTED_PLACE_ID = 74102906764176

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local Player = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

if ENV.NIGHTSHADE_GREEDY and ENV.NIGHTSHADE_GREEDY.Stop then
    pcall(ENV.NIGHTSHADE_GREEDY.Stop)
end

local Runtime = {
    Running = true,
    Busy = false,
    MovementToken = 0,
    LastAction = "Idle",
    LastError = "None",
    StartedAt = os.clock(),
    SimulatedActions = {},
    ActionCount = 0,
    FailedActions = 0,
    PromptCache = {},
    PromptCooldowns = {},
    LastCategoryAction = {},
}

ENV.NIGHTSHADE_GREEDY = Runtime

--========================================================
-- RESEARCH DATA
--========================================================

local RARITY_RANK = {
    Common = 1,
    Rare = 2,
    Epic = 3,
    Legendary = 4,
    Mythic = 5,
    Celestial = 6,
    Secret = 7,
    Divine = 8,
}

local SEEDS = {
    ["Oak"]          = {Rarity="Common",    Cost=0,                 Spawn="1 in 5"},
    ["Pine"]         = {Rarity="Common",    Cost=25,                Spawn="1 in 5"},
    ["Apple"]        = {Rarity="Rare",      Cost=200,               Spawn="1 in 9"},
    ["Peach"]        = {Rarity="Rare",      Cost=350,               Spawn="1 in 9"},
    ["Fig"]          = {Rarity="Rare",      Cost=500,               Spawn="1 in 9"},
    ["Orange"]       = {Rarity="Epic",      Cost=10000,             Spawn="1 in 15"},
    ["Lemon"]        = {Rarity="Epic",      Cost=15000,             Spawn="1 in 15"},
    ["Avocado"]      = {Rarity="Epic",      Cost=20000,             Spawn="1 in 15"},
    ["Cherry"]       = {Rarity="Legendary", Cost=2500000,           Spawn="1 in 120"},
    ["Mango"]        = {Rarity="Legendary", Cost=5000000,           Spawn="1 in 120"},
    ["Coconut"]      = {Rarity="Legendary", Cost=10000000,          Spawn="1 in 120"},
    ["Banana"]       = {Rarity="Mythic",    Cost=3000000000,        Spawn="1 in 300"},
    ["Starfruit"]    = {Rarity="Mythic",    Cost=4500000000,        Spawn="1 in 300"},
    ["Dragon Fruit"] = {Rarity="Mythic",    Cost=7000000000,        Spawn="1 in 300"},
    ["Glowing"]      = {Rarity="Celestial", Cost=500000000000,      Spawn="1 in 400"},
    ["Blooming"]     = {Rarity="Celestial", Cost=750000000000,      Spawn="1 in 400"},
    ["Magic"]        = {Rarity="Secret",    Cost=500000000000000,   Spawn="1 in 660"},
    ["Pizza"]        = {Rarity="Secret",    Cost=850000000000000,   Spawn="1 in 660"},
    ["Diamond"]      = {Rarity="Divine",    Cost=1000000000000000,  Spawn="1 in 1,000"},
    ["Void"]         = {Rarity="Divine",    Cost=1750000000000000,  Spawn="1 in 1,000"},
}

local SEED_NAMES = {}
for seedName in pairs(SEEDS) do
    table.insert(SEED_NAMES, seedName)
end
table.sort(SEED_NAMES, function(a, b)
    local ra = RARITY_RANK[SEEDS[a].Rarity] or 0
    local rb = RARITY_RANK[SEEDS[b].Rarity] or 0
    if ra ~= rb then return ra < rb end
    return SEEDS[a].Cost < SEEDS[b].Cost
end)

local MUTATIONS = {
    Dewy        = {Multiplier=2,   Source="Misty weather"},
    Shocked     = {Multiplier=2.5, Source="Lightning near harvest below the high-growth threshold"},
    Radioactive = {Multiplier=5,   Source="Acid Rain weather"},
    Charged     = {Multiplier=7.5, Source="Lightning near harvest above the high-growth threshold"},
    Golden      = {Multiplier=25,  Source="Rainbow weather"},
    Cosmic      = {Multiplier=100, Source="Meteor Shower weather"},

    -- Pet-related mutation names reported in the newer pet update:
    Infested    = {Multiplier=nil, Source="Roach pet"},
    Huge        = {Multiplier=nil, Source="Pig pet"},
    Slimy       = {Multiplier=nil, Source="Frog pet"},
    Scaled      = {Multiplier=nil, Source="Alligator pet"},
}

local WEATHER_ALIASES = {
    ["misty"] = "Misty",
    ["mist"] = "Misty",
    ["acid rain"] = "Acid Rain",
    ["acid"] = "Acid Rain",
    ["rainbow"] = "Rainbow",
    ["meteor shower"] = "Meteor Shower",
    ["meteor"] = "Meteor Shower",
}

local EGG_COSTS = {
    Common = 100,
    Rare = 200,
    Epic = 500,
    Legendary = 1000,
    Mythic = 2000,
}

local PETS = {
    Squirrel   = {Egg="Common", Role="Finds common fruit with random sizes/mutations"},
    Bunny      = {Egg="Common", Role="Finds common fruit with random sizes/mutations"},
    Mouse      = {Egg="Common", Role="Finds common fruit with random sizes/mutations"},
    Dog        = {Egg="Rare", Role="Raises mutation chance during weather"},
    Cat        = {Egg="Rare", Role="Speeds fruit growth"},
    Robin      = {Egg="Rare", Role="Finds seeds with mutation chance"},
    Chicken    = {Egg="Epic", Role="Can hatch eggs at higher levels"},
    Roach      = {Egg="Epic", Role="Applies Infested mutation"},
    Woodpecker = {Egg="Epic", Role="Chance to drop a tree seed"},
    Cow        = {Egg="Legendary", Role="Improves fertilizer effects"},
    Sheep      = {Egg="Legendary", Role="Bonus XP to other pets"},
    Pig        = {Egg="Legendary", Role="Applies Huge mutation"},
    Raccoon    = {Egg="Legendary", Role="Finds legendary fruit"},
    Frog       = {Egg="Mythic", Role="Applies Slimy mutation"},
    Magpie     = {Egg="Mythic", Role="Finds pet eggs"},
    Turtle     = {Egg="Mythic", Role="Chance to block one lightning strike"},
    Monkey     = {Egg="Mythic", Role="Finds mythic-or-higher fruit"},
    Alligator  = {Egg="Mythic", Role="Chance to apply Scaled to planted seeds"},
}

--========================================================
-- SETTINGS
--========================================================

local Settings = {
    ExecutionMode = "Mechanics", -- Mechanics | Pure Local

    -- Farm
    AutoHarvest = false,
    AutoCollect = false,
    AutoPlant = false,
    AutoSell = false,
    AutoClearDead = false,

    -- Seeds
    AutoBuySeeds = false,
    SeedBuyMode = "Highest Affordable", -- Highest Affordable | Minimum Rarity | Specific Seed | Any
    PreferredSeed = "Oak",
    MinimumRarity = "Common",
    OnlyMutatedSeeds = false,
    AutoEquipSeed = true,
    KeepCashReserve = 0,

    -- Weather / mutation
    PlantDuringWeatherOnly = false,
    AllowedWeathers = {
        Misty = true,
        ["Acid Rain"] = true,
        Rainbow = true,
        ["Meteor Shower"] = true,
    },
    MutationPriority = "Any", -- Any | Dewy | Radioactive | Golden | Cosmic
    SmartWeatherNotifications = true,

    -- Pets / eggs
    AutoBuyEggs = false,
    PreferredEgg = "Rare",
    AutoPlaceEggs = false,
    AutoHatchEggs = false,

    -- Market / support systems
    AutoMarket = false,
    AutoBuyWorms = false,
    AutoBuyGear = false,
    AutoCompost = false,
    AutoRebirth = false,

    -- Movement / engine
    MaxActionDistance = 450,
    ActionDelay = 0.20,
    PromptRetryDelay = 0.80,
    StopDistanceScale = 0.50,
    StrictOwnPlotOnly = false,
    SchedulerIdleDelay = 0.12,

    -- Intervals
    BuySeedInterval = 3,
    SellInterval = 15,
    EggInterval = 8,
    WormInterval = 12,
    GearInterval = 12,
    CompostInterval = 8,
    MarketInterval = 8,
    RebirthInterval = 15,

    Debug = false,
}

--========================================================
-- HELPERS
--========================================================

local function now()
    return os.clock()
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function contains(text, needle)
    return string.find(lower(text), lower(needle), 1, true) ~= nil
end

local function containsAny(text, needles)
    local t = lower(text)
