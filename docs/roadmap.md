# Roadmap (official stages)

See also: `creatures.md` (38 creatures, 5 worlds) · `decorations.md` (tank decor by stage)

## Build phases

| # | Phase | Status |
|---|---|---|
| 0 | Core loop (2D): market, eggs, growth, feeding, starvation, selling, saving | ✅ |
| 1 | 3D world: plaza, 8 tanks, market board, swimming fish, pop-up menus | ✅ built, testing |
| 1b | Economy re-tune (unlocks by sales, harder curve) + egg demand pricing + "growing" counts | ✅ built, testing |
| 2 | Playtest + tune with 3–5 friends (no new features) | ⬜ |
| 3 | Collection depth: rare variants, fish info on click, **decorations stage 1**, Goldfish + Pufferfish, food sweet spot, species traits, seagull, fishing pier (see below) | ⬜ |
| 3.5 | **World 2 — Coral Reef** (+ decor stage 2) — only if players reach Koi and want more | ⬜ |
| 4 | Social: Top Traders board, tank likes, Most Beautiful Tank, biggest-fish record | ⬜ |
| 5 | Retention: daily egg/streak, "while you were away", event schedule/rumors, notifications | ⬜ |
| 6 | Polish: sounds, tutorial, mobile check, icon/thumbnail, real 3D models | ⬜ |
| 7 | Monetization: Auto-Feeder, +slots, Market Insider, grow boost, Robux cosmetics | ⬜ |
| 8 | Launch: private beta → public, analytics, weekly updates | ⬜ |
| 9 | Player-to-player trading / auction house | ⬜ later |

## Phase 3 gameplay additions (after playtest)

Rule for every danger: **warning + counter + limit**. A loss must be one the player saw coming and could stop.

| Feature | Design | Ties to |
|---|---|---|
| Food sweet spot | Empty = starving · low = slow growth · middle = best growth · overfed = dirty water (slow growth until cleaned) | Water Filter decor |
| Species traits | Hardy (Goldfish: offline-safe) · Fragile (high value, needs perfect care) · Greedy (2× food) · Predator (eats small tank-mates, World 2–3) | `Config` field per species |
| Seagull 🐦 | Circles plaza ~30s first (shadow + squawk) → dives on a tank with no lid, takes **max 1 small fish**. Press E at the tank to scare it off (friends can help). **Only while owner is online** | Tank Lid, Scarecrow / Owl Statue decor |
| Fishing pier 🎣 | Press E to cast, timing-bar minigame. Mostly small/cheap catches + junk (old boot = 1 coin), rare wild egg, very rare variant. Bait costs coins (better bait = better odds). Big catches come out **small** → still need the tank to grow. Wild catches sold add market sell pressure | Replaces rescue coins as the broke-player path; side dish, **tank stays the main meal** |

All four change the economy → re-run the progression sim before shipping.

## World stages (long term)

| World | Boss | Twist |
|---|---|---|
| 1 Harbor | Koi | Feeding & starvation |
| 2 Coral Reef | Manta Ray | Tank-mate conflicts |
| 3 Deep Sea | Megalodon | Darkness / light |
| 4 Open Ocean | Blue Whale | Migration |
| 5 Mythic Waters | Leviathan → **The Kraken** | Rituals; **Release the Kraken** = prestige + server event |

## Rules

- One phase/world at a time; next world only after real players reach the current boss.
- Anything that changes the economy (species, useful decor) → re-run the progression sim first.
- Spend $0 until launch prep; art budget goes to worlds 3–5 models.
- Commit to git at the end of every phase.
