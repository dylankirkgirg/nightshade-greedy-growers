# NIGHTSHADE V3 — Greedy Growers

Purpose-built Greedy Growers automation using WindUI. V3 is a clean rebuild; it does not include the old server protection / honeypot test system.

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/nightshade.lua"))()
```

## V3 highlights

### Smart river seed sniper
- Buys conveyor seeds without moving when the executor supports `fireproximityprompt` or `fireclickdetector`.
- Checks the current replicated/displayed price first, then falls back to NIGHTSHADE's known seed database.
- Hard affordability check before interaction.
- Coin reserve and max-cost-per-seed controls.
- Skip-on-unknown-cash and skip-on-unknown-price safety switches are enabled by default.
- Specific seed, minimum rarity, highest affordable, and mutated-only modes.
- Rare-seed notifications.

### Farming
- Auto harvest at a chosen `HarvestMultiplier`.
- Auto collect fruit / Collect All.
- Auto clear dead trees.
- Auto plant and auto plant grown trees.
- Own-plot filtering via replicated ownership values such as `OwnerUserId`.
- Auto organise trees when the game exposes the interaction.
- Auto sell fruits, sell all, and sell at max inventory.

### Weather / mutations
- Misty, Acid Rain, Rainbow, and Meteor Shower detection.
- Weather-only planting filters.
- Dewy, Shocked, Radioactive, Charged, Golden, Cosmic, and pet-mutation recognition when exposed to the client.

### Farmer's Market / pets
- Auto give market fruits.
- Auto claim market tickets.
- Ticket-safe pet egg buying with reserve checks.
- Common through Mythic egg selection.
- Auto place / hatch egg interaction support.

### Utility
- Conservative low-rarity seed composting.
- Gear, worms, and furniture purchase automation only when a current price is exposed and affordable.
- Auto claim index reward.
- Guarded auto rebirth.
- Anti-AFK.
- Settings persistence when executor file APIs are available.
- Diagnostics for current Greedy Growers world surfaces and executor capabilities.

## Notes

V3 intentionally contains no direct gameplay `FireServer()` or `InvokeServer()` calls. It interacts with the normal replicated prompt/click surfaces available to the client. Distance-free interactions require the executor to support the corresponding helper; the Diagnostics tab shows capability status.
