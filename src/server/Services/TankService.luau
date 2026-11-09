-- Tank rules: eggs, feeding, growth, starvation, selling, slots.
-- Every action calls settle() first, so growth/death is always computed up to "now"
-- from timestamps (works the same whether the player was online or away for a week).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local MarketService = require(script.Parent.MarketService)

local TankService = {}

-- When a fish starts starving: the later of "food ran out" and "it was born".
local function hungerStart(data, fish): number
	return math.max(data.fedUntil, fish.born)
end

local function starveAt(data, fish): number
	local species = Config.ById[fish.species]
	return hungerStart(data, fish) + Config.real(species.starveHours * 3600)
end

-- Advance every fish to `now`. Fish only grow while fed. Returns the list of fish that died.
function TankService.settle(data, now: number)
	local died = {}
	local alive = {}
	for _, fish in data.fish do
		local species = Config.ById[fish.species]
		if not species then
			table.insert(alive, fish) -- unknown species (removed from config): keep it, never delete player items silently
			continue
		end
		local growEnd = math.min(now, data.fedUntil)
		if growEnd > fish.lastUpdate then
			local grown = (growEnd - fish.lastUpdate) * Config.TIME_SCALE / species.growSeconds
			fish.age = math.min(fish.age + grown, Config.MAX_AGE)
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
	return died
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
	})
	data.nextUid += 1
	return true, ("Bought a %s egg for %d"):format(species.name, price)
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
			bySpecies[fish.species] = bySpecies[fish.species] or {}
			table.insert(bySpecies[fish.species], Config.sizeFromAge(fish.age))
			count += 1
		else
			table.insert(keep, fish)
		end
	end
	if count == 0 then
		return false, "No adult fish to sell"
	end

	local gross = 0
	for speciesId, sizes in bySpecies do
		gross += MarketService.sell(speciesId, sizes, now)
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
		coins += math.floor(pricePerUnit * Config.sizeFromAge(adults[i].age) + 0.5)
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
	if data.slots >= Config.MAX_SLOTS then
		return false, "Tank is already max size"
	end
	local cost = Config.slotCost(data.slots)
	if data.coins < cost then
		return false, ("A new slot costs %d coins"):format(cost)
	end
	data.coins -= cost
	data.slots += 1
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
			starveAt = if species then starveAt(data, fish) else nil,
		})
	end
	local perHour, missingHours = TankService.feedQuote(data, now)
	return {
		now = now,
		coins = data.coins,
		slots = data.slots,
		maxSlots = Config.MAX_SLOTS,
		slotCost = Config.slotCost(data.slots),
		fedUntil = data.fedUntil,
		feedCost = math.ceil(perHour * missingHours),
		fish = fishList,
		stats = data.stats,
	}
end

return TankService
