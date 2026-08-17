-- NIGHTSHADE // Greedy Growers
-- WindUI Edition bootstrap
-- Loads the existing core, replaces the entire desktop-first Linoria UI block with WindUI, then runs it.

local BASE = "https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/src/part-%02d.lua"
local source = table.create(10)

for i = 1, 10 do
    local url = string.format(BASE, i)
    local ok, body = pcall(game.HttpGet, game, url)
    if not ok or type(body) ~= "string" or #body == 0 then
        error(("[NIGHTSHADE] Failed to download core part %02d: %s"):format(i, tostring(body)))
    end
    source[i] = body
end

local combined = table.concat(source, "\n")

local UI_START = "--========================================================\n-- LINORIA UI\n--========================================================"
local UI_END = "--========================================================\n-- DASHBOARD\n--========================================================"

local startAt = string.find(combined, UI_START, 1, true)
local endAt = string.find(combined, UI_END, 1, true)

if not startAt or not endAt or endAt <= startAt then
    error("[NIGHTSHADE] Could not locate the old UI block for WindUI replacement")
end

local WINDUI_ADAPTER = [==[
--========================================================
-- WINDUI UI
--========================================================

local UIS = game:GetService("UserInputService")
local isTouch = UIS.TouchEnabled

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

ENV.NIGHTSHADE_WINDUI = WindUI

local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
local width = isTouch and math.clamp(viewport.X - 28, 390, 560) or 680
local height = isTouch and math.clamp(viewport.Y - 70, 300, 440) or 520

local WindWindow = WindUI:CreateWindow({
    Title = "NIGHTSHADE // Greedy Growers",
    Icon = "sprout",
    Author = "NIGHTSHADE",
    Folder = "NightshadeGG",
    Size = UDim2.fromOffset(width, height),
    Transparent = false,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = isTouch and 132 or 180,
    HideSearchBar = isTouch,
    ScrollBarEnabled = true,
    NewElements = true,
    User = {
        Enabled = false,
        Anonymous = true,
    },
})

pcall(function()
    WindWindow:Tag({
        Title = isTouch and "MOBILE" or "DESKTOP",
        Color = isTouch and Color3.fromHex("#30A7FF") or Color3.fromHex("#6C7DFF"),
    })
end)

pcall(function()
    WindWindow:Tag({
        Title = "GG",
        Color = Color3.fromHex("#37D67A"),
    })
end)

pcall(function()
    WindWindow:CreateTopbarButton("nightshade-theme", "moon", function()
        WindUI:SetTheme(WindUI:GetCurrentTheme() == "Dark" and "Light" or "Dark")
    end, 950)
end)

local ControlRegistry = {}
local Adapter = {}
Adapter.__index = Adapter

local function currentOptionValue(value)
    if typeof(value) == "table" then
        return value[1]
    end
    return value
end

local function registerControl(flag, control)
    if flag and control then
        ControlRegistry[flag] = control
    end
    return control
end

function Adapter:Notify(info)
    if typeof(info) == "table" then
        WindUI:Notify({
            Title = tostring(info.Title or "NIGHTSHADE"),
            Content = tostring(info.Content or ""),
            Duration = tonumber(info.Duration) or 4,
            Icon = info.Icon or "moon",
        })
    else
        WindUI:Notify({
            Title = "NIGHTSHADE",
            Content = tostring(info),
            Duration = 4,
            Icon = "moon",
        })
    end
end

function Adapter:LoadConfiguration()
    pcall(function()
        local manager = WindWindow.ConfigManager
        if not manager then return end

        manager:Init(WindWindow)
        local config = manager:CreateConfig("default")

        for flag, control in pairs(ControlRegistry) do
            pcall(function()
                config:Register(flag, control)
            end)
        end

        config:Load()
    end)
end

function Adapter:Destroy()
    pcall(function()
        WindWindow:Destroy()
    end)
end

local IconMap = {
    Dashboard = "layout-dashboard",
    Farm = "sprout",
    Seeds = "package",
    Weather = "cloud-lightning",
    Pets = "paw-print",
    Market = "store",
    Utility = "settings",
    Diagnostics = "scan-search",
    ["Protection Lab"] = "shield-check",
    ["UI Settings"] = "palette",
}

local Window = {}

function Window:CreateTab(name)
    local rawTab = WindWindow:Tab({
        Title = name,
        Icon = IconMap[name] or "circle",
        Locked = false,
    })

    local wrapper = {
        Raw = rawTab,
        Name = name,
        Group = nil,
        GroupIndex = 0,
    }

    local function makeGroup(self, title)
        self.GroupIndex += 1
        self.Group = self.Raw:Section({
            Title = tostring(title or self.Name),
            Opened = true,
            Box = true,
        })
        return self.Group
    end

    local function ensureGroup(self)
        if not self.Group then
            return makeGroup(self, self.Name)
        end
        return self.Group
    end

    function wrapper:CreateSection(title)
        return makeGroup(self, title)
    end

    function wrapper:CreateButton(info)
        local group = ensureGroup(self)
        return group:Button({
            Title = tostring(info.Name or "Button"),
            Icon = info.Icon,
            Callback = info.Callback or function() end,
        })
    end

    function wrapper:CreateToggle(info)
        local group = ensureGroup(self)
        local control = group:Toggle({
            Title = tostring(info.Name or info.Flag or "Toggle"),
            Desc = info.Description,
            Flag = info.Flag,
            Value = info.CurrentValue == true,
            Callback = info.Callback or function() end,
        })
        return registerControl(info.Flag, control)
    end

    function wrapper:CreateSlider(info)
        local group = ensureGroup(self)
        local range = info.Range or {0, 100}
        local control = group:Slider({
            Title = tostring(info.Name or info.Flag or "Slider"),
            Desc = info.Description,
            Flag = info.Flag,
            Step = tonumber(info.Increment) or 1,
            Value = {
                Min = tonumber(range[1]) or 0,
                Max = tonumber(range[2]) or 100,
                Default = tonumber(info.CurrentValue) or tonumber(range[1]) or 0,
            },
            Callback = info.Callback or function() end,
        })
        return registerControl(info.Flag, control)
    end

    function wrapper:CreateDropdown(info)
        local group = ensureGroup(self)
        local defaultValue = currentOptionValue(info.CurrentOption)
        local control = group:Dropdown({
            Title = tostring(info.Name or info.Flag or "Dropdown"),
            Values = info.Options or {},
            Flag = info.Flag,
            Value = defaultValue,
            Multi = info.MultipleOptions == true,
            SearchBarEnabled = #(info.Options or {}) > 8,
            AllowNone = false,
            Callback = function(value)
                if not info.Callback then return end
                if info.MultipleOptions then
                    info.Callback(value)
                else
                    local selected = value
                    if typeof(value) == "table" and value.Title then
                        selected = value.Title
                    end
                    info.Callback({selected})
                end
            end,
        })
        return registerControl(info.Flag, control)
    end

    function wrapper:CreateInput(info)
        local group = ensureGroup(self)
        local control = group:Input({
            Title = tostring(info.Name or info.Flag or "Input"),
            Value = tostring(info.CurrentValue or ""),
            Placeholder = tostring(info.PlaceholderText or ""),
            Type = "Input",
            Callback = info.Callback or function() end,
        })
        return registerControl(info.Flag, control)
    end

    function wrapper:CreateParagraph(info)
        local group = ensureGroup(self)
        local title = tostring(info.Title or "")
        local content = tostring(info.Content or "")

        local raw = group:Paragraph({
            Title = title,
            Desc = content,
            Color = "White",
        })

        local paragraph = {}

        function paragraph:Set(newInfo)
            title = tostring(newInfo.Title or title)
            content = tostring(newInfo.Content or content)

            pcall(function() raw:SetTitle(title) end)
            pcall(function() raw:SetDesc(content) end)
            pcall(function()
                raw:Set({Title = title, Desc = content})
            end)
        end

        return paragraph
    end

    return wrapper
end

-- Keep the old variable name so the rest of NIGHTSHADE stays UI-agnostic.
local Rayfield = setmetatable({}, Adapter)

-- Compatibility shim for the helper/cleanup code that was originally written
-- around the Linoria library object.
ENV.NIGHTSHADE_LINORIA = {
    Notify = function(_, text, duration)
        WindUI:Notify({
            Title = "NIGHTSHADE",
            Content = tostring(text),
            Duration = tonumber(duration) or 4,
            Icon = "moon",
        })
    end,
    Unload = function()
        pcall(function() WindWindow:Destroy() end)
    end,
}

local Dashboard = Window:CreateTab("Dashboard")
local Farm = Window:CreateTab("Farm")
local SeedsTab = Window:CreateTab("Seeds")
local WeatherTab = Window:CreateTab("Weather")
local PetsTab = Window:CreateTab("Pets")
local MarketTab = Window:CreateTab("Market")
local Utility = Window:CreateTab("Utility")
local Diagnostics = Window:CreateTab("Diagnostics")
local Protection = Window:CreateTab("Protection Lab")
local UISettingsTab = Window:CreateTab("UI Settings")

UISettingsTab:CreateSection("Interface")

local themes = {}
pcall(function()
    for name in pairs(WindUI:GetThemes()) do
        table.insert(themes, name)
    end
end)
table.sort(themes)

if #themes == 0 then
    themes = {"Dark", "Light"}
end

UISettingsTab:CreateDropdown({
    Name = "Theme",
    Options = themes,
    CurrentOption = {"Dark"},
    MultipleOptions = false,
    Flag = "NightshadeTheme",
    Callback = function(values)
        local theme = values and values[1]
        if theme then
            pcall(function() WindUI:SetTheme(theme) end)
        end
    end,
})

UISettingsTab:CreateButton({
    Name = "Fit Window To Screen",
    Callback = function()
        local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or viewport
        local w = isTouch and math.clamp(vp.X - 28, 390, 560) or 680
        local h = isTouch and math.clamp(vp.Y - 70, 300, 440) or 520
        pcall(function() WindWindow:SetSize(UDim2.fromOffset(w, h)) end)
    end,
})

UISettingsTab:CreateButton({
    Name = "Unload NIGHTSHADE",
    Callback = function()
        if Runtime and Runtime.Stop then
            Runtime.Stop()
        else
            pcall(function() WindWindow:Destroy() end)
        end
    end,
})

UISettingsTab:CreateParagraph({
    Title = "Cross-device UI",
    Content = isTouch
        and "Mobile mode active. WindUI handles touch dragging, resizing, scrolling, sliders and dropdowns natively."
        or "Desktop mode active. The same loader automatically adapts to touch devices.",
})

]==]

combined = string.sub(combined, 1, startAt - 1)
    .. WINDUI_ADAPTER
    .. "\n\n"
    .. string.sub(combined, endAt)

local fn, compileError = loadstring(combined)
if not fn then
    error("[NIGHTSHADE] WindUI compile failed: " .. tostring(compileError))
end

return fn()
