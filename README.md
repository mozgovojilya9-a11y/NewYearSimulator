# Aura Clicker — «Цитадель Ауры»

Roblox clicker with a dungeon, managed with Rojo 7. Click mobs to earn
**Aura**, upgrade weapons/backpacks/pets, push through 20 dungeon rooms
(a boss every 5) and rebirth at the altar for a permanent multiplier.

## Systems

| System | What it does | Code |
|---|---|---|
| Click | One `ClickHit(target)` remote for mobs and trainers. Server checks target, range (60 studs) and cooldown (0.1 s), rolls damage + 10% crit x5; every accepted click swings the equipped weapon (arm Motor6D tween + blade trail, seen by everyone). | `ClickService`, `EquipmentService`, client `Combat`, `Swing` |
| Hub «Цитадель Ауры» | Castle courtyard from bricks: chevrons spawn → trainer row → portal arch. 8 trainer platforms (x1…x250, Part-built objects, lock barriers with «Нужно N Ауры» / «Перерождение N», auto-click toggle), weapon alley (4 shop weapons + rotating unique stand with countdown), backpack alley, altar, workbench stall, wheel of fortune, pet egg, 2 leaderboards (OrderedDataStore), fountain, NPC, flags, torches, trees, bushes. | `HubGenerator`, `TrainerBuilder`, `HubService`, `LeaderboardService` |
| Dungeon runs | Each portal entry starts a NEW run from room 1 in the player's own lane (up to 16 lanes, 260 studs apart); only the current and next rooms exist. Biome rooms with tiled floors and corner lights, boss arenas ×1.7, private barrier with «0/3 врагов», stage and recommended damage (green/red for you). Death / Back / room 20 end the run → «Итоги забега». Best room = record. | `DungeonGenerator`, `DungeonRuns`, client `Zone`, `Windows/RunSummary` |
| Mobs | Block rigs with Humanoid that walk (MoveTo) to the player within 40 studs, telegraph (red flash 0.5 s) and hit; bosses ×2.5 with crown + ground slam (red warning circle). HP = recommended damage × 8 clicks (bosses × 50). Death = pop + Aura crystal; «E · Собрать» only, lost after 60 s. | `MobBuilder`, `MobAI`, `DungeonRuns`, client `Combat`, `MobFx` |
| Player | HP 100, out-of-combat regen only (default Health script replaced), health bar in the dungeon. | `src/character/Health`, `MobAI`, client `Hud` |
| Shop | 4 regular weapons, 4 backpacks, 2 pets for Aura; cards show rotating ViewportFrame models; equipped weapon in hand and backpack on the back. Unique weapons only at the hub stand. | `ShopService`, `EquipmentService`, client `Windows/Shop`, `Preview` |
| Engagement | Daily reward (7-day streak), wheel of fortune (free spin / 4 h: Aura, x2 boosts, egg), 3 daily quests, player level + XP bar (reward every 5 levels), timed x2 boosts with HUD timer, egg hatch animation. | `ProgressionService`, client `Windows/Reward`, `Hud` |
| Backpacks | Passive Aura/sec online + offline income on next join (50 %, up to 8 h). | `Main.server`, `PlayerState` |
| Pets | +25 % / +75 % to all Aura. Bought for Aura or dropped by bosses. Visible next to the player. | client `Cosmetics` |
| Rebirth | Altar prompt → window; needs room 20 cleared. Resets Aura, weapons, backpacks, dungeon progress; keeps pets. Multiplier = 1 + Rebirths × 0.1. | `RebirthService`, client `Windows/Rebirth` |
| Saving | DataStore `AuraClicker_v1`, retries, never saves after a failed load, save on leave and shutdown. | `DataService` |

The server is the source of truth for every number; the client only
sends intents and draws results. **Every balance number, color, size,
text and layout constant lives in `src/shared/Config.luau`.**

## Visual style

- **Art direction:** bright cartoon "brick" castle. Light lilac stone
  (`Theme.StoneA/StoneB`, studs on top, battlements on every wall),
  accents magenta `#FF3DB8`, cyan `#2EE6FF`, gold `#FFC93C`. Neon only
  on trims, portals, runes and crystals. Font: `FredokaOne` everywhere.
- **Lighting:** hub = clear day (ClockTime 14, bloom 0.35, saturation
  +0.15); dungeon = dark but readable (ambient not black), every room
  has 4 corner lights in its biome color. The client tweens between the
  two presets when `Zone` changes, with a short screen fade.
- **Biomes (5 rooms each):** Неоновые катакомбы (dark stone + green),
  Ледяной грот (ice + cyan), Лавовая кузня (dark red + orange), Бездна
  ауры (purple + gold). Boss barriers are magenta.
- **HUD:** no `IgnoreGuiInset`; the top-left 320×60 px stays empty for
  Roblox buttons; the player list is hidden. Top center: objective.
  Left: 2×3 menu grid with «!» badges, «Назад» below it in the dungeon.
  Bottom left: Aura / rebirths / pets. Bottom center: damage, player
  health (dungeon), stage progress, 4 quick weapon upgrades. Top right:
  settings and sound. Toasts on the right, 4 s. `UIScale` shrinks the
  whole HUD on phones.
- **Rarity colors** (shop cards, pedestals): Common grey, Rare blue,
  Epic purple, Legendary gold, Mythic animated rainbow.
- **Sounds:** only built-in `rbxasset://sounds/...` files. Empty slots
  in `Config.Sounds` are `TODO` for your own uploads — never guess IDs.

## Project structure

- `src/shared/` — `Config` (balance + all visual constants), `Format` (1.2K / 3.4M / 5.6B).
- `src/server/` — `Main.server` (startup, leaderstats Aura/Rebirths/Room, income, autosave), `Atmosphere` (base lighting), `WorldKit` (brick/floor/wall/sign/beam/HP-bar helpers), `HubGenerator`/`HubService`, `DungeonGenerator`/`DungeonService`, `MobBuilder`, `ClickService`, `ShopService`, `RebirthService`, `TravelService`, `PlayerState`, `DataService`, `Effects`, `Remotes`, `RateLimit`.
- `src/client/` — `Client.client` (entry), `Combat`, `Zone`, `Prompts` (custom ProximityPrompt look), `Cosmetics`, `ui/Style` (colors, font, helpers), `ui/Popups`, `ui/Buttons`, `ui/Hud`, `ui/Windows/{Window,Shop,Rebirth,Reward,Settings}`.
- `default.project.json` — Rojo mapping. Rojo fully owns `ReplicatedStorage`, `ReplicatedFirst`, `ServerStorage`, `Lighting`, `SoundService`, `StarterGui`, `StarterPack` and `StarterPlayer`: anything an older version of the place left there is deleted on the next sync (the plugin asks for confirmation once). `Workspace` is not managed, so the server wipes it at startup except `Config.World.Keep` (`SpawnLocation`, `Baseplate`) + Terrain, then generates `Workspace.Hub` and `Workspace.Dungeon`. Set `Config.World.PurgeWorkspace = false` to keep hand-placed builds.

## Run locally

```bash
rokit install
rojo serve
```

Studio → Rojo plugin → Connect. For saving in Studio: Game Settings →
Security → **Enable Studio Access to API Services**.

## Acceptance test in Studio

1. **Output** has no red/orange errors.
2. **Spawn** in the bright citadel courtyard; purple path with yellow chevrons leads to the portal arch «ПОДЗЕМЕЛЬЕ».
3. **HUD** — nothing under the Roblox buttons (top-left), player list hidden, objective «Войди в подземелье!» on top.
4. **Hub objects** work through E: trainer rings (click dummies: +Aura, x1/x3/x6 signs), weapon stand («Купить»), altar («Переродиться» → window), shop stall («Открыть» → Мастерская), egg («Открыть» → Питомцы).
5. **Portal**: walk into the disc → fade, dungeon lighting, «Назад [B]» appears; B returns to the hub.
6. **Room 1**: real mob models, HP bars don't overlap, barrier shows «0/3 врагов / Этап 1 / Рекомендуемый урон». Hitting: flash, knockback, number; death: pop + Aura crystal; touch or E collects (+N).
7. **Clear** the room: barrier fades, «Пройдено!», toast «Этап 1 пройден!», «Этап 1/20» at the bottom, objective «Иди дальше!».
8. **Room 5**: big boss in the round arena, magenta barrier with «БИТВА С БОССОМ», camera shake on death.
9. **Quick upgrades** (4 buttons bottom center) buy/equip weapons and spend Aura; the 4th (gold) points to the hub stand.
10. **Device Emulator** (phone): everything readable, HUD scaled down.

## Balance to verify by hand (unchanged in the redesign)

- `Dungeon.BaseHealth = 6`, `HealthGrowth = 1.45` → normal mob HP ≈ 6 (room 1), 170 (room 10), 4.8K (room 19); bosses ×15.
- Weapons: Палка x1 → Катана x35 (12K); uniques x120 (60K), x450 (300K), x1600 (1.5M).
- `Hub.TrainerRate = 0.25` × `TrainerMultipliers {1, 3, 6}` — the x3/x6 rings are new, check they don't beat room-1 mobs.
- `Rebirth.MultiplierPerRebirth = 0.1`, `Offline.Efficiency = 0.5`, `BossPetDrops` 25 % / 5 %.
