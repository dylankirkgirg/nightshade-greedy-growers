# NIGHTSHADE // Greedy Growers

Linoria-based local mechanics QA / automation harness for Greedy Growers.

## Files

- `nightshade.lua` — tiny public loader that downloads the chunked NIGHTSHADE client
- `src/part-*.lua` — NIGHTSHADE client source split into raw-loadable chunks
- `NightshadeSecurity.server.lua` — optional server-authority canary for the Protection Lab

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dylankirkgirg/nightshade-greedy-growers/main/nightshade.lua"))()
```

## Protection Lab setup

1. Put `NightshadeSecurity.server.lua` in **ServerScriptService**.
2. Start your game/server.
3. Execute NIGHTSHADE with the loadstring above.
4. Open **Protection Lab**.
5. Toggle **Arm Active Protection Tests**.
6. Type `ARM`.
7. Run **Full Server-Authority Suite**.

A healthy test server should accept harmless baseline requests and reject forged identity, client-authored economy values, malformed values, impossible positions, replayed nonces, and excessive bursts. The honeypot test should register a security strike.

The normal automation path contains no direct gameplay RemoteEvent/RemoteFunction calls. The Protection Lab intentionally calls only the dedicated `ReplicatedStorage/NightshadeSecurity` canary endpoints.
