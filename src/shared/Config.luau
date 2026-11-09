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
Config.SLOT_BASE_COST = 300
Config.SLOT_COST_GROWTH = 1.7

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

-- If a player has no fish and can't afford the cheapest egg, top them up to this (no permanent soft-lock).
-- Must stay >= guppy egg price at max demand (10 * EGG_MAX_MULT 2 = 20).
Config.RESCUE_COINS = 20

-- Seagull squawk: paste a Roblox audio id from the Studio Toolbox, e.g. "rbxassetid://1234567".
-- Empty = silent gulls.
Config.SEAGULL_SOUND_ID = "rbxassetid://9118858002"

-- Fishing boat visitor (server/BoatService). Studio comes much more often so you can test it.
Config.BOAT = {
	intervalMin = if RunService:IsStudio() then 45 else 15 * 60, -- real seconds between visits
	intervalMax = if RunService:IsStudio() then 90 else 25 * 60,
	staySeconds = if RunService:IsStudio() then 120 else 4 * 60,
	priceMin = 0.75, -- offer = market price x random(priceMin..priceMax): check the board before selling!
	priceMax = 1.3,
}

-- Robux shop. id = 0 means "not created yet" (button shows "Not set up").
-- Create items on create.roblox.com -> your experience -> Monetization, then paste the ids here.
--   kind "pass"    = Game Pass, bought once, kept forever
--   kind "product" = Developer Product, can be bought again and again
Config.GROW_BOOST_MULT = 2
Config.ROBUX = {
	{ key = "autoFeeder", kind = "pass", id = 2076124464, name = "Auto-Feeder", text = "Your fish never go hungry, even while you are offline." },
	{ key = "growBoost", kind = "product", id = 3729887473, name = "Grow Boost (1 hour)", text = "All your fish grow 2x faster for 1 hour. Buy again to add time.", seconds = 3600 },
}

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

function Config.sizeFromAge(age: number): number
	if age < 1 then
		return age
	end
	return 1 + (age - 1) / Config.EXTRA_GROWTH_PERIODS * (Config.MAX_SIZE - 1)
end

return Config
