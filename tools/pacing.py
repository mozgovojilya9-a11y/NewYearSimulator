#!/usr/bin/env python3
"""
Pacing simulator for the action-RPG progression.

Reads the numbers straight from src/shared/Config.luau (no second copy of
the balance) and plays a typical active player from zero, run after run:

  - a run starts in room 1 and goes as deep as the player's damage allows
    (Damage >= RecommendedDamage(room)); a mob takes
    HP / (damage x crit average) hits at Pacing.HitsPerSecond, plus
    Pacing.MoveSeconds of walking, rooms add Pacing.RoomSeconds;
  - every kill gives XP (Config.Progression.Level), and materials:
    expected drops per kill with Config.Rarities / Config.Loot and the
    mob drop lists, picked like LootService (nearest lower rarity, else
    nearest higher);
  - between runs (Pacing.RunOverhead) the player crafts every recipe that
    is affordable and better than what is equipped;
  - Damage = weapon Damage x LevelMult(level) x armor set bonus.
Pets, passes, boosts, quests and skills are NOT counted.

Usage:
  python3 tools/pacing.py            table + events (from Config)
  python3 tools/pacing.py --readme   also rewrites the table in README.md
  python3 tools/pacing.py --tune     suggests XpBase and the room curve
                                     that hit Config.Pacing.Targets
"""

import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "shared", "Config.luau")
README = os.path.join(ROOT, "README.md")

# ---------------------------------------------------------------------------
# Tiny Luau table-literal reader (numbers, strings, booleans, nested tables;
# any other expression such as Color3.fromRGB(...) becomes None).
# ---------------------------------------------------------------------------


def strip_comments(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    out = []
    i = 0
    while i < len(src):
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < len(src) and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i : j + 1])
            i = j + 1
        elif src.startswith("--", i):
            j = src.find("\n", i)
            i = len(src) if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


class Reader:
    def __init__(self, text, pos):
        self.t = text
        self.i = pos

    def peek(self):
        while self.i < len(self.t) and self.t[self.i].isspace():
            self.i += 1
        return self.t[self.i] if self.i < len(self.t) else ""

    def table(self):
        assert self.peek() == "{"
        self.i += 1
        arr, rec = [], {}
        while True:
            if self.peek() == "}":
                self.i += 1
                break
            m = re.match(r"([A-Za-z_]\w*)\s*=(?!=)", self.t[self.i :])
            m2 = re.match(r'\[\s*"([^"]*)"\s*\]\s*=', self.t[self.i :])
            if m:
                self.i += m.end()
                rec[m.group(1)] = self.value()
            elif m2:
                self.i += m2.end()
                rec[m2.group(1)] = self.value()
            else:
                arr.append(self.value())
            if self.peek() in ",;":
                self.i += 1
        if rec and arr:
            for k, v in enumerate(arr):
                rec[k + 1] = v
            return rec
        return rec if rec else arr

    def value(self):
        c = self.peek()
        if c == "{":
            return self.table()
        if c in "\"'":
            j = self.t.index(c, self.i + 1)
            s = self.t[self.i + 1 : j]
            self.i = j + 1
            return s
        m = re.match(r"-?\d+(\.\d+)?([eE][+-]?\d+)?", self.t[self.i :])
        if m and not re.match(r"[\w.]", self.t[self.i + m.end() : self.i + m.end() + 1] or " "):
            self.i += m.end()
            return float(m.group(0))
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if self.t.startswith(word, self.i) and not re.match(r"\w", self.t[self.i + len(word)]):
                self.i += len(word)
                return val
        depth = 0
        while self.i < len(self.t):
            ch = self.t[self.i]
            if ch in "({[":
                depth += 1
            elif ch in ")}]":
                if depth == 0:
                    break
                depth -= 1
            elif ch in ",;" and depth == 0:
                break
            self.i += 1
        return None


def load_config():
    src = strip_comments(open(CONFIG, encoding="utf-8").read())
    cfg = {}
    for m in re.finditer(r"^Config\.(\w+)\s*=\s*\{", src, re.M):
        cfg[m.group(1)] = Reader(src, m.end() - 1).table()
    return cfg


# ---------------------------------------------------------------------------
# Game formulas (mirror of Config.luau / LootService)
# ---------------------------------------------------------------------------


class Game:
    def __init__(self, cfg):
        self.cfg = cfg
        self.D = cfg["Dungeon"]
        self.L = cfg["Progression"]["Level"]
        self.S = cfg["Stats"]
        self.P = cfg["Pacing"]
        self.loot = cfg["Loot"]
        self.rarities = cfg["Rarities"]
        self.rarity_index = {r["Id"]: i + 1 for i, r in enumerate(self.rarities)}
        self.materials = {m["Id"]: m for m in cfg["Materials"]}
        self.weapons = {w["Id"]: w for w in cfg["Weapons"]}
        self.sets = cfg["ArmorSets"]
        self.recipes = cfg["Recipes"]
        self.mobs = cfg["Mobs"]
        self.armor = {}
        for set_id, st in self.sets.items():
            for slot in ("Helmet", "Chest", "Legs"):
                self.armor[set_id + slot] = {
                    "Id": set_id + slot, "Set": set_id, "Slot": slot,
                    "Health": math.floor(st["Health"] * 1.5) if slot == "Chest" else st["Health"],
                    "ItemLevel": st["ItemLevel"],
                }
        self.per_kill = {}  # (biome, boss) -> {materialId: expected count}

    # Config.RecommendedDamage
    def recommended(self, room):
        d = self.D
        if room > d["LateFrom"]:
            value = d["RecommendedBase"] * d["RecommendedGrowth"] ** (d["LateFrom"] - 1) * d["LateGrowth"] ** (room - d["LateFrom"])
        elif room >= d["RampTo"]:
            value = d["RecommendedBase"] * d["RecommendedGrowth"] ** (room - 1)
        else:
            target = d["RecommendedBase"] * d["RecommendedGrowth"] ** (d["RampTo"] - 1)
            a = (room - 1) / (d["RampTo"] - 1)
            value = math.exp(math.log(d["RecommendedRoom1"]) * (1 - a) + math.log(target) * a)
        return max(1, math.floor(value))

    def mob_health(self, room, boss):
        return self.recommended(room) * (self.D["BossClicksToKill"] if boss else self.D["ClicksToKill"])

    def is_boss(self, room):
        return room % self.D["BossEvery"] == 0

    def biome(self, room):
        return min(len(self.mobs["Biomes"]), math.ceil(room / self.D["BossEvery"]))

    def xp_to_next(self, level):
        return math.floor(self.L["XpBase"] * max(1, level) ** self.L["XpExponent"])

    def level_mult(self, level):
        return 1 + (max(1, level) - 1) * self.S["DamagePerLevel"]

    def item_level(self, item):
        if item is None:
            return 0
        if item.get("ItemLevel"):
            return item["ItemLevel"]
        return math.floor(1 + self.cfg["ItemLevel"]["WeaponK"] * math.log10(max(1, item["Damage"])))

    # Expected materials of one kill (LootService.rollRarity + pickMaterial)
    def materials_per_kill(self, room):
        boss = self.is_boss(room)
        key = (self.biome(room), boss)
        if key in self.per_kill:
            return self.per_kill[key]
        biome = self.mobs["Biomes"][key[0] - 1]
        kinds = [biome["Boss"]] if boss else biome["Kinds"]
        luck = self.loot["BossLuck"] if boss else 1
        luck_from = self.rarity_index[self.loot["LuckFrom"]]
        weights = []
        for i, r in enumerate(self.rarities):
            weights.append(r["Chance"] * (luck if i + 1 >= luck_from else 1))
        total = sum(weights)
        probs = [w / total for w in weights]
        drops = self.loot["BossDrops"] if boss else 1 + self.loot["ExtraDropChance"]
        result = {}
        for kind in kinds:
            by_rarity = {}
            for mid in self.mobs["Defs"][kind]["Drops"]:
                by_rarity.setdefault(self.rarity_index[self.materials[mid]["Rarity"]], []).append(mid)
            for ri, p in enumerate(probs, start=1):
                chosen = None
                for j in list(range(ri, 0, -1)) + list(range(ri + 1, len(self.rarities) + 1)):
                    if j in by_rarity:
                        chosen = by_rarity[j]
                        break
                if not chosen:
                    continue
                for mid in chosen:
                    result[mid] = result.get(mid, 0) + p * drops / len(chosen) / len(kinds)
        self.per_kill[key] = result
        return result


# ---------------------------------------------------------------------------
# Player simulation
# ---------------------------------------------------------------------------


class Player:
    def __init__(self, game):
        self.g = game
        self.t = 0.0
        self.level = 1
        self.xp = 0.0
        self.record = 0
        self.weapon = game.weapons["Stick"]
        self.armor = {"Helmet": None, "Chest": None, "Legs": None}
        self.mats = {}
        self.owned = set(["Stick"])
        self.events = []
        self.snaps = []  # (time, level, record, weapon, gear score, damage)

    def set_bonus(self):
        sets = {a["Set"] for a in self.armor.values() if a}
        if len(sets) == 1 and all(self.armor.values()):
            return self.g.sets[sets.pop()]["Bonus"]
        return 0

    def damage(self):
        return max(1, math.floor(self.weapon["Damage"] * self.g.level_mult(self.level) * (1 + self.set_bonus())))

    def gear_score(self):
        return self.g.item_level(self.weapon) + sum(self.g.item_level(a) for a in self.armor.values())

    def snapshot(self):
        self.snaps.append((self.t, self.level, self.record, self.weapon["Id"], self.gear_score(), self.damage()))

    def add_xp(self, amount):
        self.xp += amount
        while self.xp >= self.g.xp_to_next(self.level):
            self.xp -= self.g.xp_to_next(self.level)
            self.level += 1
            if self.level % 10 == 0:
                self.events.append((self.t, "level", self.level))

    def craft(self):
        """Best affordable weapon; armor a whole set at a time (so the set
        bonus is never lost by swapping one piece)."""
        recipes = {r["Id"]: r for r in self.g.recipes}
        crafted = True
        while crafted:
            crafted = False
            for r in self.g.recipes:
                if r["Kind"] != "Weapon" or r["Id"] in self.owned:
                    continue
                item = self.g.weapons[r["Id"]]
                if item["Damage"] <= self.weapon["Damage"]:
                    continue
                if any(self.mats.get(m, 0) < n for m, n in r["Materials"].items()):
                    continue
                for m, n in r["Materials"].items():
                    self.mats[m] -= n
                self.owned.add(r["Id"])
                self.weapon = item
                self.events.append((self.t, "craft", r["Id"]))
                crafted = True
            current = next(iter({a["Set"] for a in self.armor.values() if a}), None)
            order = [k for k, v in self.g.sets.items() if not v.get("Robux")]
            for set_id in order:
                if current and self.g.sets[set_id]["ItemLevel"] <= self.g.sets[current]["ItemLevel"]:
                    continue
                pieces = [recipes.get(set_id + slot) for slot in ("Helmet", "Chest", "Legs")]
                if None in pieces:
                    continue
                need = {}
                for r in pieces:
                    for m, n in r["Materials"].items():
                        need[m] = need.get(m, 0) + n
                if any(self.mats.get(m, 0) < n for m, n in need.items()):
                    continue
                for m, n in need.items():
                    self.mats[m] -= n
                for r in pieces:
                    self.owned.add(r["Id"])
                    self.armor[self.g.armor[r["Id"]]["Slot"]] = self.g.armor[r["Id"]]
                self.events.append((self.t, "armor", set_id))
                crafted = True
                break

    def kill(self, room):
        g = self.g
        boss = g.is_boss(room)
        crit = g.S["CritChance"] * (g.S["CritDamage"] - 1)
        hits = g.mob_health(room, boss) / (self.damage() * (1 + crit))
        self.t += hits / g.P["HitsPerSecond"] + g.P["MoveSeconds"]
        self.add_xp((g.L["XpPerBoss"] if boss else g.L["XpPerKill"]) * room)
        for m, n in g.materials_per_kill(room).items():
            self.mats[m] = self.mats.get(m, 0) + n

    def run(self):
        g = self.g
        room = 1
        mobs = (g.D["MobsMin"] + g.D["MobsMax"]) / 2
        while room <= g.D["Rooms"] and self.damage() >= g.recommended(room):
            count = 1 if g.is_boss(room) else mobs
            whole = int(count)
            for _ in range(whole):
                self.kill(room)
            if count > whole:  # fractional mob: its share of time / rewards
                t0, xp0, mats0 = self.t, self.xp, dict(self.mats)
                self.kill(room)
                frac = count - whole
                self.t = t0 + (self.t - t0) * frac
            self.t += g.P["RoomSeconds"]
            if room > self.record:
                self.record = room
                if room % 5 == 0 or room == 1:
                    self.events.append((self.t, "stage", room))
            room += 1
        self.t += g.P["RunOverhead"]
        self.craft()
        self.snapshot()


def simulate(game, minutes):
    p = Player(game)
    p.snapshot()
    while p.t < minutes * 60:
        before = p.t
        p.run()
        if p.t == before:
            break
    return p


def state_at(p, minute):
    best = p.snaps[0]
    for snap in p.snaps:
        if snap[0] <= minute * 60:
            best = snap
    return best


# ---------------------------------------------------------------------------
# Tuning
# ---------------------------------------------------------------------------


def tune(cfg):
    T = cfg["Pacing"]["Targets"]
    D = cfg["Dungeon"]
    stages = sorted((int(k), v) for k, v in T["Stages"].items())
    for _ in range(12):
        game = Game(cfg)
        # 1) room curve through the damage the player has right before the
        #    target minute of each stage (the "typical gear" of that moment)
        p = simulate(game, stages[-1][1] + 5)
        points = []
        room1 = None
        late = None
        for stage, minute in stages:
            dmg = state_at(p, minute)[5]
            if stage < D["RampTo"]:
                room1 = dmg
            elif stage > D["LateFrom"]:
                late = (stage, dmg)
            else:
                points.append((stage, math.log(dmg)))
        n = len(points)
        mx = sum(x for x, _ in points) / n
        my = sum(y for _, y in points) / n
        slope = sum((x - mx) * (y - my) for x, y in points) / sum((x - mx) ** 2 for x, _ in points)
        intercept = my - slope * mx
        D["RecommendedGrowth"] = round(math.exp(slope), 3)
        D["RecommendedBase"] = round(math.exp(intercept + slope), 2)
        if room1:
            D["RecommendedRoom1"] = max(1, room1)
        if late:
            at_late = D["RecommendedBase"] * D["RecommendedGrowth"] ** (D["LateFrom"] - 1)
            D["LateGrowth"] = round((late[1] / at_late) ** (1 / (late[0] - D["LateFrom"])), 3)
        # 2) XpBase so the level at the target minute matches
        lo, hi = 1.0, 2000.0
        for _ in range(25):
            mid = (lo + hi) / 2
            cfg["Progression"]["Level"]["XpBase"] = mid
            p = simulate(Game(cfg), T["LevelMinute"])
            if state_at(p, T["LevelMinute"])[1] > T["Level"]:
                lo = mid
            else:
                hi = mid
        cfg["Progression"]["Level"]["XpBase"] = round(hi, 1)
    print("Suggested Config numbers:")
    print("  Progression.Level.XpBase =", cfg["Progression"]["Level"]["XpBase"])
    print("  Dungeon.RecommendedRoom1 =", D["RecommendedRoom1"])
    print("  Dungeon.RecommendedBase =", D["RecommendedBase"])
    print("  Dungeon.RecommendedGrowth =", D["RecommendedGrowth"])
    print("  Dungeon.LateGrowth =", D["LateGrowth"])
    return cfg


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


def fmt(n):
    n = float(n)
    for div, suf in ((1e9, "B"), (1e6, "M"), (1e3, "K")):
        if n >= div:
            v = n / div
            return ("%.0f" if v >= 100 else "%.1f" if v >= 10 else "%.2f") % v + suf
    return "%d" % n


def report(cfg):
    game = Game(cfg)
    minutes = [int(m) for m in cfg["Pacing"]["ReportMinutes"]]
    p = simulate(game, minutes[-1])
    names = {w["Id"]: w["Id"] for w in cfg["Weapons"]}
    rows = ["| Минута | Уровень | Этап (рекорд) | Урон | Рек. урон следующего этапа | Gear Score | Оружие |", "|---:|---:|---:|---:|---:|---:|---|"]
    for m in minutes:
        t, level, record, weapon, gs, dmg = state_at(p, m)
        nxt = game.recommended(min(game.D["Rooms"], record + 1))
        rows.append("| %d | %d | %d | %s | %s | %d | %s |" % (m, level, record, fmt(dmg), fmt(nxt), gs, names[weapon]))
    table = "\n".join(rows)

    ev = ["| Событие | Минута |", "|---|---:|"]
    for t, kind, value in p.events:
        if kind == "stage":
            ev.append("| Этап %d (рек. урон %s) | %.1f |" % (value, fmt(game.recommended(value)), t / 60))
    for t, kind, value in p.events:
        if kind == "level":
            ev.append("| Уровень %d | %.1f |" % (value, t / 60))
    for t, kind, value in p.events:
        if kind == "armor":
            ev.append("| Скрафчен сет брони: %s (ур. предмета %d) | %.1f |" % (value, game.sets[value]["ItemLevel"], t / 60))
        elif kind == "craft" and value in game.weapons:
            ev.append("| Скрафчено: %s (урон %d, ур. предмета %d) | %.1f |" % (value, game.weapons[value]["Damage"], game.item_level(game.weapons[value]), t / 60))
    events = "\n".join(ev)
    return table, events


def write_readme(table, events):
    text = open(README, encoding="utf-8").read()
    start, end = "<!-- pacing:start -->", "<!-- pacing:end -->"
    block = (
        start
        + "\n_Сгенерировано `python3 tools/pacing.py --readme` из `Config.luau`. "
        "Модель: активная игра забегами от 1-й комнаты, крафт лучшего доступного снаряжения; "
        "без питомцев, пассов, бустов, заданий и навыков._\n\n"
        + table + "\n\n" + events + "\n" + end
    )
    if start in text:
        text = re.sub(re.escape(start) + r".*?" + re.escape(end), lambda _: block, text, flags=re.S)
    else:
        text = text.rstrip() + "\n\n## Темп прокачки\n\n" + block + "\n"
    open(README, "w", encoding="utf-8").write(text)


def main():
    cfg = load_config()
    if "--tune" in sys.argv:
        cfg = tune(cfg)
    table, events = report(cfg)
    print(table)
    print()
    print(events)
    if "--readme" in sys.argv:
        write_readme(table, events)
        print("\nREADME.md updated.")


if __name__ == "__main__":
    main()
