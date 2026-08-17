    if contains(text, "collect") then score += 18 end
    if containsAny(text, {"treebaseprompt", "tree"}) then score += 20 end

    -- Avoid the common partial-clear bug: fruit Collect prompts inside a dead tree
    -- are not the dead-tree removal action.
    if containsAny(text, {"collect fruit", "fruit", "produce", "crop"}) then score -= 160 end
    if containsAny(text, {"harvest", "seed", "egg", "market"}) and not containsAny(text, {"dead", "withered"}) then score -= 90 end

    if interaction:IsA("ProximityPrompt") and interaction.Enabled then score += 5 end
    return score
end

local function deadActionIn(tree)
    local best, bestScore
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) and underRoot(interaction, tree) then
            local score = deadActionScore(interaction, tree)
            if score > 0 and (not bestScore or score > bestScore) then
                best, bestScore = interaction, score
            end
        end
    end
    return best, bestScore
end

local function deadTreeCandidates()
    local out, seen = {}, {}

    for _, tree in ipairs(treeCandidates()) do
        if treeDead(tree) and not seen[tree] then
            seen[tree] = true
            table.insert(out, tree)
        end
    end

    -- Second pass starts from explicit dead-removal interactions. This catches
    -- trees whose model/name no longer looks like a normal live tree.
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) then
            local text = buildText(interaction, 10)
            if containsAny(text, {"clear dead", "remove dead", "chop dead", "dead tree", "withered tree"}) then
                local tree = treeRootFromInteraction(interaction)
                if tree and not seen[tree] then
                    local own = ownState(tree)
                    if (not Settings.OwnPlotOnly or own ~= false) and treeDead(tree) then
                        seen[tree] = true
                        table.insert(out, tree)
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return safeFullName(a) < safeFullName(b)
    end)
    return out
end

local function waitDeadTreeResolved(tree, action)
    local deadline = os.clock() + math.max(0.2, Settings.DeadConfirmTimeout)
    repeat
        if not isAlive(tree) then return true, "tree removed" end
        if not treeDead(tree) then return true, "dead state cleared" end
        if action and not isAlive(action) then
            -- A prompt disappearing is only confirmation when no replacement
            -- dead-tree action appears under the same tree model.
            local replacement = deadActionIn(tree)
            if not replacement then return true, "clear action removed" end
        end
        task.wait(0.05)
    until os.clock() >= deadline
    return false, "clear was not confirmed"
end

local function clearDeadTree(tree)
    if not tree or not isAlive(tree) or not treeDead(tree) then return false, "not dead" end

    local blockedUntil = Runtime.DeadTreeBackoff[tree]
    if blockedUntil and os.clock() < blockedUntil then return false, "backoff" end

    local own = ownState(tree)
    if Settings.OwnPlotOnly and own == false then return false, "not owned" end

    local action = deadActionIn(tree)
    if not action then
        Runtime.DeadTreeBackoff[tree] = os.clock() + Settings.DeadRetryBackoff
        Runtime.DeadSweep.Failed += 1
        return false, "no dead-tree action"
    end

    if not interact(action, "Clear Dead Tree", 0) then
        Runtime.DeadTreeBackoff[tree] = os.clock() + Settings.DeadRetryBackoff
        Runtime.DeadSweep.Failed += 1
        return false, Runtime.LastError
    end

    local confirmed, reason = waitDeadTreeResolved(tree, action)
    if confirmed then
        Runtime.DeadTreeBackoff[tree] = nil
        Runtime.Stats.Support += 1
        Runtime.Stats.DeadTrees += 1
        Runtime.DeadSweep.Cleared += 1
        Runtime.DeadSweep.Last = reason
        return true, reason
    end

    Runtime.DeadTreeBackoff[tree] = os.clock() + Settings.DeadRetryBackoff
    Runtime.DeadSweep.Failed += 1
    Runtime.DeadSweep.Last = reason
    Runtime.LastError = reason .. " @ " .. safeFullName(tree)
    return false, reason
end

local function clearDeadSweep(maxActionsOverride)
    Runtime.DeadSweep.Scans += 1
    local maxActions = math.max(1, tonumber(maxActionsOverride) or Settings.DeadSweepMaxActions)
    local totalCleared = 0

    for _ = 1, math.max(1, Settings.DeadSweepMaxPasses) do
        local candidates = deadTreeCandidates()
        Runtime.DeadSweep.Found = #candidates
        Runtime.DeadSweep.Remaining = #candidates
        if #candidates == 0 then break end

        local progressed = false
        for _, tree in ipairs(candidates) do
            if totalCleared >= maxActions then break end
            local ok = clearDeadTree(tree)
            if ok then
                totalCleared += 1
                progressed = true
                task.wait(Settings.DeadRescanDelay)
            end
        end

        if totalCleared >= maxActions or not progressed then break end
        task.wait(Settings.DeadRescanDelay)
    end

    local remaining = deadTreeCandidates()
    Runtime.DeadSweep.Remaining = #remaining
    if #remaining == 0 then
        Runtime.DeadSweep.Last = totalCleared > 0 and "plot clean" or "no dead trees"
    elseif totalCleared > 0 then
        Runtime.DeadSweep.Last = "partial sweep; retrying remaining later"
    end

    return totalCleared > 0, totalCleared, #remaining
end

local function clearDeadOne()
    local acted = clearDeadSweep(1)
    return acted
end

local function plantOne()
    if not weatherAllowed() then return false end
    if not equipBestSeed() then return false end

    for _, interaction in ipairs(findInteractions({"plant", "seedplot", "plant seed", "dirt"})) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then
            if interact(interaction, "Plant Seed") then
                Runtime.Stats.Plants = Runtime.Stats.Plants + 1
                return true
            end
        end
    end
    return false
end

local function plantGrownTreeOne()
    for _, interaction in ipairs(findInteractions({"plant grown tree", "grown tree", "replant tree"})) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then
            if interact(interaction, "Plant Grown Tree") then
                Runtime.Stats.Plants = Runtime.Stats.Plants + 1
                return true
            end
        end
    end
    return false
end

local function organiseOne()
    for _, interaction in ipairs(findInteractions({"organise", "organize", "arrange tree"})) do
        local own = ownState(interaction)
        if not Settings.OwnPlotOnly or own ~= false then
            if interact(interaction, "Organise Trees") then return true end
        end
    end
    return false
end

--========================================================
-- FRUIT / SELL
--========================================================

local function collectOneFruit()
    if Settings.UseCollectAll then
        for _, interaction in ipairs(findInteractions({"collect all"})) do
            local own = ownState(interaction)
            if not Settings.OwnPlotOnly or own ~= false then
                if interact(interaction, "Collect All Fruits") then
                    Runtime.Stats.Fruits = Runtime.Stats.Fruits + 1
                    return true
                end
            end
        end
    end

    local root = fruitRoot()
    if root then
        for interaction in pairs(Runtime.InteractionSet) do
            if isAlive(interaction) and underRoot(interaction, root) then
                local own = ownState(interaction)
                if not Settings.OwnPlotOnly or own ~= false then
                    if interact(interaction, "Collect Fruit") then
                        Runtime.Stats.Fruits = Runtime.Stats.Fruits + 1
