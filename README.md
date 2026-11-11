# Aura Clicker

Roblox "+1" clicker simulator, managed with Rojo 7. Click to gain Aura,
fight mobs, buy weapons/backpacks/pets, rebirth for permanent
multipliers.

## Project structure

**Shared** (`ReplicatedStorage.Shared`)
- `src/shared/Config.luau` — all balance numbers: click/crit, zone & mobs, weapons, backpacks, pets, rebirth, sounds, remote names, default player data.
- `src/shared/Format.luau` — number formatting (`1.25K`, `3.4M`).

**Server** (`ServerScriptService`)
- `Main.server.luau` — entry point: starts services, leaderstats (Aura, Rebirths), passive income tick, autosave.
- `DataService.luau` — DataStore `AuraClicker_v1`: retries, never saves after a failed load, save on leave and on shutdown.
- `PlayerState.luau` — the economy: click power, Aura multiplier, income, spending currencies, syncing state to Player attributes.
- `ClickService.luau` — the КЛИК button (`ClickHit`).
- `MobService.luau` — builds `Workspace.AuraZone` at runtime, mobs, damage, rewards, respawn (`MobHit`).
- `ShopService.luau` — buy/equip weapons, backpacks, pets (`ShopRequest`).
- `RebirthService.luau` — rebirth (`RebirthRequest`).
- `Effects.luau`, `Remotes.luau`, `RateLimit.luau` — helpers.

**Client** (`StarterPlayerScripts`)
- `Client.client.luau` — entry point, requires the modules below.
- `Ui` (shared helpers, popups, toasts), `TopBar`, `ClickButton`, `Combat`, `Panels` (side menu + windows), `Shop`, `Cosmetics` (backpacks/pets on characters), `Rebirth`.

`default.project.json` — Rojo mapping. `StarterGui` is fully owned by Rojo (empty);
`Workspace` is not managed by Rojo: the zone and mobs are created by the server at runtime.

The server is the source of truth for every number: the client only asks
("I clicked", "I hit this mob", "buy this"), and the server checks
cooldowns, range, prices and ownership.

## Status — all 7 days done

- [x] Day 1 — Rojo structure, persistent data, top bar UI
- [x] Day 2 — click: +1 Aura, 10% crit x5, server cooldown, popups and sound
- [x] Day 3 — zone "Поляна Ауры", 4 mob types incl. boss, click damage, respawn, Aura + 💎 drops
- [x] Day 4 — shop with 4 weapons, buy/equip, damage multiplier
- [x] Day 5 — 3 backpacks (passive Aura/sec), 2 pets for 💎, visible on characters
- [x] Day 6 — rebirth (permanent multiplier), particles, sounds
- [x] Day 7 — data-safety fixes, balance pass, release checklist

## Balance (edit in `Config.luau`)

| | Item | Effect | Cost |
|---|---|---|---|
| Weapon | Палка / Деревянный меч / Железный меч / Катана Ауры | damage x1 / x3 / x10 / x35 | free / 100 / 1.2K / 12K Aura |
| Backpack | Мешочек / Ранец / Ранец Ауры | +2 / +10 / +50 Aura per sec | 300 / 3K / 25K Aura |
| Pet | Искорка / Дракончик Ауры | +50% / +150% all Aura | 10 / 60 💎 |
| Rebirth | — | Aura multiplier = 1 + rebirths | 50K × 3^rebirths Aura |

| Mob | HP | Aura | 💎 | Respawn |
|---|---|---|---|---|
| Слизень ×4 | 8 | 15 | 5% → 1 | 3 s |
| Гоблин ×3 | 40 | 80 | 15% → 1 | 4 s |
| Тень ×2 | 200 | 450 | 40% → 2 | 6 s |
| Страж Ауры (boss) | 2.5K | 6K | 100% → 5 | 45 s |

Every Aura gain (click, kill, backpack) is multiplied by pet × rebirth.
Everyone who hit a mob gets the full reward when it dies.

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

## Full playtest (acceptance)

Studio → Game Settings → Security → **Studio Access to API Services** must be on for saving.

1. Play. Output has no red errors. Top bar shows Aura / 💎 / online, a stats line shows damage and multiplier, left menu has Магазин / Питомцы / Ребёрт.
2. **Click button** (bottom middle): +1, ~10% golden `КРИТ! +5`, sound.
3. **Zone**: walk forward (~70 studs) to the purple disc "Поляна Ауры". Click a Слизень: `-1` popup, white flash, HP bar drops. Kill it: particles, `+15 ✨`, sometimes `+1 💎`. It respawns in 3 s.
4. Too far away (> 80 studs) → toast "Подойди ближе к мобу!"; nothing happens server-side.
5. **Shop**: buy Деревянный меч for 100 → equipped automatically, stats line shows `Урон: 3`, Слизень dies in 3 clicks. Equip Палка again → damage back to 1.
6. **Backpack**: buy Мешочек (300) → stats line shows `+2/сек`, Aura grows by itself; a box appears on your back.
7. **Pets**: farm 10 💎, buy Искорка → glowing pet follows you, multiplier shows `x1.5`.
8. **Rebirth** at 50K Aura: toast "Доступен ребёрт!", press the button twice → purple flash, Aura 0, weapons/backpacks reset, 💎 and pet kept, multiplier x2 (x3 with Искорка), Rebirths = 1 in the leaderboard.
9. Stop, Play again → Aura, 💎, items, pet, rebirths all restored.
10. Two players (Test → Clients and Servers → 2 players): both see each other's pets/backpacks; both hit one Гоблин → both get the reward.

## Release checklist

1. In Studio: **File → Publish to Roblox** (the place connected via Rojo).
2. Creator Dashboard → the experience → **Configure**: name "Aura Clicker", description, icon (512×512) and at least one thumbnail.
3. Game Settings → Security: **Enable Studio Access to API Services** (only needed for Studio tests; live servers always have DataStores).
4. Permissions → **Public**. Set max players (e.g. 12).
5. Join the live game from the website once and repeat steps 1–9 of the playtest.

Sounds use built-in `rbxasset://sounds/...` files; replace the IDs in
`Config.Sounds` with your own `rbxassetid://` uploads if you prefer.
