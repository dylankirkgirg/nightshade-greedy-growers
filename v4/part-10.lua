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
end})

Diagnostics:Button({Title="Print Greedy Growers Surfaces", Callback=function()
    local names = {"ConveyorSeeds", "FruitSpawns", "SellStand", "CompostBin", "Worm Shop", "Gear Shop", "Pet Shop", "Farmers Market", "SeedPlot"}
    print("========== NIGHTSHADE V4 // SURFACES ==========")
    for _, name in ipairs(names) do
        local obj = Workspace:FindFirstChild(name, true)
        print(name, obj and safeFullName(obj) or "NOT FOUND")
    end
    print("==================================================")
    notify("Diagnostics", "Printed surface scan to console.", 4)
end})

Diagnostics:Button({Title="Print River Candidates", Callback=function()
    print("========== NIGHTSHADE V4 // RIVER ==========")
    for i, entity in ipairs(seedCandidates()) do
        local ok, reason, name, rarity, price, source, money = affordability(entity)
        print(i, safeFullName(entity), "|", name, rarity, price, source, "cash", money, ok and "ELIGIBLE" or reason)
    end
    print("==============================================")
    notify("Diagnostics", tostring(Runtime.SeedCandidates) .. " river candidates printed.", 4)
end})

Diagnostics:Button({Title="Audit Dead Trees", Callback=function()
    local candidates = deadTreeCandidates()
    print("========== NIGHTSHADE V4 // DEAD TREE AUDIT ==========")
    print("Found:", #candidates, "| confirmed cleared total:", Runtime.Stats.DeadTrees, "| failures:", Runtime.DeadSweep.Failed)
    for i, tree in ipairs(candidates) do
        local action, score = deadActionIn(tree)
        print(i, safeFullName(tree), "| action:", action and safeFullName(action) or "NONE", "| score:", score or "n/a", "| owned:", ownState(tree))
    end
    print("========================================================")
    Runtime.DeadSweep.Found = #candidates
    Runtime.DeadSweep.Remaining = #candidates
    notify("Dead-tree audit", tostring(#candidates) .. " dead tree(s) currently detected.", 4)
end})

Diagnostics:Button({Title="Print All Prompts / Clicks", Callback=function()
    print("========== NIGHTSHADE V4 // INTERACTIONS ==========")
    local count = 0
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) then
            count = count + 1
            if interaction:IsA("ProximityPrompt") then
                print(count, safeFullName(interaction), "|", interaction.ActionText, "|", interaction.ObjectText)
            else
                print(count, safeFullName(interaction), "| ClickDetector")
            end
        end
    end
    print("Total:", count)
    print("======================================================")
    notify("Diagnostics", tostring(count) .. " interactions printed.", 4)
end})

Diagnostics:Button({Title="Copy Snapshot", Callback=function()
    local s = snapshot()
    if setclipboard then
        pcall(setclipboard, s)
        notify("Snapshot", "Copied.", 3)
    else
        print(s)
        notify("Snapshot", "Clipboard unavailable; printed.", 4)
    end
end})

Diagnostics:Toggle({Title="Debug Logging", Value=Settings.Debug, Callback=function(v) Settings.Debug=v end})

-- Cross-device appearance controls.
local UISettings = Window:Tab({Title="UI Settings", Icon="palette"})
local themeNames = {}
pcall(function()
    local themes = WindUI:GetThemes()
    for name in pairs(themes or {}) do
        table.insert(themeNames, name)
    end
end)
table.sort(themeNames)
if #themeNames == 0 then themeNames = {"Dark", "Light"} end

UISettings:Dropdown({
    Title="Theme",
    Values=themeNames,
    Value="Dark",
    SearchBarEnabled=#themeNames > 8,
    Callback=function(value)
        local selected = value
        if type(value) == "table" then selected = value.Title or value.Value or value[1] end
        if selected then pcall(function() WindUI:SetTheme(selected) end) end
    end,
})

UISettings:Slider({
    Title="UI Scale",
    Desc="Adjust NIGHTSHADE without changing Roblox UI scale.",
    Step=0.05,
    Value={Min=0.65, Max=1.15, Default=UIState.Scale},
    Callback=function(value)
        UIState.AutoFit = false
        applyUIScale(value)
    end,
})

UISettings:Toggle({
    Title="Auto Fit On Rotation / Resize",
    Value=UIState.AutoFit,
    Callback=function(value)
        UIState.AutoFit = value
        if value then fitWindowToDevice(false) end
    end,
})

UISettings:Button({Title="Fit UI To This Screen", Icon="maximize", Callback=function()
    UIState.AutoFit = true
    fitWindowToDevice(true)
    notify("Interface", "Re-fitted NIGHTSHADE to this screen.", 3)
end})

UISettings:Button({Title="Save NIGHTSHADE Settings", Icon="save", Callback=function()
    local ok, err = saveConfig()
    notify("Settings", ok and "Saved." or tostring(err), 3)
end})

UISettings:Button({Title="Unload NIGHTSHADE", Icon="power", Callback=function()
    Runtime.Stop()
end})

UISettings:Paragraph({
    Title="Cross-device mode",
    Desc=touch
        and "Touch mode is active. The window auto-sizes for phone/tablet, the mobile NIGHTSHADE button reopens the UI, and WindUI handles native touch dragging/scrolling."
        or "Desktop mode is active. The same loader automatically switches layouts on touch devices.",
    Image=touch and "smartphone" or "monitor",
})

--========================================================
-- CLEANUP
--========================================================

function Runtime.Stop()
    if not Runtime.Running then return end
    Runtime.Running = false
    Settings.Master = false
    pcall(saveConfig)
    for _, c in ipairs(Runtime.Connections) do pcall(c.Disconnect, c) end
    Runtime.Connections = {}
    pcall(function() Window:Destroy() end)
end


-- WindUI cleanup is handled through Runtime.Stop / Window:Destroy.

task.delay(0.8, refreshStatus)
task.spawn(function()
    while Runtime.Running do
        task.wait(2)
        refreshStatus()
    end
end)

if game.PlaceId ~= EXPECTED_PLACE_ID then
    notify("Place warning", "Expected Greedy Growers " .. EXPECTED_PLACE_ID .. ", current " .. tostring(game.PlaceId), 7)
end

notify("NIGHTSHADE V4 loaded", (touch and "WindUI mobile • " or "WindUI desktop • ") .. "verified dead-tree sweeper • strict seed sniper ready", 5)
print("[NIGHTSHADE V4] Loaded • WindUI cross-device")
print("[NIGHTSHADE V4] fireproximityprompt:", fireproximityprompt ~= nil)
print("[NIGHTSHADE V4] fireclickdetector:", fireclickdetector ~= nil)
