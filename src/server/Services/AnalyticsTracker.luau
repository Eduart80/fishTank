-- Player tracking for the Creator Dashboard (free, invisible to players).
--  * Onboarding funnel: shows the % of new players reaching each first-time step,
--    so we see exactly where people quit.
--  * Economy events: where coins come from (sales, rescue) and go (eggs, food, slots).
--  * Custom events: fish starved, rescue given.
-- Every call is wrapped in pcall: analytics must never break the game.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local AnalyticsTracker = {}

local STEPS = {
	"Joined",
	"Bought first egg",
	"First fish grown",
	"First sale",
	"Clownfish unlocked",
	"Grew a 2nd species",
}

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Analytics]", err)
	end
end

-- Highest onboarding step this player has reached (steps must happen in order).
local function stepReached(data): number
	local hasAdult, hasOtherSpecies = false, false
	for _, fish in data.fish do
		if fish.age >= 1 then
			hasAdult = true
		end
		if fish.species ~= "guppy" then
			hasOtherSpecies = true
		end
	end
	local stats = data.stats
	local clown = Config.ById.clownfish
	local checks = {
		#data.fish > 0 or stats.sold > 0 or stats.died > 0, -- 2 egg
		hasAdult or stats.sold > 0, -- 3 grown
		stats.sold > 0, -- 4 sale
		clown ~= nil and stats.earned >= (clown.unlockEarned or 0), -- 5 unlock
		hasOtherSpecies or (data.onboard or 0) >= 6, -- 6 second species
	}
	local step = 1
	for i, ok in checks do
		if not ok then
			break
		end
		step = i + 1
	end
	return step
end

AnalyticsTracker._stepReached = stepReached -- for the Studio test runner

-- Call after anything that may change progress (cheap; logs only new steps).
function AnalyticsTracker.check(player: Player, data)
	local target = stepReached(data)
	local done = data.onboard or 0
	if target <= done then
		return
	end
	for step = done + 1, target do
		safe(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, step, STEPS[step])
	end
	data.onboard = target
end

local SINKS = { buyEgg = true, feed = true, buySlot = true }
local SOURCES = { sell = true, sellAllAdults = true }

-- Coin movement from one player action (delta = coins after - coins before).
function AnalyticsTracker.economy(player: Player, data, action: string, delta: number, sku: string?)
	if delta == 0 then
		return
	end
	local flow
	if delta < 0 and SINKS[action] then
		flow = Enum.AnalyticsEconomyFlowType.Sink
	elseif delta > 0 and (SOURCES[action] or action == "rescue") then
		flow = Enum.AnalyticsEconomyFlowType.Source
	else
		return
	end
	local transaction = if action == "rescue" then Enum.AnalyticsEconomyTransactionType.TimedReward.Name
		elseif flow == Enum.AnalyticsEconomyFlowType.Sink then Enum.AnalyticsEconomyTransactionType.Shop.Name
		else Enum.AnalyticsEconomyTransactionType.Gameplay.Name
	safe(AnalyticsService.LogEconomyEvent, AnalyticsService, player, flow, "Coins", math.abs(math.floor(delta)), math.floor(data.coins), transaction, sku or action)
end

function AnalyticsTracker.custom(player: Player, name: string, value: number?)
	safe(AnalyticsService.LogCustomEvent, AnalyticsService, player, name, value or 1)
end

return AnalyticsTracker
