-- NIGHTSHADE // Linoria cross-device compatibility layer
-- Loaded automatically by nightshade.lua after the main client.
-- Keeps desktop behavior unchanged and adds touch support on phones/tablets.

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

if not UserInputService.TouchEnabled then
    return
end

local ENV = (getgenv and getgenv()) or _G
local Library = ENV.NIGHTSHADE_LINORIA

if not Library then
    warn("[NIGHTSHADE MOBILE] Linoria library was not found.")
    return
end

local screenGui = Library.ScreenGui

if not screenGui then
    warn("[NIGHTSHADE MOBILE] Linoria ScreenGui was not found.")
    return
end

local State = ENV.NIGHTSHADE_MOBILE or {}
ENV.NIGHTSHADE_MOBILE = State

if State.Installed then
    return
end

State.Installed = true
State.AutoFit = true
State.Scale = 1
State.MinScale = 0.42
State.MaxScale = 1.10
State.Dragging = false

local function viewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(800, 450)
end

local function findMainHolder()
    local best
    local bestArea = 0

    for _, child in ipairs(screenGui:GetChildren()) do
        if child:IsA("Frame") then
            local size = child.AbsoluteSize
            local area = size.X * size.Y

            if size.X >= 250 and size.Y >= 180 and area > bestArea then
                best = child
                bestArea = area
            end
        end
    end

    return best
end

task.wait(0.25)

local holder = findMainHolder()

if not holder then
    for _ = 1, 20 do
        task.wait(0.1)
        holder = findMainHolder()
        if holder then break end
    end
end

if not holder then
    State.Installed = false
    warn("[NIGHTSHADE MOBILE] Could not locate the Linoria window.")
    return
end

State.Holder = holder

local originalWidth = math.max(holder.AbsoluteSize.X, holder.Size.X.Offset, 500)
local originalHeight = math.max(holder.AbsoluteSize.Y, holder.Size.Y.Offset, 400)

State.OriginalWidth = originalWidth
State.OriginalHeight = originalHeight

local uiScale = holder:FindFirstChild("NightshadeMobileScale")
if not uiScale then
    uiScale = Instance.new("UIScale")
    uiScale.Name = "NightshadeMobileScale"
    uiScale.Parent = holder
end

State.UIScale = uiScale

local function autoScaleValue()
    local size = viewport()
    local usableWidth = math.max(size.X - 20, 250)
    local usableHeight = math.max(size.Y - 76, 220)

    return math.clamp(
        math.min(
            usableWidth / originalWidth,
            usableHeight / originalHeight,
            1
        ),
        State.MinScale,
        1
    )
end

local function setScale(value, manual)
    value = math.clamp(tonumber(value) or State.Scale, State.MinScale, State.MaxScale)
    State.Scale = value
    uiScale.Scale = value

    if manual then
        State.AutoFit = false
    end
end

local function centerWindow()
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Position = UDim2.fromScale(0.5, 0.5)
end

local function fitWindow()
    State.AutoFit = true
    setScale(autoScaleValue(), false)
    centerWindow()
end

local function toggleWindow()
    if type(Library.Toggle) == "function" then
        local ok = pcall(function()
            Library:Toggle()
        end)
        if ok then return end
    end

    holder.Visible = not holder.Visible
end

fitWindow()

-- Touch dragging for Linoria's title bar.
holder.Active = true

local dragInput
local dragStart
local dragStartPosition

holder.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local localY = input.Position.Y - holder.AbsolutePosition.Y
    local titleBarHeight = math.max(36 * State.Scale, 24)

    if localY < 0 or localY > titleBarHeight then
        return
    end

    State.Dragging = true
    dragInput = input
    dragStart = input.Position
    dragStartPosition = holder.Position

    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            State.Dragging = false
            dragInput = nil
        end
    end)
end)

UserInputService.InputChanged:Connect(function(input)
    if not State.Dragging or input ~= dragInput then
        return
    end

    if not dragStart or not dragStartPosition then
        return
    end

    local delta = input.Position - dragStart

    holder.Position = UDim2.new(
        dragStartPosition.X.Scale,
        dragStartPosition.X.Offset + delta.X,
        dragStartPosition.Y.Scale,
        dragStartPosition.Y.Offset + delta.Y
    )
end)

-- Floating phone/tablet controls: resize, toggle, reset/fit.
local oldDock = screenGui:FindFirstChild("NightshadeMobileDock")
if oldDock then
    oldDock:Destroy()
end

local dock = Instance.new("Frame")
dock.Name = "NightshadeMobileDock"
dock.AnchorPoint = Vector2.new(1, 1)
dock.Position = UDim2.new(1, -10, 1, -14)
dock.Size = UDim2.fromOffset(184, 48)
dock.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
dock.BackgroundTransparency = 0.06
dock.BorderSizePixel = 0
dock.ZIndex = 500
dock.Parent = screenGui

local dockCorner = Instance.new("UICorner")
dockCorner.CornerRadius = UDim.new(0, 10)
dockCorner.Parent = dock

local dockStroke = Instance.new("UIStroke")
dockStroke.Color = Color3.fromRGB(65, 68, 76)
dockStroke.Thickness = 1
dockStroke.Parent = dock

local dockLayout = Instance.new("UIListLayout")
dockLayout.FillDirection = Enum.FillDirection.Horizontal
dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dockLayout.Padding = UDim.new(0, 5)
dockLayout.Parent = dock

local function addButton(label, width, callback, accent)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(width, 38)
    button.BackgroundColor3 = accent and Color3.fromRGB(45, 95, 150) or Color3.fromRGB(25, 25, 30)
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Text = label
    button.TextColor3 = Color3.fromRGB(242, 242, 246)
    button.TextSize = label == "N" and 16 or 19
    button.Font = Enum.Font.GothamMedium
    button.ZIndex = 501
    button.Parent = dock

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = button

    button.Activated:Connect(callback)
    return button
end

addButton("−", 38, function()
    setScale(State.Scale - 0.07, true)
end)

addButton("N", 48, function()
    toggleWindow()
end, true)

addButton("+", 38, function()
    setScale(State.Scale + 0.07, true)
end)

addButton("↺", 38, function()
    fitWindow()
end)

-- Re-fit after orientation or viewport changes if auto-fit is still enabled.
task.spawn(function()
    local lastViewport = viewport()

    while holder.Parent and screenGui.Parent do
        local current = viewport()

        if current ~= lastViewport then
            lastViewport = current
            if State.AutoFit then
                fitWindow()
            end
        end

        task.wait(0.35)
    end
end)

pcall(function()
    Library:Notify(
        "NIGHTSHADE Mobile\nDrag the title bar to move. Use − / + to resize, N to hide/show, ↺ to auto-fit.",
        7
    )
end)

print("[NIGHTSHADE MOBILE] Touch compatibility enabled at", math.floor(State.Scale * 100) .. "%")
