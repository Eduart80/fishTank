-- Tank rules: eggs, feeding, growth, starvation, selling, slots.
-- Every action calls settle() first, so growth/death is always computed up to "now"
-- from timestamps (works the same whether the player was online or away for a week).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local MarketService = require(script.Parent.MarketService)

local TankService = {}

-- When a fish starts starving: the later of "food ran out" and "it was born", pushed back by the
-- hungry time the player spent offline (data.hungerPause, only valid for the fedUntil it was made for:
-- feeding again sets a new fedUntil and the pause no longer applies).
local function hungerStart(data, fish): number
	local start = data.fedUntil
	local pause = data.hungerPause
	if pause and pause.fedUntil == data.fedUntil then
		start += pause.seconds
	end
	return math.max(start, fish.born)
end

local function starveAt(data, fish): number
	local species = Config.ById[fish.species]
	return hungerStart(data, fish) + Config.real(species.starveHours * 3600)
end

local variantRng = Random.new()

-- Advance every fish to `now`. Fish only grow while fed. Returns (died, mutated).
-- weather = { storm = bool, night = bool, blood = bool } (nil = no mutations). roll = test hook returning 0..1.
function TankService.settle(data, now: number, weather, roll: (() -> number)?)
	-- Auto-Feeder (Robux pass): food never runs out, also across offline time
	if data.autoFeeder then
		data.fedUntil = math.max(data.fedUntil, now + Config.real(Config.MAX_FEED_HOURS * 3600))
	end
	local boostUntil = data.boostUntil or 0
	local died = {}
	local alive = {}
	local mutated = {}
	for _, fish in data.fish do
		local species = Config.ById[fish.species]
		if not species then
			table.insert(alive, fish) -- unknown species (removed from config): keep it, never delete player items silently
			continue
		end
		local growEnd = math.min(now, data.fedUntil)
		local ageBefore = fish.age
		local step = now - fish.lastUpdate
		if growEnd > fish.lastUpdate then
			-- Grow Boost (Robux): the part of this stretch inside the boost counts GROW_BOOST_MULT times
			local boosted = math.max(0, math.min(growEnd, boostUntil) - fish.lastUpdate)
			local effective = (growEnd - fish.lastUpdate) + boosted * (Config.GROW_BOOST_MULT - 1)
			local grown = effective * Config.TIME_SCALE / species.growSeconds * Config.growMult(fish)
			fish.age = math.min(fish.age + grown, Config.MAX_AGE)
			if fish.starter and fish.age >= 1 then
				fish.starter = nil -- adult: back to normal speed
			end
		end
		-- grew up just now, while online: the weather may mutate it
		if weather and ageBefore < 1 and fish.age >= 1 and not fish.variant and step <= Config.VARIANT_MAX_STEP then
			local kind = if weather.storm then "storm" elseif weather.blood then "blood" elseif weather.night then "moon" else nil
			local v = kind and Config.VARIANTS[kind]
			local chance = if v then v.chance + (if data.luckyCharm then Config.LUCKY_CHARM_BONUS else 0) else 0
			if v and (if roll then roll() else variantRng:NextNumber()) < chance then
				fish.variant = kind
				table.insert(mutated, fish)
			end
		end
		fish.lastUpdate = now
		if now >= starveAt(data, fish) then
			table.insert(died, fish)
		else
			table.insert(alive, fish)
		end
	end
	data.fish = alive
	if #died > 0 then
		data.stats.died += #died
	end
	data.lastSeen = now
	return died, mutated
end

-- Call on join BEFORE settle(). ONE-TIME grace: the first time food runs out while the player is
-- away, that offline hungry time does not count toward starving (data.offlineGraceUsed). After that,
-- offline hunger counts like online hunger (feed before leaving, or Auto-Feeder).
-- Returns what the summary needs (nil = new player / no gap).
function TankService.beginReturn(data, now: number)
	local last = data.lastSeen
	if not last then
		-- saves from before lastSeen existed: every settle stamped fish.lastUpdate
		for _, fish in data.fish do
			last = math.max(last or 0, fish.lastUpdate)
		end
	end
	if not last or now <= last then
		return nil
	end
	local graceUsedNow = false
	if not data.autoFeeder and not data.offlineGraceUsed then
		local hungryFrom = math.max(last, data.fedUntil)
		if now > hungryFrom then
			data.offlineGraceUsed = true
			graceUsedNow = true
			local pause = data.hungerPause
			if pause and pause.fedUntil == data.fedUntil then
				pause.seconds += now - hungryFrom
			else
				data.hungerPause = { fedUntil = data.fedUntil, seconds = now - hungryFrom }
			end
		end
	end
	local ages = {}
	for _, fish in data.fish do
		ages[fish.uid] = fish.age
	end
	return { seconds = now - last, ages = ages, fedUntil = data.fedUntil, grace = graceUsedNow }
end

local function duration(seconds: number): string
	if seconds >= 86400 then
		return ("%dd %dh"):format(seconds // 86400, (seconds % 86400) // 3600)
	elseif seconds >= 3600 then
		return ("%dh %dm"):format(seconds // 3600, (seconds % 3600) // 60)
	end
	return ("%dm"):format(math.max(1, seconds // 60))
end

-- Call AFTER settle(). "Welcome back" text, or nil for a short break / empty tank.
function TankService.awaySummary(data, now: number, away): string?
	if away and away.grace and #data.fish > 0 then
		return "Your fish ran out of food while you were away! The harbor kept them alive THIS time. Next time they can starve: feed them before you leave, or get the Auto-Feeder."
	end
	if not away or away.seconds < Config.AWAY_SUMMARY_SECONDS or #data.fish == 0 then
		return nil
	end
	local grewUp, adults = 0, 0
	for _, fish in data.fish do
		if fish.age >= 1 then
			adults += 1
			local before = away.ages[fish.uid]
			if before and before < 1 then
				grewUp += 1
			end
		end
	end
	local parts = { ("Welcome back! You were away %s."):format(duration(away.seconds)) }
	if grewUp > 0 then
		table.insert(parts, ("%d fish grew up!"):format(grewUp))
	end
	if adults > 0 then
		table.insert(parts, ("%d ready to sell."):format(adults))
	end
	if data.fedUntil < now then
		table.insert(parts, ("Food ran out %s ago, so they stopped growing. Feed them now, they get hungry while you play!"):format(duration(now - data.fedUntil)))
	end
	return table.concat(parts, " ")
end

function TankService.buyEgg(data, speciesId: string, now: number)
	local species = Config.ById[speciesId]
	if not species then
		return false, "Unknown fish"
	end
	if data.stats.earned < (species.unlockEarned or 0) then
		return false, ("%s unlocks when your fish sales reach %d coins (you're at %d)"):format(species.name, species.unlockEarned, math.floor(data.stats.earned))
	end
	if #data.fish >= data.slots then
		return false, "Your tank is full. Sell fish or buy a slot."
	end
	local price = MarketService.getEggPrice(speciesId, now)
	if data.coins < price then
		return false, ("A %s egg costs %d right now"):format(species.name, price)
	end
	if #data.fish == 0 and data.fedUntil < now then
		data.fedUntil = now + Config.real(Config.EMPTY_TANK_FREE_FEED_HOURS * 3600)
	end
	data.coins -= price
	MarketService.recordEggBuy(speciesId)
	table.insert(data.fish, {
		uid = data.nextUid,
		species = speciesId,
		age = 0,
		born = now,
		lastUpdate = now,
		starter = if data.stats.sold < Config.STARTER_SALES then true else nil,
	})
	data.nextUid += 1
	return true, ("Bought a %s egg for %d"):format(species.name, price)
end

-- A free egg (Starter Pack). No price, no unlock check, no market egg demand. false = tank full.
function TankService.giveEgg(data, speciesId: string, now: number, variant: string?): boolean
	if not Config.ById[speciesId] or #data.fish >= data.slots then
		return false
	end
	if #data.fish == 0 and data.fedUntil < now then
		data.fedUntil = now + Config.real(Config.EMPTY_TANK_FREE_FEED_HOURS * 3600)
	end
	table.insert(data.fish, { uid = data.nextUid, species = speciesId, age = 0, born = now, lastUpdate = now, starter = if data.stats.sold < Config.STARTER_SALES then true else nil, variant = variant })
	data.nextUid += 1
	return true
end

-- Rare Egg: a random species the player has unlocked + a rare variant by Config.RARE_EGG_ODDS.
function TankService.rollRareEgg(data, rng: Random?): (string, string)
	local r = rng or Random.new()
	local unlocked = {}
	for _, species in Config.Species do
		if Config.RARE_EGG_SPECIES[species.id] and data.stats.earned >= (species.unlockEarned or 0) then
			table.insert(unlocked, species.id)
		end
	end
	local speciesId = unlocked[r:NextInteger(1, #unlocked)] -- Guppy is always unlocked
	local total = 0
	for _, odd in Config.RARE_EGG_ODDS do
		total += odd.weight
	end
	local pick = r:NextNumber() * total
	for _, odd in Config.RARE_EGG_ODDS do
		pick -= odd.weight
		if pick <= 0 then
			return speciesId, odd.variant
		end
	end
	return speciesId, Config.RARE_EGG_ODDS[1].variant
end

-- Egg Incubator: eggs that did not fit (full tank) wait here and hatch into the tank as soon as
-- a slot is free. Never capped: they can be paid for with Robux. Returns the fish placed now.
function TankService.hatchIncubator(data, now: number)
	local placed = {}
	local incubator = data.incubator
	while incubator and #incubator > 0 and #data.fish < data.slots do
		local egg = table.remove(incubator, 1)
		if TankService.giveEgg(data, egg.species, now, egg.variant) then
			table.insert(placed, data.fish[#data.fish])
		end
	end
	return placed
end

-- Coins per (game) hour of food for the current tank
local function feedCostPerHour(data): number
	local cost = 0
	for _, fish in data.fish do
		local species = Config.ById[fish.species]
		cost += if species then species.feedPerHour else 1
	end
	return cost
end

function TankService.feedQuote(data, now: number)
	local perHour = feedCostPerHour(data)
	local base = math.max(now, data.fedUntil)
	local maxUntil = now + Config.real(Config.MAX_FEED_HOURS * 3600)
	local missingHours = math.max(0, (maxUntil - base) * Config.TIME_SCALE / 3600)
	return perHour, missingHours, base
end

-- Fills food up to MAX_FEED_HOURS, or as far as the player can afford.
function TankService.feed(data, now: number)
	if #data.fish == 0 then
		return false, "No fish to feed"
	end
	local perHour, missingHours, base = TankService.feedQuote(data, now)
	if missingHours < 0.05 then
		return false, "Food is already full"
	end
	local hours = math.min(missingHours, data.coins / perHour)
	if hours < 0.05 then
		return false, "Not enough coins for food"
	end
	local cost = math.min(data.coins, math.ceil(hours * perHour))
	data.coins -= cost
	data.fedUntil = base + Config.real(hours * 3600)
	return true, ("Fed for %.1f h (-%d coins)"):format(hours, cost)
end

-- Sells the given fish (or all adults if uids is nil). Juveniles are skipped.
function TankService.sell(data, uids: { number }?, now: number)
	local wanted = nil
	if uids then
		wanted = {}
		for _, uid in uids do
			wanted[uid] = true
		end
	end

	local bySpecies = {}
	local keep = {}
	local count = 0
	for _, fish in data.fish do
		local sellable = fish.age >= 1 and Config.ById[fish.species] ~= nil and (wanted == nil or wanted[fish.uid])
		if sellable then
			bySpecies[fish.species] = bySpecies[fish.species] or { sizes = {}, plain = 0, weighted = 0 }
			local group = bySpecies[fish.species]
			local size = Config.sizeFromAge(fish.age)
			table.insert(group.sizes, size)
			group.plain += size
			group.weighted += size * Config.variantMult(fish)
			count += 1
		else
			table.insert(keep, fish)
		end
	end
	if count == 0 then
		return false, "No adult fish to sell"
	end

	local gross = 0
	for speciesId, group in bySpecies do
		-- market sees normal fish (normal pressure); variants earn their multiplier on top
		gross += MarketService.sell(speciesId, group.sizes, now) * group.weighted / group.plain
	end
	local net = math.floor(gross * (1 - Config.MARKET_FEE))
	data.fish = keep
	data.coins += net
	data.stats.earned += net
	data.stats.sold += count
	return true, ("Sold %d fish for %d coins"):format(count, net)
end

-- Sells up to maxCount adult fish of one species to an NPC buyer (fishing boat) at a fixed
-- price per size-1 fish. Biggest first. No market fee, no market pressure. Returns count, coins.
function TankService.sellToBuyer(data, speciesId: string, maxCount: number, pricePerUnit: number)
	local adults = {}
	for _, fish in data.fish do
		if fish.species == speciesId and fish.age >= 1 then
			table.insert(adults, fish)
		end
	end
	table.sort(adults, function(a, b)
		return a.age > b.age
	end)
	local count = math.min(maxCount, #adults)
	if count <= 0 then
		return 0, 0
	end
	local sold, coins = {}, 0
	for i = 1, count do
		sold[adults[i]] = true
		coins += math.floor(pricePerUnit * Config.sizeFromAge(adults[i].age) * Config.variantMult(adults[i]) + 0.5)
	end
	local keep = {}
	for _, fish in data.fish do
		if not sold[fish] then
			table.insert(keep, fish)
		end
	end
	data.fish = keep
	data.coins += coins
	data.stats.earned += coins
	data.stats.sold += count
	return count, coins
end

-- No fish + can't afford the cheapest egg = stuck forever. Top up so they can restart.
-- Returns true if a rescue happened.
function TankService.rescueIfBroke(data, now: number): boolean
	if #data.fish > 0 then
		return false
	end
	local cheapest = math.huge
	for _, species in Config.Species do
		if data.stats.earned >= (species.unlockEarned or 0) then
			cheapest = math.min(cheapest, MarketService.getEggPrice(species.id, now))
		end
	end
	if data.coins >= cheapest then
		return false
	end
	data.coins = math.max(data.coins, Config.RESCUE_COINS)
	return true
end

function TankService.buySlot(data)
	if data.slots >= Config.maxSlots(data) then
		return false, "Tank is already max size"
	end
	local cost = Config.slotCost(data.slots)
	if data.coins < cost then
		return false, ("A new slot costs %d coins"):format(cost)
	end
	data.coins -= cost
	local oldStage = Config.tankStage(data.slots)
	data.slots += 1
	local stage = Config.tankStage(data.slots)
	if stage > oldStage then
		return true, ("Your tank grew into a %s! (%d slots)"):format(Config.TANK_STAGES[stage].name, data.slots)
	end
	local nextStage = Config.TANK_STAGES[stage + 1]
	if nextStage then
		return true, ("Tank upgraded to %d slots · %d more to %s"):format(data.slots, nextStage.minSlots - data.slots, nextStage.name)
	end
	return true, ("Tank upgraded to %d slots"):format(data.slots)
end

-- What the client is allowed to see
function TankService.publicState(data, now: number)
	local fishList = {}
	for _, fish in data.fish do
		local species = Config.ById[fish.species]
		table.insert(fishList, {
			uid = fish.uid,
			species = fish.species,
			age = fish.age,
			starter = fish.starter,
			variant = fish.variant,
			starveAt = if species then starveAt(data, fish) else nil,
		})
	end
	local perHour, missingHours = TankService.feedQuote(data, now)
	return {
		now = now,
		coins = data.coins,
		slots = data.slots,
		maxSlots = Config.maxSlots(data),
		slotCost = Config.slotCost(data.slots),
		fedUntil = data.fedUntil,
		feedCost = math.ceil(perHour * missingHours),
		fish = fishList,
		stats = data.stats,
		autoFeeder = data.autoFeeder == true,
		boostUntil = data.boostUntil or 0,
		incubator = if data.incubator then #data.incubator else 0,
		starterPack = data.starterPack == true,
		luckyCharm = data.luckyCharm == true,
		vip = data.vip == true,
		bigTank = data.bigTank == true,
		weatherRadio = data.weatherRadio == true,
	}
end

return TankService
