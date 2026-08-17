    for _, needle in ipairs(needles) do
        if string.find(t, lower(needle), 1, true) then
            return true
        end
    end
    return false
end

local function safeGetAttribute(instance, name)
    local ok, value = pcall(function()
        return instance:GetAttribute(name)
    end)
    if ok then return value end
    return nil
end

local function notify(title, content, duration)
    if ENV.NIGHTSHADE_LINORIA then
        pcall(function()
            ENV.NIGHTSHADE_LINORIA:Notify(
                tostring(title) .. "\n" .. tostring(content),
                duration or 4
            )
        end)
    end
end

local function dprint(...)
    if Settings.Debug then
        print("[NIGHTSHADE]", ...)
    end
end

local function formatNumber(n)
    n = tonumber(n)
    if not n then return "?" end
    local abs = math.abs(n)
    local units = {
        {1e15, "Qa"},
        {1e12, "T"},
        {1e9, "B"},
        {1e6, "M"},
        {1e3, "K"},
    }
    for _, entry in ipairs(units) do
        if abs >= entry[1] then
            return string.format("%.2f%s", n / entry[1], entry[2])
        end
    end
    return tostring(math.floor(n))
end

local function getCharacter()
    local character = Player.Character
    if not character then return nil end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or humanoid.Health <= 0 then
        return nil
    end

    return character, humanoid, root
end

local function getWorldPosition(instance)
    if not instance then return nil end

    if instance:IsA("ProximityPrompt") then
        return getWorldPosition(instance.Parent)
    elseif instance:IsA("Attachment") then
        return instance.WorldPosition
    elseif instance:IsA("BasePart") then
        return instance.Position
    elseif instance:IsA("Model") then
        return instance:GetPivot().Position
    end

    local part = instance:FindFirstAncestorWhichIsA("BasePart")
    if part then return part.Position end

    local model = instance:FindFirstAncestorWhichIsA("Model")
    if model then return model:GetPivot().Position end

    return nil
end

local function buildInstanceText(instance, maxDepth)
    maxDepth = maxDepth or 6
    local parts = {}

    if instance:IsA("ProximityPrompt") then
        table.insert(parts, instance.Name)
        table.insert(parts, instance.ActionText)
        table.insert(parts, instance.ObjectText)
    else
        table.insert(parts, instance.Name)
    end

    local object = instance.Parent
    local depth = 0

    while object and object ~= game and depth < maxDepth do
        table.insert(parts, object.Name)
        object = object.Parent
        depth += 1
    end

    return lower(table.concat(parts, " "))
end

local function tableFirst(t)
    if typeof(t) == "table" then
        return t[1]
    end
    return t
end

--========================================================
-- LOCAL PLAYER DATA READERS
-- Purely reads replicated/local values; never writes them.
--========================================================

local function readNamedNumber(names)
    local wanted = {}
    for _, name in ipairs(names) do
        wanted[lower(name)] = true
    end

    local containers = {
        Player:FindFirstChild("leaderstats"),
        Player:FindFirstChild("Data"),
        Player:FindFirstChild("Stats"),
        Player:FindFirstChild("Currencies"),
    }

    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetDescendants()) do
                if wanted[lower(child.Name)] and (
                    child:IsA("IntValue") or
                    child:IsA("NumberValue")
                ) then
                    return child.Value, child:GetFullName()
                end
            end
        end
    end

    for _, name in ipairs(names) do
        local value = safeGetAttribute(Player, name)
        if typeof(value) == "number" then
            return value, "Player attribute: " .. name
        end
    end

    return nil, nil
end

local function getCash()
    return readNamedNumber({"Cash","Money","Coins","Coin","Currency"})
end

local function getTickets()
    return readNamedNumber({"Tickets","Ticket"})
end

local function getInventoryUsage()
    local used = readNamedNumber({"InventorySize","InventoryCount","Storage","FruitCount"})
    local max = readNamedNumber({"StorageMaxSize","MaxInventory","InventoryMax","StorageLimit"})
    return used, max
end

--========================================================
-- GAME KNOWLEDGE DETECTION
--========================================================

local function detectSeedName(text)
    local best
    for seedName in pairs(SEEDS) do
        if contains(text, seedName) then
            if not best or #seedName > #best then
                best = seedName
            end
        end
    end
    return best
end

local function detectRarity(text)
    for rarity, _ in pairs(RARITY_RANK) do
        if contains(text, rarity) then
            return rarity
        end
    end
    return nil
end

local function detectMutation(instance)
    local text = buildInstanceText(instance)

    for mutation in pairs(MUTATIONS) do
        if contains(text, mutation) then
            return mutation
        end
    end

    local object = instance
    local depth = 0

    while object and object ~= game and depth < 6 do
        for _, key in ipairs({"Mutation","Mutations","Variant","Effect"}) do
            local value = safeGetAttribute(object, key)
            if value ~= nil then
                local s = tostring(value)
                for mutation in pairs(MUTATIONS) do
                    if contains(s, mutation) then
                        return mutation
                    end
                end
            end
        end
        object = object.Parent
        depth += 1
    end

    return nil
end

local function detectEggTier(text)
    for tier in pairs(EGG_COSTS) do
        if contains(text, tier) and containsAny(text, {"egg","pet"}) then
            return tier
        end
    end
    return nil
end

local function scanCurrentWeather()
    -- 1) Workspace / game attributes
    for _, holder in ipairs({Workspace, game}) do
        for _, key in ipairs({"CurrentWeather","Weather","ActiveWeather","WeatherType"}) do
            local value = safeGetAttribute(holder, key)
            if value then
                local v = lower(value)
                for alias, canonical in pairs(WEATHER_ALIASES) do
                    if contains(v, alias) then
                        return canonical, holder:GetFullName() .. " attribute"
                    end
                end
            end
        end
    end

    -- 2) Named instances
    for _, object in ipairs(Workspace:GetDescendants()) do
        local name = lower(object.Name)
        for alias, canonical in pairs(WEATHER_ALIASES) do
            if contains(name, alias) then
                return canonical, object:GetFullName()
            end
        end
    end

    -- 3) Visible UI text
    local playerGui = Player:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                local text = lower(object.Text)
                for alias, canonical in pairs(WEATHER_ALIASES) do
                    if contains(text, alias) then
                        return canonical, object:GetFullName()
                    end
                end
            end
        end
    end

    return "Unknown", "No matching replicated/local weather indicator"
end

--========================================================
-- OWNERSHIP DETECTION
--========================================================

local OWNER_KEYS = {
    "Owner","OwnerId","OwnerUserId","Player","PlayerId",
    "PlayerUserId","UserId","PlotOwner","PlotOwnerId"
}

local function matchesOwner(value)
    if typeof(value) == "Instance" then
        return value == Player
    elseif typeof(value) == "number" then
        return value == Player.UserId
    elseif typeof(value) == "string" then
        local v = lower(value)
        return v == lower(Player.Name)
            or v == lower(Player.DisplayName)
            or tonumber(value) == Player.UserId
    end
    return false
end

local function ownershipState(instance)
    local object = instance
    local foundMarker = false
    local depth = 0

    while object and object ~= Workspace and depth < 10 do
        if lower(object.Name) == lower(Player.Name) then
            return true
        end

        for _, key in ipairs(OWNER_KEYS) do
            local attr = safeGetAttribute(object, key)
            if attr ~= nil then
                foundMarker = true
                if matchesOwner(attr) then
                    return true
                end
            end
