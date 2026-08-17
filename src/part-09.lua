--========================================================
-- PROTECTION LAB
-- Dedicated defensive server-authority probes.
--
-- IMPORTANT:
--   This tab ONLY actively sends test payloads to:
--     ReplicatedStorage/NightshadeSecurity/Probe
--     ReplicatedStorage/NightshadeSecurity/Honeypot
--
--   It does NOT blindly fire the game's normal remotes.
--   That makes the tests repeatable and keeps them from
--   accidentally buying/selling/rebirthing during QA.
--========================================================

local ProtectionRS = game:GetService("ReplicatedStorage")

local ProtectionState = {
    Armed = false,
    ArmPhrase = "",
    LastSuite = "Not run",
}

local function getProtectionFolder()
    return ProtectionRS:FindFirstChild("NightshadeSecurity")
end

local function getProtectionProbe()
    local folder = getProtectionFolder()
    if not folder then return nil end

    local remote = folder:FindFirstChild("Probe")
    if remote and remote:IsA("RemoteFunction") then
        return remote
    end

    return nil
end

local function getProtectionHoneypot()
    local folder = getProtectionFolder()
    if not folder then return nil end

    local remote = folder:FindFirstChild("Honeypot")
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end

    return nil
end

local function protectionIsArmed()
    if game.PlaceId ~= EXPECTED_PLACE_ID then
        return false, "PlaceId lock failed"
    end

    if not ProtectionState.Armed then
        return false, "Protection Lab is not armed"
    end

    if string.upper(trim(ProtectionState.ArmPhrase)) ~= "ARM" then
        return false, 'Type ARM in the confirmation box'
    end

    return true
end

local function invokeProtectionProbe(payload)
    local armed, why = protectionIsArmed()
    if not armed then
        return false, nil, why
    end

    local probe = getProtectionProbe()
    if not probe then
        return false, nil, "NightshadeSecurity/Probe is not installed on the server"
    end

    local ok, result = pcall(function()
        return probe:InvokeServer(payload)
    end)

    if not ok then
        return false, nil, "Invoke error: " .. tostring(result)
    end

    return true, result, nil
end

local function resultAccepted(result)
    return typeof(result) == "table" and result.accepted == true
end

local function resultReason(result)
    if typeof(result) == "table" then
        return tostring(result.reason or result.code or "no reason")
    end
    return tostring(result)
end

local function runSingleProtectionTest(name, payload, shouldAccept)
    local called, result, err = invokeProtectionProbe(payload)

    if not called then
        return {
            Name = name,
            Pass = false,
            Detail = err or "probe call failed",
        }
    end

    local accepted = resultAccepted(result)
    local pass = accepted == shouldAccept

    return {
        Name = name,
        Pass = pass,
        Detail =
            "accepted=" .. tostring(accepted) ..
            " | expected=" .. tostring(shouldAccept) ..
            " | " .. resultReason(result),
    }
end

local function printProtectionResults(results)
    print("")
    print("========== NIGHTSHADE // PROTECTION LAB ==========")

    local passed = 0

    for _, result in ipairs(results) do
        local marker = result.Pass and "[PASS]" or "[FAIL]"
        if result.Pass then passed += 1 end

        print(marker, result.Name, "|", result.Detail)
    end

    print(
        "Score:",
        tostring(passed) .. "/" .. tostring(#results)
    )
    print("==================================================")
    print("")

    ProtectionState.LastSuite =
        tostring(passed) .. "/" .. tostring(#results) .. " passed"

    return passed, #results
end

local function runProtectionSuite()
    local armed, why = protectionIsArmed()
    if not armed then
        notify("Protection Lab", why, 5)
        return
    end

    if not getProtectionProbe() then
        notify(
            "Protection Lab",
            "Server probe missing. Install NightshadeSecurity.server.lua in ServerScriptService first.",
            7
        )
        return
    end

    local nonce = "nightshade-" .. tostring(Player.UserId) .. "-" .. tostring(math.floor(now() * 1000))

    local results = {}

    table.insert(results, runSingleProtectionTest(
        "Baseline authenticated ping",
        {
            kind = "Ping",
            claimedUserId = Player.UserId,
        },
        true
    ))

    table.insert(results, runSingleProtectionTest(
        "Spoofed player identity",
        {
            kind = "SpoofIdentity",
            claimedUserId = Player.UserId + 999,
        },
        false
    ))

    table.insert(results, runSingleProtectionTest(
        "Huge client-authored economy value",
        {
            kind = "Economy",
            action = "GrantCash",
            amount = 1e18,
        },
        false
    ))

    table.insert(results, runSingleProtectionTest(
        "Negative economy value",
        {
            kind = "Economy",
            action = "Buy",
            amount = -999999999,
        },
        false
    ))

    table.insert(results, runSingleProtectionTest(
        "Wrong-type economy value",
        {
            kind = "Economy",
            action = "Buy",
            amount = "999999999",
        },
        false
    ))

    table.insert(results, runSingleProtectionTest(
        "Non-finite economy value",
        {
            kind = "Economy",
            action = "Buy",
            amount = 0 / 0,
        },
        false
    ))

    table.insert(results, runSingleProtectionTest(
        "Impossible world position",
        {
            kind = "Position",
            position = Vector3.new(10000000, 10000000, 10000000),
        },
        false
    ))

    table.insert(results, runSingleProtectionTest(
        "Fresh replay nonce baseline",
        {
            kind = "ReplayCheck",
            nonce = nonce,
        },
        true
    ))

    table.insert(results, runSingleProtectionTest(
        "Replay attack",
        {
            kind = "ReplayCheck",
            nonce = nonce,
        },
        false
    ))

    local rejected = 0
    local burstCount = 12

    for i = 1, burstCount do
        local called, result = invokeProtectionProbe({
            kind = "Ping",
            claimedUserId = Player.UserId,
            sequence = i,
        })

        if called and not resultAccepted(result) then
            rejected += 1
        end
    end

    table.insert(results, {
        Name = "Burst / rate-limit protection",
        Pass = rejected > 0,
        Detail =
            tostring(rejected) ..
            "/" .. tostring(burstCount) ..
            " burst requests rejected",
    })

    local passed, total = printProtectionResults(results)

    notify(
        "Protection Lab",
        "Server-authority suite: " ..
        tostring(passed) .. "/" .. tostring(total) ..
        " passed.\nFull details printed to console.",
        8
    )
end

local function runHoneypotTest()
    local armed, why = protectionIsArmed()
    if not armed then
        notify("Protection Lab", why, 5)
        return
    end

    local honeypot = getProtectionHoneypot()
    if not honeypot then
        notify(
            "Protection Lab",
            "NightshadeSecurity/Honeypot is not installed on the server.",
            6
        )
        return
    end

    local before = Player:GetAttribute("NightshadeSecurityStrikes") or 0

    local ok, err = pcall(function()
        honeypot:FireServer({
            fakeAdmin = true,
            claimedUserId = Player.UserId + 1,
            requestedAction = "GrantEverything",
        })
    end)

    if not ok then
        notify("Honeypot", "Client call errored: " .. tostring(err), 6)
        return
    end

    task.wait(0.35)

    local after = Player:GetAttribute("NightshadeSecurityStrikes") or 0

    if after > before then
        notify(
            "Honeypot PASS",
            "Server detected the forbidden remote call. Strikes: " ..
            tostring(before) .. " -> " .. tostring(after),
            7
        )
    else
        notify(
            "Honeypot CHECK",
            "No strike was replicated back. Check the server console / probe installation.",
            7
        )
    end
end

local function remoteSurfaceSnapshot()
    local rows = {}
    local dangerous = 0

    local sensitiveWords = {
        "admin","give","grant","reward","cash","money","coin",
        "buy","purchase","sell","rebirth","prestige","inventory",
        "seed","harvest","plant","market","trade","pet","egg",
        "data","save","load","teleport"
    }

    for _, object in ipairs(ProtectionRS:GetDescendants()) do
