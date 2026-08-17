--[[
    NIGHTSHADE // Greedy Growers
    Server-side protection canary / QA probe

    INSTALL:
      Put this Script in ServerScriptService.

    PURPOSE:
      This does NOT replace your game's real validation.
      It gives the NIGHTSHADE client a safe, dedicated endpoint for testing:
        - identity spoof rejection
        - client-authored economy rejection
        - wrong / non-finite value rejection
        - impossible-position rejection
        - replay protection
        - request rate limiting
        - honeypot detection

    The client harness only actively attacks THESE canary remotes.
    It does not need to blindly mutate your production gameplay remotes.

    Target PlaceId: 74102906764176
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EXPECTED_PLACE_ID = 74102906764176

if game.PlaceId ~= EXPECTED_PLACE_ID and not RunService:IsStudio() then
    warn("[NIGHTSHADE SECURITY] Wrong PlaceId; protection probe did not start.")
    return
end

local Config = {
    WindowSeconds = 3,
    MaxRequestsPerWindow = 8,
    KickOnHoneypot = false,
    Verbose = true,
}

local folder = ReplicatedStorage:FindFirstChild("NightshadeSecurity")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "NightshadeSecurity"
    folder.Parent = ReplicatedStorage
end

local probe = folder:FindFirstChild("Probe")
if not probe then
    probe = Instance.new("RemoteFunction")
    probe.Name = "Probe"
    probe.Parent = folder
end

local honeypot = folder:FindFirstChild("Honeypot")
if not honeypot then
    honeypot = Instance.new("RemoteEvent")
    honeypot.Name = "Honeypot"
    honeypot.Parent = folder
end

local State = {}

local function getState(player)
    local state = State[player]
    if not state then
        state = {
            WindowStart = os.clock(),
            Requests = 0,
            Nonces = {},
            Strikes = 0,
        }
        State[player] = state
    end
    return state
end

local function finiteNumber(value)
    return typeof(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function recordStrike(player, reason)
    local state = getState(player)
    state.Strikes += 1
    player:SetAttribute("NightshadeSecurityStrikes", state.Strikes)
    warn("[NIGHTSHADE SECURITY]", player.Name, "strike", state.Strikes, "|", reason)
end

local function rateLimit(player)
    local state = getState(player)
    local current = os.clock()

    if current - state.WindowStart >= Config.WindowSeconds then
        state.WindowStart = current
        state.Requests = 0
    end

    state.Requests += 1
    return state.Requests <= Config.MaxRequestsPerWindow
end

local function reject(player, reason, strike)
    if strike then
        recordStrike(player, reason)
    end

    return {
        accepted = false,
        reason = reason,
        serverUserId = player.UserId,
    }
end

local function accept(player, reason)
    return {
        accepted = true,
        reason = reason,
        serverUserId = player.UserId,
    }
end

probe.OnServerInvoke = function(player, payload)
    if not rateLimit(player) then
        return reject(player, "rate_limited", false)
    end

    if typeof(payload) ~= "table" then
        return reject(player, "payload_must_be_table", true)
    end

    local kind = payload.kind
    if typeof(kind) ~= "string" then
        return reject(player, "missing_kind", true)
    end

    if kind == "Ping" then
        if payload.claimedUserId ~= nil and payload.claimedUserId ~= player.UserId then
            return reject(player, "ping_identity_mismatch", true)
        end
        return accept(player, "pong")
    end

    if kind == "SpoofIdentity" then
        if payload.claimedUserId ~= player.UserId then
            return reject(player, "spoofed_identity_rejected", true)
        end
        return accept(player, "identity_matches_server_player")
    end

    if kind == "Economy" then
        local amount = payload.amount

        if not finiteNumber(amount) then
            return reject(player, "invalid_economy_number", true)
        end

        if amount < 0 then
            return reject(player, "negative_economy_value", true)
        end

        return reject(player, "client_cannot_author_economy", true)
    end

    if kind == "Position" then
        if typeof(payload.position) ~= "Vector3" then
            return reject(player, "position_must_be_vector3", true)
        end

        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return reject(player, "character_not_ready", false)
        end

        local distance = (payload.position - root.Position).Magnitude
        if distance > 100 then
            return reject(player, "impossible_position_distance", true)
        end

        return accept(player, "position_within_canary_limit")
    end

    if kind == "ReplayCheck" then
        local nonce = payload.nonce

        if typeof(nonce) ~= "string" or #nonce < 8 or #nonce > 128 then
            return reject(player, "invalid_nonce", true)
        end

        local state = getState(player)
        if state.Nonces[nonce] then
            return reject(player, "replay_detected", true)
        end

        state.Nonces[nonce] = os.clock()

        local count = 0
        for _ in pairs(state.Nonces) do
            count += 1
        end

        if count > 128 then
            local oldestNonce
            local oldestTime

            for savedNonce, createdAt in pairs(state.Nonces) do
                if not oldestTime or createdAt < oldestTime then
                    oldestTime = createdAt
                    oldestNonce = savedNonce
                end
            end

            if oldestNonce then
                state.Nonces[oldestNonce] = nil
            end
        end

        return accept(player, "fresh_nonce")
    end

    return reject(player, "unknown_probe_kind", true)
end

honeypot.OnServerEvent:Connect(function(player, payload)
    recordStrike(player, "honeypot_remote_called")

    if Config.Verbose then
        warn("[NIGHTSHADE SECURITY] Honeypot payload from", player.Name, typeof(payload))
    end

    if Config.KickOnHoneypot then
        player:Kick("Security canary triggered.")
    end
end)

Players.PlayerRemoving:Connect(function(player)
    State[player] = nil
end)

print("[NIGHTSHADE SECURITY] Protection canary online.")
