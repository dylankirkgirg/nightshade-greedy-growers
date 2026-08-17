local ThemeManager = loadstring(game:HttpGet(
    LINORIA_REPO .. "addons/ThemeManager.lua"
))()

local SaveManager = loadstring(game:HttpGet(
    LINORIA_REPO .. "addons/SaveManager.lua"
))()

ENV.NIGHTSHADE_LINORIA = Library

local Adapter = {}
Adapter.__index = Adapter

local LinoriaWindow = Library:CreateWindow({
    Title = "NIGHTSHADE // Greedy Growers",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.18,
})

local function uniqueId(prefix)
    Runtime._LinoriaId = (Runtime._LinoriaId or 0) + 1
    return tostring(prefix or "Control") .. "_" .. tostring(Runtime._LinoriaId)
end

local function currentOptionValue(value)
    if typeof(value) == "table" then
        return value[1]
    end
    return value
end

local function roundingFromIncrement(increment)
    increment = tonumber(increment) or 1
    if increment >= 1 then
        return 0
    end

    local decimals = 0
    local v = increment
    while v < 1 and decimals < 4 do
        v *= 10
        decimals += 1
    end

    return decimals
end

function Adapter:Notify(info)
    if typeof(info) == "table" then
        local title = tostring(info.Title or "NIGHTSHADE")
        local content = tostring(info.Content or "")
        local duration = tonumber(info.Duration) or 4

        Library:Notify(title .. "\n" .. content, duration)
    else
        Library:Notify(tostring(info), 4)
    end
end

function Adapter:LoadConfiguration()
    pcall(function()
        SaveManager:LoadAutoloadConfig()
    end)
end

function Adapter:Destroy()
    pcall(function()
        Library:Unload()
    end)
end

local Window = {}

function Window:CreateTab(name)
    local rawTab = LinoriaWindow:AddTab(name)

    local wrapper = {
        Raw = rawTab,
        Name = name,
        Side = "Left",
        Group = nil,
        GroupIndex = 0,
    }

    local function makeGroup(self, title)
        self.GroupIndex += 1

        local side = self.Side
        self.Side = (self.Side == "Left") and "Right" or "Left"

        if side == "Left" then
            self.Group = self.Raw:AddLeftGroupbox(title)
        else
            self.Group = self.Raw:AddRightGroupbox(title)
        end

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

        return group:AddButton({
            Text = tostring(info.Name or "Button"),
            Func = info.Callback or function() end,
            DoubleClick = false,
        })
    end

    function wrapper:CreateToggle(info)
        local group = ensureGroup(self)
        local id = info.Flag or uniqueId(info.Name)

        local control = group:AddToggle(id, {
            Text = tostring(info.Name or id),
            Default = info.CurrentValue == true,
        })

        if info.Callback then
            control:OnChanged(function()
                info.Callback(control.Value)
            end)
        end

        return control
    end

    function wrapper:CreateSlider(info)
        local group = ensureGroup(self)
        local id = info.Flag or uniqueId(info.Name)

        local range = info.Range or {0, 100}
        local control = group:AddSlider(id, {
            Text = tostring(info.Name or id),
            Default = tonumber(info.CurrentValue) or tonumber(range[1]) or 0,
            Min = tonumber(range[1]) or 0,
            Max = tonumber(range[2]) or 100,
            Rounding = roundingFromIncrement(info.Increment),
            Suffix = info.Suffix or "",
            Compact = false,
        })

        if info.Callback then
            control:OnChanged(function()
                info.Callback(control.Value)
            end)
        end

        return control
    end

    function wrapper:CreateDropdown(info)
        local group = ensureGroup(self)
        local id = info.Flag or uniqueId(info.Name)

        local values = info.Options or {}
        local defaultValue = currentOptionValue(info.CurrentOption)

        local default = 1
        if defaultValue ~= nil then
            for i, value in ipairs(values) do
                if tostring(value) == tostring(defaultValue) then
                    default = i
                    break
                end
            end
        end

        local control = group:AddDropdown(id, {
            Values = values,
            Default = default,
            Multi = info.MultipleOptions == true,
            Text = tostring(info.Name or id),
        })

        if info.Callback then
            control:OnChanged(function()
                if info.MultipleOptions then
                    info.Callback(control.Value)
                else
                    info.Callback({control.Value})
                end
            end)
        end

        return control
    end

    function wrapper:CreateInput(info)
        local group = ensureGroup(self)
        local id = info.Flag or uniqueId(info.Name)

        local control = group:AddInput(id, {
            Default = tostring(info.CurrentValue or ""),
            Numeric = false,
            Finished = false,
            Text = tostring(info.Name or id),
            Placeholder = tostring(info.PlaceholderText or ""),
        })

        if info.Callback then
            control:OnChanged(function()
                info.Callback(control.Value)
            end)
        end

        return control
    end

    function wrapper:CreateParagraph(info)
        local group = ensureGroup(self)

        local title = tostring(info.Title or "")
        local content = tostring(info.Content or "")

        local titleLabel = group:AddLabel(title, true)
        local contentLabel = group:AddLabel(content, true)

        local paragraph = {}

        function paragraph:Set(newInfo)
            local newTitle = tostring(newInfo.Title or title)
            local newContent = tostring(newInfo.Content or content)

            title = newTitle
            content = newContent

            pcall(function()
                titleLabel:SetText(newTitle)
            end)

            pcall(function()
                contentLabel:SetText(newContent)
            end)
        end

        return paragraph
    end

    return wrapper
end

local Rayfield = setmetatable({}, Adapter)

local Dashboard = Window:CreateTab("Dashboard")
local Farm = Window:CreateTab("Farm")
local SeedsTab = Window:CreateTab("Seeds")
local WeatherTab = Window:CreateTab("Weather")
local PetsTab = Window:CreateTab("Pets")
local MarketTab = Window:CreateTab("Market")
local Utility = Window:CreateTab("Utility")
local Diagnostics = Window:CreateTab("Diagnostics")
local Protection = Window:CreateTab("Protection Lab")

local UISettingsTab = LinoriaWindow:AddTab("UI Settings")
local MenuGroup = UISettingsTab:AddLeftGroupbox("Menu")

MenuGroup:AddLabel("NIGHTSHADE // Linoria")
MenuGroup:AddButton({
    Text = "Unload NIGHTSHADE",
    Func = function()
        if Runtime and Runtime.Stop then
            Runtime.Stop()
        else
            Library:Unload()
        end
    end,
})

MenuGroup:AddLabel("Menu key"):AddKeyPicker("NightshadeMenuKey", {
    Default = "RightShift",
    NoUI = true,
    Text = "Toggle menu",
})

Library.ToggleKeybind = Options.NightshadeMenuKey

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"NightshadeMenuKey"})

ThemeManager:SetFolder("NightshadeGG")
SaveManager:SetFolder("NightshadeGG/GreedyGrowers")

ThemeManager:ApplyToTab(UISettingsTab)
SaveManager:BuildConfigSection(UISettingsTab)

pcall(function()
    Library.AccentColor = Color3.fromRGB(85, 170, 255)
    Library.AccentColorDark = Color3.fromRGB(55, 110, 165)
    Library.MainColor = Color3.fromRGB(18, 18, 20)
    Library.BackgroundColor = Color3.fromRGB(13, 13, 15)
    Library.OutlineColor = Color3.fromRGB(45, 45, 50)
end)

--========================================================
-- DASHBOARD
--========================================================

local StatusParagraph = Dashboard:CreateParagraph({
    Title = "NIGHTSHADE Status",
    Content = "Loading local snapshot...",
})

Dashboard:CreateButton({
