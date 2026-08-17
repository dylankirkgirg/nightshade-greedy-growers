    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("BasePart") then
            local name = lower(object.Name)
            if containsAny(name, PICKUP_NAME_WORDS) then
                local dist = (root.Position - object.Position).Magnitude
                if dist <= Settings.MaxActionDistance and (not bestDist or dist < bestDist) then
                    best, bestDist = object, dist
                end
            end
        end
    end

    return best, bestDist
end

local function collectPhysicalPickup()
    local object = findNearestPhysicalPickup()
    if not object then return false end

    if Settings.ExecutionMode == "Pure Local" then
        return logSimulatedAction("CollectPhysical", object)
    end

    local position = getWorldPosition(object)
    if not position then return false end

    Runtime.LastAction = "CollectPhysical"
    return walkTo(position, 1.5)
end

--========================================================
-- CATEGORY PROCESSOR
--========================================================

local function processCategory(category)
    local prompt = findBestPrompt(category)
    if not prompt then return false end

    Runtime.Busy = true
    local ok = activatePrompt(prompt)
    Runtime.Busy = false
    return ok
end

local function intervalReady(key, seconds)
    local last = Runtime.LastCategoryAction[key] or 0
    return now() - last >= seconds
end

local function markInterval(key)
    Runtime.LastCategoryAction[key] = now()
end

--========================================================
-- SMART WEATHER ADVICE
--========================================================

local LastWeather = nil

local function maybeNotifyWeather()
    if not Settings.SmartWeatherNotifications then return end

    local weather = scanCurrentWeather()

    if weather ~= LastWeather then
        LastWeather = weather

        if weather == "Misty" then
            notify("Weather // Misty", "Dewy opportunity. Dog helps mutation farming; plant now if you're targeting weather mutations.", 6)
        elseif weather == "Acid Rain" then
            notify("Weather // Acid Rain", "Radioactive opportunity. Mutation-focused planting is worth prioritizing.", 6)
        elseif weather == "Rainbow" then
            notify("Weather // Rainbow", "Golden opportunity. Strong time to plant/hold mutation-target seeds.", 6)
        elseif weather == "Meteor Shower" then
            notify("Weather // Meteor Shower", "Cosmic opportunity. Highest reported core weather multiplier.", 6)
        end
    end
end

task.spawn(function()
    while Runtime.Running do
        pcall(maybeNotifyWeather)
        task.wait(1.0)
    end
end)

--========================================================
-- MAIN SCHEDULER
--========================================================

task.spawn(function()
    while Runtime.Running do
        local acted = false

        if Settings.AutoClearDead and not acted then
            acted = processCategory("ClearDead")
        end

        if Settings.AutoHarvest and not acted then
            acted = processCategory("Harvest")
        end

        if Settings.AutoCollect and not acted then
            acted = processCategory("Collect")
            if not acted then
                acted = collectPhysicalPickup()
            end
        end

        if Settings.AutoMarket and not acted and intervalReady("Market", Settings.MarketInterval) then
            acted = processCategory("Market")
            if acted then markInterval("Market") end
        end

        if Settings.AutoPlant and not acted and weatherAllowsPlanting() then
            acted = processCategory("Plant")
        end

        if Settings.AutoCompost and not acted and intervalReady("Compost", Settings.CompostInterval) then
            acted = processCategory("Compost")
            if acted then markInterval("Compost") end
        end

        if Settings.AutoBuySeeds and not acted and intervalReady("BuySeed", Settings.BuySeedInterval) then
            acted = processCategory("BuySeed")
            if acted then markInterval("BuySeed") end
        end

        if Settings.AutoPlaceEggs and not acted then
            acted = processCategory("PlaceEgg")
        end

        if Settings.AutoHatchEggs and not acted then
            acted = processCategory("HatchEgg")
        end

        if Settings.AutoBuyEggs and not acted and intervalReady("BuyEgg", Settings.EggInterval) then
            acted = processCategory("BuyEgg")
            if acted then markInterval("BuyEgg") end
        end

        if Settings.AutoBuyWorms and not acted and intervalReady("BuyWorm", Settings.WormInterval) then
            acted = processCategory("BuyWorm")
            if acted then markInterval("BuyWorm") end
        end

        if Settings.AutoBuyGear and not acted and intervalReady("BuyGear", Settings.GearInterval) then
            acted = processCategory("BuyGear")
            if acted then markInterval("BuyGear") end
        end

        if Settings.AutoSell and not acted and intervalReady("Sell", Settings.SellInterval) then
            acted = processCategory("Sell")
            if acted then markInterval("Sell") end
        end

        if Settings.AutoRebirth and not acted and intervalReady("Rebirth", Settings.RebirthInterval) then
            acted = processCategory("Rebirth")
            if acted then markInterval("Rebirth") end
        end

        task.wait(acted and Settings.ActionDelay or Settings.SchedulerIdleDelay)
    end
end)

--========================================================
-- DIAGNOSTICS / SNAPSHOTS
--========================================================

local function countPromptCategories()
    local counts = {}

    for prompt in pairs(Runtime.PromptCache) do
        if prompt and prompt.Parent then
            local category = classifyPrompt(prompt)
            counts[category] = (counts[category] or 0) + 1
        end
    end

    return counts
end

local function promptSummaryText()
    local counts = countPromptCategories()

    local order = {
        "Plant","Harvest","Collect","BuySeed","Sell","ClearDead",
        "Market","BuyEgg","PlaceEgg","HatchEgg","BuyWorm","BuyGear",
        "Compost","Rebirth","Unknown"
    }

    local parts = {}

    for _, category in ipairs(order) do
        table.insert(parts, category .. ":" .. tostring(counts[category] or 0))
    end

    return table.concat(parts, " | ")
end

local function inventorySummaryText()
    local seeds = getSeedTools()
    local byName = {}

    for _, entry in ipairs(seeds) do
        local key = entry.Seed or "Unknown"
        if entry.Mutation then
            key ..= " [" .. entry.Mutation .. "]"
        end
        byName[key] = (byName[key] or 0) + 1
    end

    local parts = {}
    for name, count in pairs(byName) do
        table.insert(parts, name .. " x" .. count)
    end
    table.sort(parts)

    if #parts == 0 then return "No seed tools detected." end
    return table.concat(parts, ", ")
end

local function snapshotText()
    local cash, cashSource = getCash()
    local tickets, ticketSource = getTickets()
    local used, max = getInventoryUsage()
    local weather, weatherSource = scanCurrentWeather()

    local lines = {
        "NIGHTSHADE // Greedy Growers Snapshot",
        "PlaceId: " .. tostring(game.PlaceId),
        "Expected PlaceId: " .. tostring(EXPECTED_PLACE_ID),
        "Execution Mode: " .. Settings.ExecutionMode,
        "Current Weather: " .. tostring(weather) .. " (" .. tostring(weatherSource) .. ")",
        "Cash: " .. formatNumber(cash) .. " [" .. tostring(cashSource) .. "]",
        "Tickets: " .. formatNumber(tickets) .. " [" .. tostring(ticketSource) .. "]",
        "Inventory: " .. tostring(used or "?") .. "/" .. tostring(max or "?"),
        "Seed Tools: " .. inventorySummaryText(),
        "Prompt Scan: " .. promptSummaryText(),
        "Last Action: " .. tostring(Runtime.LastAction),
        "Actions: " .. tostring(Runtime.ActionCount),
        "Failures: " .. tostring(Runtime.FailedActions),
        "Last Error: " .. tostring(Runtime.LastError),
    }

    return table.concat(lines, "\n")
end

local function copyText(text)
    if setclipboard then
        local ok = pcall(setclipboard, text)
        if ok then
            notify("Copied", "Diagnostic text copied to clipboard.", 3)
            return true
        end
    end

    print(text)
    notify("Clipboard unavailable", "Printed the data to console instead.", 4)
    return false
end

--========================================================
-- LINORIA UI
--========================================================

local LINORIA_REPO =
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

local Library = loadstring(game:HttpGet(
    LINORIA_REPO .. "Library.lua"
))()

