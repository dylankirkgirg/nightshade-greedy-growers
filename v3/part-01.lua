--[[
    NIGHTSHADE V3 // Greedy Growers
    PlaceId: 74102906764176

    Goals:
      - purpose-built for Greedy Growers, not generic prompt walking
      - no direct FireServer / InvokeServer gameplay calls
      - distance-free normal interaction helpers where executor supports them
      - hard affordability guards before buying conveyor seeds / ticket eggs
      - mobile-first WindUI
      - no server protection / honeypot code

    The script intentionally targets public/replicated interaction surfaces and
    executor interaction helpers. If an interaction surface changes after a game
    update, Diagnostics can show what the current client exposes.
]]

--========================================================
-- SERVICES / BOOT
--========================================================

local EXPECTED_PLACE_ID = 74102906764176

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local Player = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

if ENV.NIGHTSHADE_GG_V3 and ENV.NIGHTSHADE_GG_V3.Stop then
    pcall(ENV.NIGHTSHADE_GG_V3.Stop)
end

local Runtime = {
    Running = true,
    Started = os.clock(),
    Connections = {},
    Interacted = setmetatable({}, {__mode = "k"}),
    SeenSeeds = setmetatable({}, {__mode = "k"}),
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
}
ENV.NIGHTSHADE_GG_V3 = Runtime

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Runtime.Connections, c)
    return c
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
    local ok, name = pcall(function() return inst:GetFullName() end)
    return ok and name or tostring(inst)
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

local function parseCurrency(text)
    local s=tostring(text or ""):gsub(",","")
    local number,suffix=s:match("%$?%s*([%d%.]+)%s*([KkMmBbTt]?[Qq]?[AaIi]?)")
    if not number then return nil end
    local n=tonumber(number)
    if not n then return nil end
    suffix=lower(suffix)
    local mult={
        k=1e3,m=1e6,b=1e9,t=1e12,
        qa=1e15,qi=1e18,
    }
    return n*(mult[suffix] or 1)
end

local function firstAncestorModel(inst)
    if not inst then return nil end
    if inst:IsA("Model") then return inst end
    return inst:FindFirstAncestorWhichIsA("Model")
end

local function getPosition(inst)
    if not inst then return nil end
    if inst:IsA("Attachment") then return inst.WorldPosition end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        local ok, pivot = pcall(inst.GetPivot, inst)
        return ok and pivot.Position or nil
    end
    if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then
        return getPosition(inst.Parent)
    end
    local part = inst:FindFirstAncestorWhichIsA("BasePart")
    if part then return part.Position end
    local model = firstAncestorModel(inst)
    return model and getPosition(model) or nil
end

--========================================================
-- GAME DATA
--========================================================

local RARITY_RANK = {
    Common = 1, Rare = 2, Epic = 3, Legendary = 4,
    Mythic = 5, Celestial = 6, Secret = 7, Divine = 8,
}

local RARITIES = {
    "Common","Rare","Epic","Legendary","Mythic","Celestial","Secret","Divine"
}

local SEEDS = {
    ["Oak"]          = {Rarity="Common",    Cost=0,                Spawn="1/5"},
    ["Pine"]         = {Rarity="Common",    Cost=25,               Spawn="1/5"},
    ["Apple"]        = {Rarity="Rare",      Cost=200,              Spawn="1/9"},
    ["Peach"]        = {Rarity="Rare",      Cost=350,              Spawn="1/9"},
    ["Fig"]          = {Rarity="Rare",      Cost=500,              Spawn="1/9"},
    ["Orange"]       = {Rarity="Epic",      Cost=10000,            Spawn="1/15"},
    ["Lemon"]        = {Rarity="Epic",      Cost=15000,            Spawn="1/15"},
    ["Avocado"]      = {Rarity="Epic",      Cost=20000,            Spawn="1/15"},
    ["Cherry"]       = {Rarity="Legendary", Cost=2500000,          Spawn="1/120"},
    ["Mango"]        = {Rarity="Legendary", Cost=5000000,          Spawn="1/120"},
    ["Coconut"]      = {Rarity="Legendary", Cost=10000000,         Spawn="1/120"},
    ["Banana"]       = {Rarity="Mythic",    Cost=3000000000,       Spawn="1/300"},
    ["Starfruit"]    = {Rarity="Mythic",    Cost=4500000000,       Spawn="1/300"},
    ["Dragon Fruit"] = {Rarity="Mythic",    Cost=7000000000,       Spawn="1/300"},
    ["Glowing"]      = {Rarity="Celestial", Cost=500000000000,     Spawn="1/400"},
    ["Blooming"]     = {Rarity="Celestial", Cost=750000000000,     Spawn="1/400"},
    ["Magic"]        = {Rarity="Secret",    Cost=500000000000000,  Spawn="1/660"},
    ["Pizza"]        = {Rarity="Secret",    Cost=850000000000000,  Spawn="1/660"},
    ["Diamond"]      = {Rarity="Divine",    Cost=1000000000000000, Spawn="1/1000"},
    ["Void"]         = {Rarity="Divine",    Cost=1750000000000000, Spawn="1/1000"},
}

local SEED_NAMES = {}
for name in pairs(SEEDS) do table.insert(SEED_NAMES, name) end
table.sort(SEED_NAMES, function(a,b)
    local ra, rb = RARITY_RANK[SEEDS[a].Rarity], RARITY_RANK[SEEDS[b].Rarity]
    if ra ~= rb then return ra < rb end
    return SEEDS[a].Cost < SEEDS[b].Cost
end)

local MUTATIONS = {
    Dewy={Multiplier=2, Weather="Misty"},
    Shocked={Multiplier=2.5, Weather="Lightning"},
    Radioactive={Multiplier=5, Weather="Acid Rain"},
    Charged={Multiplier=7.5, Weather="Lightning"},
    Golden={Multiplier=25, Weather="Rainbow"},
    Cosmic={Multiplier=100, Weather="Meteor Shower"},
    Infested={Multiplier=nil, Weather="Pet"},
    Huge={Multiplier=nil, Weather="Pet"},
    Slimy={Multiplier=nil, Weather="Pet"},
    Scaled={Multiplier=nil, Weather="Pet"},
}

local EGG_COSTS = {
    Common=100, Rare=200, Epic=500, Legendary=1000, Mythic=2000,
}

local PETS = {
    Squirrel="Finds common fruit", Bunny="Finds common fruit", Mouse="Finds common fruit",
    Dog="Improves mutation chance during weather", Cat="Speeds fruit growth", Robin="Finds seeds with mutation chance",
    Chicken="Can hatch eggs at higher level", Roach="Infested mutation", Woodpecker="Chance to find a tree seed",
    Cow="Improves fertilizer", Sheep="Bonus pet XP", Pig="Huge mutation", Raccoon="Finds legendary fruit",
    Frog="Slimy mutation", Magpie="Finds pet eggs", Turtle="Can block lightning",
    Monkey="Finds Mythic+ fruit", Alligator="Scaled mutation chance",
}

--========================================================
-- SETTINGS / CONFIG
--========================================================

local Settings = {
    -- Farm
    Master = false,
    AutoHarvest = false,
    HarvestAtMultiplier = 1,
    AutoCollectFruit = false,
    UseCollectAll = true,
    AutoCollectDead = false,
    AutoPlant = false,
    AutoPlantGrownTrees = false,
    AutoOrganiseTrees = false,
    AutoSellFruits = false,
    AutoSellAll = false,
    AutoSellAtMax = true,
    MinimumFruitsToSell = 1,
    AutoEquipSeed = true,
    OwnPlotOnly = true,
    DirectInteractions = true,
    AllowWalkFallback = false,

    -- Seeds
    AutoBuySeeds = false,
    BuyMode = "Highest Affordable",
    PreferredSeed = "Oak",
    MinimumRarity = "Common",
    BuyMutatedOnly = false,
    MaxSeedCost = 0,
    KeepCoinReserve = 0,
    SkipIfCashUnknown = true,
    SkipIfPriceUnknown = true,
    RareSeedNotify = true,
    SeedActionDelay = 0.18,

    -- Plant / weather
    PlantDuringWeatherOnly = false,
    WeatherMisty = true,
    WeatherAcidRain = true,
    WeatherRainbow = true,
    WeatherMeteor = true,
    WeatherUnknown = false,
    NotifyWeather = true,

    -- Market
    AutoGiveMarketFruits = false,
    AutoClaimMarketTickets = false,
    MarketMinimumFruits = 1,

    -- Pets
    AutoBuyPetEggs = false,
    EggTier = "Rare",
    KeepTicketReserve = 0,
    AutoPlaceEggs = false,
    AutoHatchEggs = false,

    -- Support
    AutoCompostSeeds = false,
    CompostMaxRarity = "Common",
    AutoBuyGear = false,
    AutoBuyWorms = false,
    AutoBuyFurniture = false,
    AutoClaimIndexReward = false,
    AutoRebirth = false,
    StrictRebirthReady = true,

    -- Timings
    FarmLoopDelay = 0.15,
    BuyLoopDelay = 0.15,
    MarketLoopDelay = 1.0,
    SupportLoopDelay = 1.5,
    ActionCooldown = 0.25,

    AntiAFK = true,
    Debug = false,
}

local CONFIG_FILE = "nightshade_gg_v3.json"

local function loadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if ok and type(decoded) == "table" then
        for k,v in pairs(decoded) do
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
-- WINDUI
--========================================================

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
local touch = UserInputService.TouchEnabled
local width = touch and math.clamp(viewport.X - 24, 350, 560) or 720
local height = touch and math.clamp(viewport.Y - 60, 310, 500) or 540

local Window = WindUI:CreateWindow({
    Title = "NIGHTSHADE V3",
    Icon = "sprout",
    Author = "Greedy Growers",
    Folder = "NightshadeGGV3",
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
    Window:Tag({Title="GG V3", Color=Color3.fromHex("#37D67A")})
    Window:Tag({Title=touch and "MOBILE" or "PC", Color=Color3.fromHex("#309BFF")})
end)

local function notify(title, content, duration)
    pcall(function()
        WindUI:Notify({
            Title=tostring(title),
            Content=tostring(content),
            Duration=duration or 4,
            Icon="bell",
        })
    end)
end

--========================================================
-- DATA READERS
--========================================================

local function readNumber(names)
    local wanted = {}
    for _, name in ipairs(names) do wanted[lower(name)] = true end

    local roots = {
        Player:FindFirstChild("leaderstats"),
        Player:FindFirstChild("Data"),
        Player:FindFirstChild("Stats"),
        Player:FindFirstChild("Currencies"),
        Player:FindFirstChild("Inventory"),
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
        local value = safeAttr(Player,key)
        if type(value)=="number" then return value, "Player."..key end
    end

    -- Last-resort replicated UI reader for executors/games that don't expose
    -- the currency as a ValueObject/attribute.
    local gui=Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible then
                local parentName=d.Parent and d.Parent.Name or ""
                if containsAny(d.Name.." "..parentName,names) then
                    local parsed=parseCurrency(d.Text)
                    if parsed then return parsed,safeFullName(d).." (text)" end
                end
            end
        end
    end

    return nil,nil
end

local function cash()
    return readNumber({"Cash","Coins","Money","Currency","CASH"})
end

local function tickets()
    return readNumber({"Tickets","Ticket","TICKETS"})
end

local function inventoryCount()
    return readNumber({"InventoryCount","InventorySize","FruitCount","Storage","STORAGE_SIZE","Fruits"})
end

local function inventoryMax()
    return readNumber({"STORAGE_MAX_SIZE","StorageMaxSize","InventoryMax","MaxInventory","StorageLimit"})
end

local function character()
    local c = Player.Character
    if not c then return nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or not r or h.Health <= 0 then return nil end
    return c,h,r
end

local function buildText(inst, depth)
    depth = depth or 5
    local out = {}
    local current = inst

    if inst:IsA("ProximityPrompt") then
        table.insert(out,inst.Name)
        table.insert(out,inst.ActionText)
        table.insert(out,inst.ObjectText)
    else
        table.insert(out,inst.Name)
    end

    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            if d.Visible then table.insert(out,d.Text) end
        elseif d:IsA("StringValue") then
            table.insert(out,tostring(d.Value))
        end
    end

    for _=1,depth do
        current=current.Parent
        if not current or current==game then break end
        table.insert(out,current.Name)
    end

    return lower(table.concat(out," "))
end

local function readAnyAttribute(inst, keys)
    local model = firstAncestorModel(inst) or inst
    local nodes = {inst, model}
    if model and model.Parent then table.insert(nodes,model.Parent) end
    for _, node in ipairs(nodes) do
        if node then
            for _, key in ipairs(keys) do
                local v=safeAttr(node,key)
                if v~=nil then return v end
                local child=node:FindFirstChild(key)
                if child and child:IsA("ValueBase") then return child.Value end
            end
        end
    end
    return nil
end

--========================================================
-- WEATHER / MUTATIONS
--========================================================

local WEATHER_ALIASES = {
    ["misty"]="Misty", ["mist"]="Misty",
    ["acid rain"]="Acid Rain", ["acid"]="Acid Rain",
    ["rainbow"]="Rainbow",
    ["meteor shower"]="Meteor Shower", ["meteor"]="Meteor Shower",
}

local function currentWeather()
    for _, root in ipairs({Workspace, ReplicatedStorage, game}) do
        for _, key in ipairs({"CurrentWeather","Weather","ActiveWeather","WeatherType"}) do
            local v=safeAttr(root,key)
            if v then
                for alias,name in pairs(WEATHER_ALIASES) do
                    if contains(v,alias) then return name end
                end
            end
        end
    end

    local gui=Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible then
                for alias,name in pairs(WEATHER_ALIASES) do
                    if contains(d.Text,alias) then return name end
                end
            end
        end
    end

    for _, d in ipairs(Workspace:GetChildren()) do
        for alias,name in pairs(WEATHER_ALIASES) do
            if contains(d.Name,alias) then return name end
        end
    end

    return "Unknown"
end

local function weatherAllowed()
    if not Settings.PlantDuringWeatherOnly then return true end
    local w=currentWeather()
    if w=="Misty" then return Settings.WeatherMisty end
    if w=="Acid Rain" then return Settings.WeatherAcidRain end
    if w=="Rainbow" then return Settings.WeatherRainbow end
    if w=="Meteor Shower" then return Settings.WeatherMeteor end
    return Settings.WeatherUnknown
end

local function mutationList(inst)
    local found={}
    local text=buildText(inst,4)
    for name in pairs(MUTATIONS) do
        if contains(text,name) then found[name]=true end
    end
    local raw=readAnyAttribute(inst,{"Mutation","Mutations","Modifiers","Variant"})
    if raw then
        local s=tostring(raw)
        for name in pairs(MUTATIONS) do
            if contains(s,name) then found[name]=true end
        end
    end
    local list={}
    for name in pairs(found) do table.insert(list,name) end
    table.sort(list)
    return list
end

local function mutationMultiplier(inst)
    local product=1
    local known=false
    for _, name in ipairs(mutationList(inst)) do
        local m=MUTATIONS[name] and MUTATIONS[name].Multiplier
        if m then product*=m known=true end
    end
    return known and product or nil
end

--========================================================
-- OWNERSHIP / GAME OBJECT HELPERS
--========================================================

local function ownState(inst)
    local node=inst
    for _=1,9 do
        if not node or node==Workspace then break end
        if lower(node.Name)==lower(Player.Name) then return true end
        for _, key in ipairs({"OwnerUserId","OwnerId","PlayerUserId","UserId","Owner"}) do
            local v=safeAttr(node,key)
            if v~=nil then
                if tonumber(v)==Player.UserId or lower(v)==lower(Player.Name) then return true end
                return false
            end
            local child=node:FindFirstChild(key)
            if child and child:IsA("ValueBase") then
                local cv=child.Value
                local numeric=tonumber(tostring(cv))
                if cv==Player or numeric==Player.UserId or lower(cv)==lower(Player.Name) then return true end
                return false
            end
        end
        node=node.Parent
    end
    return nil
end

local function directPrompt(prompt)
    if not prompt or not isAlive(prompt) or not prompt.Enabled then return false,"invalid prompt" end

    if fireproximityprompt then
        local ok,err=pcall(fireproximityprompt,prompt)
        return ok,err
    end

    local _,_,root=character()
    local pos=getPosition(prompt)
    if not root or not pos or (root.Position-pos).Magnitude>prompt.MaxActivationDistance+2 then
        return false,"fireproximityprompt unsupported and prompt is out of range"
    end

    local ok,err=pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration,0.03)+0.03)
        prompt:InputHoldEnd()
    end)
    return ok,err
end

local function directClick(click)
    if not click or not isAlive(click) then return false,"invalid click" end
    if fireclickdetector then
        local ok,err=pcall(fireclickdetector,click)
        return ok,err
    end
    return false,"fireclickdetector unsupported"
end

local function interact(inst, actionKey)
    if not inst then return false end
    local last=Runtime.Interacted[inst] or 0
    if os.clock()-last < Settings.ActionCooldown then return false end
    Runtime.Interacted[inst]=os.clock()

    local prompt
    local click

    if inst:IsA("ProximityPrompt") then prompt=inst end
    if inst:IsA("ClickDetector") then click=inst end

    prompt=prompt or inst:FindFirstChildWhichIsA("ProximityPrompt",true)
    click=click or inst:FindFirstChildWhichIsA("ClickDetector",true)

    local ok,err=false,"no interaction"
    if prompt then ok,err=directPrompt(prompt) end
    if not ok and click then ok,err=directClick(click) end

    if ok then
        Runtime.Stats.Actions+=1
        Runtime.LastAction=actionKey or "Interact"
        Runtime.LastError="None"
        return true
    end

    Runtime.LastError=tostring(err)
    return false
end

local function findInteractionByWords(words, roots)
    roots=roots or {Workspace}
    local candidates={}
    for _, root in ipairs(roots) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
                    local text=buildText(d,5)
                    if containsAny(text,words) then
                        table.insert(candidates,d)
                    end
                end
            end
        end
    end
    return candidates
end

--========================================================
-- SEED CONVEYOR / SMART BUYER
--========================================================

local function seedNameFrom(inst)
    local raw=readAnyAttribute(inst,{"Seed","SeedName","Name","Type"})
    if raw then
        for name in pairs(SEEDS) do
            if contains(raw,name) then return name end
        end
    end
    local text=buildText(inst,5)
    for name in pairs(SEEDS) do
        if contains(text,name) then return name end
    end
    return nil
end

local function seedRarity(inst, seedName)
    local raw=readAnyAttribute(inst,{"Rarity","Tier"})
    if raw then
        for _, rarity in ipairs(RARITIES) do
            if contains(raw,rarity) then return rarity end
        end
    end
    if seedName and SEEDS[seedName] then return SEEDS[seedName].Rarity end
    return nil
end

local function seedPrice(inst, seedName)
    local raw=readAnyAttribute(inst,{"price","Price","cost","Cost","SeedCost"})
    if type(raw)=="number" then return raw,"replicated" end
    if type(raw)=="string" then
        local n=parseCurrency(raw)
        if n then return n,"replicated" end
    end

    -- Prefer what the current game visibly displays over the research database.
    local visible=parseCurrency(buildText(inst,3))
    if visible then return visible,"display" end

    if seedName and SEEDS[seedName] then return SEEDS[seedName].Cost,"database" end
    return nil,"unknown"
end

local function isSeedCandidate(inst)
    if not inst then return false end
    if safeAttr(inst,"IsSeed")==true then return true end
    local name=seedNameFrom(inst)
    if name then return true end
    return contains(buildText(inst,3),"seed")
end

local function conveyorRoot()
    return Workspace:FindFirstChild("ConveyorSeeds",true)
        or Workspace:FindFirstChild("Seeds",true)
        or Workspace:FindFirstChild("SeedConveyor",true)
end

local function seedCandidates()
    local root=conveyorRoot()
    if not root then return {} end
    local out={}
    local seen={}
    for _, child in ipairs(root:GetChildren()) do
        local model=firstAncestorModel(child) or child
        if not seen[model] and isSeedCandidate(model) then
            seen[model]=true
            table.insert(out,model)
        end
    end
    -- Some versions nest seeds one extra layer.
    if #out==0 then
        for _, d in ipairs(root:GetDescendants()) do
            local model=firstAncestorModel(d) or d
            if not seen[model] and (d:IsA("ProximityPrompt") or d:IsA("ClickDetector")) and isSeedCandidate(model) then
                seen[model]=true
                table.insert(out,model)
            end
        end
    end
    return out
end

local function isMutatedSeed(inst)
    if #mutationList(inst)>0 then return true end
    local raw=readAnyAttribute(inst,{"Mutation","Mutations","IsMutated","Mutated"})
    return raw~=nil and raw~=false and tostring(raw)~="" and tostring(raw)~="None"
end

local function seedAllowed(inst)
    local name=seedNameFrom(inst)
    local rarity=seedRarity(inst,name)
    local price,priceSource=seedPrice(inst,name)
    local money=cash()

    -- The important guard: if we know it is unaffordable, NEVER touch it.
    if money~=nil and price~=nil and money-price < Settings.KeepCoinReserve then
        return false,"unaffordable",name,price,rarity
    end

    if money==nil and Settings.SkipIfCashUnknown then
        return false,"cash unknown",name,price,rarity
    end

    if price==nil and Settings.SkipIfPriceUnknown then
        return false,"price unknown",name,price,rarity
    end

    if Settings.MaxSeedCost>0 and price and price>Settings.MaxSeedCost then
        return false,"over max cost",name,price,rarity
    end

    if Settings.BuyMutatedOnly and not isMutatedSeed(inst) then
        return false,"not mutated",name,price,rarity
    end

    if Settings.BuyMode=="Specific Seed" then
        if not name or lower(name)~=lower(Settings.PreferredSeed) then
            return false,"wrong seed",name,price,rarity
        end
    elseif Settings.BuyMode=="Minimum Rarity" then
        if not rarity or (RARITY_RANK[rarity] or 0)<(RARITY_RANK[Settings.MinimumRarity] or 1) then
            return false,"below rarity",name,price,rarity
        end
    end

    return true,"allowed",name,price,rarity
end

local function seedScore(inst)
    local allowed,_,name,price,rarity=seedAllowed(inst)
    if not allowed then return -math.huge end
    local score=(RARITY_RANK[rarity] or 0)*1e9+(price or 0)
    if name==Settings.PreferredSeed then score+=1e15 end
    if isMutatedSeed(inst) then score+=1e14 end
    return score
end

local function seedInteraction(inst)
    -- Prefer interaction living on the seed itself.
    local bestPrompt
    local bestClick
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local text=buildText(d,2)
            if containsAny(text,{"buy","purchase","seed","get"}) then
                bestPrompt=d break
            end
            bestPrompt=bestPrompt or d
        elseif d:IsA("ClickDetector") then
            bestClick=bestClick or d
        end
    end
    return bestPrompt or bestClick
end

local LastRareNotice=setmetatable({}, {__mode="k"})

local function scanBestRiverSeed()
    local candidates=seedCandidates()
    local best,bestScore
    local money=cash()

    for _, seed in ipairs(candidates) do
        local ok,reason,name,price,rarity=seedAllowed(seed)
        local label=(name or seed.Name).." | "..(rarity or "?").." | $"..abbreviate(price)

        if not bestScore or seedScore(seed)>bestScore then
            bestScore=seedScore(seed)
            best=seed
        end

        if Settings.RareSeedNotify and rarity and (RARITY_RANK[rarity] or 0)>=4 and not LastRareNotice[seed] then
            LastRareNotice[seed]=true
            local affordable=(ok and "AFFORDABLE") or ("SKIP: "..reason)
            notify("River Seed // "..rarity,(name or seed.Name).." • $"..abbreviate(price).." • "..affordable,5)
        end
    end

    if best and bestScore>-math.huge then
        local _,_,name,price,rarity=seedAllowed(best)
        Runtime.BestRiverSeed=(name or best.Name).." • "..(rarity or "?").." • $"..abbreviate(price)
        return best
    end

    Runtime.BestRiverSeed=#candidates>0 and "No eligible seed" or "No conveyor seeds detected"
    return nil
end

local function buyBestSeed()
    local best=scanBestRiverSeed()
    if not best then return false end

    local ok,reason,name,price,rarity=seedAllowed(best)
    if not ok then
        Runtime.Stats.SeedsSkipped+=1
        return false
    end

    local interaction=seedInteraction(best)
    if not interaction then
        Runtime.LastError="eligible seed had no prompt/click detector"
        return false
    end

    if interact(interaction,"Buy Seed") then
        Runtime.Stats.SeedsBought+=1
        if Settings.RareSeedNotify and rarity and (RARITY_RANK[rarity] or 0)>=4 then
            notify("Seed Sniped",(name or "Seed").." • "..rarity.." • $"..abbreviate(price),4)
        end
        task.wait(Settings.SeedActionDelay)
        return true
    end
    return false
end

--========================================================
-- INVENTORY / SEED EQUIP
--========================================================

local function seedTools()
    local out={}
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and (contains(t.Name,"seed") or seedNameFrom(t)) then
                table.insert(out,t)
            end
        end
    end
    scan(Player.Character)
    scan(Player:FindFirstChildOfClass("Backpack"))
    return out
end

local function bestSeedTool()
    local best,bestScore
    for _, tool in ipairs(seedTools()) do
        local name=seedNameFrom(tool)
        local rarity=seedRarity(tool,name)
        local score=(RARITY_RANK[rarity] or 0)*1e9+(name and SEEDS[name] and SEEDS[name].Cost or 0)
        if name==Settings.PreferredSeed then score+=1e15 end
        if isMutatedSeed(tool) then score+=1e14 end
        if not bestScore or score>bestScore then best,bestScore=tool,score end
    end
    return best
end

local function equipBestSeed()
    if not Settings.AutoEquipSeed then return true end
    local c,h=character()
    if not h then return false end
    local tool=bestSeedTool()
    if not tool then return false end
    if tool.Parent==c then return true end
    pcall(h.EquipTool,h,tool)
    task.wait(0.05)
    return tool.Parent==c
end

--========================================================
-- TREES / HARVEST / DEAD / PLANT
--========================================================

local function playerTrees()
    local out={}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") and (d.Name:match("^PlotTree_") or contains(d.Name,"tree")) then
            local own=ownState(d)
            if (not Settings.OwnPlotOnly) or own==true then
                table.insert(out,d)
            end
        end
    end
    return out
end

local function treeMultiplier(tree)
    local v=readAnyAttribute(tree,{"HarvestMultiplier","Multiplier","GrowthMultiplier"})
    if type(v)=="number" then return v end
    if type(v)=="string" then return tonumber(v:match("[%d%.]+")) end

    for _, d in ipairs(tree:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible then
            local m=d.Text:match("[xX]%s*([%d%.]+)") or d.Text:match("([%d%.]+)%s*[xX]")
            if m then return tonumber(m) end
        end
    end
    return 0
end

local function treeDead(tree)
    local v=readAnyAttribute(tree,{"IsDead","Dead","Destroyed"})
    if v==true then return true end
    return containsAny(buildText(tree,2),{"dead tree","withered","isdead"})
end

local function findTreePrompt(tree, words)
    local fallback
    for _, d in ipairs(tree:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            fallback=fallback or d
            if containsAny(buildText(d,2),words) then return d end
        elseif d:IsA("ClickDetector") then
            fallback=fallback or d
        end
    end
    return fallback
end

local function harvestOne()
    local best,bestMult
    for _, tree in ipairs(playerTrees()) do
        if not treeDead(tree) then
            local mult=treeMultiplier(tree)
            if mult>=Settings.HarvestAtMultiplier and (not bestMult or mult>bestMult) then
                best,bestMult=tree,mult
            end
        end
    end
    if not best then return false end
    local action=findTreePrompt(best,{"harvest","chop","treebaseprompt"})
    if action and interact(action,"Harvest x"..tostring(bestMult)) then
        Runtime.Stats.Harvests+=1
        return true
    end
    return false
end

local function clearDeadOne()
    for _, tree in ipairs(playerTrees()) do
        if treeDead(tree) then
            local action=findTreePrompt(tree,{"dead","remove","clear","chop","collect"})
            if action and interact(action,"Clear Dead Tree") then
                Runtime.Stats.Support+=1
                return true
            end
        end
    end
    return false
end

local function plantOne()
    if not weatherAllowed() then return false end
    if not equipBestSeed() then return false end

    local candidates=findInteractionByWords({"plant","seedplot","dirt","plant seed"})
    for _, action in ipairs(candidates) do
        local own=ownState(action)
        if (not Settings.OwnPlotOnly) or own==true then
            if interact(action,"Plant") then
                Runtime.Stats.Plants+=1
                return true
            end
        end
    end
    return false
end

local function plantGrownTreeOne()
    for _, a in ipairs(findInteractionByWords({"plant grown tree","grown tree","replant tree"})) do
        local own=ownState(a)
        if (not Settings.OwnPlotOnly) or own~=false then
            if interact(a,"Plant Grown Tree") then
                Runtime.Stats.Plants+=1
                return true
            end
        end
    end
    return false
end

local function organiseOne()
    local candidates=findInteractionByWords({"organise","organize","arrange tree"})
    for _, a in ipairs(candidates) do
        if interact(a,"Organise Trees") then return true end
    end
    return false
end

--========================================================
-- FRUITS / COLLECT / SELL
--========================================================

local function fruitRoot()
    return Workspace:FindFirstChild("FruitSpawns",true)
        or Workspace:FindFirstChild("Fruits",true)
end

local function collectOneFruit()
    if Settings.UseCollectAll then
        local all=findInteractionByWords({"collect all","collect fruits","collect fruit"})
        for _, a in ipairs(all) do
            if interact(a,"Collect All Fruits") then
                Runtime.Stats.Fruits+=1
                return true
            end
        end
    end

    local root=fruitRoot()
    if root then
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
                local own=ownState(d)
                if (not Settings.OwnPlotOnly) or own~=false then
                    if interact(d,"Collect Fruit") then
                        Runtime.Stats.Fruits+=1
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function storageFull()
    local used=inventoryCount()
    local max=inventoryMax()
    return used and max and max>0 and used>=max
end

local function sell(kind)
    local roots={}
    local stand=Workspace:FindFirstChild("SellStand",true)
    if stand then table.insert(roots,stand) else table.insert(roots,Workspace) end

    local words
    if kind=="all" then
        words={"sell all","sell everything"}
    else
        words={"sell fruits","sell fruit","sell"}
    end

    for _, a in ipairs(findInteractionByWords(words,roots)) do
        if interact(a,kind=="all" and "Sell All" or "Sell Fruits") then
            Runtime.Stats.Sells+=1
            return true
        end
    end
    return false
end

--========================================================
-- FARMERS MARKET / TICKETS
--========================================================

local function marketRoot()
    return Workspace:FindFirstChild("Farmers Market",true)
        or Workspace:FindFirstChild("FarmersMarket",true)
        or Workspace:FindFirstChild("MarketRows",true)
end

local function marketGive()
    local root=marketRoot()
    if not root then return false end
    for _, a in ipairs(findInteractionByWords({"give","submit","turn in","market fruit","deliver"}, {root})) do
        if interact(a,"Give Market Fruits") then
            Runtime.Stats.Market+=1
            return true
        end
    end
    return false
end

local function marketClaim()
    local root=marketRoot()
    if not root then return false end
    for _, a in ipairs(findInteractionByWords({"claim","ticket","reward"}, {root})) do
        if interact(a,"Claim Market Tickets") then
            Runtime.Stats.Market+=1
            return true
        end
    end
    return false
end

--========================================================
-- PET EGGS
--========================================================

local function eggTierFrom(inst)
    local text=buildText(inst,5)
    for tier in pairs(EGG_COSTS) do
        if contains(text,tier) and containsAny(text,{"egg","pet"}) then return tier end
    end
    local raw=readAnyAttribute(inst,{"Rarity","Tier","EggTier"})
    if raw then
        for tier in pairs(EGG_COSTS) do if contains(raw,tier) then return tier end end
    end
    return nil
end

local function buyEgg()
    local root=Workspace:FindFirstChild("Pet Shop",true) or Workspace:FindFirstChild("Eggs",true)
    if not root then return false end

    local tix=tickets()
    local cost=EGG_COSTS[Settings.EggTier]
    if not tix or not cost or tix-cost<Settings.KeepTicketReserve then
        return false
    end

    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
            local tier=eggTierFrom(d)
            if tier==Settings.EggTier then
                if interact(d,"Buy "..tier.." Egg") then
                    Runtime.Stats.Support+=1
                    return true
                end
            end
        end
    end
    return false
end

local function eggAction(words,label)
    for _, a in ipairs(findInteractionByWords(words)) do
        if interact(a,label) then Runtime.Stats.Support+=1 return true end
    end
    return false
end

--========================================================
-- COMPOST / GEAR / WORMS / FURNITURE / INDEX
--========================================================

local function rarityAtMost(tool,maxRarity)
    local name=seedNameFrom(tool)
    local r=seedRarity(tool,name)
    return r and (RARITY_RANK[r] or 99)<=(RARITY_RANK[maxRarity] or 1)
end

local function compostOne()
    local bin=Workspace:FindFirstChild("CompostBin",true) or Workspace:FindFirstChild("Compost",true)
    if not bin then return false end

    local c,h=character()
    if not h then return false end
    local chosen
    for _, tool in ipairs(seedTools()) do
        if rarityAtMost(tool,Settings.CompostMaxRarity) then chosen=tool break end
    end
    if not chosen then return false end
    pcall(h.EquipTool,h,chosen)
    task.wait(0.05)

    for _, d in ipairs(bin:GetDescendants()) do
        if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
            if interact(d,"Compost Seed") then Runtime.Stats.Support+=1 return true end
        end
    end
    return false
end

local function shopAction(shopNames,words,label)
    local root
    for _, name in ipairs(shopNames) do
        root=Workspace:FindFirstChild(name,true)
        if root then break end
    end
    if not root then return false end

    -- Unknown-priced shop purchases are intentionally conservative.
    -- If a candidate exposes cost/price, we respect the coin reserve.
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
            local text=buildText(d,4)
            if containsAny(text,words) then
                local cost=readAnyAttribute(d,{"price","Price","cost","Cost"})
                local money=cash()
                if type(cost)=="number" and money and money-cost>=Settings.KeepCoinReserve then
                    if interact(d,label) then Runtime.Stats.Support+=1 return true end
                end
            end
        end
    end
    return false
end

local function claimIndex()
    for _, a in ipairs(findInteractionByWords({"claim index","index reward","claim reward"})) do
        if interact(a,"Claim Index Reward") then Runtime.Stats.Support+=1 return true end
    end
    return false
end

--========================================================
-- REBIRTH
--========================================================

local function rebirthReady()
    for _, key in ipairs({"CanRebirth","RebirthReady","ReadyToRebirth"}) do
        local v=safeAttr(Player,key)
        if v==true then return true end
    end
    local gui=Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible then
                local t=lower(d.Text)
                if containsAny(t,{"rebirth ready","ready to rebirth","rebirth available"}) then return true end
            end
        end
    end
    return not Settings.StrictRebirthReady
end

local function rebirth()
    if not rebirthReady() then return false end
    for _, a in ipairs(findInteractionByWords({"rebirth"})) do
        if interact(a,"Rebirth") then Runtime.Stats.Support+=1 return true end
    end
    return false
end

--========================================================
-- SCHEDULERS
--========================================================

local function enabled(v)
    return Runtime.Running and Settings.Master and v
end

task.spawn(function()
    while Runtime.Running do
        local acted=false

        if enabled(Settings.AutoCollectDead) then acted=clearDeadOne() end
        if enabled(Settings.AutoSellAtMax) and not acted and storageFull() then acted=sell(Settings.AutoSellAll and "all" or "fruits") end
        if enabled(Settings.AutoHarvest) and not acted then acted=harvestOne() end
        if enabled(Settings.AutoCollectFruit) and not acted then acted=collectOneFruit() end
        if enabled(Settings.AutoPlant) and not acted then acted=plantOne() end
        if enabled(Settings.AutoPlantGrownTrees) and not acted then acted=plantGrownTreeOne() end
        if enabled(Settings.AutoOrganiseTrees) and not acted then acted=organiseOne() end
        if enabled(Settings.AutoSellFruits) and not acted then
            local used=inventoryCount()
            if not used or used>=Settings.MinimumFruitsToSell then acted=sell("fruits") end
        end
        if enabled(Settings.AutoSellAll) and not acted then acted=sell("all") end

        task.wait(acted and Settings.ActionCooldown or Settings.FarmLoopDelay)
    end
end)

task.spawn(function()
    while Runtime.Running do
        if enabled(Settings.AutoBuySeeds) then
            pcall(buyBestSeed)
        else
            pcall(scanBestRiverSeed)
        end
        task.wait(Settings.BuyLoopDelay)
    end
end)

task.spawn(function()
    while Runtime.Running do
        if Settings.Master then
            if Settings.AutoGiveMarketFruits then pcall(marketGive) end
            if Settings.AutoClaimMarketTickets then pcall(marketClaim) end
            if Settings.AutoBuyPetEggs then pcall(buyEgg) end
            if Settings.AutoPlaceEggs then pcall(eggAction,{"place egg","set egg"},"Place Egg") end
            if Settings.AutoHatchEggs then pcall(eggAction,{"hatch egg","hatch"},"Hatch Egg") end
        end
        task.wait(Settings.MarketLoopDelay)
    end
end)

task.spawn(function()
    while Runtime.Running do
        if Settings.Master then
            if Settings.AutoCompostSeeds then pcall(compostOne) end
            if Settings.AutoBuyGear then pcall(shopAction,{"Gear Shop"},{"buy","gear","fertilizer"},"Buy Gear") end
            if Settings.AutoBuyWorms then pcall(shopAction,{"Worm Shop"},{"buy","worm","can of worms"},"Buy Worms") end
            if Settings.AutoBuyFurniture then pcall(shopAction,{"Furniture Shop","Decor"},{"buy","furniture","decor"},"Buy Furniture") end
            if Settings.AutoClaimIndexReward then pcall(claimIndex) end
            if Settings.AutoRebirth then pcall(rebirth) end
        end
        task.wait(Settings.SupportLoopDelay)
    end
end)

local lastWeather
task.spawn(function()
    while Runtime.Running do
        local w=currentWeather()
        Runtime.CurrentWeather=w
        if Settings.NotifyWeather and w~=lastWeather then
            lastWeather=w
            if w~="Unknown" then
                local msg="Weather active"
                if w=="Misty" then msg="Dewy mutation opportunity • Dog is useful"
                elseif w=="Acid Rain" then msg="Radioactive mutation opportunity"
                elseif w=="Rainbow" then msg="Golden x25 opportunity"
                elseif w=="Meteor Shower" then msg="Cosmic x100 opportunity" end
                notify("Weather // "..w,msg,5)
            end
        end
        task.wait(0.7)
    end
end)

if Settings.AntiAFK then
    connect(Player.Idled,function()
        if not Settings.AntiAFK then return end
        pcall(function()
            VirtualUser:Button2Down(Vector2.new(0,0),Workspace.CurrentCamera.CFrame)
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0,0),Workspace.CurrentCamera.CFrame)
        end)
    end)
end

--========================================================
-- UI
--========================================================

local Home=Window:Tab({Title="Home",Icon="house"})
local Farm=Window:Tab({Title="Farm",Icon="sprout"})
local SeedsTab=Window:Tab({Title="Seeds",Icon="package"})
local Weather=Window:Tab({Title="Weather",Icon="cloud-lightning"})
local Market=Window:Tab({Title="Market",Icon="store"})
local Pets=Window:Tab({Title="Pets",Icon="paw-print"})
local Utility=Window:Tab({Title="Utility",Icon="wrench"})
local Diagnostics=Window:Tab({Title="Diagnostics",Icon="scan-search"})

local Status=Home:Paragraph({
    Title="NIGHTSHADE V3",
    Desc="Greedy Growers engine loaded.",
    Image="sprout",
})

local function snapshot()
    local money,moneySrc=cash()
    local tix,tixSrc=tickets()
    local used=inventoryCount()
    local max=inventoryMax()
    local caps={
        "fireproximityprompt="..tostring(fireproximityprompt~=nil),
        "fireclickdetector="..tostring(fireclickdetector~=nil),
        "files="..tostring(writefile~=nil and readfile~=nil),
    }
    return table.concat({
        "Place: "..tostring(game.PlaceId)..(game.PlaceId==EXPECTED_PLACE_ID and " ✓" or " ⚠"),
        "Cash: $"..abbreviate(money),
        "Tickets: "..abbreviate(tix),
        "Storage: "..tostring(used or "?").."/"..tostring(max or "?"),
        "Weather: "..Runtime.CurrentWeather,
        "Best river seed: "..Runtime.BestRiverSeed,
        "Last: "..Runtime.LastAction,
        "Actions: "..Runtime.Stats.Actions.." | Seeds: "..Runtime.Stats.SeedsBought.." | Harvests: "..Runtime.Stats.Harvests,
        table.concat(caps," • "),
    },"\n")
end

local function refreshStatus()
    pcall(function() Status:SetDesc(snapshot()) end)
end

Home:Button({Title="Refresh Status",Icon="refresh-cw",Callback=refreshStatus})

Home:Toggle({
    Title="MASTER AUTOMATION",
    Desc="Global kill switch. Individual toggles stay configured.",
    Value=Settings.Master,
    Callback=function(v) Settings.Master=v end,
})

Home:Button({
    Title="Save Settings",
    Icon="save",
    Callback=function()
        local ok,err=saveConfig()
        notify(ok and "Saved" or "Save failed",ok and CONFIG_FILE or tostring(err),3)
    end,
})

Home:Button({
    Title="Panic Stop",
    Icon="octagon",
    Callback=function()
        Settings.Master=false
        notify("Automation stopped","Master switch is OFF.",3)
    end,
})

Home:Paragraph({
    Title="V3 behavior",
    Desc="Seed purchases never walk. If cash/price is known and the seed would cross your coin reserve, NIGHTSHADE does not touch the interaction at all.",
    Image="shield-check",
})

-- FARM
Farm:Toggle({Title="Auto Harvest",Value=Settings.AutoHarvest,Callback=function(v) Settings.AutoHarvest=v end})
Farm:Slider({
    Title="Harvest At Multiplier",
    Desc="Only harvest trees at or above this replicated/displayed multiplier.",
    Value={Min=1,Max=100,Default=Settings.HarvestAtMultiplier},
    Step=0.5,
    Callback=function(v) Settings.HarvestAtMultiplier=v end,
})
Farm:Toggle({Title="Auto Collect Fruit",Value=Settings.AutoCollectFruit,Callback=function(v) Settings.AutoCollectFruit=v end})
Farm:Toggle({Title="Use Collect All First",Value=Settings.UseCollectAll,Callback=function(v) Settings.UseCollectAll=v end})
Farm:Toggle({Title="Auto Collect Dead Trees",Value=Settings.AutoCollectDead,Callback=function(v) Settings.AutoCollectDead=v end})
Farm:Toggle({Title="Auto Plant",Value=Settings.AutoPlant,Callback=function(v) Settings.AutoPlant=v end})
Farm:Toggle({Title="Auto Plant Grown Trees",Value=Settings.AutoPlantGrownTrees,Callback=function(v) Settings.AutoPlantGrownTrees=v end})
Farm:Toggle({Title="Auto Equip Best Seed",Value=Settings.AutoEquipSeed,Callback=function(v) Settings.AutoEquipSeed=v end})
Farm:Toggle({Title="Own Plot Only",Value=Settings.OwnPlotOnly,Callback=function(v) Settings.OwnPlotOnly=v end})
Farm:Toggle({Title="Auto Organise Trees",Value=Settings.AutoOrganiseTrees,Callback=function(v) Settings.AutoOrganiseTrees=v end})
Farm:Toggle({Title="Auto Sell Fruits",Value=Settings.AutoSellFruits,Callback=function(v) Settings.AutoSellFruits=v end})
Farm:Toggle({Title="Auto Sell All",Value=Settings.AutoSellAll,Callback=function(v) Settings.AutoSellAll=v end})
Farm:Toggle({Title="Auto Sell At Max Inventory",Value=Settings.AutoSellAtMax,Callback=function(v) Settings.AutoSellAtMax=v end})
Farm:Slider({
    Title="Minimum Fruits To Sell",
    Value={Min=1,Max=200,Default=Settings.MinimumFruitsToSell},
    Step=1,
    Callback=function(v) Settings.MinimumFruitsToSell=v end,
})

-- SEEDS
SeedsTab:Toggle({
    Title="Auto Buy Seeds — NO MOVEMENT",
    Desc="Uses the seed's own prompt/click interaction directly when supported.",
    Value=Settings.AutoBuySeeds,
    Callback=function(v) Settings.AutoBuySeeds=v end,
})
SeedsTab:Dropdown({
    Title="Buy Mode",
    Values={"Highest Affordable","Any Affordable","Specific Seed","Minimum Rarity"},
    Value=Settings.BuyMode,
    Callback=function(v) Settings.BuyMode=v end,
})
SeedsTab:Dropdown({
    Title="Preferred / Specific Seed",
    Values=SEED_NAMES,
    Value=Settings.PreferredSeed,
    SearchBarEnabled=true,
    Callback=function(v) Settings.PreferredSeed=v end,
})
SeedsTab:Dropdown({
    Title="Minimum Rarity",
    Values=RARITIES,
    Value=Settings.MinimumRarity,
    Callback=function(v) Settings.MinimumRarity=v end,
})
SeedsTab:Toggle({Title="Only Mutated Seeds",Value=Settings.BuyMutatedOnly,Callback=function(v) Settings.BuyMutatedOnly=v end})
SeedsTab:Input({
    Title="Max Cost Per Seed (0 = off)",
    Value=tostring(Settings.MaxSeedCost),
    Placeholder="0",
    Callback=function(v) Settings.MaxSeedCost=tonumber(v) or 0 end,
})
SeedsTab:Input({
    Title="Keep Coin Reserve",
    Desc="A seed is never touched if buying it would go below this.",
    Value=tostring(Settings.KeepCoinReserve),
    Placeholder="0",
    Callback=function(v) Settings.KeepCoinReserve=tonumber(v) or 0 end,
})
SeedsTab:Toggle({
    Title="Skip If Cash Unknown",
    Desc="Recommended ON. Prevents accidental purchase fallback.",
    Value=Settings.SkipIfCashUnknown,
    Callback=function(v) Settings.SkipIfCashUnknown=v end,
})
SeedsTab:Toggle({
    Title="Skip If Price Unknown",
    Desc="Recommended ON. Known seeds use NIGHTSHADE's price database.",
    Value=Settings.SkipIfPriceUnknown,
    Callback=function(v) Settings.SkipIfPriceUnknown=v end,
})
SeedsTab:Toggle({Title="Rare Seed Notifications",Value=Settings.RareSeedNotify,Callback=function(v) Settings.RareSeedNotify=v end})
SeedsTab:Button({
    Title="Scan River Now",
    Icon="scan-search",
    Callback=function()
        scanBestRiverSeed()
        notify("River scan",Runtime.BestRiverSeed,5)
    end,
})
SeedsTab:Button({
    Title="Buy Best Eligible Seed Once",
    Icon="shopping-cart",
    Callback=function()
        local ok=buyBestSeed()
        notify("Seed buyer",ok and "Purchase interaction sent." or ("Skipped • "..Runtime.LastError),4)
    end,
})

-- WEATHER
Weather:Toggle({Title="Only Plant During Selected Weather",Value=Settings.PlantDuringWeatherOnly,Callback=function(v) Settings.PlantDuringWeatherOnly=v end})
Weather:Toggle({Title="Misty / Dewy",Value=Settings.WeatherMisty,Callback=function(v) Settings.WeatherMisty=v end})
Weather:Toggle({Title="Acid Rain / Radioactive",Value=Settings.WeatherAcidRain,Callback=function(v) Settings.WeatherAcidRain=v end})
Weather:Toggle({Title="Rainbow / Golden",Value=Settings.WeatherRainbow,Callback=function(v) Settings.WeatherRainbow=v end})
Weather:Toggle({Title="Meteor Shower / Cosmic",Value=Settings.WeatherMeteor,Callback=function(v) Settings.WeatherMeteor=v end})
Weather:Toggle({Title="Allow Unknown Weather",Value=Settings.WeatherUnknown,Callback=function(v) Settings.WeatherUnknown=v end})
Weather:Toggle({Title="Weather Notifications",Value=Settings.NotifyWeather,Callback=function(v) Settings.NotifyWeather=v end})
Weather:Button({
    Title="Current Weather",
    Callback=function() notify("Weather",currentWeather(),4) end,
})
Weather:Paragraph({
    Title="Known core mutations",
    Desc="Dewy x2 • Shocked x2.5 • Radioactive x5 • Charged x7.5 • Golden x25 • Cosmic x100. Pet mutations are detected too when replicated.",
    Image="sparkles",
})

-- MARKET
Market:Toggle({Title="Auto Give Market Fruits",Value=Settings.AutoGiveMarketFruits,Callback=function(v) Settings.AutoGiveMarketFruits=v end})
Market:Toggle({Title="Auto Claim Market Tickets",Value=Settings.AutoClaimMarketTickets,Callback=function(v) Settings.AutoClaimMarketTickets=v end})
Market:Button({Title="Give Market Fruit Once",Callback=function() notify("Market",marketGive() and "Submitted." or "No eligible interaction found.",3) end})
Market:Button({Title="Claim Market Tickets Once",Callback=function() notify("Market",marketClaim() and "Claimed." or "Nothing claimable found.",3) end})
Market:Paragraph({
    Title="Farmer's Market",
    Desc="The current public Update 2.0 guide reports three fruit offers per day that pay Tickets. NIGHTSHADE scans the replicated Market UI/world interactions rather than assuming an offer.",
    Image="store",
})

-- PETS
Pets:Toggle({Title="Auto Buy Pet Eggs",Value=Settings.AutoBuyPetEggs,Callback=function(v) Settings.AutoBuyPetEggs=v end})
Pets:Dropdown({
    Title="Egg Tier",
    Values={"Common","Rare","Epic","Legendary","Mythic"},
    Value=Settings.EggTier,
    Callback=function(v) Settings.EggTier=v end,
})
Pets:Input({
    Title="Keep Ticket Reserve",
    Value=tostring(Settings.KeepTicketReserve),
    Placeholder="0",
    Callback=function(v) Settings.KeepTicketReserve=tonumber(v) or 0 end,
})
Pets:Toggle({Title="Auto Place Eggs",Value=Settings.AutoPlaceEggs,Callback=function(v) Settings.AutoPlaceEggs=v end})
Pets:Toggle({Title="Auto Hatch Eggs",Value=Settings.AutoHatchEggs,Callback=function(v) Settings.AutoHatchEggs=v end})
Pets:Button({
    Title="Pet Recommendation",
    Callback=function()
        local w=currentWeather()
        local msg=(w~="Unknown") and "Weather active: Dog is the mutation-focused pick. Robin/Woodpecker are strong utility."
            or "General utility: Robin + Woodpecker. Cat for growth, Sheep for XP, Magpie for eggs, Turtle for lightning."
        notify("Pet recommendation",msg,7)
    end,
})
Pets:Paragraph({
    Title="Egg costs",
    Desc="Common 100 • Rare 200 • Epic 500 • Legendary 1,000 • Mythic 2,000 Tickets. Purchases are skipped before interaction if your ticket reserve would be broken.",
    Image="egg",
})

-- UTILITY
Utility:Toggle({Title="Auto Compost Low-Rarity Seeds",Value=Settings.AutoCompostSeeds,Callback=function(v) Settings.AutoCompostSeeds=v end})
Utility:Dropdown({Title="Compost Up To Rarity",Values=RARITIES,Value=Settings.CompostMaxRarity,Callback=function(v) Settings.CompostMaxRarity=v end})
Utility:Toggle({Title="Auto Buy Gear (known price only)",Value=Settings.AutoBuyGear,Callback=function(v) Settings.AutoBuyGear=v end})
Utility:Toggle({Title="Auto Buy Worms (known price only)",Value=Settings.AutoBuyWorms,Callback=function(v) Settings.AutoBuyWorms=v end})
Utility:Toggle({Title="Auto Buy Furniture (known price only)",Value=Settings.AutoBuyFurniture,Callback=function(v) Settings.AutoBuyFurniture=v end})
Utility:Toggle({Title="Auto Claim Index Reward",Value=Settings.AutoClaimIndexReward,Callback=function(v) Settings.AutoClaimIndexReward=v end})
Utility:Toggle({Title="Auto Rebirth",Value=Settings.AutoRebirth,Callback=function(v) Settings.AutoRebirth=v end})
Utility:Toggle({
    Title="Strict Rebirth Ready Check",
    Desc="Recommended ON so a prompt alone is not enough to rebirth.",
    Value=Settings.StrictRebirthReady,
    Callback=function(v) Settings.StrictRebirthReady=v end,
})
Utility:Toggle({Title="Anti AFK",Value=Settings.AntiAFK,Callback=function(v) Settings.AntiAFK=v end})
Utility:Button({Title="Save Settings",Icon="save",Callback=function() local ok,e=saveConfig() notify("Settings",ok and "Saved." or tostring(e),3) end})

-- DIAGNOSTICS
Diagnostics:Button({
    Title="Executor Capability Check",
    Callback=function()
        notify("Capabilities",
            "fireproximityprompt: "..tostring(fireproximityprompt~=nil)..
            "\nfireclickdetector: "..tostring(fireclickdetector~=nil)..
            "\nclipboard: "..tostring(setclipboard~=nil)..
            "\nfiles: "..tostring(writefile~=nil),7)
    end,
})

Diagnostics:Button({
    Title="Print Greedy Growers Surfaces",
    Callback=function()
        local names={"ConveyorSeeds","FruitSpawns","SellStand","CompostBin","Worm Shop","Gear Shop","Pet Shop","Farmers Market","SeedPlot"}
        print("========== NIGHTSHADE V3 // SURFACES ==========")
        for _, name in ipairs(names) do
            local obj=Workspace:FindFirstChild(name,true)
            print(name,obj and safeFullName(obj) or "NOT FOUND")
        end
        print("===============================================")
        notify("Diagnostics","Printed game-surface scan to console.",4)
    end,
})

Diagnostics:Button({
    Title="Print Unknown Prompts / Clicks",
    Callback=function()
        print("========== NIGHTSHADE V3 // INTERACTIONS ==========")
        local count=0
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
                count+=1
                if d:IsA("ProximityPrompt") then
                    print(count,safeFullName(d),"|",d.ActionText,"|",d.ObjectText)
                else
                    print(count,safeFullName(d),"| ClickDetector")
                end
            end
        end
        print("Total:",count)
        print("===================================================")
        notify("Diagnostics",tostring(count).." interactions printed.",4)
    end,
})

Diagnostics:Button({
    Title="Copy Snapshot",
    Callback=function()
        local s=snapshot()
        if setclipboard then pcall(setclipboard,s) notify("Snapshot","Copied.",3)
        else print(s) notify("Snapshot","Clipboard unavailable; printed.",4) end
    end,
})

Diagnostics:Toggle({Title="Debug Logging",Value=Settings.Debug,Callback=function(v) Settings.Debug=v end})

--========================================================
-- CLEANUP
--========================================================

function Runtime.Stop()
    Runtime.Running=false
    Settings.Master=false
    pcall(saveConfig)
    for _, c in ipairs(Runtime.Connections) do pcall(c.Disconnect,c) end
    table.clear(Runtime.Connections)
    pcall(function() Window:Destroy() end)
end

task.delay(0.8,refreshStatus)
task.spawn(function()
    while Runtime.Running do
        task.wait(2)
        refreshStatus()
    end
end)

if game.PlaceId~=EXPECTED_PLACE_ID then
    notify("Place warning","Expected Greedy Growers "..EXPECTED_PLACE_ID..", current "..tostring(game.PlaceId),7)
end

notify(
    "NIGHTSHADE V3 loaded",
    touch and "Mobile WindUI • seed sniper ready" or "WindUI • seed sniper ready",
    5
)

print("[NIGHTSHADE V3] Loaded.")
print("[NIGHTSHADE V3] fireproximityprompt:",fireproximityprompt~=nil)
print("[NIGHTSHADE V3] fireclickdetector:",fireclickdetector~=nil)
