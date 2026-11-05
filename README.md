# NewYearSimulator — Winter Academy

Roblox Luau project managed with Rojo 7.

This branch contains a playable vertical-slice foundation for the original Winter Academy simulator: academy environment, mentor collection, lightning training, server-authoritative monster combat, item drops, inventory and item selling.

## Project structure

- `src/shared/Config.luau` — zones, mentors, monster progression, combat balance, item definitions and drop pools.
- `src/server/Main.server.luau` — authoritative training, mentor purchases/equipment, combat, rewards, item sales and RemoteEvents.
- `src/server/DataService.luau` — compatible player persistence using the existing `NewYearSim_v1` DataStore.
- `src/server/WinterAcademy.server.luau` — generated academy, mentor gallery, training court and first combat arena.
- `src/client/Client.client.luau` — responsive HUD, animated panels, mentor/world/inventory/quest windows, combat feedback and reward popup.
- `default.project.json` — Rojo DataModel mapping.

## Run locally

From the repository root:

```bash
rokit install
rojo serve
```

Keep the terminal running while Roblox Studio is connected. In Roblox Studio, open the Rojo plugin and connect to the local server.

To build a place file without starting the live server:

```bash
rojo build -o /tmp/NewYearSimulator.rbxlx
```

## Roblox Studio setup

1. Publish a separate private test experience.
2. In **Game Settings → Security**, enable **Studio Access to API Services** for that test experience.
3. Connect Rojo, then run the place in Studio.
4. Confirm the player loads and existing data is preserved before testing any migration or reset.
5. Test the first vertical slice:
   - Train until the first-stage battle requirement is met.
   - Open **Наставники**, hire/equip a mentor, and confirm the lightning multiplier changes.
   - Start the fight, attack, and watch the enemy health bar.
   - Win the fight and confirm the reward popup appears.
   - Open **Инвентарь**, confirm the drop exists, sell one item, and confirm the Wins balance changes.
   - Stop and rejoin the test session to verify persistence.

## Important boundaries

- The existing DataStore name and player key format are intentionally preserved. New fields use defaults so older records can be loaded; test this against a separate test experience before production.
- The current 3D scene and mentor figures are original stylized constructions from Roblox Parts. They are a deliberate low-poly placeholder style, not imported hero-grade MeshPart assets. Replace or augment them with licensed original meshes when those assets are ready; do not invent asset IDs.
- This slice does not claim to include a complete pet system, Robux shop, crafting tree, full multi-world progression or production-ready monetization. Those require their own implementation and Roblox Creator Dashboard product IDs.
- Studio runtime behavior, DataStore access, combat feel and UI on physical mobile devices must be manually tested in Roblox Studio. A successful `rojo build` only verifies project mapping/build output; it does not prove runtime correctness.

## Vercel

Vercel can host web assets or APIs connected to this repository. It does not run the Roblox game server or publish a Roblox experience.
