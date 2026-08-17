        sidebar = math.clamp(math.floor(width * 0.26), 96, 128)
    elseif tablet then
        width = math.clamp(vp.X - 42, 520, 760)
        height = math.clamp(vp.Y - 80, 400, 590)
        sidebar = 150
    else
        width = math.clamp(math.floor(vp.X * 0.58), 680, 860)
        height = math.clamp(math.floor(vp.Y * 0.68), 500, 650)
        sidebar = 180
    end

    return {
        Viewport = vp,
        Phone = phone,
        Tablet = tablet,
        Width = width,
        Height = height,
        Sidebar = sidebar,
    }
end

local Layout = deviceLayout()

local Window = WindUI:CreateWindow({
    Title = "NIGHTSHADE V4 // Greedy Growers",
    Author = "NIGHTSHADE",
    Folder = "NightshadeGGV4",
    Icon = "sprout",
    Size = UDim2.fromOffset(Layout.Width, Layout.Height),
    Theme = "Dark",
    Transparent = false,
    Resizable = true,
    SideBarWidth = Layout.Sidebar,
    HideSearchBar = Layout.Phone,
    ScrollBarEnabled = true,
    NewElements = true,
    User = {Enabled = false, Anonymous = true},
    OpenButton = {
        Title = "NIGHTSHADE",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
        Enabled = true,
        Draggable = true,
        OnlyMobile = touch,
        Scale = Layout.Phone and 0.52 or 0.62,
        Color = ColorSequence.new(
            Color3.fromHex("#1D78FF"),
            Color3.fromHex("#7B5CFF")
        ),
    },
    Topbar = {
        Height = Layout.Phone and 40 or 44,
        ButtonsType = "Mac",
    },
})

pcall(function()
    Window:Tag({
        Title = "V4",
        Icon = "sparkles",
        Color = Color3.fromHex("#735CFF"),
        Border = true,
    })
    Window:Tag({
        Title = Layout.Phone and "PHONE" or (Layout.Tablet and "TABLET" or "DESKTOP"),
        Icon = touch and "smartphone" or "monitor",
        Color = touch and Color3.fromHex("#2F9DFF") or Color3.fromHex("#37D67A"),
        Border = true,
    })
end)

local function notify(title, content, duration)
    pcall(function()
        WindUI:Notify({
            Title = tostring(title or "NIGHTSHADE"),
            Content = tostring(content or ""),
            Duration = tonumber(duration) or 4,
            Icon = "moon",
        })
    end)
end

local UIState = {
    AutoFit = true,
    Scale = Layout.Phone and 0.90 or 1,
    LastViewport = Layout.Viewport,
}

local function applyUIScale(value)
    value = math.clamp(tonumber(value) or UIState.Scale, 0.65, 1.15)
    UIState.Scale = value
    pcall(function() Window:SetUIScale(value) end)
end

local function fitWindowToDevice(resetScale)
    Layout = deviceLayout()
    if resetScale then
        UIState.Scale = Layout.Phone and 0.90 or 1
    end
    applyUIScale(UIState.Scale)
    pcall(function()
        Window:SetSize(UDim2.fromOffset(Layout.Width, Layout.Height))
    end)
end

applyUIScale(UIState.Scale)

-- Re-fit after phone/tablet rotation, split-screen changes, or desktop resize.
task.spawn(function()
    while Runtime.Running do
        task.wait(0.45)
        local vp = viewportSize()
        if vp ~= UIState.LastViewport then
            UIState.LastViewport = vp
            if UIState.AutoFit then
                fitWindowToDevice(false)
            end
        end
    end
end)

--========================================================
-- REPLICATED DATA READERS
--========================================================

local function readNumber(names)
    local wanted = {}
    for _, name in ipairs(names) do wanted[lower(name)] = true end

    local roots = {
        Player:FindFirstChild("leaderstats"),
        Player:FindFirstChild("Data"),
        Player:FindFirstChild("Stats"),
        Player:FindFirstChild("Currencies"),
        Player:FindFirstChild("Inventory"),
    }

    for _, root in ipairs(roots) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if wanted[lower(d.Name)] and (d:IsA("NumberValue") or d:IsA("IntValue")) then
                    return d.Value, safeFullName(d)
                end
            end
        end
    end

    for _, key in ipairs(names) do
        local value = safeAttr(Player, key)
        if type(value) == "number" then return value, "Player." .. key end
    end

    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                local context = d.Name .. " " .. (d.Parent and d.Parent.Name or "")
                if containsAny(context, names) then
                    local parsed = parseCompactNumber(d.Text)
                    if parsed then return parsed, safeFullName(d) .. " (text)" end
                end
            end
        end
    end

    return nil, nil
end

local function cash()
    return readNumber({"Cash", "Coins", "Money", "Currency", "CASH"})
end

local function tickets()
    return readNumber({"Tickets", "Ticket", "TICKETS"})
end

local function inventoryCount()
    return readNumber({"InventoryCount", "InventorySize", "FruitCount", "Storage", "STORAGE_SIZE", "Fruits"})
end

local function inventoryMax()
    return readNumber({"STORAGE_MAX_SIZE", "StorageMaxSize", "InventoryMax", "MaxInventory", "StorageLimit"})
end

local function character()
    local c = Player.Character
    if not c then return nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or not r or h.Health <= 0 then return nil end
    return c, h, r
end

--========================================================
-- INTERACTION INDEX
--========================================================

local function isInteraction(inst)
    return inst and (inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector"))
end

for _, d in ipairs(Workspace:GetDescendants()) do
    if isInteraction(d) then Runtime.InteractionSet[d] = true end
