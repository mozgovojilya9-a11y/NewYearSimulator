# Aura Clicker

Roblox "+1" clicker simulator, managed with Rojo 7. Click to gain Aura,
fight mobs, buy weapons/backpacks/pets, rebirth for permanent
multipliers.

## Project structure

- `src/shared/Config.luau` — shared tuning values and default player data.
- `src/server/DataService.luau` — loads/saves each player's data via DataStore (`AuraClicker_v1`).
- `src/server/Main.server.luau` — wires player join/leave into DataService and leaderstats.
- `src/server/ClickService.luau` — server-authoritative click handling: `ClickHit` RemoteEvent, per-player cooldown, crit roll, Aura award.
- `src/client/Client.client.luau` — top bar UI (Aura + online), click button, floating numbers, crit effect and click sound.
- `default.project.json` — Rojo DataModel mapping.

## Current status (Day 5 of 7)

- [x] Rojo project structure
- [x] Player data persistence (Aura, Zone, EquippedWeapon, Rebirths)
- [x] Top bar UI (Aura + online count)
- [x] Click mechanic: +1 Aura per click, 10% crit x5, server-side cooldown (Day 2)
- [x] Zone "Поляна Ауры" with 4 mob types (incl. boss), click damage, respawn, Aura + 💎 Gem drops (Day 3)
- [x] Shop with 4 weapons (Палка → Катана Ауры), buy/equip, damage multiplier (Day 4)
- [x] 3 backpacks (passive Aura/sec) and 2 pets for 💎 (+50% / +150% Aura), visible on the character (Day 5)
- [ ] Rebirth system (Day 6)
- [ ] Balance pass and release (Day 7)

## Run locally

```bash
rokit install
rojo serve
```

Keep the terminal running while Roblox Studio is connected. In Studio,
open the Rojo plugin and connect to the local server.

To build a place file without starting the live server:

```bash
rojo build -o /tmp/AuraClicker.rbxlx
```

## Acceptance test (Day 2)

1. Connect Rojo in Studio and press Play.
2. A round purple **КЛИК!** button is in the lower middle of the screen.
3. Click it: the button squishes, a `+1` floats up, a click sound plays, and "Аура" in the top bar counts up by 1.
4. Keep clicking: roughly 1 in 10 clicks shows a golden `КРИТ! +5`, a gold ring, a button shake and a lower-pitched sound; Aura grows by 5.
5. Autoclick / spam as fast as possible: Aura grows by at most ~10 clicks per second (server cooldown 0.1s).
6. Cheat check: switch the Command Bar to **Client** and run `game.ReplicatedStorage.ClickHit:FireServer(999999)` — Aura still grows only by 1 or 5 (arguments from the client are ignored).
7. Stop, Play again — Aura is restored from the DataStore (requires Studio Access to API Services).
8. Output has no errors.

## Acceptance test (Day 1)

1. Connect Rojo in Studio and press Play.
2. Confirm the top bar appears showing "Аура: 0" and "Онлайн: 1".
3. Check Output for errors.
4. Stop and rejoin — data should load without errors (still 0 until Day 2 adds the click mechanic).
