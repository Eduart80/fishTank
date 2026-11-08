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

function MarketService.currentEvent(now: number)
	return MarketMath.eventAt(now, #Config.Species)
end

function MarketService.getPrice(id: string, now: number): number
	local species = Config.ById[id]
	local mult = MarketMath.eventMult(MarketService.currentEvent(now), species.index)
	return MarketMath.price(species, now, pressureOf(id, "sell", now), mult)
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
	local mult = MarketMath.eventMult(MarketService.currentEvent(now), species.index)
	local gross, added = MarketMath.quoteSale(species, now, pressureOf(id, "sell", now), mult, sizes)
	state[id].sell.pending += added
	return gross
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
	local prices, eggPrices, growing = {}, {}, {}
	for _, species in Config.Species do
		prices[species.id] = MarketService.getPrice(species.id, now)
		eggPrices[species.id] = MarketService.getEggPrice(species.id, now)
		growing[species.id] = math.floor(MarketService.getGrowing(species.id, now) + 0.5)
	end
	local event = MarketService.currentEvent(now)
	local eventInfo = nil
	if event then
		local fishName = if event.speciesIndex then Config.Species[event.speciesIndex].name else ""
		eventInfo = {
			title = event.def.title,
			text = (string.gsub(event.def.text, "{fish}", fishName)),
			speciesId = if event.speciesIndex then Config.Species[event.speciesIndex].id else nil,
			endsAt = event.endsAt,
		}
	end
	return {
		now = now,
		prices = prices,
		eggPrices = eggPrices,
		growing = growing,
		history = history,
		event = eventInfo,
		fee = Config.MARKET_FEE,
	}
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
			task.wait(MarketMath.HISTORY_STEP)
			recordHistory(os.time())
		end
	end)
end

return MarketService
