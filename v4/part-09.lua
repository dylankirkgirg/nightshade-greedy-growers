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
        if enabled(Settings.AutoBuySeeds) then pcall(buyBestSeed)
        else pcall(selectRiverSeed) end
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

--========================================================
-- UI
--========================================================

local Home = Window:Tab({Title="Home", Icon="house"})
local Farm = Window:Tab({Title="Farm", Icon="sprout"})
local SeedsTab = Window:Tab({Title="Seeds", Icon="package"})
local Weather = Window:Tab({Title="Weather", Icon="cloud-lightning"})
local Market = Window:Tab({Title="Market", Icon="store"})
local Pets = Window:Tab({Title="Pets", Icon="paw-print"})
local Utility = Window:Tab({Title="Utility", Icon="wrench"})
local Diagnostics = Window:Tab({Title="Diagnostics", Icon="scan-search"})

local Status = Home:Paragraph({Title="NIGHTSHADE V4", Desc="Loading snapshot...", Image="sprout"})

local function snapshot()
    local money, moneySource = cash()
    local tix, ticketSource = tickets()
    local used = inventoryCount()
    local maximum = inventoryMax()
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
        "Dead trees: cleared " .. Runtime.Stats.DeadTrees .. " • remaining " .. Runtime.DeadSweep.Remaining .. " • failed " .. Runtime.DeadSweep.Failed,
        "Dead sweep: " .. Runtime.DeadSweep.Last,
        "fireproximityprompt=" .. tostring(fireproximityprompt ~= nil) .. " • fireclickdetector=" .. tostring(fireclickdetector ~= nil),
    }, "\n")
end

local function refreshStatus()
    pcall(function() Status:SetDesc(snapshot()) end)
end

Home:Toggle({Title="MASTER AUTOMATION", Desc="Global kill switch.", Value=Settings.Master, Callback=function(v) Settings.Master=v end})
Home:Button({Title="Refresh Status", Icon="refresh-cw", Callback=refreshStatus})
Home:Button({Title="Save Settings", Icon="save", Callback=function()
    local ok, err = saveConfig()
    notify(ok and "Saved" or "Save failed", ok and CONFIG_FILE or tostring(err), 3)
end})
Home:Button({Title="Panic Stop", Icon="octagon", Callback=function()
    Settings.Master = false
    notify("Automation stopped", "Master switch is OFF.", 3)
end})
Home:Paragraph({
    Title="V4 buyer guard",
    Desc="The river buyer reads an explicit live Price/Cost first, falls back to the seed database only for recognized seeds, checks affordability, then checks it again immediately before the interaction.",
    Image="shield-check",
})

Farm:Toggle({Title="Auto Harvest", Value=Settings.AutoHarvest, Callback=function(v) Settings.AutoHarvest=v end})
Farm:Slider({Title="Harvest At Multiplier", Value={Min=1,Max=100,Default=Settings.HarvestAtMultiplier}, Step=0.5, Callback=function(v) Settings.HarvestAtMultiplier=v end})
Farm:Toggle({Title="Auto Collect Fruit", Value=Settings.AutoCollectFruit, Callback=function(v) Settings.AutoCollectFruit=v end})
Farm:Toggle({Title="Use Collect All First", Value=Settings.UseCollectAll, Callback=function(v) Settings.UseCollectAll=v end})
Farm:Toggle({Title="Auto Clear Dead Trees", Desc="Full verified sweep: keeps rescanning until your plot is clean or every remaining tree is temporarily backed off.", Value=Settings.AutoClearDead, Callback=function(v) Settings.AutoClearDead=v end})
Farm:Slider({Title="Dead Trees Per Sweep", Value={Min=1,Max=64,Default=Settings.DeadSweepMaxActions}, Step=1, Callback=function(v) Settings.DeadSweepMaxActions=v end})
Farm:Button({Title="Clear ALL Dead Trees Now", Callback=function()
    local _, cleared, remaining = clearDeadSweep()
    notify("Dead-tree sweep", "Confirmed cleared: " .. tostring(cleared) .. " • remaining: " .. tostring(remaining), 5)
end})
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
SeedsTab:Button({Title="Scan River Now", Icon="scan-search", Callback=function()
    selectRiverSeed()
    notify("River scan", Runtime.BestRiverSeed, 5)
end})
SeedsTab:Button({Title="Buy Best Eligible Seed Once", Icon="shopping-cart", Callback=function()
    local ok = buyBestSeed()
    notify("Seed buyer", ok and (Settings.SeedDryRun and "Dry-run target selected." or "Purchase interaction sent.") or ("Skipped • " .. Runtime.LastError), 4)
end})

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
    notify("Capabilities",
        "fireproximityprompt: " .. tostring(fireproximityprompt ~= nil) ..
        "\nfireclickdetector: " .. tostring(fireclickdetector ~= nil) ..
        "\nclipboard: " .. tostring(setclipboard ~= nil) ..
        "\nfiles: " .. tostring(writefile ~= nil), 7)
