# Aura Clicker

Roblox "+1" clicker simulator, managed with Rojo 7. Click to gain Aura,
fight mobs, buy weapons/backpacks/pets, rebirth for permanent
multipliers.

## Project structure

- `src/shared/Config.luau` — shared tuning values and default player data.
- `src/server/DataService.luau` — loads/saves each player's data via DataStore (`AuraClicker_v1`).
- `src/server/Main.server.luau` — wires player join/leave into DataService and leaderstats.
- `src/client/Client.client.luau` — top bar UI showing Aura and online count.
- `default.project.json` — Rojo DataModel mapping.

## Current status (Day 1 of 7)

- [x] Rojo project structure
- [x] Player data persistence (Aura, Zone, EquippedWeapon, Rebirths)
- [x] Top bar UI (Aura + online count)
- [ ] Click mechanic (Day 2)
- [ ] Mobs and combat (Day 3)
- [ ] Weapons and shop (Day 4)
- [ ] Backpacks and pets (Day 5)
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

## Acceptance test (Day 1)

1. Connect Rojo in Studio and press Play.
2. Confirm the top bar appears showing "Аура: 0" and "Онлайн: 1".
3. Check Output for errors.
4. Stop and rejoin — data should load without errors (still 0 until Day 2 adds the click mechanic).
