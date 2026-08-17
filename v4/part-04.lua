end

connect(Workspace.DescendantAdded, function(d)
    if isInteraction(d) then Runtime.InteractionSet[d] = true end
end)

connect(Workspace.DescendantRemoving, function(d)
    Runtime.InteractionSet[d] = nil
    Runtime.LastInteract[d] = nil
end)

local function underRoot(inst, root)
    if not root then return true end
    if inst == root then return true end
    local ok, result = pcall(inst.IsDescendantOf, inst, root)
    return ok and result or false
end

local function findInteractions(words, root)
    local out = {}
    for inst in pairs(Runtime.InteractionSet) do
        if isAlive(inst) and underRoot(inst, root) then
            local text = buildText(inst, 5)
            if containsAny(text, words) then table.insert(out, inst) end
        end
    end
    return out
end

local function directPrompt(prompt)
    if not prompt or not isAlive(prompt) or not prompt.Enabled then return false, "invalid prompt" end

    if fireproximityprompt then
        local ok, err = pcall(fireproximityprompt, prompt)
        return ok, err
    end

    -- Safe fallback: only works if the player is already naturally in range.
    local _, _, root = character()
    local parent = prompt.Parent
    local pos
    if parent and parent:IsA("Attachment") then pos = parent.WorldPosition
    elseif parent and parent:IsA("BasePart") then pos = parent.Position
    elseif parent and parent:IsA("Model") then
        local ok, pivot = pcall(parent.GetPivot, parent)
        if ok then pos = pivot.Position end
    end

    if not root or not pos or (root.Position - pos).Magnitude > prompt.MaxActivationDistance + 1 then
        return false, "fireproximityprompt unavailable / out of range"
    end

    local ok, err = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration, 0.03) + 0.03)
        prompt:InputHoldEnd()
    end)
    return ok, err
end

local function directClick(click)
    if not click or not isAlive(click) then return false, "invalid click" end
    if not fireclickdetector then return false, "fireclickdetector unavailable" end
    local ok, err = pcall(fireclickdetector, click)
    return ok, err
end

local function interact(inst, label, customCooldown)
    if not isInteraction(inst) then return false end
    local cooldown = customCooldown or Settings.ActionCooldown
    local last = Runtime.LastInteract[inst] or 0
    if os.clock() - last < cooldown then return false end
    Runtime.LastInteract[inst] = os.clock()

    local ok, err
    if inst:IsA("ProximityPrompt") then ok, err = directPrompt(inst)
    else ok, err = directClick(inst) end

    if ok then
        Runtime.Stats.Actions = Runtime.Stats.Actions + 1
        Runtime.LastAction = label or "Interact"
        Runtime.LastError = "None"
        return true
    end

    Runtime.LastError = tostring(err)
    return false
end

--========================================================
-- OWNERSHIP / ROOT HELPERS
--========================================================

local function ownState(inst)
    local node = inst
    for _ = 1, 10 do
        if not node or node == Workspace then break end
        if lower(node.Name) == lower(Player.Name) then return true end

        for _, key in ipairs({"OwnerUserId", "OwnerId", "PlayerUserId", "UserId", "Owner"}) do
            local v = safeAttr(node, key)
            if v ~= nil then
                if tonumber(v) == Player.UserId or lower(v) == lower(Player.Name) then return true end
                return false
            end
            local child = node:FindFirstChild(key)
            if child and child:IsA("ValueBase") then
                local cv = child.Value
                if cv == Player or tonumber(tostring(cv)) == Player.UserId or lower(cv) == lower(Player.Name) then return true end
                return false
            end
        end
        node = node.Parent
    end
    return nil
end

local function findNamedRoot(names)
    for _, name in ipairs(names) do
        local root = Workspace:FindFirstChild(name, true)
        if root then return root end
    end
    return nil
end

local function conveyorRoot()
    return findNamedRoot({"ConveyorSeeds", "SeedConveyor", "Conveyor Seeds"})
end

local function fruitRoot()
    return findNamedRoot({"FruitSpawns", "Fruits", "Fruit Spawns"})
end

local function marketRoot()
    return findNamedRoot({"Farmers Market", "FarmersMarket", "MarketRows"})
end

--========================================================
-- WEATHER / MUTATIONS
--========================================================

local WEATHER_ALIASES = {
    ["misty"] = "Misty", ["mist"] = "Misty",
    ["acid rain"] = "Acid Rain", ["acid"] = "Acid Rain",
    ["rainbow"] = "Rainbow",
    ["meteor shower"] = "Meteor Shower", ["meteor"] = "Meteor Shower",
}

local function currentWeather()
    for _, root in ipairs({Workspace, ReplicatedStorage, game}) do
        for _, key in ipairs({"CurrentWeather", "Weather", "ActiveWeather", "WeatherType"}) do
            local v = safeAttr(root, key)
            if v ~= nil then
                for alias, name in pairs(WEATHER_ALIASES) do
                    if contains(v, alias) then return name end
                end
            end
        end
    end

    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible then
                for alias, name in pairs(WEATHER_ALIASES) do
                    if contains(d.Text, alias) then return name end
                end
            end
        end
    end

    return "Unknown"
end

local function weatherAllowed()
    if not Settings.PlantDuringWeatherOnly then return true end
    local w = currentWeather()
    if w == "Misty" then return Settings.WeatherMisty end
    if w == "Acid Rain" then return Settings.WeatherAcidRain end
    if w == "Rainbow" then return Settings.WeatherRainbow end
    if w == "Meteor Shower" then return Settings.WeatherMeteor end
    return Settings.WeatherUnknown
end

local function mutationList(inst)
    local found = {}
    local text = buildText(inst, 4)
    for name in pairs(MUTATIONS) do
        if contains(text, name) then found[name] = true end
    end

    local raw = readAny(inst, {"Mutation", "Mutations", "Modifiers", "Variant"})
    if raw ~= nil then
        for name in pairs(MUTATIONS) do
            if contains(raw, name) then found[name] = true end
        end
    end

    local out = {}
    for name in pairs(found) do table.insert(out, name) end
    table.sort(out)
    return out
end

local function isMutated(inst)
    if #mutationList(inst) > 0 then return true end
    local raw = readAny(inst, {"IsMutated", "Mutated"})
    return raw == true
end

--========================================================
-- STRICT DISPLAY PRICE READER
--========================================================

local function explicitDisplayedPrice(inst)
    if not inst then return nil, "unknown" end

    local raw = readAny(inst, {"Price", "price", "Cost", "cost", "SeedCost", "PurchasePrice"})
    if type(raw) == "number" then return raw, "replicated" end
    if type(raw) == "string" then
