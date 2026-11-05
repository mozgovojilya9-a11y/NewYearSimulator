# NewYearSimulator

Roblox Luau project managed with Rojo.

## Project structure

- `src/shared/Config.luau` — game balance, zones, rebirths and heroes.
- `src/server/Main.server.luau` — server-authoritative game logic.
- `src/server/DataService.luau` — player data persistence.
- `src/client/Client.client.luau` — client UI and input.
- `default.project.json` — Rojo DataModel mapping.

## Roblox Studio

Install Rojo and the Rojo Studio plugin, run `rojo serve` in this repository, then connect from the plugin in Roblox Studio.

Enable Studio API Services for DataStore testing in a separate test experience before production.

## Vercel

Vercel is linked to this repository for repository-connected builds/previews. It hosts only web assets and APIs; it does not run the Roblox game server or publish a Roblox experience. The game itself is built and published through Roblox Studio/Rojo.
