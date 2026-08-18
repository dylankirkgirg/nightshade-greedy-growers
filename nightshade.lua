--[[ NIGHTSHADE V5 — recovery build for Greedy Growers ]]

if getgenv then
	if getgenv().__NIGHTSHADE_LOADED then
		warn("[NIGHTSHADE] Already loaded, aborting duplicate execution")
		return
	end
	getgenv().__NIGHTSHADE_LOADED = true
end

local NS = {}

-- ===== Config =====
NS.Config = {
	ExpectedPlaceId = 74102906764176,
	MaxLogLines = 200,
	ScanDepth = 6,
	MaxCandidates = 30,
}

-- ===== State =====
NS.State = {
	connections = {},
	scan = {
		conveyorSeeds = nil,
		serviceCandidates = {},
		currencyCandidates = {},
		seeds = {},
	},
}

-- ===== Logger =====
NS.Logger = { lines = {} }

function NS.Logger.log(tag, msg)
	local line = string.format("[NIGHTSHADE][%s] %s", tag, msg)
	print(line)
	table.insert(NS.Logger.lines, line)
	if #NS.Logger.lines > NS.Config.MaxLogLines then
		table.remove(NS.Logger.lines, 1)
	end
	if NS.UI and NS.UI.appendLog then
		NS.UI.appendLog(line)
	end
end

function NS.Logger.pass(msg) NS.Logger.log("PASS", msg) end
function NS.Logger.fail(msg) NS.Logger.log("FAIL", msg) end
function NS.Logger.resolve(msg) NS.Logger.log("RESOLVE", msg) end
function NS.Logger.action(msg) NS.Logger.log("ACTION", msg) end
function NS.Logger.verify(msg) NS.Logger.log("VERIFY", msg) end

-- ===== Runtime =====
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

NS.Runtime = {
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	Workspace = Workspace,
	LocalPlayer = Players.LocalPlayer,
}

function NS.Runtime.cleanup()
	for _, conn in ipairs(NS.State.connections) do
		pcall(function() conn:Disconnect() end)
	end
	NS.State.connections = {}
	if NS.UI and NS.UI.gui then
		NS.UI.gui:Destroy()
	end
	if getgenv then getgenv().__NIGHTSHADE_LOADED = nil end
end

-- ===== Scanner =====
NS.Scanner = {}

function NS.Scanner.findConveyorSeeds()
	local found = Workspace:FindFirstChild("ConveyorSeeds", true)
	if not found then
		local function search(inst, depth)
			if depth > NS.Config.ScanDepth then return nil end
			for _, child in ipairs(inst:GetChildren()) do
				if child.Name == "ConveyorSeeds" then
					return child
				end
				local r = search(child, depth + 1)
				if r then return r end
			end
			return nil
		end
		found = search(Workspace, 0)
	end
	NS.State.scan.conveyorSeeds = found
	return found
end

function NS.Scanner.findServiceCandidates()
	local candidates = {}
	local patterns = { "Service", "Controller" }
	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if #candidates >= NS.Config.MaxCandidates then break end
		for _, pattern in ipairs(patterns) do
			if string.find(descendant.Name, pattern) then
				table.insert(candidates, descendant)
				break
			end
		end
	end
	NS.State.scan.serviceCandidates = candidates
	return candidates
end

function NS.Scanner.findCurrencyCandidates()
	local candidates = {}
	local player = NS.Runtime.LocalPlayer
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, child in ipairs(leaderstats:GetChildren()) do
			if child:IsA("NumberValue") or child:IsA("IntValue") then
				table.insert(candidates, child)
			end
		end
	end
	local commonNames = { "Cash", "Coins", "Money" }
	for _, name in ipairs(commonNames) do
		local attr = player:GetAttribute(name)
		if attr ~= nil then
			table.insert(candidates, { name = name, value = attr, isAttribute = true })
		end
	end
	NS.State.scan.currencyCandidates = candidates
	return candidates
end

function NS.Scanner.findSeeds()
	local seeds = {}
	if NS.State.scan.conveyorSeeds then
		for _, child in ipairs(NS.State.scan.conveyorSeeds:GetChildren()) do
			table.insert(seeds, {
				instance = child,
				name = child.Name,
				dataKey = child:GetAttribute("dataKey"),
			})
		end
	end
	NS.State.scan.seeds = seeds
	return seeds
end

function NS.Scanner.runAll()
	NS.Scanner.findConveyorSeeds()
	NS.Scanner.findServiceCandidates()
	NS.Scanner.findCurrencyCandidates()
	NS.Scanner.findSeeds()
end

-- ===== Resolvers =====
NS.Resolvers = {}

function NS.Resolvers.resolveConveyorSeeds()
	local inst = NS.State.scan.conveyorSeeds
	if inst then
		return true, inst, inst:GetFullName()
	end
	return false, nil, "not found under Workspace within depth " .. NS.Config.ScanDepth
end

function NS.Resolvers.resolveCurrency()
	local candidates = NS.State.scan.currencyCandidates
	if #candidates > 0 then
		local first = candidates[1]
		if first.isAttribute then
			return true, first, string.format("attribute %s = %s", first.name, tostring(first.value))
		end
		return true, first, first:GetFullName() .. " = " .. tostring(first.Value)
	end
	return false, nil, "no leaderstats NumberValue/IntValue or Cash/Coins/Money attribute found"
end

function NS.Resolvers.resolveSeedConveyorService()
	for _, inst in ipairs(NS.State.scan.serviceCandidates) do
		if string.find(inst.Name, "SeedConveyorService") then
			return true, inst, inst:GetFullName() .. " (" .. inst.ClassName .. ")"
		end
	end
	local names = {}
	for _, c in ipairs(NS.State.scan.serviceCandidates) do
		table.insert(names, c.Name)
	end
	return false, nil, "not found by exact name; candidates: " .. table.concat(names, ", ")
end

function NS.Resolvers.resolveRequestPurchase()
	local ok, serviceInst = NS.Resolvers.resolveSeedConveyorService()
	if not ok then
		return false, nil, "cannot resolve without SeedConveyorService"
	end

	local target = serviceInst
	if serviceInst:IsA("ModuleScript") then
		local success, mod = pcall(require, serviceInst)
		if success and type(mod) == "table" then
			target = mod
		else
			return false, nil, "SeedConveyorService is a ModuleScript but require() failed or returned non-table"
		end
	end

	if type(target) == "table" then
		local fn = target.RequestPurchase
		if fn then
			return true, fn, "table method SeedConveyorService.RequestPurchase"
		end
		return false, nil, "module table has no RequestPurchase key"
	end

	local remote = serviceInst:FindFirstChild("RequestPurchase")
	if remote and (remote:IsA("RemoteFunction") or remote:IsA("RemoteEvent")) then
		return true, remote, remote:GetFullName() .. " (" .. remote.ClassName .. ")"
	end

	return false, nil, "no RequestPurchase child RemoteFunction/RemoteEvent under " .. serviceInst:GetFullName()
end

-- ===== UI =====
NS.UI = { dashboardLabels = {}, selectedSeed = nil }

function NS.UI.build()
	local player = NS.Runtime.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "NightshadeV5"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	NS.UI.gui = gui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 420, 0, 520)
	frame.Position = UDim2.new(0, 20, 0, 20)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	frame.Parent = gui
	NS.UI.frame = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	title.TextColor3 = Color3.fromRGB(200, 80, 220)
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 18
	title.Text = "NIGHTSHADE V5"
	title.Parent = frame

	local dashboard = Instance.new("Frame")
	dashboard.Size = UDim2.new(1, -10, 0, 190)
	dashboard.Position = UDim2.new(0, 5, 0, 35)
	dashboard.BackgroundTransparency = 1
	dashboard.Parent = frame
	NS.UI.dashboard = dashboard

	local logFrame = Instance.new("ScrollingFrame")
	logFrame.Size = UDim2.new(1, -10, 0, 180)
	logFrame.Position = UDim2.new(0, 5, 0, 230)
	logFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logFrame.ScrollBarThickness = 6
	logFrame.Parent = frame
	NS.UI.logFrame = logFrame

	local logLayout = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Parent = logFrame

	local dumpButton = Instance.new("TextButton")
	dumpButton.Size = UDim2.new(1, -10, 0, 26)
	dumpButton.Position = UDim2.new(0, 5, 0, 415)
	dumpButton.Text = "Dump Runtime Contract"
	dumpButton.Parent = frame
	NS.UI.dumpButton = dumpButton

	local seedPanel = Instance.new("Frame")
	seedPanel.Size = UDim2.new(1, -10, 0, 40)
	seedPanel.Position = UDim2.new(0, 5, 0, 445)
	seedPanel.BackgroundTransparency = 1
	seedPanel.Parent = frame
	NS.UI.seedPanel = seedPanel

	local testPurchaseButton = Instance.new("TextButton")
	testPurchaseButton.Size = UDim2.new(1, -10, 0, 26)
	testPurchaseButton.Position = UDim2.new(0, 5, 0, 488)
	testPurchaseButton.Text = "Test Purchase (no seed selected)"
	testPurchaseButton.Parent = frame
	NS.UI.testPurchaseButton = testPurchaseButton
end

function NS.UI.setDashboardLine(key, index, passed, text)
	local label = NS.UI.dashboardLabels[key]
	if not label then
		label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 19)
		label.Position = UDim2.new(0, 0, 0, (index - 1) * 19)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Font = Enum.Font.Code
		label.TextSize = 13
		label.Parent = NS.UI.dashboard
		NS.UI.dashboardLabels[key] = label
	end
	label.TextColor3 = passed and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(220, 80, 80)
	label.Text = (passed and "[PASS] " or "[FAIL] ") .. text
end

function NS.UI.appendLog(line)
	if not NS.UI.logFrame then return end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.Font = Enum.Font.Code
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = line
	label.LayoutOrder = #NS.UI.logFrame:GetChildren()
	label.Parent = NS.UI.logFrame
end

function NS.UI.renderSeedButtons(seeds)
	for _, child in ipairs(NS.UI.seedPanel:GetChildren()) do
		child:Destroy()
	end
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Parent = NS.UI.seedPanel
	for _, seed in ipairs(seeds) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 80, 1, 0)
		btn.Text = seed.name
		btn.Parent = NS.UI.seedPanel
		btn.MouseButton1Click:Connect(function()
			NS.UI.selectedSeed = seed
			NS.UI.testPurchaseButton.Text = "Test Purchase: " .. seed.name
		end)
	end
end

-- ===== Boot =====
NS.Boot = {}

local function report(key, index, passed, text)
	if passed then NS.Logger.pass(text) else NS.Logger.fail(text) end
	NS.UI.setDashboardLine(key, index, passed, text)
end

function NS.Boot.run()
	report("boot", 1, true, "NIGHTSHADE boot")

	local placeIdOk = game.PlaceId == NS.Config.ExpectedPlaceId
	report("placeid", 2, placeIdOk,
		"Correct PlaceId (expected " .. NS.Config.ExpectedPlaceId .. ", got " .. tostring(game.PlaceId) .. ")")

	local playerOk = NS.Runtime.LocalPlayer ~= nil
	report("player", 3, playerOk,
		playerOk and ("LocalPlayer found: " .. NS.Runtime.LocalPlayer.Name) or "LocalPlayer not found")

	local character = playerOk and (NS.Runtime.LocalPlayer.Character or NS.Runtime.LocalPlayer.CharacterAdded:Wait())
	report("character", 4, character ~= nil,
		character ~= nil and "Character found" or "Character not found")

	local scanOk = pcall(NS.Scanner.runAll)
	report("scan", 5, scanOk,
		scanOk and "ReplicatedStorage scanned" or "Scanner threw an error")

	local okConveyor, _, detailConveyor = NS.Resolvers.resolveConveyorSeeds()
	report("conveyor", 6, okConveyor, "ConveyorSeeds: " .. detailConveyor)

	local okCurrency, _, detailCurrency = NS.Resolvers.resolveCurrency()
	report("currency", 7, okCurrency, "Currency: " .. detailCurrency)

	local okService, _, detailService = NS.Resolvers.resolveSeedConveyorService()
	report("service", 8, okService, "SeedConveyorService: " .. detailService)

	local okPurchase, _, detailPurchase = NS.Resolvers.resolveRequestPurchase()
	report("purchase", 9, okPurchase, "RequestPurchase: " .. detailPurchase)

	local seeds = NS.State.scan.seeds
	local withKey = 0
	for _, s in ipairs(seeds) do
		if s.dataKey then withKey = withKey + 1 end
	end
	report("datakey", 10, withKey > 0,
		"Seed dataKey values detected: " .. withKey .. "/" .. #seeds)

	NS.UI.renderSeedButtons(seeds)
end

-- ===== Actions =====
NS.Actions = {}

function NS.Actions.dumpRuntimeContract()
	NS.Logger.log("DUMP", "----- Runtime Contract Dump -----")
	NS.Logger.log("DUMP", "ConveyorSeeds: " ..
		(NS.State.scan.conveyorSeeds and NS.State.scan.conveyorSeeds:GetFullName() or "nil"))

	NS.Logger.log("DUMP", "Service candidates (" .. #NS.State.scan.serviceCandidates .. "):")
	for _, inst in ipairs(NS.State.scan.serviceCandidates) do
		NS.Logger.log("DUMP", "  " .. inst:GetFullName() .. " (" .. inst.ClassName .. ")")
	end

	NS.Logger.log("DUMP", "Currency candidates (" .. #NS.State.scan.currencyCandidates .. "):")
	for _, c in ipairs(NS.State.scan.currencyCandidates) do
		if c.isAttribute then
			NS.Logger.log("DUMP", "  attribute " .. c.name .. " = " .. tostring(c.value))
		else
			NS.Logger.log("DUMP", "  " .. c:GetFullName() .. " = " .. tostring(c.Value))
		end
	end

	NS.Logger.log("DUMP", "Seeds (" .. #NS.State.scan.seeds .. "):")
	for _, s in ipairs(NS.State.scan.seeds) do
		NS.Logger.log("DUMP", "  " .. s.name .. " dataKey=" .. tostring(s.dataKey))
	end

	NS.Logger.log("DUMP", "----- End Dump -----")
end

-- ===== Verification =====
NS.Verification = {}

function NS.Verification.snapshotCurrency()
	local ok, inst = NS.Resolvers.resolveCurrency()
	if not ok then return nil end
	if inst.isAttribute then
		return NS.Runtime.LocalPlayer:GetAttribute(inst.name)
	end
	return inst.Value
end

function NS.Actions.testPurchase(seed)
	if not seed then
		NS.Logger.fail("Test Purchase pressed with no seed selected")
		return
	end
	if not seed.dataKey then
		NS.Logger.fail("Selected seed " .. seed.name .. " has no dataKey attribute")
		return
	end

	local okService, _, serviceDetail = NS.Resolvers.resolveSeedConveyorService()
	local okFn, fn, fnDetail = NS.Resolvers.resolveRequestPurchase()
	if not okService or not okFn then
		NS.Logger.fail("Cannot test purchase: service=" .. tostring(okService) .. " requestPurchase=" .. tostring(okFn))
		return
	end

	NS.Logger.resolve("Seed: " .. seed.name .. " dataKey=" .. tostring(seed.dataKey))
	NS.Logger.resolve("Service: " .. serviceDetail)
	NS.Logger.resolve("RequestPurchase: " .. fnDetail)

	local before = NS.Verification.snapshotCurrency()
	NS.Logger.verify("Cash before = " .. tostring(before))

	NS.Logger.action('RequestPurchase("' .. tostring(seed.dataKey) .. '")')

	local success, result
	if fn:IsA("RemoteFunction") then
		success, result = pcall(function()
			return fn:InvokeServer(seed.dataKey)
		end)
	elseif fn:IsA("RemoteEvent") then
		success, result = pcall(function()
			fn:FireServer(seed.dataKey)
			return "fired (RemoteEvent, no return value)"
		end)
	else
		success, result = pcall(function()
			return fn(seed.dataKey)
		end)
	end

	if not success then
		NS.Logger.fail("RequestPurchase errored: " .. tostring(result))
		return
	end
	NS.Logger.pass("RequestPurchase call completed, result = " .. tostring(result))

	task.wait(1)

	local after = NS.Verification.snapshotCurrency()
	NS.Logger.verify("Cash after = " .. tostring(after))

	if before ~= nil and after ~= nil and after ~= before then
		NS.Logger.pass("Purchase confirmed: cash changed " .. tostring(before) .. " -> " .. tostring(after))
	else
		NS.Logger.fail("Purchase unconfirmed: cash unchanged (before=" .. tostring(before) .. ", after=" .. tostring(after) .. ")")
	end
end

-- ===== Wire up and boot =====
NS.UI.build()

NS.UI.dumpButton.MouseButton1Click:Connect(NS.Actions.dumpRuntimeContract)
NS.UI.testPurchaseButton.MouseButton1Click:Connect(function()
	NS.Actions.testPurchase(NS.UI.selectedSeed)
end)

NS.Boot.run()

return NS
