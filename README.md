# NIGHTSHADE V5 — Greedy Growers

Recovery build. V3/V3.1/V4 (`v3/`, `v31/`, `v4/`) used a generic ProximityPrompt/ClickDetector-guessing engine and a multipart chunk loader — both are the reason NIGHTSHADE stopped working reliably. V5 replaces that architecture entirely: one single Lua file, no loader, no prompt-guessing, and no feature is enabled until its underlying game action is confirmed working live.

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/nightshade.lua"))()
```

## Status

- **Boot health-check dashboard**: working — 10/10 checks pass live.
- **Seed purchase**: proven live. `RequestPurchase(spawnId)` confirmed against the real Knit service contract.
- Every other feature (harvest, collect, sell, plant, clear dead trees, pets, market, gear, worms, rebirth) is **not yet implemented** — each gets resolved and proven one at a time before it's added, per the design doc.

## Real client contract (confirmed live, not assumed)

Greedy Growers runs on [Knit](https://github.com/Sleitnick/Knit). Client services live under `ReplicatedStorage.Packages._Index.sleitnick_knit@<ver>.knit.Services.<ServiceName>`, each a Folder with an `RF` subfolder of RemoteFunctions and an `RE` subfolder of RemoteEvents — reached by **exact instance name**, not by pattern-matching `*Service*`/`*Controller*` (Knit's own package internals drown out any capped pattern search).

- `ConveyorSeeds` = `Workspace.BigField.ConveyorSeeds`, whose `SeedHolder` children carry `SeedType`/`SpawnId`/`Rarity` attributes (not `dataKey`)
- Currency = `Players.LocalPlayer.leaderstats.Cash`, a **StringValue** (e.g. `"$305.12Qi"`), not Number/IntValue
- `SeedConveyorService.RF.RequestPurchase` — RemoteFunction, `:InvokeServer(spawnId)`, single positional argument
- The conveyor cycles items every few seconds — a `SpawnId` scanned even a minute earlier can be stale; re-validate live right before firing

## Repo layout

- `nightshade.lua` — the V5 single-file build (current).
- `docs/superpowers/specs/` — design spec.
- `docs/superpowers/plans/` — implementation plan.
- `v3/`, `v31/`, `v4/` — archived, broken, kept for reference only. Do not use.

## Security

`NightshadeSecurity.server.lua` (planned, not yet in this repo) is a defensive QA canary for `ServerScriptService` — it validates that the server correctly rejects spoofed identity, out-of-range values, and replay attempts. It does not replace real server-side validation and only talks to dedicated test endpoints (`ReplicatedStorage.NightshadeSecurity`), never production gameplay remotes.
