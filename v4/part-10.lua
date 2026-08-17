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

-- Cross-device appearance controls.
local UISettings = Window:Tab({Title="UI Settings", Icon="palette"})
local themeNames = {}
pcall(function()
    local themes = WindUI:GetThemes()
    for name in pairs(themes or {}) do
        table.insert(themeNames, name)
    end
end)
table.sort(themeNames)
if #themeNames == 0 then themeNames = {"Dark", "Light"} end

UISettings:Dropdown({
    Title="Theme",
    Values=themeNames,
    Value="Dark",
    SearchBarEnabled=#themeNames > 8,
    Callback=function(value)
        local selected = value
        if type(value) == "table" then selected = value.Title or value.Value or value[1] end
        if selected then pcall(function() WindUI:SetTheme(selected) end) end
    end,
})

UISettings:Slider({
    Title="UI Scale",
    Desc="Adjust NIGHTSHADE without changing Roblox UI scale.",
    Step=0.05,
    Value={Min=0.65, Max=1.15, Default=UIState.Scale},
    Callback=function(value)
        UIState.AutoFit = false
        applyUIScale(value)
    end,
})

UISettings:Toggle({
    Title="Auto Fit On Rotation / Resize",
    Value=UIState.AutoFit,
    Callback=function(value)
        UIState.AutoFit = value
        if value then fitWindowToDevice(false) end
    end,
})

UISettings:Button({Title="Fit UI To This Screen", Icon="maximize", Callback=function()
    UIState.AutoFit = true
    fitWindowToDevice(true)
    notify("Interface", "Re-fitted NIGHTSHADE to this screen.", 3)
end})

UISettings:Button({Title="Save NIGHTSHADE Settings", Icon="save", Callback=function()
    local ok, err = saveConfig()
    notify("Settings", ok and "Saved." or tostring(err), 3)
end})

UISettings:Button({Title="Unload NIGHTSHADE", Icon="power", Callback=function()
    Runtime.Stop()
end})

UISettings:Paragraph({
    Title="Cross-device mode",
    Desc=touch
        and "Touch mode is active. The window auto-sizes for phone/tablet, the mobile NIGHTSHADE button reopens the UI, and WindUI handles native touch dragging/scrolling."
        or "Desktop mode is active. The same loader automatically switches layouts on touch devices.",
    Image=touch and "smartphone" or "monitor",
})

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


-- WindUI cleanup is handled through Runtime.Stop / Window:Destroy.

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

notify("NIGHTSHADE V4 loaded", (touch and "WindUI mobile • " or "WindUI desktop • ") .. "verified dead-tree sweeper • strict seed sniper ready", 5)
print("[NIGHTSHADE V4] Loaded • WindUI cross-device")
print("[NIGHTSHADE V4] fireproximityprompt:", fireproximityprompt ~= nil)
print("[NIGHTSHADE V4] fireclickdetector:", fireclickdetector ~= nil)
