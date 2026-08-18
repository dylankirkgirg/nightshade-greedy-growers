# NIGHTSHADE V5 — Recovery Build Design

## Problem

NIGHTSHADE (Roblox automation/QA panel for Greedy Growers) is broken: UI loads,
automation does nothing. Root cause is architectural — V4 used a multipart
loader plus a generic ProximityPrompt-guessing engine ("find anything named
Buy/Harvest/etc and walk to it"), instead of the game's real client
service/controller contract. Static analysis of a working third-party script
(Ouroboros) shows Greedy Growers exposes real APIs (`SeedConveyorService`,
`RequestPurchase`, `ConveyorSeeds`, seed `dataKey` attribute) that V4 never
used.

## Goal

Rebuild as a single-file instrumentation/debug build (V5) that proves one
real game action (seed purchase) works before adding anything else. No
feature ships as "on" until its resolver and verification step have run
live and shown observable state change.

## Non-goals (this spec)

- Full feature parity with V4 (harvest/sell/pets/market/etc.) — future specs,
  one action at a time, after purchase is proven.
- Polished UI / external UI libraries (Rayfield, Linoria).
- The server-side security canary (`NightshadeSecurity.server.lua`) — separate,
  not blocking client recovery work.

## Architecture

Single file: `nightshade.lua`. No `loadstring`-chained parts, no
concatenation. Organized as clearly-commented sections in execution order:

```
Config      -- constants: expected PlaceId, log level, colors
Logger      -- timestamped [NIGHTSHADE][TAG] console + on-screen log
Runtime     -- duplicate-execution guard, Players/RS/Workspace refs, cleanup registry
Scanner     -- bounded descendant walks: find ConveyorSeeds, service folders, currency
Resolvers   -- pure functions, one per game contract, return (ok, result, detail)
UI          -- native Instance.new ScreenGui: health dashboard + log console + debug panel
Actions     -- one-shot testable actions (TestPurchase first; others follow later)
Verification-- before/after snapshot + diff reporting
Automation  -- (stubbed/disabled in V5 — no loops until an action is proven)
Cleanup     -- unload function: disconnect all connections, destroy UI
```

All state lives in one local table (`NS`), no scattered globals. Duplicate-run
guard: check/set `getgenv().__NIGHTSHADE_LOADED`.

### UI

Plain Roblox `ScreenGui` + `Frame`, built with `Instance.new` only — no
external UI library. Contains:
- Health-check dashboard (list of PASS/FAIL lines, matches the boot sequence)
- Scrollable log console (`ScrollingFrame` of `TextLabel`s, capped at N lines)
- "Dump Runtime Contract" button
- Debug panel: seed dropdown (from Scanner results) + "Test Purchase" button

### Boot sequence

Runs once on load, each step logged as `[NIGHTSHADE][PASS]` or `[FAIL]`:

1. NIGHTSHADE boot (always PASS if this line runs)
2. Correct PlaceId (`game.PlaceId == 74102906764176`)
3. LocalPlayer found
4. Character found
5. ReplicatedStorage scanned (Scanner completes without error)
6. ConveyorSeeds found
7. Currency source found
8. SeedConveyorService resolved
9. RequestPurchase resolved
10. Seed dataKey values detected (≥1 seed with a readable `dataKey` attribute)

A FAIL on any step does not stop the boot — later steps still attempt and
report, so a partial environment still gives a useful dashboard.

### Scanner

Bounded, targeted descendant search (not a blind `GetDescendants()` dump):
- Looks for an instance named `ConveyorSeeds` under `workspace` (search depth
  capped, e.g. 6 levels, stop on first match by name)
- Looks for folders/modules under `ReplicatedStorage` whose name matches
  `*SeedConveyorService*`, `*Service*`, `*Controller*` (name-based candidate
  list, capped at ~30 results, logged as candidates not assumptions)
- Looks for currency: player `leaderstats` NumberValue/IntValue children, and
  common attribute names (`Cash`, `Coins`, `Money`) on `LocalPlayer`
- Results stored in `NS.scan` table for resolvers and the UI to read

### Resolvers

Each resolver is a pure function `resolveX() -> ok, result, detail` called
both during boot and on-demand from "Dump Runtime Contract". They:
- Never guess (no "if name contains Buy" prompt matching)
- Read only from `NS.scan` results or direct known paths
- Return enough detail (`instance`, `path`, candidates-considered) for the
  log line to be informative on failure

Four resolvers for V5: `resolveConveyorSeeds`, `resolveCurrency`,
`resolveSeedConveyorService`, `resolveRequestPurchase`.

### Stage 2 — Test Purchase (the one proven action)

Debug panel lets you pick one seed found by the Scanner (by name/dataKey) and
press "Test Purchase". Before calling anything, UI shows: seed instance path,
name, dataKey, best-guess price (if discoverable), current cash, resolved
service, resolved method name. Button is disabled if any required resolver
failed.

On press: snapshot cash + relevant inventory/stock state, `pcall` the
`RequestPurchase(dataKey)` invocation (via `InvokeServer` if it's a
RemoteFunction, matching what Ouroboros' contract implies — confirmed at
runtime, not assumed), log the raw pcall result, re-snapshot, diff, and log
`[NIGHTSHADE][VERIFY]` with before/after values and a PASS/FAIL confirmation
line.

### Automation

Stubbed only — a disabled toggle placeholder, no actual loop. Enabling real
Auto Buy Seed is a future spec, once Test Purchase has been confirmed working
live at least once via Opiumware.

## Error handling

No bare `pcall(...)` that swallows errors silently. Every resolver/action
failure logs the tag, what was attempted, and what candidates were found
nearby (from `NS.scan`), so a FAIL is diagnosable from the on-screen console
alone.

## Testing / verification loop

This is a live Roblox script, not a unit-testable module. Verification means:
1. Load into Opiumware (computer-use drives this: paste script, inject)
2. Screenshot NIGHTSHADE's own on-screen dashboard + log console
3. Read PASS/FAIL lines directly off the rendered UI
4. For Test Purchase: confirm the VERIFY log shows an actual cash/inventory
   delta, not just "no error thrown"

No separate test framework — the health dashboard and Verification step *are*
the test suite for this build.

## Open risks / unknowns to confirm at runtime, not assumed here

- Whether `RequestPurchase` is a RemoteFunction (`InvokeServer`) or
  RemoteEvent (`FireServer`) — Ouroboros static analysis didn't confirm this;
  the resolver must detect the instance's ClassName and use the right call.
- Exact currency attribute/leaderstat name — Scanner reports candidates,
  doesn't hardcode one.
- Whether `SeedConveyorService` is a ModuleScript (requires `require()`) or
  already-instantiated table/RemoteFunction container — resolver must handle
  both and log which it found.
