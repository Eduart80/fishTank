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
| 7 | Monetization (see order below) | ⬜ |
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

| Egg hatchery stock | Each species has a global stock (e.g. Koi 10). Buying lowers it ("8 left"), restocks slowly over time; price rises as stock falls. **Guppy never sells out** (price rises only) so new players can always start. "Only 2 Koi eggs left!" = urgency | Market board EGG column, MemoryStore (same as egg pressure) |

| Fisherman visitors | Builds on the fishing boat (✅ built): an NPC walks off the boat to YOUR tank with a personal offer. Characters: Old Pete (fair), Rich Collector (big fish only, pays extra), Sneaky Sam (below market, check the board!). Accept/Decline, max 1 visit per 15–20 min, only while online | Fishing boat, pier |

All of these change the economy → re-run the progression sim before shipping.

### Bait Shack 🏪 (after the fishing minigame works)

Hut at the pier entrance. Main job: a **coin sink** (keeps coins leaving the game so prices still matter).

| Item | Type | Effect |
|---|---|---|
| Rods: Bamboo → Fiberglass → Carbon → Legendary | One-time upgrade | Cast farther → reach deeper zones |
| Fishing line | Upgrade | Big fish don't snap the line and escape |
| Hooks: small / big / golden | Upgrade | Choose your target: big hook lands big fish, misses small ones |
| Worms 🪱 | Consumable, cheap | Basic bait → small fish |
| Shrimp / squid bait | Consumable | Attracts salmon, tuna |
| Glowing lure | Consumable, rare | Night fishing, rare-variant chance |
| Tank food types: flakes / pellets / premium | Consumable | Ties to food sweet spot: cheap · growth bonus · rare-variant chance |

**Distance zones:** buoys in the sea mark rings 🟢 near (rod 1) → 🟡 mid (rod 2) → 🔴 far (rod 3) → 🟣 deep (Legendary). Players *see* the better water before they can reach it.

Rules:
- Useful gear = **coins only**. Robux = cosmetic rods only (same stats).
- Bait is used up (ongoing sink).
- Caught fish are small → the tank stays the main loop.

## Monetization (phase 7) — sell time & safety, not market power

| Rank | Item | Why people pay |
|---|---|---|
| 1 | **Auto-Feeder** (Game Pass) | Fear of losing fish — strongest reason in this game |
| 2 | **Grow boost 2×/1h** (Dev Product), **+Tank slots** (capped) | Impatience |
| 3 | **Premium Payouts** | Free — paid by Roblox for daily returning Premium players |
| 4 | **Starter pack** (once, small) | First purchase; payers pay again |
| 5 | Cosmetics — only **visible/social** ones (tank themes, title above head, Most Beautiful Tank) | Bonus income only |

Never: big coin packs, gear that catches better fish (paid players would wreck the shared market).

## Will players come back? — measure, don't guess

Funnel events (AnalyticsService) to see **where** players quit:
joined → bought first egg → first fish grew → first sale → first unlock → came back next day.

| Check | Target | If below |
|---|---|---|
| First egg bought in 2 min | 90% | Spawn/UI confusing → tutorial |
| First sale in 15 min | 70% | Start too slow → faster guppy |
| Day-1 return (D1) | 20%+ | Fix the first session before any new feature |
| Day-7 return (D7) | 5%+ | Need stronger daily reasons (phase 5) |
| Avg session | 15 min+ | Too little to do while waiting (→ fishing) |

Benchmarks are rough; Creator Dashboard shows real D1/D7 + session length once live.

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
