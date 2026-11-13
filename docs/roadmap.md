# Roadmap (official stages)

See also: `creatures.md` (38 creatures, 5 worlds) · `decorations.md` (tank decor by stage)

## Build phases

| # | Phase | Status |
|---|---|---|
| 0 | Core loop (2D): market, eggs, growth, feeding, starvation, selling, saving | ✅ |
| 1 | 3D world: plaza, 8 tanks, market board, swimming fish, pop-up menus | ✅ built, testing |
| 1b | Economy re-tune (unlocks by sales, harder curve) + egg demand pricing + "growing" counts | ✅ built, testing |
| 1c | **Tank stages** (Small → Medium → Large → Sea Pen, pie slices toward the sea, by slots 6/10/15/20) · 3 piers (main/east/west) with one boat each, taking turns · phone HUD | ✅ built 2026-11-09 |
| 1d | Ambience (sunny lighting, clouds, tank bubbles, 14 palms) · **Harbor Store hut + patios** (4 spots per tank, 7 coin items + 3 Robux items, inventory "My items" tab, flag colour picker, saved) · ✕ close on every window | ✅ built 2026-11-09 (Robux patio products: ids still 0 = create Developer Products) |
| 1e | **Before the playtest:** (a) **Stress test** — Studio-only switch: all 8 tanks Sea Pen, 24 Koi each, 4 torches per patio; check FPS/memory in Studio (Performance Stats, Ctrl+F6) AND on a real phone (private publish, F9 console). Likely fixes if slow: animate only nearby tanks' fish, cap torch lights, fewer transparent layers. (b) **Visible storm** — dark sky, rain around the camera, rough sea, palm sway, thunder (user picks sound), seagulls leave, start toast; same system later for festival/chef looks. (c) Slot button text "+1 Fish Slot · N more to Medium Tank". (d) Robux product IDs (Neon Palm, Treasure Chest, Golden Fish, Starter Pack) | ⬜ next |
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
| 4 | **Starter pack** (once, small) — ⬜ NEXT, before launch: ~R$ 99, once per player = 500 coins + Beach Umbrella + 1 Clownfish egg. Developer Product, granted via ShopService (saved before PurchaseGranted), flag `data.starterPack` blocks a 2nd buy, hidden in the shop once owned | First purchase; payers pay again |
| 5 | Cosmetics — only **visible/social** ones (tank themes, title above head, Most Beautiful Tank) | Bonus income only |

Never: big coin packs, gear that catches better fish (paid players would wreck the shared market).
Maybe later (only after playtest + analytics show the market is healthy): small coin packs, capped
(e.g. 1,000 coins, max 1 per day), or Robux tank slots capped at +2. Decided 2026-11-09.

**Live Robux products (2026-11-09):** Auto-Feeder pass 2076124464 · Grow Boost 3729887473 · Starter Pack 3730113426 ·
Neon Palm 3730113254 · Treasure Chest 3730113317 · Golden Fish Statue 3730113388 (Managed pricing ON for all).

**Next monetization ideas to discuss (user asked to keep these, 2026-11-09)** — all "time & show-off, never market power":

| Idea | Type | Why players buy |
|---|---|---|
| Extra tank slot (capped at +2 total) | Developer Product | Impatience; fish still grow at normal speed |
| Tank themes (Coral Pink, Night Glow, Pirate Ship) | Developer Product | Show-off: sand, glass tint, decor colours |
| Title above head ("Fish Tycoon", "Koi King") | Developer Product | Show-off, visible everywhere |
| More Robux patio items (Neon Sign with your name, Pirate Flag, Golden Chair) | Developer Product | Show-off; system already exists |
| VIP Game Pass (gold name, +1 patio spot, VIP chat tag) | Game Pass | One-time, small perks |
| Premium Payouts | Automatic | Roblox pays for Premium players' time; just keep players playing |

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

## Round 2 plan — Coral Reef (draft 2026-11-12, NOT built)

Problem: Koi takes 20 h, so top players turn into "check once a day" players and drift away.
Round 2 must add things to DO, not longer timers.

| Decision | Draft |
|---|---|
| Harbor tank | **Stays active.** Reef = a SECOND tank; fast Reef fish to manage while the Koi grows |
| Timers | Restart the fast→slow ladder: Seahorse ~30 min ... Manta Ray boss ~24 h, higher coin values |
| New skill | Tank-mates: Octopus eats Lobster, etc. (see creatures.md World 2). Heater + Reinforced Lid decor |
| Unlock | Sea Pen + sell a full-size Koi + 50,000-coin boat ticket (coin sink) → "Travel to Reef" boat at main pier, unlocked forever |
| Build as | Second place in the same experience (TeleportService), same DataStore; own map, own market board |
| Teaser now | "Coral Reef — coming soon. Sell a Koi to unlock!" sign at the pier (cheap) |
| **Start building when** | First playtester hits `Unlocked_Tuna` (custom event on the Creator Dashboard) — Koi is ~1-2 weeks after Publish |

Open questions: does the Reef have its own market or share prices with the Harbor? Same 8-player servers?

## World stages (long term)

| World | Boss | Twist |
|---|---|---|
| 1 Harbor | Koi | Feeding & starvation |
| 2 Coral Reef | Manta Ray | Tank-mate conflicts |
| 3 Deep Sea | Megalodon | Darkness / light |
| 4 Open Ocean | Blue Whale | Migration |
| 5 Mythic Waters | Leviathan → **The Kraken** | Rituals; **Release the Kraken** = prestige + server event |

## Creature size rule — big creatures need big tanks (decided 2026-11-09)

Real scale (1 stud ≈ 0.28 m). A creature fits a tank stage if its **length ≤ ~70% of the tank length**.
Tested in Studio with `TestWhale` (server/StudioWhale): orca 28 studs fits the Sea Pen easily,
humpback 50 fills it (biggest that still looks right), blue whale 90 sticks out onto the plaza.

| Home | Tank length | Max creature | Examples |
|---|---|---|---|
| Small Tank (6+ slots) | 10 | ~7 studs | guppy, clownfish |
| Medium Tank (10+) | 22 | ~15 | salmon, tuna |
| Large Tank (15+) | 40 | ~28 | stingray, sea turtle, orca |
| Sea Pen (20+) | 70 | ~50 | sharks, humpback |
| World 4 ocean bay (own map, netted open sea) | 250+ | 90+ | **blue whale** |
| World 5 | — | — | **Kraken** is released (event), never kept |

- New species get a `minStage` in Config; buying the egg needs that stage ("Needs a Large Tank").
- Harbor island stays at 4 stages: a 5th would block the boat routes and swallow the island.
- Whale-size and myth creatures get their own world homes (mix of real scale + own maps).
- Anything with `minStage` changes the economy → re-run the progression sim first.

## Rules

- One phase/world at a time; next world only after real players reach the current boss.
- Anything that changes the economy (species, useful decor) → re-run the progression sim first.
- Spend $0 until launch prep; art budget goes to worlds 3–5 models.
- Commit to git at the end of every phase.
