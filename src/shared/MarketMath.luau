-- Pure price math. No services, no state: same inputs -> same price on every server.
--
-- price = basePrice * drift * eventMult / (1 + pressure / liquidity), clamped to [0.3x, 3x] base
--   drift     : slow deterministic demand waves (market moves even when nobody trades)
--   eventMult : hourly random events, seeded by the hour so all servers agree without talking
--   pressure  : recent units sold across ALL servers, decays with a 20 min half-life (mean reversion)

local MarketMath = {}

MarketMath.HALF_LIFE = 20 * 60
MarketMath.MIN_MULT = 0.3
MarketMath.MAX_MULT = 3
MarketMath.HISTORY_POINTS = 60 -- one point per minute = last hour on the chart
MarketMath.HISTORY_STEP = 60
MarketMath.EVENT_CHANCE = 0.4 -- chance an hour has an event
MarketMath.EVENT_DURATION = 20 * 60

MarketMath.EVENTS = {
	{ id = "festival", title = "Sushi Festival", text = "Everyone wants {fish}! Price x{mult}", mult = 2.5, scope = "one" },
	{ id = "chef", title = "Celebrity Chef", text = "A famous chef is buying {fish}. Price x{mult}", mult = 3, scope = "one" },
	{ id = "scare", title = "Fish Flu Scare", text = "Nobody wants {fish} right now. Price x0.5", mult = 0.5, scope = "one" },
	{ id = "storm", title = "Storm at Sea", text = "No boats out today. All prices +40%", mult = 1.4, scope = "all" },
}

local TAU = 2 * math.pi

-- Egg demand: every egg bought adds 1 to egg pressure (same 20 min half-life).
-- eggPrice = base egg price * (1 + EGG_SENSITIVITY * pressure / liquidity), capped at EGG_MAX_MULT.
-- e.g. Koi (liquidity 8): each recent Koi egg bought makes the next one ~6% pricier.
MarketMath.EGG_SENSITIVITY = 0.5
MarketMath.EGG_MAX_MULT = 2

function MarketMath.decay(pressure: number, dt: number, halfLife: number?): number
	if dt <= 0 then
		return pressure
	end
	return pressure * 0.5 ^ (dt / (halfLife or MarketMath.HALF_LIFE))
end

function MarketMath.eggMult(species, eggPressure: number): number
	return math.min(MarketMath.EGG_MAX_MULT, 1 + MarketMath.EGG_SENSITIVITY * eggPressure / species.liquidity)
end

function MarketMath.eggPrice(species, eggPressure: number): number
	return math.floor(species.eggPrice * MarketMath.eggMult(species, eggPressure) + 0.5)
end

-- Recent egg buys (decaying) at or above this show a ▲ "demand rising" marker, even when the
-- price rise is still too small to change the rounded coin price.
MarketMath.EGG_DEMAND_MARKER = 0.5

-- ~0.76x .. 1.24x, three overlapping waves (3h, 47m, 11m), phase-shifted per species
function MarketMath.drift(speciesIndex: number, t: number): number
	local s = speciesIndex * 1.7
	return 1
		+ 0.12 * math.sin(TAU * t / (3 * 3600) + s)
		+ 0.08 * math.sin(TAU * t / (47 * 60) + s * 2.3)
		+ 0.04 * math.sin(TAU * t / (11 * 60) + s * 3.1)
end

-- Returns the active event at time t, or nil. Deterministic per hour, so all servers agree.
-- The server passes a secret: clients can read this file but not the secret, so they can't
-- work out future events.
function MarketMath.eventAt(t: number, speciesCount: number, secret: number?)
	local hour = t // 3600
	local rng = Random.new(hour * 7919 + 17 + (secret or 0))
	if rng:NextNumber() > MarketMath.EVENT_CHANCE then
		return nil
	end
	local def = MarketMath.EVENTS[rng:NextInteger(1, #MarketMath.EVENTS)]
	local speciesIndex = rng:NextInteger(1, speciesCount)
	local startsAt = hour * 3600 + rng:NextInteger(0, 40) * 60
	local endsAt = startsAt + MarketMath.EVENT_DURATION
	if t < startsAt or t >= endsAt then
		return nil
	end
	return {
		def = def,
		speciesIndex = if def.scope == "one" then speciesIndex else nil,
		startsAt = startsAt,
		endsAt = endsAt,
	}
end

function MarketMath.eventMult(event, speciesIndex: number): number
	if not event then
		return 1
	end
	if event.def.scope == "all" or event.speciesIndex == speciesIndex then
		return event.def.mult
	end
	return 1
end

function MarketMath.price(species, t: number, pressure: number, eventMult: number): number
	local raw = species.basePrice * MarketMath.drift(species.index, t) * eventMult / (1 + pressure / species.liquidity)
	return math.clamp(raw, species.basePrice * MarketMath.MIN_MULT, species.basePrice * MarketMath.MAX_MULT)
end

-- Selling many fish at once walks the price down fish by fish (slippage).
-- This is also the anti-dump rule: one big seller can't sell 100 fish at the top price.
-- Returns gross coins and the pressure added.
function MarketMath.quoteSale(species, t: number, pressure: number, eventMult: number, sizes: { number }): (number, number)
	local total = 0
	local p = pressure
	for _, size in sizes do
		total += MarketMath.price(species, t, p, eventMult) * size
		p += size
	end
	return total, p - pressure
end

return MarketMath
