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

--========================================================
-- SEED CONVEYOR
--========================================================

local function seedNameFrom(inst)
    local raw = readAny(inst, {"Seed", "SeedName", "Type", "ItemName"})
    if raw ~= nil then
        for name in pairs(SEEDS) do
            if contains(raw, name) then return name end
        end
    end

    local text = buildText(inst, 4)
    for name in pairs(SEEDS) do
        if contains(text, name) then return name end
    end
    return nil
end

local function seedRarity(inst, seedName)
    local raw = readAny(inst, {"Rarity", "Tier"})
    if raw ~= nil then
        for _, rarity in ipairs(RARITIES) do
            if contains(raw, rarity) then return rarity end
        end
    end
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
    if not root then
        Runtime.SeedCandidates = 0
        return {}
    end

    local entities = {}
    local seen = {}
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, root) then
            local entity = entityUnderRoot(interaction, root)
            if entity and not seen[entity] then
                local name = seedNameFrom(entity)
                local text = buildText(entity, 3)
                if name or contains(text, "seed") then
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
    local root = conveyorRoot()
    local best, fallback
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, entity) and (not root or underRoot(interaction, root)) then
            fallback = fallback or interaction
            local text = buildText(interaction, 3)
            if containsAny(text, {"buy", "purchase", "get seed", "seed"}) then
                best = interaction
                break
            end
        end
    end
    return best or fallback
end

local function affordability(entity)
    local name = seedNameFrom(entity)
    local rarity = seedRarity(entity, name)
    local price, source = seedPrice(entity, name)
    local money = cash()

    if money == nil and Settings.SkipIfCashUnknown then
        return false, "cash unknown", name, rarity, price, source, money
    end
    if price == nil and Settings.SkipIfPriceUnknown then
        return false, "price unknown", name, rarity, price, source, money
    end
    if price and Settings.MaxSeedCost > 0 and price > Settings.MaxSeedCost then
        return false, "over max cost", name, rarity, price, source, money
    end
    if money ~= nil and price ~= nil and (money - price) < Settings.KeepCoinReserve then
        return false, "unaffordable", name, rarity, price, source, money
    end
    if Settings.BuyMutatedOnly and not isMutated(entity) then
        return false, "not mutated", name, rarity, price, source, money
    end
    if Settings.BuyMode == "Specific Seed" and lower(name) ~= lower(Settings.PreferredSeed) then
        return false, "wrong seed", name, rarity, price, source, money
    end
    if Settings.BuyMode == "Minimum Rarity" then
        local got = RARITY_RANK[rarity] or 0
        local needed = RARITY_RANK[Settings.MinimumRarity] or 1
        if got < needed then
            return false, "below rarity", name, rarity, price, source, money
        end
    end

    return true, "allowed", name, rarity, price, source, money
end

local function candidateScore(entity)
    local ok, _, name, rarity, price = affordability(entity)
    if not ok then return -math.huge end

    if Settings.BuyMode == "Any Affordable" then
        return 1
    end

    if Settings.BuyMode == "Specific Seed" then
        return 1
    end

    local score = (RARITY_RANK[rarity] or 0) * 1e12 + math.min(price or 0, 9e11)
    if Settings.PreferMutated and isMutated(entity) then score = score + 1e11 end
    return score
end

local RareNotice = setmetatable({}, {__mode = "k"})

local function selectRiverSeed()
    local candidates = seedCandidates()
    local best, bestScore

    for _, entity in ipairs(candidates) do
        local ok, reason, name, rarity, price, source = affordability(entity)

        if Settings.RareSeedNotify and rarity and (RARITY_RANK[rarity] or 0) >= 4 and not RareNotice[entity] then
            RareNotice[entity] = true
            notify(
                "River Seed // " .. rarity,
                (name or entity.Name) .. " • $" .. abbreviate(price) .. " • " .. source .. " • " .. (ok and "eligible" or reason),
                5
            )
        end

        if ok then
            if Settings.BuyMode == "Any Affordable" then
                best = entity
                break
            end
            local score = candidateScore(entity)
            if not bestScore or score > bestScore then
                best = entity
                bestScore = score
            end
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
