    Callback = function(options)
        Settings.PreferredEgg = tableFirst(options) or "Rare"
    end,
})

PetsTab:CreateToggle({
    Name = "Auto Place Eggs",
    CurrentValue = Settings.AutoPlaceEggs,
    Flag = "AutoPlaceEggs",
    Callback = function(v) Settings.AutoPlaceEggs = v end,
})

PetsTab:CreateToggle({
    Name = "Auto Hatch Eggs",
    CurrentValue = Settings.AutoHatchEggs,
    Flag = "AutoHatchEggs",
    Callback = function(v) Settings.AutoHatchEggs = v end,
})

PetsTab:CreateSlider({
    Name = "Egg Buy Interval",
    Range = {2, 60},
    Increment = 1,
    Suffix = "s",
    CurrentValue = Settings.EggInterval,
    Flag = "EggInterval",
    Callback = function(v) Settings.EggInterval = v end,
})

PetsTab:CreateSection("Pet Intelligence")

PetsTab:CreateButton({
    Name = "Best Pet Suggestion Right Now",
    Callback = function()
        local weather = scanCurrentWeather()
        local suggestion

        if weather == "Misty" or weather == "Acid Rain" or weather == "Rainbow" or weather == "Meteor Shower" then
            suggestion = "Dog for mutation weather; Robin + Woodpecker are strong general utility."
        else
            suggestion = "General utility: Robin + Woodpecker. Rotate Cat for growth, Sheep for XP, Magpie for eggs, Turtle for lightning protection."
        end

        notify("Pet suggestion", suggestion, 7)
    end,
})

PetsTab:CreateButton({
    Name = "Print All 18 Pets",
    Callback = function()
        print("========== NIGHTSHADE // PETS ==========")
        local names = {}
        for name in pairs(PETS) do table.insert(names, name) end
        table.sort(names)
        for _, name in ipairs(names) do
            local p = PETS[name]
            print(name, "|", p.Egg .. " Egg", "|", p.Role)
        end
        print("=========================================")
        notify("Pet database", "Printed all 18 researched pets to console.", 4)
    end,
})

--========================================================
-- MARKET TAB
--========================================================

MarketTab:CreateSection("Farmer's Market / Tickets")

MarketTab:CreateToggle({
    Name = "Auto Farmer's Market",
    CurrentValue = Settings.AutoMarket,
    Flag = "AutoMarket",
    Callback = function(v) Settings.AutoMarket = v end,
})

MarketTab:CreateSlider({
    Name = "Market Interaction Interval",
    Range = {2, 60},
    Increment = 1,
    Suffix = "s",
    CurrentValue = Settings.MarketInterval,
    Flag = "MarketInterval",
    Callback = function(v) Settings.MarketInterval = v end,
})

MarketTab:CreateButton({
    Name = "Read Tickets",
    Callback = function()
        local tickets, source = getTickets()
        notify(
            "Tickets",
            tickets and (formatNumber(tickets) .. "\n" .. tostring(source)) or "No local/replicated ticket value detected.",
            5
        )
    end,
})

MarketTab:CreateSection("Support Systems")

MarketTab:CreateToggle({
    Name = "Auto Compost Seeds",
    CurrentValue = Settings.AutoCompost,
    Flag = "AutoCompost",
    Callback = function(v) Settings.AutoCompost = v end,
})

MarketTab:CreateToggle({
    Name = "Auto Buy Worms",
    CurrentValue = Settings.AutoBuyWorms,
    Flag = "AutoBuyWorms",
    Callback = function(v) Settings.AutoBuyWorms = v end,
})

MarketTab:CreateToggle({
    Name = "Auto Buy Gear",
    CurrentValue = Settings.AutoBuyGear,
    Flag = "AutoBuyGear",
    Callback = function(v) Settings.AutoBuyGear = v end,
})

MarketTab:CreateToggle({
    Name = "Auto Rebirth",
    CurrentValue = Settings.AutoRebirth,
    Flag = "AutoRebirth",
    Callback = function(v) Settings.AutoRebirth = v end,
})

--========================================================
-- UTILITY TAB
--========================================================

Utility:CreateSection("Movement / Runtime")

Utility:CreateButton({
    Name = "Stop Current Movement",
    Callback = function()
        stopMovement()
        notify("Movement", "Cancelled current NIGHTSHADE movement.", 3)
    end,
})

Utility:CreateButton({
    Name = "Disable All Automation",
    Callback = function()
        for key, value in pairs(Settings) do
            if type(value) == "boolean" and string.sub(key, 1, 4) == "Auto" then
                Settings[key] = false
            end
        end

        Settings.PlantDuringWeatherOnly = false
        stopMovement()
        notify("NIGHTSHADE", "Automation state disabled internally.", 4)
    end,
})

Utility:CreateToggle({
    Name = "Debug Console",
    CurrentValue = Settings.Debug,
    Flag = "Debug",
    Callback = function(v) Settings.Debug = v end,
})

Utility:CreateButton({
    Name = "Check Place ID",
    Callback = function()
        if game.PlaceId == EXPECTED_PLACE_ID then
            notify("Place check", "Greedy Growers PlaceId matched.", 4)
        else
            notify(
                "Place check",
                "Current PlaceId: " .. tostring(game.PlaceId) ..
                "\nExpected: " .. tostring(EXPECTED_PLACE_ID),
                6
            )
        end
    end,
})

--========================================================
-- DIAGNOSTICS TAB
--========================================================

Diagnostics:CreateSection("Interaction Scanner")

Diagnostics:CreateButton({
    Name = "Scan Prompt Categories",
    Callback = function()
        local text = promptSummaryText()
        print("========== NIGHTSHADE // PROMPT SCAN ==========")
        print(text)
        print("================================================")
        notify("Prompt scan", text, 8)
    end,
})

Diagnostics:CreateButton({
    Name = "Print Every Detected Prompt",
    Callback = function()
        print("========== NIGHTSHADE // ALL PROMPTS ==========")

        local rows = {}
        for prompt in pairs(Runtime.PromptCache) do
            if prompt and prompt.Parent then
                table.insert(rows, {
                    Category = classifyPrompt(prompt),
                    Text = prompt.ActionText .. " / " .. prompt.ObjectText,
                    Path = prompt:GetFullName(),
                })
            end
        end

        table.sort(rows, function(a, b)
            if a.Category ~= b.Category then
                return a.Category < b.Category
            end
            return a.Path < b.Path
        end)

        for _, row in ipairs(rows) do
            print("[" .. row.Category .. "]", row.Text, "|", row.Path)
        end

        print("===============================================")
        notify("Diagnostics", "Printed every detected ProximityPrompt.", 4)
    end,
})

Diagnostics:CreateButton({
    Name = "Print Unknown Prompts Only",
    Callback = function()
        print("========== NIGHTSHADE // UNKNOWN PROMPTS ==========")
        local count = 0

        for prompt in pairs(Runtime.PromptCache) do
            if prompt and prompt.Parent and classifyPrompt(prompt) == "Unknown" then
                count += 1
                print(
                    prompt:GetFullName(),
                    "| ActionText:", prompt.ActionText,
                    "| ObjectText:", prompt.ObjectText
                )
            end
        end

        print("Unknown count:", count)
        print("===================================================")
        notify("Unknown prompts", tostring(count) .. " unknown prompts printed.", 4)
    end,
})

Diagnostics:CreateButton({
    Name = "Copy Full Snapshot",
    Callback = function()
        copyText(snapshotText())
    end,
})

Diagnostics:CreateButton({
    Name = "Copy Pure Local Action Log",
    Callback = function()
        local lines = {"NIGHTSHADE // Pure Local Action Log"}

        for _, entry in ipairs(Runtime.SimulatedActions) do
            table.insert(lines, entry.Time .. " | " .. entry.Category .. " | " .. entry.Target)
        end

        copyText(table.concat(lines, "\n"))
    end,
})

Diagnostics:CreateButton({
    Name = "Clear Pure Local Action Log",
    Callback = function()
        table.clear(Runtime.SimulatedActions)
        notify("Pure Local", "Simulation log cleared.", 3)
    end,
})

Diagnostics:CreateSection("Local Data Readers")

Diagnostics:CreateButton({
    Name = "Inventory Snapshot",
    Callback = function()
        notify("Seed inventory", inventorySummaryText(), 8)
        print("NIGHTSHADE Seed Inventory:", inventorySummaryText())
    end,
})

Diagnostics:CreateButton({
    Name = "Cash / Tickets / Storage Snapshot",
    Callback = function()
        local cash, cashSource = getCash()
        local tickets, ticketSource = getTickets()
        local used, max = getInventoryUsage()

        local text =
            "Cash: " .. formatNumber(cash) .. " (" .. tostring(cashSource) .. ")" ..
            "\nTickets: " .. formatNumber(tickets) .. " (" .. tostring(ticketSource) .. ")" ..
            "\nStorage: " .. tostring(used or "?") .. "/" .. tostring(max or "?")

        notify("Local data", text, 8)
    end,
})

