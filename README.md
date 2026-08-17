# NIGHTSHADE V3.1 — Greedy Growers

Purpose-built Greedy Growers automation using WindUI. V3.1 keeps the old V3 core available for rollback, but the public loader now routes to the stricter V3.1 build.

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/nightshade.lua"))()
```

## V3.1 highlights

### Strict river seed sniper
- Buys conveyor seeds without moving when the executor supports `fireproximityprompt` or `fireclickdetector`.
- Uses explicit replicated/displayed `Price` / `Cost` data first.
- Falls back to the known seed database only for recognized Greedy Growers seeds.
- Checks affordability before selecting a seed and re-checks immediately before interaction.
- Coin reserve and max-cost-per-seed controls.
- Skip-on-unknown-cash and skip-on-unknown-price guards.
- Dry-run mode for testing targeting without pressing Buy.
- Correct, separate behavior for Highest Affordable, Any Affordable, Specific Seed, and Minimum Rarity modes.
- Optional mutation preference / mutated-only mode.
- Rare-seed notifications.

### Performance / reliability
- Caches all ProximityPrompt and ClickDetector interactions instead of repeatedly scanning the entire Workspace in every automation loop.
- Tracks new/removed interactions dynamically.
- Handles nested `ConveyorSeeds` layouts by preferring the nearest seed model around each conveyor interaction.
- Per-interaction and per-seed cooldowns reduce duplicate actions.
- Public loader uses a verified bootstrap before compiling V3.1.

### Farming
- Auto harvest at a chosen `HarvestMultiplier`.
- Auto collect fruit / Collect All.
- Auto clear dead trees.
- Auto plant and auto plant grown trees.
- Own-plot filtering through replicated ownership values such as `OwnerUserId`.
- Auto organise trees when exposed by the game.
- Auto sell fruits, sell all, and sell at max inventory.

### Weather / mutations
- Misty, Acid Rain, Rainbow, and Meteor Shower detection.
- Weather-only planting filters.
- Recognizes Dewy, Shocked, Radioactive, Charged, Golden, Cosmic, Infested, Huge, Slimy, and Scaled signals when exposed to the client.

### Farmer's Market / pets
- Auto give market fruits.
- Auto claim market tickets.
- Ticket-reserve-aware pet egg buying.
- Common through Mythic egg selection.
- Uses a live displayed egg price when exposed, otherwise the known ticket-tier cost.
- Auto place / hatch egg interaction support.

### Utility
- Conservative low-rarity seed composting.
- Gear, worms, and furniture buying only when a live price is exposed and affordable.
- Auto claim index reward.
- Guarded auto rebirth.
- Anti-AFK.
- Settings persistence when executor file APIs are available.
- Diagnostics for Greedy Growers surfaces, river candidates, prompts/clicks, currency sources, and executor capabilities.

## Repo layout

- `nightshade.lua` — stable public loader.
- `v31/bootstrap.lua` — verified V3.1 bootstrap/correctness layer.
- `v31/main.lua` — V3.1 core.
- `v3/part-01.lua` — retained V3 rollback core.

## Notes

V3.1 contains no direct gameplay `FireServer()` or `InvokeServer()` calls. The script interacts with replicated prompt/click surfaces. Distance-free prompt/click interaction depends on executor support; Diagnostics shows the detected capabilities.
