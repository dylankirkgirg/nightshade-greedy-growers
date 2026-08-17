end})

Diagnostics:Button({Title="Print Greedy Growers Surfaces", Callback=function()
    local names = {"ConveyorSeeds", "FruitSpawns", "SellStand", "CompostBin", "Worm Shop", "Gear Shop", "Pet Shop", "Farmers Market", "SeedPlot"}
    print("========== NIGHTSHADE V4 // SURFACES ==========")
    for _, name in ipairs(names) do
        local obj = Workspace:FindFirstChild(name, true)
        print(name, obj and safeFullName(obj) or "NOT FOUND")
    end
    print("==================================================")
    notify("Diagnostics", "Printed surface scan to console.", 4)
end})

Diagnostics:Button({Title="Print River Candidates", Callback=function()
    print("========== NIGHTSHADE V4 // RIVER ==========")
    for i, entity in ipairs(seedCandidates()) do
        local ok, reason, name, rarity, price, source, money = affordability(entity)
        print(i, safeFullName(entity), "|", name, rarity, price, source, "cash", money, ok and "ELIGIBLE" or reason)
    end
    print("==============================================")
    notify("Diagnostics", tostring(Runtime.SeedCandidates) .. " river candidates printed.", 4)
end})

Diagnostics:Button({Title="Audit Dead Trees", Callback=function()
    local candidates = deadTreeCandidates()
    print("========== NIGHTSHADE V4 // DEAD TREE AUDIT ==========")
    print("Found:", #candidates, "| confirmed cleared total:", Runtime.Stats.DeadTrees, "| failures:", Runtime.DeadSweep.Failed)
    for i, tree in ipairs(candidates) do
        local action, score = deadActionIn(tree)
        print(i, safeFullName(tree), "| action:", action and safeFullName(action) or "NONE", "| score:", score or "n/a", "| owned:", ownState(tree))
    end
    print("========================================================")
    Runtime.DeadSweep.Found = #candidates
    Runtime.DeadSweep.Remaining = #candidates
    notify("Dead-tree audit", tostring(#candidates) .. " dead tree(s) currently detected.", 4)
end})

Diagnostics:Button({Title="Print All Prompts / Clicks", Callback=function()
    print("========== NIGHTSHADE V4 // INTERACTIONS ==========")
    local count = 0
    for interaction in pairs(Runtime.InteractionSet) do
        if isAlive(interaction) then
            count = count + 1
            if interaction:IsA("ProximityPrompt") then
                print(count, safeFullName(interaction), "|", interaction.ActionText, "|", interaction.ObjectText)
            else
                print(count, safeFullName(interaction), "| ClickDetector")
            end
        end
    end
    print("Total:", count)
    print("======================================================")
    notify("Diagnostics", tostring(count) .. " interactions printed.", 4)
end})

Diagnostics:Button({Title="Copy Snapshot", Callback=function()
    local s = snapshot()
    if setclipboard then
        pcall(setclipboard, s)
        notify("Snapshot", "Copied.", 3)
    else
        print(s)
        notify("Snapshot", "Clipboard unavailable; printed.", 4)
    end
end})

Diagnostics:Toggle({Title="Debug Logging", Value=Settings.Debug, Callback=function(v) Settings.Debug=v end})

-- Native Linoria menu/theme/config controls.
local UISettings = LinoriaWindow:AddTab("UI Settings")
local MenuGroup = UISettings:AddLeftGroupbox("Menu")
MenuGroup:AddButton({Text="Unload NIGHTSHADE", Func=function() Runtime.Stop() end})
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("NS4_MenuKey", {Default="RightShift", NoUI=true, Text="Menu keybind"})
Library.ToggleKeybind = Options.NS4_MenuKey
ThemeManager:ApplyToTab(UISettings)
SaveManager:BuildConfigSection(UISettings)
pcall(function() SaveManager:LoadAutoloadConfig() end)

--========================================================
-- CLEANUP
--========================================================

function Runtime.Stop()
    if not Runtime.Running then return end
    Runtime.Running = false
    Settings.Master = false
    pcall(saveConfig)
    for _, c in ipairs(Runtime.Connections) do pcall(c.Disconnect, c) end
    Runtime.Connections = {}
    pcall(function() Window:Destroy() end)
end


pcall(function()
    Library:OnUnload(function()
        if Runtime.Running then
            Runtime.Running = false
            Settings.Master = false
            pcall(saveConfig)
            for _, c in ipairs(Runtime.Connections) do pcall(c.Disconnect, c) end
            Runtime.Connections = {}
        end
    end)
end)

task.delay(0.8, refreshStatus)
task.spawn(function()
    while Runtime.Running do
        task.wait(2)
        refreshStatus()
    end
end)

if game.PlaceId ~= EXPECTED_PLACE_ID then
    notify("Place warning", "Expected Greedy Growers " .. EXPECTED_PLACE_ID .. ", current " .. tostring(game.PlaceId), 7)
end

notify("NIGHTSHADE V4 loaded", "Linoria • verified dead-tree sweeper • strict seed sniper ready", 5)
print("[NIGHTSHADE V4] Loaded")
print("[NIGHTSHADE V4] fireproximityprompt:", fireproximityprompt ~= nil)
print("[NIGHTSHADE V4] fireclickdetector:", fireclickdetector ~= nil)
