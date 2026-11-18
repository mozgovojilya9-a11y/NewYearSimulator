#!/usr/bin/env python3
"""
Pacing simulator for the action-RPG progression (gate runs).

Reads the numbers straight from src/shared/Config.luau (no second copy of
the balance) and plays a typical active player from zero, run after run:

  - a run = the hardest open gate location (Config.Gates.Locations: rank
    open by level and a cleared lower rank) whose last section the
    player's damage handles (Pacing.EntryShare x RecommendedDamage);
  - every section holds its group (Sections = { 5, 6, 4 }, elites by
    Config.Sections.Elites); an enemy takes HP / (damage x crit average)
    hits at Pacing.HitsPerSecond plus Pacing.EnemySeconds; a section adds
    Pacing.SectionSeconds; the boss takes BossClicksToKill hits x
    Pacing.BossOverhead;
  - every kill gives XP and credits (x Config.Sections rewards), drops by
    Config.Loot (tables by gate rank and enemy type), the boss chest gives
    BossItems + the grade bonus (grade by ParSeconds);
  - a better item is worn, the rest is salvaged into cores; between runs
    (Pacing.RunOverhead) the weapon and the armor are enhanced while the
    credits and cores last (chance and pity above +9 as in the game);
  - Damage = weapon damage (with enhance) x LevelMult(level) x Сила
    (Pacing.StrShare of the stat points).
Passes, boosts, quests, skills and artifacts are NOT counted. The drops
are random: the run uses a fixed seed, so the table is repeatable.

Usage:
  python3 tools/pacing.py            table + events (from Config)
  python3 tools/pacing.py --readme   also rewrites the table in README.md
  python3 tools/pacing.py --tune     suggests XpBase for Targets.Level at
                                     Targets.LevelMinute
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
        self.items = cfg["Items"]
        self.forge = cfg["Forge"]
        self.credits = cfg["Credits"]
        self.attrs = cfg["Attributes"]
        self.rarities = cfg["Rarities"]
        self.rarity_index = {r["Id"]: i + 1 for i, r in enumerate(self.rarities)}
        self.defs = cfg["Mobs"]["Defs"]
        self.roles = cfg["Enemies"]["Roles"]
        self.elite = cfg["Enemies"]["Elite"]
        self.sec = cfg["Sections"]
        self.gates = cfg["Gates"]
        self.locations = [l for l in self.gates["Locations"] if l.get("Ready") is not False]
        for l in self.locations:
            l["BossTier"] = l["Tier"] + len(l["Sections"]) * l["TierStep"]
        grades = cfg["Grades"]
        self.grades = [grades[k] for k in sorted(k for k in grades if isinstance(k, int))]

    # Config.RecommendedDamage (by tier)
    def recommended(self, tier):
        d = self.D
        if tier > d["LateFrom"]:
            value = d["RecommendedBase"] * d["RecommendedGrowth"] ** (d["LateFrom"] - 1) * d["LateGrowth"] ** (tier - d["LateFrom"])
        elif tier >= d["RampTo"]:
            value = d["RecommendedBase"] * d["RecommendedGrowth"] ** (tier - 1)
        else:
            target = d["RecommendedBase"] * d["RecommendedGrowth"] ** (d["RampTo"] - 1)
            a = (tier - 1) / (d["RampTo"] - 1)
            value = math.exp(math.log(d["RecommendedRoom1"]) * (1 - a) + math.log(target) * a)
        return max(1, math.floor(value))

    def mob_health(self, tier, boss, role="Melee", elite=False):
        if boss:
            return self.recommended(tier) * self.D["BossClicksToKill"]
        hp = self.recommended(tier) * self.D["ClicksToKill"] * self.roles[role]["Health"]
        return hp * (self.elite["Health"] if elite else 1)

    def xp_to_next(self, level):
        l = self.L
        late = l["LateGrowth"] ** (level - l["LateFrom"]) if level > l["LateFrom"] else 1
        return math.floor(l["XpBase"] * max(1, level) ** l["XpExponent"] * late)

    def level_mult(self, level):
        return 1 + (max(1, level) - 1) * self.S["DamagePerLevel"]

    def kill_credits(self, tier, boss):
        c = self.credits
        return max(1, math.floor(c["PerKill"] * c["Growth"] ** (max(1, tier) - 1) * (c["BossMultiplier"] if boss else 1)))

    # Shared.Items
    def weapon_damage(self, item):
        i = self.items
        base = i["Weapon"]["Base"] * i["Weapon"]["Growth"] ** item["L"] * i["RarityMult"][item["R"]] * item["Q"]
        return max(1, math.floor(base * (1 + self.forge["PerLevel"] * item["E"]) + 0.5))

    def armor_health(self, item):
        i = self.items
        a = i["Armor"]
        base = (a["HealthBase"] + a["HealthPerLevel"] * item["L"]) * i["RarityMult"][item["R"]] * item["Q"]
        if item["Slot"] == "Chest":
            base *= a["ChestMult"]
        return math.floor(base * (1 + self.forge["PerLevel"] * item["E"]) + 0.5)

    def score(self, item):
        if item is None:
            return 0
        return math.floor(item["L"] * self.items["ScoreRarity"][item["R"]] + self.items["ScorePerEnhance"] * item["E"] + 0.5)

    def enhance_cost(self, item):
        target = item["E"] + 1
        e = self.forge["Enhance"]
        credits = math.floor(e["Credits"] * (1 + item["L"] / 10) * e["Growth"] ** (target - 1) + 0.5)
        cores = math.ceil(target * e["CoresPerLevel"] * self.rarity_index[item["R"]] / 2)
        return credits, cores

    def enhance_chance(self, item):
        target = item["E"] + 1
        index = int(target - self.forge["ChanceFrom"])
        chances = self.forge["Chance"]
        base = chances[index] if 0 <= index < len(chances) else 1
        return min(1, base + (item.get("F", 0) * self.forge["Pity"] if base < 1 else 0))

    def salvage(self, item):
        return max(1, math.floor(self.forge["Salvage"]["Cores"][item["R"]] * (1 + item["L"] / 50) + 0.5))

    # LootService.RollRarity (luck 1)
    def roll_rarity(self, rng, rank, enemy, min_rarity=None):
        weights = self.loot["Tables"][rank][enemy]
        allowed = [r["Id"] for r in self.rarities if weights.get(r["Id"], 0) > 0]
        floor = 0
        if min_rarity:
            floor = min(self.rarity_index[min_rarity], self.rarity_index[allowed[-1]])
        pool = [(rid, weights[rid]) for rid in allowed if self.rarity_index[rid] >= floor]
        roll = rng.random() * sum(w for _, w in pool)
        for rid, w in pool:
            roll -= w
            if roll <= 0:
                return rid
        return pool[-1][0]

    def generate(self, rng, tier, rarity):
        i = self.items
        level = max(1, min(int(i["MaxLevel"]), int(tier * i["LevelPerRoom"]) + rng.randint(-int(i["LevelSpread"]), int(i["LevelSpread"]))))
        item = {"L": level, "R": rarity, "Q": round(i["Roll"][0] + (i["Roll"][1] - i["Roll"][0]) * rng.random(), 2), "E": 0}
        if rng.random() < i["WeaponShare"]:
            item["Slot"] = "Weapon"
            # own class OwnClassChance of the time, else one of three at random
            item["Usable"] = rng.random() < i["OwnClassChance"] + (1 - i["OwnClassChance"]) / 3
        else:
            item["Slot"] = rng.choice(["Helmet", "Chest", "Legs"])
            item["Usable"] = True
        return item

    def grade(self, seconds, par):
        for g in self.grades:
            t = g.get("Time")
            if t is None or seconds <= par * t:
                return g
        return self.grades[-1]


# ---------------------------------------------------------------------------
# Player simulation
# ---------------------------------------------------------------------------


class Player:
    def __init__(self, game, seed=1):
        import random
        self.g = game
        self.rng = random.Random(seed)
        self.t = 0.0
        self.level = 1
        self.xp = 0.0
        self.location = None
        self.cleared = set()
        self.runs = []  # (location id, seconds, level)
        # the starter weapon (Stick: damage 1)
        self.gear = {"Weapon": {"L": 1, "R": "Common", "Q": 0.55, "E": 0, "Slot": "Weapon", "Usable": True}, "Helmet": None, "Chest": None, "Legs": None}
        self.credits = 0
        self.cores = 0
        self.best_rarity = 1
        self.events = []
        self.snaps = []  # (time, level, location name, weapon text, gear score, damage)

    def strength(self):
        a = self.g.attrs
        points = (self.level - 1) * a["PointsPerLevel"] * self.g.P.get("StrShare", 0.6)
        return 1 + points * 0.01

    def damage(self):
        w = self.gear["Weapon"]
        return max(1, math.floor(self.g.weapon_damage(w) * self.g.level_mult(self.level) * self.strength()))

    def gear_score(self):
        return sum(self.g.score(i) for i in self.gear.values())

    def weapon_text(self):
        w = self.gear["Weapon"]
        names = {r["Id"]: r["Name"] for r in self.g.rarities}
        return "%s, ур. %d%s" % (names[w["R"]], w["L"], (" +%d" % w["E"]) if w["E"] else "")

    def snapshot(self):
        name = self.location["Name"] if self.location else "—"
        self.snaps.append((self.t, self.level, name, self.weapon_text(), self.gear_score(), self.damage()))

    def add_xp(self, amount):
        self.xp += amount
        while self.xp >= self.g.xp_to_next(self.level):
            self.xp -= self.g.xp_to_next(self.level)
            self.level += 1
            if self.level in (2, 3, 5) or self.level % 5 == 0:
                self.events.append((self.t, "level", self.level))

    def power(self, item):
        if item is None:
            return 0
        return self.g.weapon_damage(item) if item["Slot"] == "Weapon" else self.g.armor_health(item)

    def take(self, item):
        """A picked item: worn when it is better, else salvaged."""
        g = self.g
        ri = g.rarity_index[item["R"]]
        if ri > self.best_rarity and ri >= 3:
            self.best_rarity = ri
            self.events.append((self.t, "rarity", item["R"]))
        worn = self.gear[item["Slot"]]
        if item["Usable"] and self.power(item) > self.power(worn):
            if worn and not (item["Slot"] == "Weapon" and worn["L"] == 1 and worn["R"] == "Common"):
                self.cores += g.salvage(worn)
            self.gear[item["Slot"]] = item
        else:
            self.cores += g.salvage(item)

    def forge(self):
        """Between runs: enhance the weapon first, then the armor, while
        there are credits and cores (up to +9 freely, above with the chance)."""
        g = self.g
        for _ in range(60):
            best = None
            for slot in ("Weapon", "Chest", "Helmet", "Legs"):
                item = self.gear[slot]
                if not item or item["E"] >= g.forge["MaxEnhance"]:
                    continue
                credits, cores = g.enhance_cost(item)
                if credits <= self.credits * (1.0 if slot == "Weapon" else 0.5) and cores <= self.cores:
                    if best is None or item["E"] < best[0]["E"] or slot == "Weapon":
                        best = (item, credits, cores)
                        if slot == "Weapon":
                            break
            if not best:
                return
            item, credits, cores = best
            self.credits -= credits
            self.cores -= cores
            if self.rng.random() < g.enhance_chance(item):
                item["E"] += 1
                item["F"] = 0
                if item["Slot"] == "Weapon" and item["E"] in (5, 10, 15):
                    self.events.append((self.t, "enhance", item["E"]))
            else:
                item["F"] = item.get("F", 0) + 1

    def rank_open(self, rank):
        info = self.g.gates["RankInfo"][rank]
        if self.level < info["Level"]:
            return False
        need = info.get("Requires")
        return not need or any(l["Rank"] == need and l["Id"] in self.cleared for l in self.g.locations)

    def pick(self):
        """The hardest open location whose last section the damage handles."""
        g = self.g
        best = g.locations[0]
        for l in g.locations:
            last = l["Tier"] + (len(l["Sections"]) - 1) * l["TierStep"]
            if self.rank_open(l["Rank"]) and self.damage() >= g.P["EntryShare"] * g.recommended(last) and l["Tier"] >= best["Tier"]:
                best = l
        return best

    def kill(self, loc, tier, role, elite):
        g = self.g
        crit = g.S["CritChance"] * (g.S["CritDamage"] - 1)
        hits = g.mob_health(tier, False, role, elite) / (self.damage() * (1 + crit))
        self.t += hits / g.P["HitsPerSecond"] + g.P["EnemySeconds"]
        weight = g.sec["Reward"] * (g.sec["EliteReward"] if elite else g.sec["SwarmReward"] if role == "Swarm" else 1)
        self.add_xp(g.L["XpPerKill"] * tier * weight)
        self.credits += g.kill_credits(tier, False) * weight
        enemy = "Elite" if elite else "Normal"
        if self.rng.random() < g.loot["DropChance"][enemy]:
            self.take(g.generate(self.rng, tier, g.roll_rarity(self.rng, loc["Rank"], enemy)))

    def run(self):
        g = self.g
        loc = self.pick()
        if loc is not self.location:
            self.events.append((self.t, "location", loc["Name"]))
        self.location = loc
        start = self.t
        elites = g.sec["Elites"]
        for i, count in enumerate(loc["Sections"]):
            tier = loc["Tier"] + i * loc["TierStep"]
            self.t += g.P["SectionSeconds"]
            n_elite = int(elites[min(i, len(elites) - 1)])
            for k in range(int(count)):
                mob = g.defs[self.rng.choice(loc["Mobs"])]
                role = mob.get("Role", "Melee")
                elite = k < n_elite
                if elite and role in ("Swarm", "Healer"):
                    role = "Melee"
                if role == "Healer" and i == 0:
                    role = "Melee"
                self.kill(loc, tier, role, elite)
        # the boss
        tier = loc["BossTier"]
        crit = g.S["CritChance"] * (g.S["CritDamage"] - 1)
        hits = g.mob_health(tier, True) / (self.damage() * (1 + crit))
        self.t += hits / g.P["HitsPerSecond"] * g.P["BossOverhead"] + 3
        self.add_xp(g.L["XpPerBoss"] * tier)
        self.credits += g.kill_credits(tier, True)
        seconds = self.t - start
        grade = g.grade(seconds, loc["ParSeconds"])
        rank = loc["Rank"]
        for n in range(int(g.loot["BossItems"] + grade["Items"])):
            rarity = g.roll_rarity(self.rng, rank, "Boss", g.loot["BossMinRarity"][rank] if n == 0 else None)
            self.take(g.generate(self.rng, tier, rarity))
        self.runs.append((loc["Id"], seconds, self.level, grade["Id"]))
        self.cleared.add(loc["Id"])
        self.t += g.P["RunOverhead"]
        self.forge()
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
    """XpBase so the level at Targets.LevelMinute is Targets.Level. The
    tier curve (Dungeon.Recommended*) is set by hand from the item level
    math (drops are tier x LevelPerRoom, weapons x1.046 per item level);
    the report shows when each location is first entered so it can be
    checked against Targets.Tiers."""
    T = cfg["Pacing"]["Targets"]
    lo, hi = 1.0, 3000.0
    for _ in range(30):
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
    print("Targets (tier -> minute):", {int(k): v for k, v in T["Tiers"].items()})
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
    rows = ["| Минута | Уровень | Врата (локация забега) | Урон | Gear Score | Оружие |", "|---:|---:|---|---:|---:|---|"]
    for m in minutes:
        t, level, name, weapon, gs, dmg = state_at(p, m)
        rows.append("| %d | %d | %s | %s | %d | %s |" % (m, level, name, fmt(dmg), gs, weapon))
    table = "\n".join(rows)

    names = {r["Id"]: r["Name"] for r in cfg["Rarities"]}
    ev = ["| Событие | Минута |", "|---|---:|"]
    for t, kind, value in p.events:
        if kind == "location":
            ev.append("| Первый забег: %s | %.1f |" % (value, t / 60))
    for t, kind, value in p.events:
        if kind == "level":
            ev.append("| Уровень %d | %.1f |" % (value, t / 60))
    for t, kind, value in p.events:
        if kind == "rarity":
            ev.append("| Первый предмет редкости «%s» | %.1f |" % (names[value], t / 60))
        elif kind == "enhance":
            ev.append("| Оружие заточено до +%d | %.1f |" % (value, t / 60))
    # run length of each location (the first runs, the player at its level)
    first = {}
    for loc_id, seconds, level, grade in p.runs:
        first.setdefault(loc_id, []).append(seconds)
    for l in game.locations:
        if l["Id"] in first:
            runs = first[l["Id"]][:3]
            ev.append("| Забег «%s» (первые %d) | %.1f мин |" % (l["Name"], len(runs), sum(runs) / len(runs) / 60))
    events = "\n".join(ev)
    return table, events


def write_readme(table, events):
    text = open(README, encoding="utf-8").read()
    start, end = "<!-- pacing:start -->", "<!-- pacing:end -->"
    block = (
        start
        + "\n_Сгенерировано `python3 tools/pacing.py --readme` из `Config.luau`. "
        "Модель: активная игра забегами во Врата (самая сложная открытая локация, которую тянет урон): "
        "участки с группами врагов и босс; предметы падают по таблицам рангов Врат, "
        "лучшее надевается, остальное разбирается на ядра, оружие и броня затачиваются между забегами; "
        "60% очков характеристик идут в Силу. Без пассов, бустов, заданий, навыков и артефактов._\n\n"
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
