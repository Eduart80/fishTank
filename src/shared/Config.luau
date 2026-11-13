-- All game tuning lives here. Change numbers, not code.
local RunService = game:GetService("RunService")

local Config = {}

-- Studio runs every timer 30x faster so a full grow / starve cycle can be tested in minutes.
-- Live servers always run at 1 (real time).
Config.TIME_SCALE = if RunService:IsStudio() then 30 else 1

-- Player start
Config.STARTING_COINS = 100
Config.STARTING_SLOTS = 6
Config.STARTING_FEED_HOURS = 2

-- Tank slots (coin sink): slot n costs SLOT_BASE_COST * SLOT_COST_GROWTH^(n - STARTING_SLOTS)
Config.MAX_SLOTS = 24
Config.BIG_TANK_SLOTS = 2 -- Bigger Tank pass: +2 slots once, and the max goes up by the same
function Config.maxSlots(data): number
	return Config.MAX_SLOTS + (if data.bigTank then Config.BIG_TANK_SLOTS else 0)
end
Config.LUCKY_CHARM_BONUS = 0.15 -- Lucky Charm pass: + this to every weather mutation chance
Config.SLOT_BASE_COST = 300
Config.SLOT_COST_GROWTH = 1.7

-- Tank stages: the tank grows backwards toward the sea inside its own pie slice (8 slices,
-- never overlap). Front glass never moves. Shape = trapezoid seen from above, in plot-local
-- studs: front edge at z = -5 (half width 10), back edge at backZ (half width halfBack).
-- +z points away from the plaza, toward the sea. Visual only: no economy effect.
Config.TANK_STAGES = {
	{ name = "Small Tank", minSlots = 6, backZ = 5, halfBack = 10, height = 12 },
	{ name = "Medium Tank", minSlots = 10, backZ = 17, halfBack = 15, height = 12 },
	{ name = "Large Tank", minSlots = 15, backZ = 35, halfBack = 22, height = 14 },
	{ name = "Sea Pen", minSlots = 20, backZ = 65, halfBack = 32, height = 16 },
}

-- Market
Config.MARKET_FEE = 0.05 -- 5% of every sale leaves the economy

-- Food: a full tank can be fed at most this many (game) hours ahead
Config.MAX_FEED_HOURS = 12
Config.EMPTY_TANK_FREE_FEED_HOURS = 1 -- mercy food when the first egg goes into an empty, unfed tank

-- Growth: age 0 -> 1 = juvenile to adult (growSeconds). Adults keep growing to MAX_SIZE
-- over EXTRA_GROWTH_PERIODS more grow periods. Sell value = market price * size.
Config.MAX_SIZE = 1.6
Config.EXTRA_GROWTH_PERIODS = 3
Config.MAX_AGE = 1 + Config.EXTRA_GROWTH_PERIODS

-- growSeconds / starveHours are game time (divided by TIME_SCALE for real time).
-- liquidity = how many fish-units the whole market absorbs before price drops ~50%.
-- unlockEarned = lifetime coins earned from selling before this egg can be bought.
-- orderSize = how many fish a Chef/Festival event buys at the bonus price (all servers together).
-- maxEventMult = cap on bonus events for expensive fish (a x3 Koi would skip days of progress).
-- Tuned 2026-11-08 by progression sim: casual player reaches Koi ~day 15, heavy player ~day 11
-- (old numbers: everything unlocked by day 3). Re-tune with real playtest data.
Config.Species = {
	{ id = "guppy", name = "Guppy", eggPrice = 10, basePrice = 15, growSeconds = 10 * 60, starveHours = 12, feedPerHour = 1, liquidity = 300, unlockEarned = 0, orderSize = 12, color = Color3.fromRGB(255, 170, 60) },
	{ id = "clownfish", name = "Clownfish", eggPrice = 40, basePrice = 62, growSeconds = 45 * 60, starveHours = 18, feedPerHour = 1, liquidity = 120, unlockEarned = 150, orderSize = 8, color = Color3.fromRGB(255, 110, 40) },
	{ id = "salmon", name = "Salmon", eggPrice = 150, basePrice = 235, growSeconds = 3 * 3600, starveHours = 24, feedPerHour = 2, liquidity = 50, unlockEarned = 1500, orderSize = 5, color = Color3.fromRGB(250, 128, 114) },
	{ id = "tuna", name = "Tuna", eggPrice = 500, basePrice = 800, growSeconds = 8 * 3600, starveHours = 36, feedPerHour = 4, liquidity = 20, unlockEarned = 8000, orderSize = 3, maxEventMult = 2, color = Color3.fromRGB(90, 140, 220) },
	{ id = "koi", name = "Koi", eggPrice = 2000, basePrice = 3300, growSeconds = 20 * 3600, starveHours = 48, feedPerHour = 10, liquidity = 8, unlockEarned = 30000, orderSize = 2, maxEventMult = 2, color = Color3.fromRGB(245, 245, 245) },
}

-- First session: eggs bought before the player has sold STARTER_SALES fish grow STARTER_GROW_MULT
-- times faster until adult (first Guppy ~2 min instead of 10), so a new player sees the whole
-- buy -> grow -> sell loop in the first minutes. Players who already sold fish are not affected.
Config.STARTER_SALES = 6
Config.STARTER_GROW_MULT = 5
function Config.growMult(fish): number
	return if fish.starter and fish.age < 1 then Config.STARTER_GROW_MULT else 1
end

-- Offline: the FIRST time food runs out while a player is away, that time does not count toward
-- starving (one-time grace, TankService.beginReturn). After that offline hunger counts.
-- Back after this many (real) seconds = "Welcome back" summary.
Config.AWAY_SUMMARY_SECONDS = if RunService:IsStudio() then 60 else 5 * 60

-- Daily login streak (RewardsService). A "day" = UTC day on live servers; Studio uses 2-minute
-- days so a streak can be tested by stopping and starting again. Rewards loop after the last entry.
-- An egg that does not fit in the tank is paid out as its egg price in coins.
Config.DAY_SECONDS = if RunService:IsStudio() then 120 else 86400
Config.DAILY_REWARDS = {
	{ coins = 25 },
	{ egg = "guppy", coins = 20 },
	{ coins = 50 },
	{ egg = "clownfish" },
	{ coins = 100 },
	{ coins = 150 },
	{ egg = "salmon", coins = 100 }, -- day 7: a taste of the next fish even before it unlocks
}

-- Invite a friend: a brand-new player who joins through someone's invite / share link gets a gift;
-- the inviter gets coins if they are on the same server (capped per lifetime against alt farming).
Config.INVITE = {
	newPlayerGift = { egg = "clownfish", coins = 50 },
	inviterCoins = 150,
	maxRewards = 10,
}

-- World 2 (Coral Reef) unlock rule — draft, see docs/roadmap.md "Round 2 plan". Shown on the
-- Reef Ferry preview card. Not enforced yet (World 2 is not built).
Config.REEF_UNLOCK = { slots = 20, ticket = 50000 }

-- If a player has no fish and can't afford the cheapest egg, top them up to this (no permanent soft-lock).
-- Must stay >= guppy egg price at max demand (10 * EGG_MAX_MULT 2 = 20).
Config.RESCUE_COINS = 20

-- Seagull squawk: paste a Roblox audio id from the Studio Toolbox, e.g. "rbxassetid://1234567".
-- Empty = silent gulls.
Config.SEAGULL_SOUND_ID = "rbxassetid://9118858002"

-- Weather mutations: when a fish grows up (age crosses 1) WHILE the owner is online, the weather at
-- that moment can turn it into a variant that sells for mult x. Storm wins over night.
-- Variant fish put normal pressure on the market; the bonus is paid on top.
-- VARIANT_MAX_STEP: only short (online) growth steps can roll, so logging in during a storm
-- does not mutate fish that grew up offline.
Config.VARIANTS = {
	storm = { name = "Stormborn", icon = "⚡", mult = 2, chance = 0.25, color = Color3.fromRGB(110, 200, 255) },
	moon = { name = "Moonlit", icon = "🌙", mult = 1.5, chance = 0.3, color = Color3.fromRGB(150, 175, 255) }, -- silver-blue moonlight -- FULL MOON nights only
	-- Rare Egg only (Robux), never from weather (no chance field)
	albino = { name = "Albino", icon = "⚪", mult = 2, color = Color3.fromRGB(255, 215, 228) }, -- pinkish white, like real albino fish
	golden = { name = "Golden", icon = "✨", mult = 3, color = Color3.fromRGB(255, 200, 60) },
}
-- Rare Egg (Robux developer product): a species the player has unlocked, always a rare variant.
-- Only CHEAP species (decided 2026-11-13): a collector fish, never a paid shortcut to Koi money.
Config.RARE_EGG_SPECIES = { guppy = true, clownfish = true, salmon = true }
Config.RARE_EGG_ODDS = {
	{ variant = "albino", weight = 75 },
	{ variant = "golden", weight = 25 },
}
Config.VARIANT_MAX_STEP = 30
function Config.variantMult(fish): number
	local v = fish.variant and Config.VARIANTS[fish.variant]
	return if v then v.mult else 1
end

-- Day / night (shared/DayNight + client/Sky). Real seconds; same sky on every server.
-- Day = sunrise (06:00) to sunset (18:00), night = 18:00 to 06:00 (shorter, so phones are not dark long).
-- STUDIO: Workspace attribute "TestClock" (0-24, e.g. 22 = night; 0 = normal cycle).
Config.DAY_NIGHT = { daySeconds = 20 * 60, nightSeconds = 5 * 60 }

-- Moon phases: one phase per night, 8 nights per cycle (full moon every 8 nights = ~3 h 20 min).
-- Moonlit fish only on FULL MOON nights. Texture ids: upload art/moon_*.png to Roblox (Creator Hub
-- -> Images/Decals) and paste the ids here. Empty = that phase shows no moon until uploaded.
-- STUDIO: Workspace attribute "TestMoon" = a phase key (e.g. full) forces that phase.
Config.MOON_SIZE = 20 -- angular size of the moon (user: 24 too huge, 11 too small, wanted it bigger again)
Config.MOON_PHASES = {
	{ key = "new", name = "New Moon", icon = "🌑", texture = "" }, -- no moon, only stars
	{ key = "crescent_waxing", name = "Waxing Crescent", icon = "🌒", texture = "" },
	{ key = "half_waxing", name = "First Quarter", icon = "🌓", texture = "" },
	{ key = "gibbous_waxing", name = "Waxing Gibbous", icon = "🌔", texture = "" },
	{ key = "full", name = "Full Moon", icon = "🌕", texture = "rbxasset://sky/moon.jpg" },
	{ key = "gibbous_waning", name = "Waning Gibbous", icon = "🌖", texture = "" },
	{ key = "half_waning", name = "Last Quarter", icon = "🌗", texture = "" },
	{ key = "crescent_waning", name = "Waning Crescent", icon = "🌘", texture = "" },
}

-- Storm sounds (client/Weather). Paste Roblox audio ids from the Studio Toolbox (Creator Store ->
-- Audio, search "thunder" / "rain loop"). Empty = silent (rain + lightning still show).
Config.THUNDER_SOUND_ID = "rbxassetid://130457325001606" -- sudden close thunder crack (picked 2026-11-13)
Config.THUNDER_FAR_SOUND_ID = "rbxassetid://102164464566453" -- distant rumble, for bolts on the horizon
Config.RAIN_SOUND_ID = "rbxassetid://1516791621" -- rain loop (picked 2026-11-13)

-- Fishing boat visitor (server/BoatService). Studio comes much more often so you can test it.
Config.BOAT = {
	intervalMin = if RunService:IsStudio() then 45 else 15 * 60, -- real seconds between visits
	intervalMax = if RunService:IsStudio() then 90 else 25 * 60,
	staySeconds = if RunService:IsStudio() then 120 else 4 * 60,
	priceMin = 0.75, -- offer = market price x random(priceMin..priceMax): check the board before selling!
	priceMax = 1.3,
	-- one boat per pier, each on its own timer. angle = pier turned around the island centre
	-- (0 = main pier; must match the piers built in WorldService.start)
	piers = {
		{ angle = 0, name = "main pier" },
		{ angle = 90, name = "east pier" },
		{ angle = -90, name = "west pier" },
	},
}

-- Robux shop. id = 0 means "not created yet" (button shows "Not set up").
-- Create items on create.roblox.com -> your experience -> Monetization, then paste the ids here.
--   kind "pass"    = Game Pass, bought once, kept forever
--   kind "product" = Developer Product, can be bought again and again
Config.GROW_BOOST_MULT = 2
Config.ROBUX = {
	-- once = one per player (hidden as Owned after). Contents are granted by server/ShopService.
	{ key = "starterPack", kind = "product", id = 3730113426, once = true, name = "Starter Pack", text = "500 coins + Beach Umbrella + a Clownfish egg. One per player!", coins = 500, item = "umbrella", egg = "clownfish" },
	{ key = "autoFeeder", kind = "pass", id = 2076124464, name = "Auto-Feeder", text = "Your fish never go hungry, even offline: they keep growing and never starve." },
	{ key = "rareEgg", kind = "product", id = 3730899968, name = "Rare Egg", text = "A mystery Guppy, Clownfish or Salmon egg (ones you have unlocked). Always hatches Albino (2x) or Golden (3x)!" },
	-- Game Passes added 2026-11-13: id 0 = "Not set up" until created on Creator Hub (Monetization -> Passes)
	{ key = "luckyCharm", kind = "pass", id = 2087996536, name = "Lucky Charm", text = "Storms and full moons love you: Stormborn 40% (was 25%), Moonlit 45% (was 30%)." },
	{ key = "vip", kind = "pass", id = 2089568498, name = "VIP", text = "Gold VIP name tag + [VIP] in chat + double coins from every daily reward." },
	{ key = "bigTank", kind = "pass", id = 2089022518, name = "Bigger Tank", text = "+2 fish slots forever (max 26 instead of 24)." },
	{ key = "weatherRadio", kind = "pass", id = 2089628546, name = "Weather Radio", text = "See when the next storm and full moon come, so you can time your eggs." },
	{ key = "growBoost", kind = "product", id = 3729887473, name = "Grow Boost (1 hour)", text = "All your fish grow 2x faster for 1 hour. Buy again to add time.", seconds = 3600 },
}

-- Harbor Store: patio items, placed on the 4 spots beside your tank (2 each side of the front glass).
-- PRETTY ONLY: no effect on fish or coins earned (safe for the economy, coin items are a coin sink).
-- Each item costs EITHER coins (price) OR Robux (robuxId = a Developer Product id; 0 = "Not set up").
-- Robux items: create a Developer Product per item on create.roblox.com -> your experience ->
-- Monetization -> Developer Products, set the Robux price there, paste the id here.
Config.PATIO_SPOTS = 4
Config.PATIO_MAX_OWNED = 10 -- per item, in your inventory
Config.PATIO_ITEMS = {
	{ id = "flag", name = "Flag", price = 100, colorable = true, text = "Tall flag. Pick its colour when you place it." },
	{ id = "chair", name = "Beach Chair", price = 120, text = "Striped deck chair. You can sit in it!" },
	{ id = "torch", name = "Tiki Torch", price = 150, text = "Bamboo torch with a real flame and warm light." },
	{ id = "lifebuoy", name = "Lifebuoy Stand", price = 180, text = "Red and white ring on a post." },
	{ id = "umbrella", name = "Beach Umbrella", price = 200, text = "Big red and white sun umbrella." },
	{ id = "pottedPalm", name = "Potted Palm", price = 250, text = "A little palm tree in a clay pot." },
	{ id = "sandcastle", name = "Sandcastle", price = 400, text = "Towers, walls and a tiny flag." },
	{ id = "neonPalm", name = "Neon Palm", robuxId = 3730113254, text = "Glowing palm tree, shines at night." },
	{ id = "treasure", name = "Treasure Chest", robuxId = 3730113317, text = "Open chest full of gold, sparkling." },
	{ id = "goldenFish", name = "Golden Fish Statue", robuxId = 3730113388, text = "Shiny gold fish on a stone pedestal." },
}
Config.PatioById = {}
for _, item in Config.PATIO_ITEMS do
	Config.PatioById[item.id] = item
end
-- Colours for items with colorable = true (picked when placing; pick up + place again to change)
Config.PATIO_COLORS = {
	{ key = "red", name = "Red", color = Color3.fromRGB(220, 50, 50) },
	{ key = "orange", name = "Orange", color = Color3.fromRGB(245, 140, 30) },
	{ key = "yellow", name = "Yellow", color = Color3.fromRGB(250, 210, 40) },
	{ key = "green", name = "Green", color = Color3.fromRGB(50, 170, 70) },
	{ key = "blue", name = "Blue", color = Color3.fromRGB(40, 110, 220) },
	{ key = "purple", name = "Purple", color = Color3.fromRGB(140, 70, 200) },
	{ key = "black", name = "Black", color = Color3.fromRGB(30, 30, 35) },
	{ key = "white", name = "White", color = Color3.fromRGB(245, 245, 240) },
}
Config.PatioColorByKey = {}
for _, c in Config.PATIO_COLORS do
	Config.PatioColorByKey[c.key] = c
end
Config.PATIO_DEFAULT_COLOR = "blue"

-- Studio only: run the scenario tests (server/Tests) every time you press Play. Never runs live.
Config.RUN_TESTS_IN_STUDIO = true

-- 3D look: scale = body size multiplier, speed = studs/sec, tail/stripe colors (stripe optional)
local VISUALS = {
	guppy = { scale = 0.8, speed = 6, tail = Color3.fromRGB(255, 80, 170) },
	clownfish = { scale = 1.0, speed = 4.5, tail = Color3.fromRGB(255, 110, 40), stripe = Color3.fromRGB(255, 255, 255) },
	salmon = { scale = 1.6, speed = 5, tail = Color3.fromRGB(200, 90, 80) },
	tuna = { scale = 2.0, speed = 7, tail = Color3.fromRGB(40, 60, 110), stripe = Color3.fromRGB(230, 200, 60) },
	koi = { scale = 2.2, speed = 3, tail = Color3.fromRGB(255, 255, 255), stripe = Color3.fromRGB(230, 60, 40) },
}

Config.ById = {}
for index, species in Config.Species do
	species.index = index
	species.visual = VISUALS[species.id]
	Config.ById[species.id] = species
end

-- Game seconds -> real seconds
function Config.real(gameSeconds: number): number
	return gameSeconds / Config.TIME_SCALE
end

function Config.slotCost(currentSlots: number): number
	return math.floor(Config.SLOT_BASE_COST * Config.SLOT_COST_GROWTH ^ (currentSlots - Config.STARTING_SLOTS))
end

function Config.tankStage(slots: number): number
	local stage = 1
	for i, s in Config.TANK_STAGES do
		if slots >= s.minSlots then
			stage = i
		end
	end
	return stage
end

function Config.sizeFromAge(age: number): number
	if age < 1 then
		return age
	end
	return 1 + (age - 1) / Config.EXTRA_GROWTH_PERIODS * (Config.MAX_SIZE - 1)
end

return Config
