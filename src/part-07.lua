    Name = "Refresh Status",
    Callback = function()
        StatusParagraph:Set({
            Title = "NIGHTSHADE Status",
            Content = snapshotText(),
        })
    end,
})

Dashboard:CreateDropdown({
    Name = "Execution Mode",
    Options = {"Mechanics","Pure Local"},
    CurrentOption = {Settings.ExecutionMode},
    MultipleOptions = false,
    Flag = "ExecutionMode",
    Callback = function(options)
        Settings.ExecutionMode = tableFirst(options) or "Mechanics"

        if Settings.ExecutionMode == "Pure Local" then
            stopMovement()
            notify(
                "Pure Local enabled",
                "No prompts will be activated. Actions are simulated/logged locally only.",
                6
            )
        else
            notify(
                "Mechanics mode enabled",
                "No direct remote calls. Normal prompt interactions may still be processed by your game.",
                6
            )
        end
    end,
})

Dashboard:CreateButton({
    Name = "Show Current Weather / Recommendation",
    Callback = function()
        local weather, source = scanCurrentWeather()
        local suggestion = "No specific weather target detected."

        if weather == "Misty" then
            suggestion = "Dewy target. Dog is the mutation-focused pet pick."
        elseif weather == "Acid Rain" then
            suggestion = "Radioactive target. Mutation planting is attractive."
        elseif weather == "Rainbow" then
            suggestion = "Golden target. Prioritize valuable seeds."
        elseif weather == "Meteor Shower" then
            suggestion = "Cosmic target. Highest reported core weather multiplier."
        end

        notify("Weather // " .. weather, suggestion .. "\nDetected via: " .. source, 7)
    end,
})

--========================================================
-- FARM TAB
--========================================================

Farm:CreateSection("Core Automation")

Farm:CreateToggle({
    Name = "Auto Harvest",
    CurrentValue = Settings.AutoHarvest,
    Flag = "AutoHarvest",
    Callback = function(v) Settings.AutoHarvest = v end,
})

Farm:CreateToggle({
    Name = "Auto Collect Fruit",
    CurrentValue = Settings.AutoCollect,
    Flag = "AutoCollect",
    Callback = function(v) Settings.AutoCollect = v end,
})

Farm:CreateToggle({
    Name = "Auto Plant",
    CurrentValue = Settings.AutoPlant,
    Flag = "AutoPlant",
    Callback = function(v) Settings.AutoPlant = v end,
})

Farm:CreateToggle({
    Name = "Auto Sell",
    CurrentValue = Settings.AutoSell,
    Flag = "AutoSell",
    Callback = function(v) Settings.AutoSell = v end,
})

Farm:CreateToggle({
    Name = "Clear Dead / Withered Trees",
    CurrentValue = Settings.AutoClearDead,
    Flag = "AutoClearDead",
    Callback = function(v) Settings.AutoClearDead = v end,
})

Farm:CreateSection("Behavior")

Farm:CreateToggle({
    Name = "Own Plot Only (strict)",
    CurrentValue = Settings.StrictOwnPlotOnly,
    Flag = "StrictOwnPlotOnly",
    Callback = function(v) Settings.StrictOwnPlotOnly = v end,
})

Farm:CreateSlider({
    Name = "Action Delay",
    Range = {0.05, 2},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = Settings.ActionDelay,
    Flag = "ActionDelay",
    Callback = function(v) Settings.ActionDelay = v end,
})

Farm:CreateSlider({
    Name = "Maximum Search Distance",
    Range = {50, 1200},
    Increment = 25,
    Suffix = " studs",
    CurrentValue = Settings.MaxActionDistance,
    Flag = "MaxActionDistance",
    Callback = function(v) Settings.MaxActionDistance = v end,
})

Farm:CreateSlider({
    Name = "Auto Sell Interval",
    Range = {2, 180},
    Increment = 1,
    Suffix = "s",
    CurrentValue = Settings.SellInterval,
    Flag = "SellInterval",
    Callback = function(v) Settings.SellInterval = v end,
})

--========================================================
-- SEEDS TAB
--========================================================

SeedsTab:CreateSection("Seed Buying")

SeedsTab:CreateToggle({
    Name = "Auto Buy Seeds",
    CurrentValue = Settings.AutoBuySeeds,
    Flag = "AutoBuySeeds",
    Callback = function(v) Settings.AutoBuySeeds = v end,
})

SeedsTab:CreateDropdown({
    Name = "Buy Mode",
    Options = {"Highest Affordable","Minimum Rarity","Specific Seed","Any"},
    CurrentOption = {Settings.SeedBuyMode},
    MultipleOptions = false,
    Flag = "SeedBuyMode",
    Callback = function(options)
        Settings.SeedBuyMode = tableFirst(options) or "Highest Affordable"
    end,
})

SeedsTab:CreateDropdown({
    Name = "Preferred Seed",
    Options = SEED_NAMES,
    CurrentOption = {Settings.PreferredSeed},
    MultipleOptions = false,
    Flag = "PreferredSeed",
    Callback = function(options)
        Settings.PreferredSeed = tableFirst(options) or "Oak"
    end,
})

SeedsTab:CreateDropdown({
    Name = "Minimum Rarity",
    Options = {"Common","Rare","Epic","Legendary","Mythic","Celestial","Secret","Divine"},
    CurrentOption = {Settings.MinimumRarity},
    MultipleOptions = false,
    Flag = "MinimumRarity",
    Callback = function(options)
        Settings.MinimumRarity = tableFirst(options) or "Common"
    end,
})

SeedsTab:CreateToggle({
    Name = "Only Mutated Seeds",
    CurrentValue = Settings.OnlyMutatedSeeds,
    Flag = "OnlyMutatedSeeds",
    Callback = function(v) Settings.OnlyMutatedSeeds = v end,
})

SeedsTab:CreateToggle({
    Name = "Auto Equip Best Seed",
    CurrentValue = Settings.AutoEquipSeed,
    Flag = "AutoEquipSeed",
    Callback = function(v) Settings.AutoEquipSeed = v end,
})

SeedsTab:CreateInput({
    Name = "Keep Cash Reserve",
    CurrentValue = tostring(Settings.KeepCashReserve),
    PlaceholderText = "0",
    RemoveTextAfterFocusLost = false,
    Flag = "KeepCashReserve",
    Callback = function(text)
        Settings.KeepCashReserve = tonumber(text) or 0
    end,
})

SeedsTab:CreateSlider({
    Name = "Seed Buy Interval",
    Range = {1, 30},
    Increment = 1,
    Suffix = "s",
    CurrentValue = Settings.BuySeedInterval,
    Flag = "BuySeedInterval",
    Callback = function(v) Settings.BuySeedInterval = v end,
})

SeedsTab:CreateSection("Research Database")

SeedsTab:CreateButton({
    Name = "Print All 20 Seeds",
    Callback = function()
        print("========== NIGHTSHADE // SEEDS ==========")
        for _, seedName in ipairs(SEED_NAMES) do
            local d = SEEDS[seedName]
            print(
                seedName,
                "|", d.Rarity,
                "| Cost:", formatNumber(d.Cost),
                "| Spawn:", d.Spawn
            )
        end
        print("==========================================")
        notify("Seed database", "Printed all 20 researched seeds to console.", 4)
    end,
})

--========================================================
-- WEATHER TAB
--========================================================

WeatherTab:CreateSection("Weather-Aware Farming")

WeatherTab:CreateToggle({
    Name = "Only Plant During Selected Weather",
    CurrentValue = Settings.PlantDuringWeatherOnly,
    Flag = "PlantDuringWeatherOnly",
    Callback = function(v) Settings.PlantDuringWeatherOnly = v end,
})

for _, weather in ipairs({"Misty","Acid Rain","Rainbow","Meteor Shower"}) do
    WeatherTab:CreateToggle({
        Name = "Allow " .. weather,
        CurrentValue = Settings.AllowedWeathers[weather],
        Flag = "AllowWeather_" .. weather:gsub("%s",""),
        Callback = function(v)
            Settings.AllowedWeathers[weather] = v
        end,
    })
end

WeatherTab:CreateToggle({
    Name = "Weather Notifications",
    CurrentValue = Settings.SmartWeatherNotifications,
    Flag = "SmartWeatherNotifications",
    Callback = function(v) Settings.SmartWeatherNotifications = v end,
})

WeatherTab:CreateButton({
    Name = "Show Mutation Database",
    Callback = function()
        local lines = {}

        for mutation, d in pairs(MUTATIONS) do
            table.insert(
                lines,
                mutation .. " | x" .. tostring(d.Multiplier or "?") .. " | " .. d.Source
            )
        end

        table.sort(lines)
        print("========== NIGHTSHADE // MUTATIONS ==========")
        for _, line in ipairs(lines) do print(line) end
        print("==============================================")
        notify("Mutation database", "Printed researched mutation info to console.", 4)
    end,
})

--========================================================
-- PETS TAB
--========================================================

PetsTab:CreateSection("Egg Automation")

PetsTab:CreateToggle({
    Name = "Auto Buy Pet Eggs",
    CurrentValue = Settings.AutoBuyEggs,
    Flag = "AutoBuyEggs",
    Callback = function(v) Settings.AutoBuyEggs = v end,
})

PetsTab:CreateDropdown({
    Name = "Preferred Egg",
    Options = {"Common","Rare","Epic","Legendary","Mythic"},
    CurrentOption = {Settings.PreferredEgg},
    MultipleOptions = false,
    Flag = "PreferredEgg",
