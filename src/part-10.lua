        if object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then
            local name = lower(object.Name)
            local sensitive = containsAny(name, sensitiveWords)

            if sensitive then
                dangerous += 1
            end

            table.insert(rows, {
                Type = object.ClassName,
                Path = object:GetFullName(),
                Sensitive = sensitive,
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.Sensitive ~= b.Sensitive then
            return a.Sensitive
        end
        return a.Path < b.Path
    end)

    print("")
    print("========== NIGHTSHADE // REMOTE SURFACE ==========")
    for _, row in ipairs(rows) do
        print(
            row.Sensitive and "[REVIEW]" or "[INFO]",
            row.Type,
            row.Path
        )
    end
    print("Total remotes:", #rows)
    print("Sensitive-name review candidates:", dangerous)
    print("==================================================")
    print("")

    notify(
        "Remote surface",
        tostring(#rows) .. " remotes found; " ..
        tostring(dangerous) .. " names flagged for manual server-validation review.\n" ..
        "Nothing was fired.",
        7
    )
end

Protection:CreateSection("Server Authority Tests")

Protection:CreateParagraph({
    Title = "How this works",
    Content =
        "This is a defensive canary lab. It only sends crafted requests to " ..
        "ReplicatedStorage/NightshadeSecurity, not your normal gameplay remotes. " ..
        "Protected servers should reject forged identity/economy/position/replay/burst tests."
})

Protection:CreateToggle({
    Name = "Arm Active Protection Tests",
    CurrentValue = false,
    Flag = "ProtectionArmed",
    Callback = function(v)
        ProtectionState.Armed = v
    end,
})

Protection:CreateInput({
    Name = "Confirmation",
    CurrentValue = "",
    PlaceholderText = "Type ARM",
    RemoveTextAfterFocusLost = false,
    Flag = "ProtectionArmPhrase",
    Callback = function(v)
        ProtectionState.ArmPhrase = v
    end,
})

Protection:CreateButton({
    Name = "Run Full Server-Authority Suite",
    Callback = runProtectionSuite,
})

Protection:CreateButton({
    Name = "Trigger Exploit Honeypot",
    Callback = runHoneypotTest,
})

Protection:CreateSection("Passive Audit")

Protection:CreateButton({
    Name = "Inventory Remote Surface (no calls)",
    Callback = remoteSurfaceSnapshot,
})

Protection:CreateButton({
    Name = "Check Protection Probe Installation",
    Callback = function()
        local folder = getProtectionFolder()
        local probe = getProtectionProbe()
        local honeypot = getProtectionHoneypot()

        notify(
            "Protection installation",
            "Folder: " .. tostring(folder ~= nil) ..
            "\nProbe: " .. tostring(probe ~= nil) ..
            "\nHoneypot: " .. tostring(honeypot ~= nil),
            6
        )
    end,
})

--========================================================
-- CLEANUP
--========================================================

function Runtime.Stop()
    Runtime.Running = false
    Runtime.MovementToken += 1

    local _, humanoid, root = getCharacter()
    if humanoid and root then
        pcall(function()
            humanoid:MoveTo(root.Position)
        end)
    end

    pcall(function()
        if ENV.NIGHTSHADE_LINORIA then
            ENV.NIGHTSHADE_LINORIA:Unload()
        end
    end)
end

--========================================================
-- LOAD CONFIG LAST
--========================================================

pcall(function()
    Rayfield:LoadConfiguration()
end)

-- Initial status refresh
task.delay(0.8, function()
    if Runtime.Running then
        pcall(function()
            StatusParagraph:Set({
                Title = "NIGHTSHADE Status",
                Content = snapshotText(),
            })
        end)
    end
end)

notify(
    "NIGHTSHADE initialized 🌑",
    "Greedy Growers mechanics harness loaded.\n" ..
    "Mode: " .. Settings.ExecutionMode .. "\n" ..
    "Gameplay remotes: 0 direct calls\nProtection Lab: dedicated canary remotes only",
    6
)

print("[NIGHTSHADE] Greedy Growers loaded.")
print("[NIGHTSHADE] Prompt scan:", promptSummaryText())
print("[NIGHTSHADE] Gameplay remote calls: 0 direct calls")
print("[NIGHTSHADE] Protection Lab uses only ReplicatedStorage/NightshadeSecurity test remotes")
