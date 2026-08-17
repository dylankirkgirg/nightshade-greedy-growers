            if promptCategory == category then
                local position = getWorldPosition(prompt)

                if position then
                    local distance = (root.Position - position).Magnitude

                    if distance <= Settings.MaxActionDistance then
                        local owner = ownershipState(prompt)

                        if (not Settings.StrictOwnPlotOnly) or owner == true then
                            local allowed = true

                            if category == "BuySeed" then
                                allowed = seedPromptAllowed(prompt)
                            elseif category == "Plant" then
                                allowed = weatherAllowsPlanting()
                            elseif category == "BuyEgg" then
                                local tier = detectEggTier(buildInstanceText(prompt))
                                if tier and lower(tier) ~= lower(Settings.PreferredEgg) then
                                    allowed = false
                                end
                            end

                            if allowed then
                                table.insert(candidates, {
                                    Prompt = prompt,
                                    Distance = distance,
                                    Score = category == "BuySeed" and seedPromptScore(prompt) or 0,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    table.sort(candidates, function(a, b)
        if category == "BuySeed" and Settings.SeedBuyMode == "Highest Affordable" then
            if a.Score ~= b.Score then
                return a.Score > b.Score
            end
        end
        return a.Distance < b.Distance
    end)

    return candidates[1].Prompt, candidates[1].Distance
end

--========================================================
-- PATHFINDING
--========================================================

local function stopMovement()
    Runtime.MovementToken += 1

    local _, humanoid, root = getCharacter()
    if humanoid and root then
        pcall(function()
            humanoid:MoveTo(root.Position)
        end)
    end
end

local function walkDirect(humanoid, destination, token, timeout)
    local done = false
    local reached = false

    local connection = humanoid.MoveToFinished:Connect(function(ok)
        reached = ok
        done = true
    end)

    humanoid:MoveTo(destination)
    local started = now()

    while Runtime.Running and Runtime.MovementToken == token and not done and now() - started < timeout do
        task.wait(0.05)
    end

    connection:Disconnect()
    return reached
end

local function walkTo(destination, stopDistance)
    local _, humanoid, root = getCharacter()
    if not humanoid or not root then return false end

    stopDistance = stopDistance or 4

    if (root.Position - destination).Magnitude <= stopDistance then
        return true
    end

    local token = Runtime.MovementToken

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
    })

    local computed = pcall(function()
        path:ComputeAsync(root.Position, destination)
    end)

    if computed and path.Status == Enum.PathStatus.Success then
        for _, waypoint in ipairs(path:GetWaypoints()) do
            if not Runtime.Running or Runtime.MovementToken ~= token then
                return false
            end

            local _, currentHumanoid, currentRoot = getCharacter()
            if not currentHumanoid or not currentRoot then return false end

            if (currentRoot.Position - destination).Magnitude <= stopDistance then
                return true
            end

            if waypoint.Action == Enum.PathWaypointAction.Jump then
                currentHumanoid.Jump = true
            end

            local ok = walkDirect(currentHumanoid, waypoint.Position, token, 3.5)

            if not ok then
                currentHumanoid.Jump = true
                task.wait(0.08)
                break
            end
        end
    end

    local _, finalHumanoid, finalRoot = getCharacter()
    if not finalHumanoid or not finalRoot then return false end

    if (finalRoot.Position - destination).Magnitude > stopDistance then
        walkDirect(finalHumanoid, destination, token, 6)
    end

    local _, _, endRoot = getCharacter()
    return endRoot and (endRoot.Position - destination).Magnitude <= stopDistance + 2
end

--========================================================
-- PURE LOCAL SIMULATION
--========================================================

local function logSimulatedAction(category, target)
    local entry = {
        Time = os.date("%H:%M:%S"),
        Category = category,
        Target = target and target:GetFullName() or "Unknown",
    }

    table.insert(Runtime.SimulatedActions, entry)
    if #Runtime.SimulatedActions > 100 then
        table.remove(Runtime.SimulatedActions, 1)
    end

    Runtime.ActionCount += 1
    Runtime.LastAction = "[LOCAL SIM] " .. category

    dprint("Pure Local simulation:", category, entry.Target)
    return true
end

--========================================================
-- NORMAL MECHANICS PROMPT ACTIVATION
--========================================================

local function activatePrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false
    end

    local category = classifyPrompt(prompt)

    if Settings.ExecutionMode == "Pure Local" then
        return logSimulatedAction(category, prompt)
    end

    if category == "Plant" then
        if not weatherAllowsPlanting() then
            return false
        end

        if Settings.AutoEquipSeed and not equipSeed() then
            Runtime.LastError = "No usable seed tool found"
            return false
        end
    end

    local position = getWorldPosition(prompt)
    if not position then return false end

    local _, _, root = getCharacter()
    if not root then return false end

    local maxDistance = math.max(prompt.MaxActivationDistance, 4)
    local stopDistance = math.clamp(maxDistance * Settings.StopDistanceScale, 2, 7)

    local direction = root.Position - position
    direction = Vector3.new(direction.X, 0, direction.Z)

    if direction.Magnitude < 0.1 then
        direction = Vector3.new(0, 0, 1)
    else
        direction = direction.Unit
    end

    local destination = position + direction * math.min(stopDistance, 5)

    if not walkTo(destination, stopDistance) then
        Runtime.FailedActions += 1
        Runtime.LastError = "Pathing failed for " .. category
        return false
    end

    task.wait(0.06)

    if not prompt.Parent or not prompt.Enabled then
        return false
    end

    Runtime.PromptCooldowns[prompt] = now()

    local ok, err = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration, 0.05) + 0.06)
        prompt:InputHoldEnd()
    end)

    if not ok then
        Runtime.FailedActions += 1
        Runtime.LastError = tostring(err)
        return false
    end

    Runtime.ActionCount += 1
    Runtime.LastAction = category
    Runtime.LastError = "None"

    dprint("Activated", category, prompt:GetFullName())
    task.wait(Settings.ActionDelay)

    return true
end

--========================================================
-- PHYSICAL FRUIT / PICKUP COLLECTION
--========================================================

local PICKUP_TAGS = {
    "Fruit","Fruits","Pickup","Collectible","CropDrop","Produce","Drop"
}

local PICKUP_NAME_WORDS = {
    "fruit","apple","peach","fig","orange","lemon","avocado",
    "cherry","mango","coconut","banana","starfruit","dragon fruit"
}

local function findNearestPhysicalPickup()
    local _, _, root = getCharacter()
    if not root then return nil end

    local best, bestDist

    for _, tag in ipairs(PICKUP_TAGS) do
        for _, object in ipairs(CollectionService:GetTagged(tag)) do
            if object and object:IsDescendantOf(Workspace) then
                local position = getWorldPosition(object)
                if position then
                    local dist = (root.Position - position).Magnitude
                    if dist <= Settings.MaxActionDistance and (not bestDist or dist < bestDist) then
                        best, bestDist = object, dist
                    end
                end
            end
        end
    end

    if best then return best, bestDist end

    -- Conservative name fallback: only small-ish unanchored/collectible-looking objects.
