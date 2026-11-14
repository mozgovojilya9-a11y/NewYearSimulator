#!/usr/bin/env python3
"""
Pacing simulator for Aura Clicker.

Reads the numbers straight from src/shared/Config.luau (no second copy of
the balance) and simulates a player from zero, second by second, using the
same formulas as the game:

  Aura per second (training share of the time)
      = TrainerTickBase x BaseAura(level) x weapon TrainingMult
        x RebirthMultiplier(rebirths) x trainer multiplier
        x (1 / TrainerTickInterval + clicksPerSecond x TrainerClickBonus)
  Damage = weapon Damage x PowerMult(Aura)
  A room r is cleared when Damage >= RecommendedDamage(r).
  Rebirth as soon as Aura >= RebirthAura(rebirths).

Player model (Config.Pacing): active play = ActiveCps clicks per second,
TrainShare of the time on the best trainer, the rest in the dungeon
(KillsPerMinute kills of the record room -> XP). The weapon follows the
record room (Config.Pacing.Weapons: what can be crafted by then). Armor,
pets, boosts and passes are NOT counted: the real game is a bit faster.

Usage:
  python3 tools/pacing.py            table + events (from Config)
  python3 tools/pacing.py --readme   also rewrites the table in README.md
  python3 tools/pacing.py --tune     suggests Config numbers that hit
                                     Config.Pacing.Targets
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

    def ws(self):
        while self.i < len(self.t) and self.t[self.i].isspace():
            self.i += 1

    def peek(self):
        self.ws()
        return self.t[self.i] if self.i < len(self.t) else ""

    def table(self):
        assert self.peek() == "{"
        self.i += 1
        arr, rec = [], {}
        while True:
            c = self.peek()
            if c == "}":
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
        m = re.match(r"-?\d+(\.\d+)?(e[+-]?\d+)?", self.t[self.i :], re.I)
        if m and not re.match(r"[\w.]", self.t[self.i + m.end() : self.i + m.end() + 1] or " "):
            self.i += m.end()
            v = float(m.group(0))
            return int(v) if v.is_integer() and "." not in m.group(0) and "e" not in m.group(0).lower() else v
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if self.t.startswith(word, self.i) and not re.match(r"\w", self.t[self.i + len(word)]):
                self.i += len(word)
                return val
        # any other expression: skip to the next , or } at this depth
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
    for m in re.finditer(r"^Config\.(\w+)\s*=\s*(-?[\d.]+)\s*$", src, re.M):
        cfg[m.group(1)] = float(m.group(2))
    return cfg


# ---------------------------------------------------------------------------
# Formulas (mirror of Config.luau functions)
# ---------------------------------------------------------------------------


class Game:
    def __init__(self, cfg):
        self.cfg = cfg
        self.A = cfg["Aura"]
        self.D = cfg["Damage"]
        self.R = cfg["Rebirth"]
        self.L = cfg["Progression"]["Level"]
        self.dungeon = cfg["Dungeon"]
        self.P = cfg["Pacing"]
        self.weapons = {w["Id"]: w for w in cfg["Weapons"]}
        self.trainers = [t for t in cfg["Trainers"] if not t.get("Pass")]
        self.extra = 1  # extra Aura multiplier (x2 pass scenario)

    def base_aura(self, level):
        return self.A["LevelGrowth"] ** (max(1, level) - 1)

    def power_mult(self, aura):
        return 1 + (max(0, aura) / self.D["PowerScale"]) ** self.D["PowerExponent"]

    def rebirth_mult(self, n):
        return self.R["MultiplierBase"] ** n

    def rebirth_aura(self, done):
        costs = self.R["Costs"]
        n = done + 1
        if n <= len(costs):
            return costs[n - 1]
        return costs[-1] * self.R["LateGrowth"] ** (n - len(costs))

    def xp_to_next(self, level):
        return math.floor(self.L["XpBase"] * max(1, level) ** self.L["XpExponent"])

    def recommended(self, room):
        d = self.dungeon
        if room >= d["RampTo"]:
            value = d["RecommendedBase"] * d["RecommendedGrowth"] ** (room - 1)
        else:
            target = d["RecommendedBase"] * d["RecommendedGrowth"] ** (d["RampTo"] - 1)
            a = (room - 1) / (d["RampTo"] - 1)
            value = math.exp(math.log(d["RecommendedRoom1"]) * (1 - a) + math.log(target) * a)
        return max(1, math.floor(value))

    def weapon_for(self, stage):
        best = "Stick"
        for entry in self.P["Weapons"]:
            if stage >= entry["Stage"]:
                best = entry["Id"]
        return self.weapons[best]


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------


class State:
    def __init__(self):
        self.t = 0
        self.aura = 0.0
        self.rebirths = 0
        self.level = 1
        self.xp = 0.0
        self.stage = 0
        self.unlocked = {"1"}
        self.events = []


def best_trainer(game, s):
    best = None
    for tr in game.trainers:
        if tr["Id"] in s.unlocked and (best is None or tr["Multiplier"] > best["Multiplier"]):
            best = tr
    return best


def step(game, s, cps, train_share, dungeon=True, hooks=None):
    """Advance one second. hooks (tuning) may force thresholds / costs."""
    A, L, P = game.A, game.L, game.P
    weapon = game.weapon_for(s.stage)
    trainer = best_trainer(game, s)
    gain = A["TrainerTickBase"] * game.base_aura(s.level) * weapon.get("TrainingMult", 1) * game.rebirth_mult(s.rebirths)
    per_second = gain * trainer["Multiplier"] * (1 / A["TrainerTickInterval"] + cps * A["TrainerClickBonus"])
    s.aura += per_second * train_share * game.extra
    s.t += 1

    # XP: a little for training, kills of the record room in the dungeon
    s.xp += train_share * L["TrainingXp"] / (L["TrainingXpTicks"] * A["TrainerTickInterval"])
    if dungeon:
        s.xp += (1 - train_share) * P["KillsPerMinute"] / 60 * L["XpPerKill"] * max(1, s.stage)
    while s.xp >= game.xp_to_next(s.level):
        s.xp -= game.xp_to_next(s.level)
        s.level += 1
        if s.level % 5 == 0:
            s.events.append((s.t, "level", s.level))

    # Trainers (Aura thresholds are remembered forever; rebirth-gated)
    for tr in game.trainers:
        if tr["Id"] in s.unlocked:
            continue
        ok = False
        if hooks and tr["Id"] in hooks.get("trainer_at", {}):
            ok = s.t >= hooks["trainer_at"][tr["Id"]]
            if ok:
                hooks.setdefault("trainer_aura", {})[tr["Id"]] = s.aura
        elif tr.get("Rebirths") is not None:
            ok = s.rebirths >= tr["Rebirths"]
        elif tr.get("Aura") is not None:
            ok = s.aura >= tr["Aura"]
        else:
            ok = True
        if ok:
            s.unlocked.add(tr["Id"])
            s.events.append((s.t, "trainer", "%s x%s" % (tr["Name"], tr["Multiplier"])))

    # Dungeon record: clear rooms while damage is enough
    if dungeon:
        damage = weapon["Damage"] * game.power_mult(s.aura)
        while s.stage < game.dungeon["Rooms"] and damage >= game.recommended(s.stage + 1):
            s.stage += 1
            if s.stage % 5 == 0:
                s.events.append((s.t, "stage", s.stage))
            weapon = game.weapon_for(s.stage)
            damage = weapon["Damage"] * game.power_mult(s.aura)

    # Rebirth
    n = s.rebirths + 1
    forced = hooks and n in hooks.get("rebirth_at", {})
    if (forced and s.t >= hooks["rebirth_at"][n]) or (not forced and s.aura >= game.rebirth_aura(s.rebirths)):
        if forced:
            hooks.setdefault("rebirth_aura", {})[n] = s.aura
        s.rebirths += 1
        s.aura = 0.0
        s.events.append((s.t, "rebirth", s.rebirths))


def simulate(game, minutes, cps=None, train_share=None, dungeon=True, hooks=None, snapshot_every=None):
    P = game.P
    cps = P["ActiveCps"] if cps is None else cps
    train_share = P["TrainShare"] if train_share is None else train_share
    s = State()
    snaps = []
    for _ in range(int(minutes * 60)):
        step(game, s, cps, train_share, dungeon, hooks)
        if snapshot_every and s.t % (snapshot_every * 60) == 0:
            snaps.append((s.t // 60, s.rebirths, s.level, s.stage, best_trainer(game, s), s.aura))
    return s, snaps


# ---------------------------------------------------------------------------
# Tuning: derive thresholds / costs that hit Config.Pacing.Targets
# ---------------------------------------------------------------------------


def nice(x):
    """Round to 2 significant digits (1234 -> 1200)."""
    if x <= 0:
        return 0
    e = 10 ** (math.floor(math.log10(x)) - 1)
    return int(round(x / e) * e)


def tune(cfg):
    T = cfg["Pacing"]["Targets"]
    game = Game(cfg)
    rebirth_times = [m * 60 for m in T["Rebirths"]]
    trainer_times = {k: v * 60 for k, v in T["Trainers"].items()}

    for _ in range(6):
        # 1) trainer thresholds + rebirth costs at the target minutes
        hooks = {"trainer_at": dict(trainer_times), "rebirth_at": {i + 1: t for i, t in enumerate(rebirth_times)}}
        simulate(game, rebirth_times[-1] / 60 + 1, hooks=hooks)
        for tid, aura in hooks["trainer_aura"].items():
            for tr in cfg["Trainers"]:
                if tr["Id"] == tid:
                    tr["Aura"] = nice(aura)
        costs = [nice(hooks["rebirth_aura"][i + 1]) for i in range(len(rebirth_times))]
        early = T["EarlyRebirths"]
        cfg["Rebirth"]["Costs"] = costs[:early]
        # late growth: geometric fit of the late costs
        late = costs[early - 1 :]
        ratios = [late[i + 1] / late[i] for i in range(len(late) - 1)]
        cfg["Rebirth"]["LateGrowth"] = round(math.exp(sum(math.log(r) for r in ratios) / len(ratios)), 2)
        game = Game(cfg)

        # 2) XpBase so the level at the target minute matches
        lo, hi = 1.0, 2000.0
        for _ in range(30):
            mid = (lo + hi) / 2
            cfg["Progression"]["Level"]["XpBase"] = mid
            s, _ = simulate(Game(cfg), T["LevelMinute"])
            if s.level > T["Level"]:
                lo = mid
            else:
                hi = mid
        cfg["Progression"]["Level"]["XpBase"] = round(hi)
        game = Game(cfg)

        # 3) Recommended damage: fit base x growth^(r-1) through the peak
        #    damage the player has at the target minute of each stage
        points = []
        room1 = None
        for stage, minute in T["Stages"].items():
            stage = int(stage)
            if stage < cfg["Dungeon"]["RampTo"]:
                s, _ = simulate(game, minute)
                room1 = max(1, math.floor(game.weapon_for(0)["Damage"] * game.power_mult(s.aura)))
                continue
            s = State()
            peak = 0
            for _ in range(int(minute * 60)):
                step(game, s, game.P["ActiveCps"], game.P["TrainShare"])
                w = game.weapon_for(stage - 1)
                peak = max(peak, w["Damage"] * game.power_mult(s.aura))
            points.append((stage, math.log(peak)))
        n = len(points)
        mx = sum(p[0] for p in points) / n
        my = sum(p[1] for p in points) / n
        slope = sum((p[0] - mx) * (p[1] - my) for p in points) / sum((p[0] - mx) ** 2 for p in points)
        intercept = my - slope * mx
        cfg["Dungeon"]["RecommendedGrowth"] = round(math.exp(slope), 3)
        cfg["Dungeon"]["RecommendedBase"] = round(math.exp(intercept + slope), 2)
        if room1:
            cfg["Dungeon"]["RecommendedRoom1"] = room1
        game = Game(cfg)

    print("Suggested Config numbers:")
    print("  Trainers Aura:", {t["Id"]: t.get("Aura") for t in cfg["Trainers"] if t.get("Aura")})
    print("  Rebirth.Costs =", cfg["Rebirth"]["Costs"])
    print("  Rebirth.LateGrowth =", cfg["Rebirth"]["LateGrowth"])
    print("  Level.XpBase =", cfg["Progression"]["Level"]["XpBase"])
    print("  Dungeon.RecommendedBase =", cfg["Dungeon"]["RecommendedBase"])
    print("  Dungeon.RecommendedGrowth =", cfg["Dungeon"]["RecommendedGrowth"])
    print("  Dungeon.RecommendedRoom1 =", cfg["Dungeon"]["RecommendedRoom1"])
    return cfg


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


def fmt(n):
    n = float(n)
    for div, suf in ((1e15, "Qa"), (1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if n >= div:
            v = n / div
            return ("%.0f" if v >= 100 else "%.1f" if v >= 10 else "%.2f") % v + suf
    return "%d" % n


def report(cfg):
    game = Game(cfg)
    minutes = cfg["Pacing"]["ReportMinutes"]
    lines = []
    lines.append("| Минута | Ребёрт | Уровень | Этап (рекорд) | Лучший тренажёр | Аура сейчас |")
    lines.append("|---:|---:|---:|---:|---|---:|")
    s = State()
    events_until = {}
    for m in range(1, minutes[-1] + 1):
        for _ in range(60):
            step(game, s, game.P["ActiveCps"], game.P["TrainShare"])
        if m in minutes:
            tr = best_trainer(game, s)
            lines.append("| %d | %d | %d | %d | %s x%s | %s |" % (m, s.rebirths, s.level, s.stage, tr["Name"], tr["Multiplier"], fmt(s.aura)))
    table = "\n".join(lines)

    def when(kind, value):
        for t, k, v in s.events:
            if k == kind and v == value:
                return t / 60
        return None

    ev = []
    ev.append("| Событие | Минута |")
    ev.append("|---|---:|")
    for n in range(1, s.rebirths + 1):
        t = when("rebirth", n)
        ev.append("| Ребёрт %d (нужно %s Ауры) | %.1f |" % (n, fmt(game.rebirth_aura(n - 1)), t))
    for t, k, v in s.events:
        if k == "trainer":
            ev.append("| Тренажёр %s | %.1f |" % (v, t / 60))
    for t, k, v in s.events:
        if k == "stage":
            ev.append("| Этап %d (рек. урон %s) | %.1f |" % (v, fmt(game.recommended(v)), t / 60))
    for t, k, v in s.events:
        if k == "level" and v % 10 == 0:
            ev.append("| Уровень %d | %.1f |" % (v, t / 60))
    events = "\n".join(ev)

    # AFK (auto-click only, no dungeon) and x2 pass, compared over 10 min
    # of training on the same trainer.
    A = game.A
    active = game.P["TrainShare"] * (1 / A["TrainerTickInterval"] + game.P["ActiveCps"] * A["TrainerClickBonus"])
    afk = 1 / A["TrainerTickInterval"] + (1 / A["AutoClickInterval"]) * A["TrainerClickBonus"]
    def rebirth_minute(g, n, **kw):
        s2, _ = simulate(g, minutes[-1], **kw)
        for t, k, v in s2.events:
            if k == "rebirth" and v == n:
                return "%.0f" % (t / 60)
        return "> %d" % minutes[-1]

    passed = Game(cfg)
    passed.extra = 2
    notes = (
        "AFK с авто-кликом даёт %d%% Ауры активной игры (%.2f против %.2f единиц тренажёра в секунду): "
        "ребёрт 4 в AFK на минуте %s (активно — %s). "
        "С пассом «x2 Аура» ребёрт 8 на минуте %s (без пасса — %s)."
        % (
            round(afk / active * 100), afk, active,
            rebirth_minute(game, 4, cps=1 / A["AutoClickInterval"], train_share=1, dungeon=False), rebirth_minute(game, 4),
            rebirth_minute(passed, 8), rebirth_minute(game, 8),
        )
    )
    return table, events, notes


def write_readme(table, events, notes):
    text = open(README, encoding="utf-8").read()
    start, end = "<!-- pacing:start -->", "<!-- pacing:end -->"
    block = (
        start
        + "\n_Сгенерировано `python3 tools/pacing.py --readme` из `Config.luau`. "
        "Модель: активная игра без пассов, брони и питомцев._\n\n"
        + table
        + "\n\n"
        + events
        + "\n\n"
        + notes
        + "\n"
        + end
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
    table, events, notes = report(cfg)
    print(table)
    print()
    print(events)
    print()
    print(notes)
    if "--readme" in sys.argv:
        write_readme(table, events, notes)
        print("\nREADME.md updated.")


if __name__ == "__main__":
    main()
