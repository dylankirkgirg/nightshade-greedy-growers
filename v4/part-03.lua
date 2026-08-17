        end
    end
    return false
end

local Window = {}
Window.__index = Window

function Window:Tab(info)
    local title = tostring((type(info) == "table" and info.Title) or info or "Tab")
    local rawTab = LinoriaWindow:AddTab(title)
    local wrapper = {Raw = rawTab, Name = title, Count = 0, GroupIndex = 0, Group = nil}

    function wrapper:_nextGroup()
        self.GroupIndex += 1
        local suffix = self.GroupIndex == 1 and "" or (" " .. tostring(self.GroupIndex))
        if self.GroupIndex % 2 == 1 then
            self.Group = self.Raw:AddLeftGroupbox(self.Name .. suffix)
        else
            self.Group = self.Raw:AddRightGroupbox(self.Name .. suffix)
        end
        self.Count = 0
        return self.Group
    end

    function wrapper:_group()
        if not self.Group or self.Count >= 8 then self:_nextGroup() end
        self.Count += 1
        return self.Group
    end

    function wrapper:Toggle(spec)
        local group = self:_group()
        local id = nextUiId(spec.Title)
        return group:AddToggle(id, {
            Text = tostring(spec.Title or "Toggle"),
            Default = spec.Value == true,
            Tooltip = spec.Desc,
            Callback = spec.Callback or function() end,
        })
    end

    function wrapper:Slider(spec)
        local group = self:_group()
        local id = nextUiId(spec.Title)
        local value = spec.Value or {}
        local min = tonumber(value.Min) or 0
        local max = tonumber(value.Max) or 100
        local default = tonumber(value.Default) or min
        local step = tonumber(spec.Step) or 1
        return group:AddSlider(id, {
            Text = tostring(spec.Title or "Slider"),
            Default = default,
            Min = min,
            Max = max,
            Rounding = roundingFromStep(step),
            Compact = false,
            Callback = function(v)
                if step > 0 then v = math.floor((v / step) + 0.5) * step end
                if spec.Callback then spec.Callback(v) end
            end,
        })
    end

    function wrapper:Dropdown(spec)
        local group = self:_group()
        local id = nextUiId(spec.Title)
        return group:AddDropdown(id, {
            Values = spec.Values or {},
            Default = spec.Value or 1,
            Multi = false,
            Text = tostring(spec.Title or "Dropdown"),
            Tooltip = spec.Desc,
            Callback = spec.Callback or function() end,
        })
    end

    function wrapper:Input(spec)
        local group = self:_group()
        local id = nextUiId(spec.Title)
        return group:AddInput(id, {
            Default = tostring(spec.Value or ""),
            Numeric = false,
            Finished = false,
            Text = tostring(spec.Title or "Input"),
            Tooltip = spec.Desc,
            Placeholder = tostring(spec.Placeholder or ""),
            Callback = spec.Callback or function() end,
        })
    end

    function wrapper:Button(spec)
        local group = self:_group()
        return group:AddButton({
            Text = tostring(spec.Title or "Button"),
            Func = spec.Callback or function() end,
            DoubleClick = false,
            Tooltip = spec.Desc,
        })
    end

    function wrapper:Paragraph(spec)
        local group = self:_group()
        local title = tostring(spec.Title or "")
        local desc = tostring(spec.Desc or "")
        local titleLabel = group:AddLabel(title, true)
        local bodyLabel = group:AddLabel(desc, true)
        local paragraph = {}
        function paragraph:SetDesc(newDesc)
            desc = tostring(newDesc or "")
            setLinoriaLabel(bodyLabel, desc)
        end
        function paragraph:SetTitle(newTitle)
            title = tostring(newTitle or "")
            setLinoriaLabel(titleLabel, title)
        end
        return paragraph
    end

    return wrapper
end

function Window:Destroy()
    pcall(function() Library:Unload() end)
end

local function notify(title, content, duration)
    pcall(function()
        Library:Notify(tostring(title or "NIGHTSHADE") .. "\n" .. tostring(content or ""), duration or 4)
    end)
end

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("NightshadeGG")
SaveManager:SetFolder("NightshadeGG/GreedyGrowersV4")

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
