-- Global fish market. Three pressure "channels" per species, all shared across servers:
--   sell  : fish sold recently        -> pushes the fish SALE price down   (20 min half-life)
--   egg   : eggs bought recently      -> pushes the EGG price up           (20 min half-life)
--   hatch : eggs bought, still growing -> shown as "N growing" = future supply (half-life ~ grow time)
-- Each server keeps local changes in `pending` and folds them into a MemoryStore hash map every
-- SYNC_INTERVAL seconds. If MemoryStore is unavailable (unpublished Studio place, outage) it runs locally.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MarketMath = require(Shared.MarketMath)

local MarketService = {}

local SYNC_INTERVAL = 30
local ORDER_SYNC_INTERVAL = 5 -- event orders are a race, keep servers closer in step
-- Server-only secret for the event schedule (server scripts never reach players' computers).
-- Same number on every server so they all agree. Keep the GitHub repo private.
local EVENT_SECRET = 48611
local KEY_EXPIRY = 7 * 24 * 3600
local CHANNELS = { "sell", "egg", "hatch" }
-- Studio gets its own market so test dumps never touch the live one
local MAP_NAME = if RunService:IsStudio() then "Market_studio_v1" else "Market_v1"

local map = nil
local warnedSyncFailure = false
do
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap(MAP_NAME)
	end)
	if ok then
		map = result
	else
		warn("[Market] MemoryStore unavailable, running local-only:", result)
	end
end

-- state[speciesId][channel] = { global = pressure at globalAt, globalAt = time, pending = local units since last sync }
local state = {}
-- history[speciesId] = { price, price, ... } oldest first
local history = {}

local function halfLife(species, channel: string): number
	if channel == "hatch" then
		-- roughly "how many are still growing": fades over about one grow period
		return Config.real(species.growSeconds) * 0.7
	end
	return MarketMath.HALF_LIFE
end

local function storeKey(id: string, channel: string): string
	return if channel == "sell" then id else id .. "_" .. channel
end

local function pressureOf(id: string, channel: string, now: number): number
	local st = state[id][channel]
	return MarketMath.decay(st.global, now - st.globalAt, halfLife(Config.ById[id], channel)) + st.pending
end

-- Weather Radio: start time of the next event with this id (e.g. "storm") within 72 h, or nil.
-- Returns now if one is running. Server only (uses the secret schedule).
function MarketService.nextEventStart(now: number, id: string): number?
	for hour = now // 3600, now // 3600 + 72 do
		local e = MarketMath.eventOfHour(hour, #Config.Species, EVENT_SECRET)
		if e and e.def.id == id and e.endsAt > now then
			return math.max(now, e.startsAt)
		end
	end
	return nil
end

function MarketService.currentEvent(now: number)
	return MarketMath.eventAt(now, #Config.Species, EVENT_SECRET)
end

-- Chef / Festival orders: the bonus price only applies to the first orderSize fish sold
-- (all servers together). order = { key, global = filled on other syncs, pending = sold here, unsynced }
local order = { key = nil, global = 0, pending = 0 }

-- Returns the limited order running right now: event, species, size. Nil if none.
local function activeOrder(now: number)
	local event = MarketService.currentEvent(now)
	if not event or not event.speciesIndex or event.def.mult <= 1 then
		return nil
	end
	local species = Config.Species[event.speciesIndex]
	local key = "order_" .. event.startsAt
	if order.key ~= key then
		order = { key = key, global = 0, pending = 0 }
	end
	return event, species, species.orderSize or 10
end

local function orderLeft(now: number): number?
	local _, _, size = activeOrder(now)
	if not size then
		return nil
	end
	return math.max(0, size - order.global - order.pending)
end

-- Event multiplier for one species: capped for expensive fish, back to 1 once the order is full.
local function eventMultFor(species, now: number): number
	local event = MarketService.currentEvent(now)
	local mult = MarketMath.eventMult(event, species.index)
	if mult > 1 then
		mult = math.min(mult, species.maxEventMult or mult)
		if event.speciesIndex == species.index and (orderLeft(now) or 0) <= 0 then
			mult = 1
		end
	end
	return mult
end

function MarketService.getPrice(id: string, now: number): number
	local species = Config.ById[id]
	return MarketMath.price(species, now, pressureOf(id, "sell", now), eventMultFor(species, now))
end

function MarketService.getEggPrice(id: string, now: number): number
	return MarketMath.eggPrice(Config.ById[id], pressureOf(id, "egg", now))
end

function MarketService.getGrowing(id: string, now: number): number
	return pressureOf(id, "hatch", now)
end

-- Records one egg purchase (raises the egg price, adds to "growing").
function MarketService.recordEggBuy(id: string)
	state[id].egg.pending += 1
	state[id].hatch.pending += 1
end

-- Sells fish of one species (list of sizes). Returns gross coins before the market fee.
function MarketService.sell(id: string, sizes: { number }, now: number): number
	local species = Config.ById[id]
	local mult = eventMultFor(species, now)
	local pressure = pressureOf(id, "sell", now)
	local _, orderSpecies = activeOrder(now)
	if mult == 1 or orderSpecies ~= species then
		local gross, added = MarketMath.quoteSale(species, now, pressure, mult, sizes)
		state[id].sell.pending += added
		return gross
	end
	-- limited order: only the fish still left in the order get the bonus, the rest normal price
	local bonusCount = math.min(#sizes, orderLeft(now) or 0)
	local bonusSizes, normalSizes = {}, {}
	for i, size in sizes do
		table.insert(if i <= bonusCount then bonusSizes else normalSizes, size)
	end
	local gross1, added1 = MarketMath.quoteSale(species, now, pressure, mult, bonusSizes)
	local gross2, added2 = MarketMath.quoteSale(species, now, pressure + added1, 1, normalSizes)
	order.pending += bonusCount
	state[id].sell.pending += added1 + added2
	return gross1 + gross2
end

local function syncChannel(id: string, channel: string, now: number)
	local st = state[id][channel]
	local hl = halfLife(Config.ById[id], channel)
	local pending = st.pending
	if map then
		local ok, result = pcall(function()
			return map:UpdateAsync(storeKey(id, channel), function(old)
				local p = 0
				if type(old) == "table" and type(old.p) == "number" and type(old.t) == "number" then
					p = MarketMath.decay(old.p, now - old.t, hl)
				end
				return { p = p + pending, t = now }
			end, KEY_EXPIRY)
		end)
		if ok and type(result) == "table" then
			st.global = result.p
			st.globalAt = result.t
			st.pending -= pending -- keep anything added while we were waiting
			return
		end
		if not warnedSyncFailure then
			warnedSyncFailure = true
			warn("[Market] sync failed, using local prices until it recovers:", result)
		end
	end
	-- local-only fallback: fold pending into our own copy so it still decays
	st.global = MarketMath.decay(st.global, now - st.globalAt, hl) + pending
	st.globalAt = now
	st.pending -= pending
end

local function syncOrder()
	local key, pending = order.key, order.pending
	if not key then
		return
	end
	if map then
		local ok, result = pcall(function()
			return map:UpdateAsync(key, function(old)
				return (if type(old) == "number" then old else 0) + pending
			end, 2 * 3600)
		end)
		if ok and type(result) == "number" then
			if order.key == key then
				order.global = result
				order.pending -= pending
			end
			return
		end
	end
	if order.key == key then -- local-only fallback
		order.global += pending
		order.pending -= pending
	end
end

local function syncAll(now: number)
	for _, species in Config.Species do
		for _, channel in CHANNELS do
			syncChannel(species.id, channel, now)
		end
	end
end

local function recordHistory(now: number)
	for _, species in Config.Species do
		local list = history[species.id]
		table.insert(list, MarketService.getPrice(species.id, now))
		while #list > MarketMath.HISTORY_POINTS do
			table.remove(list, 1)
		end
	end
end

function MarketService.snapshot(now: number)
	local prices, eggPrices, growing, eggDemand = {}, {}, {}, {}
	for _, species in Config.Species do
		prices[species.id] = MarketService.getPrice(species.id, now)
		eggPrices[species.id] = MarketService.getEggPrice(species.id, now)
		growing[species.id] = math.floor(MarketService.getGrowing(species.id, now) + 0.5)
		eggDemand[species.id] = pressureOf(species.id, "egg", now)
	end
	local event = MarketService.currentEvent(now)
	local eventInfo = nil
	if event then
		local species = if event.speciesIndex then Config.Species[event.speciesIndex] else nil
		local mult = event.def.mult
		if species and mult > 1 then
			mult = math.min(mult, species.maxEventMult or mult)
		end
		local text = string.gsub(event.def.text, "{fish}", if species then species.name else "")
		text = string.gsub(text, "{mult}", tostring(mult))
		local _, _, size = activeOrder(now)
		eventInfo = {
			title = event.def.title,
			text = text,
			speciesId = if species then species.id else nil,
			endsAt = event.endsAt,
			orderSize = size,
			orderLeft = orderLeft(now),
		}
	end
	return {
		now = now,
		prices = prices,
		eggPrices = eggPrices,
		growing = growing,
		eggDemand = eggDemand,
		history = history,
		event = eventInfo,
		fee = Config.MARKET_FEE,
	}
end

-- Studio test runner only: copy / put back all market pressure so test trades leave no trace.
function MarketService._saveForTests()
	local copy = {}
	for id, channels in state do
		copy[id] = {}
		for channel, st in channels do
			copy[id][channel] = table.clone(st)
		end
	end
	return copy
end

function MarketService._restoreForTests(copy)
	for id, channels in copy do
		for channel, st in channels do
			state[id][channel] = table.clone(st)
		end
	end
end

function MarketService.start()
	local now = os.time()
	for _, species in Config.Species do
		state[species.id] = {}
		for _, channel in CHANNELS do
			state[species.id][channel] = { global = 0, globalAt = now, pending = 0 }
		end
		history[species.id] = {}
	end

	-- pull the real global pressure before anyone can trade
	syncAll(now)

	-- backfill the last hour so charts aren't empty on a fresh server
	-- (uses today's pressure for the whole hour; good enough for a chart)
	for i = MarketMath.HISTORY_POINTS - 1, 1, -1 do
		recordHistory(now - i * MarketMath.HISTORY_STEP)
	end
	recordHistory(now)

	task.spawn(function()
		while true do
			task.wait(SYNC_INTERVAL)
			syncAll(os.time())
		end
	end)

	task.spawn(function()
		while true do
			task.wait(ORDER_SYNC_INTERVAL)
			if activeOrder(os.time()) then
				syncOrder()
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(MarketMath.HISTORY_STEP)
			recordHistory(os.time())
		end
	end)
end

return MarketService
