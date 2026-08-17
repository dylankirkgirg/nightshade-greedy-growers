            local child = object:FindFirstChild(key)
            if child then
                foundMarker = true

                if child:IsA("ObjectValue") and child.Value == Player then
                    return true
                elseif (child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue")) then
                    if matchesOwner(child.Value) then
                        return true
                    end
                end
            end
        end

        object = object.Parent
        depth += 1
    end

    if foundMarker then
        return false
    end

    return nil
end

--========================================================
-- PROMPT CLASSIFIER
--========================================================

local function classifyPrompt(prompt)
    local text = buildInstanceText(prompt)

    -- Specific systems BEFORE generic "buy"/"collect".
    if containsAny(text, {"rebirth","prestige","ascend"}) then
        return "Rebirth"
    end

    if containsAny(text, {"farmers market","farmer's market","market offer","market request","claim market","submit fruit","turn in fruit"}) then
        return "Market"
    end

    if containsAny(text, {"compost","composter","compost bin"}) then
        return "Compost"
    end

    if contains(text, "worm") and containsAny(text, {"buy","purchase","shop","get"}) then
        return "BuyWorm"
    end

    if containsAny(text, {"gear shop","buy gear","purchase gear","fertilizer shop"}) then
        return "BuyGear"
    end

    if containsAny(text, {"pet shop","egg shop"}) and containsAny(text, {"buy","purchase","egg"}) then
        return "BuyEgg"
    end

    if containsAny(text, {"place egg","plant egg","set egg","put egg"}) then
        return "PlaceEgg"
    end

    if containsAny(text, {"hatch egg","hatch"}) and contains(text, "egg") then
        return "HatchEgg"
    end

    if containsAny(text, {"dead tree","remove dead","clear dead","withered tree","destroyed tree","chop dead"}) then
        return "ClearDead"
    end

    if containsAny(text, {"sell all","sell fruit","sell fruits","sell produce","cash out"}) then
        return "Sell"
    end

    if containsAny(text, {"farmers market","market"}) and contains(text, "sell") then
        return "Sell"
    end

    if contains(text, "seed") and containsAny(text, {"buy","purchase","conveyor","river","shop","take seed","get seed"}) then
        return "BuySeed"
    end

    if containsAny(text, {"plant seed","plant","sow","place seed"}) then
        return "Plant"
    end

    if containsAny(text, {"harvest tree","harvest plant","harvest"}) then
        return "Harvest"
    end

    if containsAny(text, {"collect fruit","collect fruits","pick fruit","pick up fruit","collect produce","collect crop"}) then
        return "Collect"
    end

    -- Looser fallbacks
    if contains(text, "fruit") and containsAny(text, {"collect","pick","take"}) then
        return "Collect"
    end

    if contains(text, "tree") and containsAny(text, {"harvest","chop"}) then
        return "Harvest"
    end

    if contains(text, "sell") then
        return "Sell"
    end

    return "Unknown"
end

--========================================================
-- PROMPT CACHE
--========================================================

local function cachePrompt(object)
    if object:IsA("ProximityPrompt") then
        Runtime.PromptCache[object] = true
    end
end

local function uncachePrompt(object)
    Runtime.PromptCache[object] = nil
    Runtime.PromptCooldowns[object] = nil
end

for _, object in ipairs(Workspace:GetDescendants()) do
    cachePrompt(object)
end

Workspace.DescendantAdded:Connect(cachePrompt)
Workspace.DescendantRemoving:Connect(uncachePrompt)

local function promptReady(prompt)
    local last = Runtime.PromptCooldowns[prompt]
    if not last then return true end
    return now() - last >= Settings.PromptRetryDelay
end

--========================================================
-- INVENTORY / EQUIP
--========================================================

local function getBackpack()
    return Player:FindFirstChildOfClass("Backpack")
end

local function getSeedTools()
    local results = {}
    local character = Player.Character
    local backpack = getBackpack()

    local function inspect(container)
        if not container then return end

        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                local text = lower(item.Name)
                local seedName = detectSeedName(text)
                local isSeed = seedName ~= nil or contains(text, "seed")

                if isSeed then
                    table.insert(results, {
                        Tool = item,
                        Seed = seedName or trim(item.Name:gsub("[Ss]eed","")),
                        Mutation = detectMutation(item),
                        Equipped = container == character,
                    })
                end
            end
        end
    end

    inspect(character)
    inspect(backpack)

    return results
end

local function seedToolScore(entry)
    local seed = SEEDS[entry.Seed]
    local rarityRank = seed and RARITY_RANK[seed.Rarity] or 0
    local score = rarityRank * 1000000 + (seed and math.min(seed.Cost, 999999) or 0)

    if entry.Mutation then
        score += 100000000
    end

    if Settings.PreferredSeed ~= "" and lower(entry.Seed) == lower(Settings.PreferredSeed) then
        score += 1000000000
    end

    return score
end

local function findBestSeedTool()
    local seeds = getSeedTools()

    table.sort(seeds, function(a, b)
        return seedToolScore(a) > seedToolScore(b)
    end)

    if Settings.OnlyMutatedSeeds then
        for _, entry in ipairs(seeds) do
            if entry.Mutation then
                return entry
            end
        end
        return nil
    end

    return seeds[1]
end

local function equipSeed()
    if not Settings.AutoEquipSeed then
        return true
    end

    local character, humanoid = getCharacter()
    if not humanoid then return false end

    local entry = findBestSeedTool()
    if not entry then return false end

    if entry.Equipped then
        return true
    end

    pcall(function()
        humanoid:EquipTool(entry.Tool)
    end)

    task.wait(0.10)
    return entry.Tool.Parent == character
end

--========================================================
-- SEED-BUY INTELLIGENCE
--========================================================

local function canAffordSeed(seedName)
    local data = SEEDS[seedName]
    if not data then return true end

    local cash = getCash()
    if cash == nil then return true end

    return cash - Settings.KeepCashReserve >= data.Cost
end

local function seedPromptAllowed(prompt)
    local text = buildInstanceText(prompt)
    local seedName = detectSeedName(text)
    local mutation = detectMutation(prompt)

    if Settings.OnlyMutatedSeeds and not mutation then
        return false
    end

    if Settings.SeedBuyMode == "Specific Seed" then
        if not seedName or lower(seedName) ~= lower(Settings.PreferredSeed) then
            return false
        end
    elseif Settings.SeedBuyMode == "Minimum Rarity" then
        if seedName and SEEDS[seedName] then
            local rank = RARITY_RANK[SEEDS[seedName].Rarity] or 0
            local min = RARITY_RANK[Settings.MinimumRarity] or 1
            if rank < min then return false end
        end
    end

    if seedName and not canAffordSeed(seedName) then
        return false
    end

    return true
end

local function seedPromptScore(prompt)
    local text = buildInstanceText(prompt)
    local seedName = detectSeedName(text)
    local mutation = detectMutation(prompt)

    local score = 0

    if seedName and SEEDS[seedName] then
        score += (RARITY_RANK[SEEDS[seedName].Rarity] or 0) * 1000000
        score += math.min(SEEDS[seedName].Cost, 999999)
    end

    if mutation then
        score += 100000000
    end

    if seedName and lower(seedName) == lower(Settings.PreferredSeed) then
        score += 1000000000
    end

    return score
end

--========================================================
-- WEATHER GATING
--========================================================

local function weatherAllowsPlanting()
    if not Settings.PlantDuringWeatherOnly then
        return true
    end

    local weather = scanCurrentWeather()
    return Settings.AllowedWeathers[weather] == true
end

--========================================================
-- PROMPT SELECTION
--========================================================

local function findBestPrompt(category)
    local _, _, root = getCharacter()
    if not root then return nil end

    local candidates = {}

    for prompt in pairs(Runtime.PromptCache) do
        if prompt and prompt.Parent and prompt.Enabled and promptReady(prompt) then
            local promptCategory = classifyPrompt(prompt)

