        Runtime.Stats.SeedsSkipped = Runtime.Stats.SeedsSkipped + 1
        Runtime.LastError = reason
        return false
    end

    -- TOCTOU guard: re-read cash/price immediately before interaction.
    if Settings.RequireFreshAffordability then
        task.wait()
        local ok2, reason2, name2, rarity2, price2, source2 = affordability(entity)
        if not ok2 then
            Runtime.Stats.SeedsSkipped = Runtime.Stats.SeedsSkipped + 1
            Runtime.LastError = "fresh-check: " .. reason2
            return false
        end
        name, rarity, price, source = name2, rarity2, price2, source2
    end

    local interaction = seedInteraction(entity)
    if not interaction then
        Runtime.LastError = "eligible seed had no interaction"
        return false
    end

    if Settings.SeedDryRun then
        Runtime.LastAction = "DRY RUN: " .. (name or entity.Name)
        Runtime.LastError = "None"
        return true
    end

    if interact(interaction, "Buy Seed // " .. (name or entity.Name), Settings.SeedCooldown) then
        Runtime.Stats.SeedsBought = Runtime.Stats.SeedsBought + 1
        if Settings.RareSeedNotify and rarity and (RARITY_RANK[rarity] or 0) >= 4 then
            notify("Seed Sniped", (name or "Seed") .. " • " .. rarity .. " • $" .. abbreviate(price) .. " • " .. source, 4)
        end
        return true
    end

    return false
end

--========================================================
-- SEED INVENTORY / EQUIP
--========================================================

local function seedTools()
    local out = {}
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and (contains(t.Name, "seed") or seedNameFrom(t)) then
                table.insert(out, t)
            end
        end
    end
    scan(Player.Character)
    scan(Player:FindFirstChildOfClass("Backpack"))
    return out
end

local function bestSeedTool()
    local best, bestScore
    for _, tool in ipairs(seedTools()) do
        local name = seedNameFrom(tool)
        local rarity = seedRarity(tool, name)
        local score = (RARITY_RANK[rarity] or 0) * 1e12 + (name and SEEDS[name] and math.min(SEEDS[name].Cost, 9e11) or 0)
        if name == Settings.PreferredSeed then score = score + 1e13 end
        if isMutated(tool) then score = score + 1e11 end
        if not bestScore or score > bestScore then
            best, bestScore = tool, score
        end
    end
    return best
end

local function equipBestSeed()
    if not Settings.AutoEquipSeed then return true end
    local c, h = character()
    if not h then return false end
    local tool = bestSeedTool()
    if not tool then return false end
    if tool.Parent == c then return true end
    pcall(h.EquipTool, h, tool)
    task.wait(0.05)
    return tool.Parent == c
end

--========================================================
-- TREES / FARM
--========================================================

local function treeRootFromInteraction(interaction)
    if not interaction then return nil end
    local node = interaction
    local fallback = firstAncestorModel(interaction)
    local best, bestScore = nil, -math.huge

    for _ = 1, 12 do
        if not node or node == Workspace then break end
        if node:IsA("Model") then
            local score = 0
            local text = buildText(node, 2)
            if containsAny(text, {"dead tree", "withered tree", "treebase", "tree"}) then score += 30 end
            if containsAny(text, {"fruit", "seed conveyor", "egg"}) then score -= 25 end
            local dead = readAny(node, {"IsDead", "Dead", "Destroyed", "Withered"})
            if dead == true or lower(dead) == "true" or containsAny(dead, {"dead", "withered", "destroyed"}) then score += 70 end
            if score > bestScore then best, bestScore = node, score end
        end
        node = node.Parent
    end

    return best or fallback
end

local function treeCandidates()
    local out, seen = {}, {}

    -- Interaction-driven index: cheap, live, and resilient to trees being replaced.
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) then
            local text = buildText(interaction, 9)
            if containsAny(text, {
                "treebaseprompt", "harvest", "dead tree", "withered tree",
                "clear dead", "remove dead", "chop dead", "tree"
            }) then
                local model = treeRootFromInteraction(interaction)
                if model and not seen[model] then
                    local own = ownState(model)
                    if not Settings.OwnPlotOnly or own ~= false then
                        seen[model] = true
                        table.insert(out, model)
                    end
                end
            end
        end
    end

    return out
end

local function treeMultiplier(tree)
    local v = readAny(tree, {"HarvestMultiplier", "Multiplier", "GrowthMultiplier"})
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v:match("[%d%.]+")) or 0 end

    for _, d in ipairs(tree:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible then
            local m = d.Text:match("[xX]%s*([%d%.]+)") or d.Text:match("([%d%.]+)%s*[xX]")
            if m then return tonumber(m) or 0 end
        end
    end
    return 0
end

local function deadValue(value)
    if value == true then return true end
    if type(value) == "number" then return value == 1 end
    if type(value) == "string" then
        local v = lower(value)
        return v == "true" or v == "1" or containsAny(v, {"dead", "withered", "destroyed"})
    end
    return false
end

local function treeDead(tree)
    if not tree or not isAlive(tree) then return false end
    local v = readAny(tree, {"IsDead", "Dead", "Destroyed", "Withered", "State", "TreeState"})
    if deadValue(v) then return true end

    local text = buildText(tree, 4)
    if containsAny(text, {"dead tree", "withered tree", "isdead", "tree dead", "destroyed tree"}) then return true end

    -- Some builds only expose dead state through the replacement interaction.
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, tree) then
            local it = buildText(interaction, 8)
            if containsAny(it, {"clear dead", "remove dead", "chop dead", "dead tree", "withered tree"}) then
                return true
            end
        end
    end
    return false
end

local function actionIn(root, words)
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, root) and containsAny(buildText(interaction, 3), words) then
            return interaction
        end
    end
    return nil
end

local function harvestOne()
    local best, bestMult
    for _, tree in ipairs(treeCandidates()) do
        if not treeDead(tree) then
            local mult = treeMultiplier(tree)
            if mult >= Settings.HarvestAtMultiplier and (not bestMult or mult > bestMult) then
                best, bestMult = tree, mult
            end
        end
    end
    if not best then return false end
    local action = actionIn(best, {"harvest", "treebaseprompt", "chop"})
    if action and interact(action, "Harvest x" .. tostring(bestMult)) then
        Runtime.Stats.Harvests = Runtime.Stats.Harvests + 1
        return true
    end
    return false
end

local function deadActionScore(interaction, tree)
    if not interaction or not isAlive(interaction) or not underRoot(interaction, tree) then return -math.huge end
    local text = buildText(interaction, 9)
    local score = 0

    if containsAny(text, {"clear dead tree", "remove dead tree", "chop dead tree"}) then score += 180 end
    if containsAny(text, {"dead tree", "withered tree"}) then score += 120 end
    if containsAny(text, {"clear", "remove"}) then score += 70 end
    if contains(text, "chop") then score += 45 end
