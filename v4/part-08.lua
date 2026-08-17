                        return true
                    end
                end
            end
        end
    end
    return false
end

local function storageFull()
    local used = inventoryCount()
    local maximum = inventoryMax()
    return used ~= nil and maximum ~= nil and maximum > 0 and used >= maximum
end

local function sell(kind)
    local stand = findNamedRoot({"SellStand", "Sell Stand"})
    local words = kind == "all" and {"sell all", "sell everything"} or {"sell fruits", "sell fruit", "sell"}
    for _, interaction in ipairs(findInteractions(words, stand)) do
        if interact(interaction, kind == "all" and "Sell All" or "Sell Fruits") then
            Runtime.Stats.Sells = Runtime.Stats.Sells + 1
            return true
        end
    end
    return false
end

--========================================================
-- MARKET / PETS
--========================================================

local function marketGive()
    local root = marketRoot()
    if not root then return false end
    for _, interaction in ipairs(findInteractions({"give", "submit", "turn in", "deliver"}, root)) do
        if interact(interaction, "Give Market Fruits") then
            Runtime.Stats.Market = Runtime.Stats.Market + 1
            return true
        end
    end
    return false
end

local function marketClaim()
    local root = marketRoot()
    if not root then return false end
    for _, interaction in ipairs(findInteractions({"claim", "ticket", "reward"}, root)) do
        if interact(interaction, "Claim Market Tickets") then
            Runtime.Stats.Market = Runtime.Stats.Market + 1
            return true
        end
    end
    return false
end

local function eggTierFrom(inst)
    local raw = readAny(inst, {"Rarity", "Tier", "EggTier"})
    if raw ~= nil then
        for tier in pairs(EGG_COSTS) do
            if contains(raw, tier) then return tier end
        end
    end
    local text = buildText(inst, 5)
    for tier in pairs(EGG_COSTS) do
        if contains(text, tier) and containsAny(text, {"egg", "pet"}) then return tier end
    end
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
                    if interact(interaction, "Buy " .. tier .. " Egg") then
                        Runtime.Stats.Support = Runtime.Stats.Support + 1
                        return true
                    end
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
            if interact(interaction, label) then
                Runtime.Stats.Support = Runtime.Stats.Support + 1
                return true
            end
        end
    end
    return false
end

--========================================================
-- SUPPORT SHOPS / COMPOST / INDEX / REBIRTH
--========================================================

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
    for _, tool in ipairs(seedTools()) do
        if rarityAtMost(tool, Settings.CompostMaxRarity) then
            chosen = tool
            break
        end
    end
    if not chosen then return false end

    pcall(h.EquipTool, h, chosen)
    task.wait(0.05)

    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, bin) then
            if interact(interaction, "Compost Seed") then
                Runtime.Stats.Support = Runtime.Stats.Support + 1
                return true
            end
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
                if interact(interaction, label) then
                    Runtime.Stats.Support = Runtime.Stats.Support + 1
                    return true
                end
            end
        end
    end
    return false
end

local function claimIndex()
    for _, interaction in ipairs(findInteractions({"claim index", "index reward", "claim reward"})) do
        if interact(interaction, "Claim Index Reward") then
            Runtime.Stats.Support = Runtime.Stats.Support + 1
            return true
        end
    end
    return false
end

local function rebirthReady()
    for _, key in ipairs({"CanRebirth", "RebirthReady", "ReadyToRebirth"}) do
        if safeAttr(Player, key) == true then return true end
    end

    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible and containsAny(d.Text, {"rebirth ready", "ready to rebirth", "rebirth available"}) then
                return true
            end
        end
    end

    return not Settings.StrictRebirthReady
end

local function rebirth()
    if not rebirthReady() then return false end
    for _, interaction in ipairs(findInteractions({"rebirth"})) do
        if interact(interaction, "Rebirth") then
            Runtime.Stats.Support = Runtime.Stats.Support + 1
            return true
        end
    end
    return false
end

--========================================================
-- LOOPS
--========================================================

local function enabled(toggle)
    return Runtime.Running and Settings.Master and toggle
end

task.spawn(function()
    while Runtime.Running do
        local acted = false

        if enabled(Settings.AutoClearDead) then acted = clearDeadSweep() end
        if enabled(Settings.AutoSellAtMax) and not acted and storageFull() then acted = sell(Settings.AutoSellAll and "all" or "fruits") end
        if enabled(Settings.AutoHarvest) and not acted then acted = harvestOne() end
