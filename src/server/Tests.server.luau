-- Scenario tests. Run automatically when you press Play/Run in STUDIO (never on live servers).
-- Results print in View -> Output:  ✅ PASS / ❌ FAIL lines and a summary at the end.
-- Uses fake player data only; market changes made by the tests are rolled back afterwards.
-- Turn off with Config.RUN_TESTS_IN_STUDIO = false.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
if not RunService:IsStudio() or not Config.RUN_TESTS_IN_STUDIO then
	return
end

local MarketMath = require(Shared.MarketMath)
local Services = script.Parent:WaitForChild("Services")
local DataService = require(Services.DataService)
local MarketService = require(Services.MarketService)
local TankService = require(Services.TankService)
local AnalyticsTracker = require(Services.AnalyticsTracker)
local PatioService = require(Services.PatioService)
local PatioModels = require(Services.PatioModels)

-- wait until Main has started the market (WorldService starts right after it)
workspace:WaitForChild("FishWorld", 30)

local H = 3600
local passed, failed = 0, 0
local failures = {}

local function newPlayer(now)
	return DataService.defaultData(now)
end

local function addFish(data, speciesId, age, now)
	table.insert(data.fish, { uid = data.nextUid, species = speciesId, age = age, born = now, lastUpdate = now })
	data.nextUid += 1
	return data.fish[#data.fish]
end

-- game hours -> real seconds (Studio runs TIME_SCALE x faster)
local function later(now, gameHours)
	return now + Config.real(gameHours * H)
end

local function test(name, fn)
	local checks = {}
	local function check(ok, what)
		if not ok then
			table.insert(checks, what)
		end
	end
	local ok, err = pcall(fn, check)
	if not ok then
		table.insert(checks, "crashed: " .. tostring(err))
	end
	if #checks == 0 then
		passed += 1
		print("✅ PASS  " .. name)
	else
		failed += 1
		table.insert(failures, name)
		warn("❌ FAIL  " .. name .. "  →  " .. table.concat(checks, " | "))
	end
end

local marketBackup = MarketService._saveForTests()
local now = os.time()
print("──────── Fish Market scenario tests ────────")

-- New player --------------------------------------------------------------
test("New player starts with 100 coins, 6 slots, no fish, food on", function(check)
	local d = newPlayer(now)
	check(d.coins == Config.STARTING_COINS, "coins " .. d.coins)
	check(d.slots == Config.STARTING_SLOTS, "slots " .. d.slots)
	check(#d.fish == 0, "has fish")
	check(d.fedUntil > now, "no starting food")
end)

-- Eggs --------------------------------------------------------------------
test("Buy a guppy egg: coins go down, 1 fish in tank", function(check)
	local d = newPlayer(now)
	local price = MarketService.getEggPrice("guppy", now)
	local ok = TankService.buyEgg(d, "guppy", now)
	check(ok, "refused")
	check(#d.fish == 1, "fish count " .. #d.fish)
	check(d.coins == Config.STARTING_COINS - price, "coins " .. d.coins .. " expected " .. (Config.STARTING_COINS - price))
end)

test("Can't buy an egg with 0 coins", function(check)
	local d = newPlayer(now)
	d.coins = 0
	local ok = TankService.buyEgg(d, "guppy", now)
	check(not ok, "egg was given for free")
	check(#d.fish == 0, "fish appeared")
end)

test("Clownfish locked until 150 earned, then buyable", function(check)
	local d = newPlayer(now)
	d.coins = 1000
	check(not TankService.buyEgg(d, "clownfish", now), "bought while locked")
	d.stats.earned = 150
	check(TankService.buyEgg(d, "clownfish", now), "still locked at 150 earned")
end)

test("Koi locked for a new rich player", function(check)
	local d = newPlayer(now)
	d.coins = 1000000
	check(not TankService.buyEgg(d, "koi", now), "koi bought without unlock")
end)

test("Unknown fish id is refused", function(check)
	local d = newPlayer(now)
	check(not TankService.buyEgg(d, "kraken", now), "accepted fake species")
end)

test("Full tank refuses more eggs", function(check)
	local d = newPlayer(now)
	d.coins = 10000
	for _ = 1, d.slots do
		addFish(d, "guppy", 0, now)
	end
	check(not TankService.buyEgg(d, "guppy", now), "egg added to a full tank")
	check(#d.fish == d.slots, "fish count " .. #d.fish)
end)

test("First egg into an empty, unfed tank gets free mercy food", function(check)
	local d = newPlayer(now)
	d.fedUntil = now - 10
	TankService.buyEgg(d, "guppy", now)
	check(d.fedUntil > now, "no mercy food")
end)

-- Growth ------------------------------------------------------------------
test("Fed guppy becomes adult after its grow time", function(check)
	local d = newPlayer(now)
	d.fedUntil = later(now, 12)
	local fish = addFish(d, "guppy", 0, now)
	TankService.settle(d, now + Config.real(Config.ById.guppy.growSeconds) + 1)
	check(fish.age >= 1, ("age %.2f"):format(fish.age))
end)

test("Hungry fish don't grow", function(check)
	local d = newPlayer(now)
	d.fedUntil = now
	local fish = addFish(d, "guppy", 0.5, now)
	TankService.settle(d, later(now, 1))
	check(fish.age == 0.5, ("age changed to %.2f"):format(fish.age))
end)

test("Growth stops at max age", function(check)
	local d = newPlayer(now)
	d.fedUntil = later(now, 12)
	local fish = addFish(d, "guppy", Config.MAX_AGE - 0.01, now)
	TankService.settle(d, later(now, 11))
	check(fish.age <= Config.MAX_AGE, ("age %.2f"):format(fish.age))
end)

-- Starvation --------------------------------------------------------------
test("Guppy survives 11h hungry", function(check)
	local d = newPlayer(now)
	d.fedUntil = now
	addFish(d, "guppy", 1, now)
	local died = TankService.settle(d, later(now, 11))
	check(#died == 0, "died early")
end)

test("Guppy starves after 12h hungry, koi survives", function(check)
	local d = newPlayer(now)
	d.fedUntil = now
	addFish(d, "guppy", 1, now)
	addFish(d, "koi", 1, now)
	local died = TankService.settle(d, later(now, 13))
	check(#died == 1 and died[1].species == "guppy", "died: " .. #died)
	check(#d.fish == 1 and d.fish[1].species == "koi", "koi missing")
	check(d.stats.died == 1, "died stat " .. d.stats.died)
end)

test("Every species dies after its own starve time (and not before)", function(check)
	for _, species in Config.Species do
		local d = newPlayer(now)
		d.fedUntil = now
		addFish(d, species.id, 1, now)
		local early = TankService.settle(d, later(now, species.starveHours - 0.5))
		check(#early == 0, species.name .. " died too early")
		local dead = TankService.settle(d, later(now, species.starveHours + 0.5))
		check(#dead == 1, species.name .. " didn't die")
	end
end)

test("Away for a week with no food: everything dead, nothing negative", function(check)
	local d = newPlayer(now)
	d.fedUntil = now
	for _, species in Config.Species do
		addFish(d, species.id, 1, now)
	end
	TankService.settle(d, later(now, 24 * 7))
	check(#d.fish == 0, #d.fish .. " still alive")
	check(d.coins >= 0, "coins negative")
end)

test("Unknown species in save data is kept, not deleted", function(check)
	local d = newPlayer(now)
	addFish(d, "removed_species", 1, now)
	TankService.settle(d, later(now, 100))
	check(#d.fish == 1, "fish deleted")
end)

-- Feeding -----------------------------------------------------------------
test("Feeding with no fish is refused", function(check)
	local d = newPlayer(now)
	check(not TankService.feed(d, now), "fed an empty tank")
end)

test("Feeding costs coins and pushes food time up", function(check)
	local d = newPlayer(now)
	d.fedUntil = now
	addFish(d, "guppy", 0, now)
	local ok = TankService.feed(d, now)
	check(ok, "refused")
	check(d.coins < Config.STARTING_COINS, "free food")
	check(d.fedUntil > now, "food time not moved")
end)

test("Feeding a full tank again is refused (no double charge)", function(check)
	local d = newPlayer(now)
	addFish(d, "guppy", 0, now)
	TankService.feed(d, now)
	local coins = d.coins
	check(not TankService.feed(d, now), "fed again")
	check(d.coins == coins, "charged twice")
end)

test("Poor player buys only the food they can afford", function(check)
	local d = newPlayer(now)
	d.fedUntil = now
	d.coins = 3
	addFish(d, "guppy", 0, now)
	TankService.feed(d, now)
	check(d.coins >= 0, "coins negative: " .. d.coins)
	check(d.fedUntil > now and d.fedUntil <= later(now, 3) + 1, "wrong food amount")
end)

-- Selling -----------------------------------------------------------------
test("Baby fish can't be sold", function(check)
	local d = newPlayer(now)
	addFish(d, "guppy", 0.5, now)
	check(not TankService.sell(d, nil, now), "sold a baby")
	check(#d.fish == 1, "baby removed")
end)

test("Selling an adult: coins up, earned up, fish gone", function(check)
	local d = newPlayer(now)
	local fish = addFish(d, "guppy", 1, now)
	local coins = d.coins
	local ok = TankService.sell(d, { fish.uid }, now)
	check(ok, "refused")
	check(d.coins > coins, "no coins")
	check(d.stats.earned == d.coins - coins, "earned stat wrong")
	check(#d.fish == 0, "fish still there")
end)

test("Sell all adults keeps the babies", function(check)
	local d = newPlayer(now)
	addFish(d, "guppy", 1, now)
	addFish(d, "guppy", 1.5, now)
	addFish(d, "guppy", 0.3, now)
	TankService.sell(d, nil, now)
	check(#d.fish == 1 and d.fish[1].age == 0.3, "wrong fish left: " .. #d.fish)
end)

test("Can't sell someone else's fish id", function(check)
	local d = newPlayer(now)
	addFish(d, "guppy", 1, now)
	check(not TankService.sell(d, { 999 }, now), "sold a fish that isn't ours")
	check(#d.fish == 1, "our fish removed")
end)

test("Bigger fish sells for more", function(check)
	local a, b = newPlayer(now), newPlayer(now)
	local fa = addFish(a, "clownfish", 1, now)
	local fb = addFish(b, "clownfish", Config.MAX_AGE, now)
	local backup = MarketService._saveForTests()
	TankService.sell(a, { fa.uid }, now)
	MarketService._restoreForTests(backup)
	TankService.sell(b, { fb.uid }, now)
	MarketService._restoreForTests(backup)
	check(b.coins > a.coins, ("normal %d vs big %d"):format(a.coins, b.coins))
end)

-- Rescue ------------------------------------------------------------------
test("Broke with no fish: rescue gives coins once", function(check)
	local d = newPlayer(now)
	d.coins = 0
	check(TankService.rescueIfBroke(d, now), "no rescue")
	check(d.coins == Config.RESCUE_COINS, "coins " .. d.coins)
	check(not TankService.rescueIfBroke(d, now), "rescued twice")
end)

test("No rescue while you still own fish", function(check)
	local d = newPlayer(now)
	d.coins = 0
	addFish(d, "guppy", 0, now)
	check(not TankService.rescueIfBroke(d, now), "rescued with fish")
end)

test("Rescue coins can always buy a guppy egg (even at max demand)", function(check)
	local maxEgg = Config.ById.guppy.eggPrice * MarketMath.EGG_MAX_MULT
	check(Config.RESCUE_COINS >= maxEgg, ("rescue %d < max egg %d"):format(Config.RESCUE_COINS, maxEgg))
end)

-- Slots -------------------------------------------------------------------
test("Buying a slot costs coins and adds 1 slot", function(check)
	local d = newPlayer(now)
	d.coins = Config.slotCost(d.slots)
	check(TankService.buySlot(d), "refused")
	check(d.slots == Config.STARTING_SLOTS + 1, "slots " .. d.slots)
	check(d.coins == 0, "coins " .. d.coins)
end)

test("No slots beyond the max", function(check)
	local d = newPlayer(now)
	d.slots = Config.MAX_SLOTS
	d.coins = 1e12
	check(not TankService.buySlot(d), "went past max")
end)

test("Tank stages follow slots: 6=Small, 10=Medium, 15=Large, 20+=Sea Pen", function(check)
	check(Config.tankStage(Config.STARTING_SLOTS) == 1, "start")
	check(Config.tankStage(9) == 1 and Config.tankStage(10) == 2, "medium at 10")
	check(Config.tankStage(14) == 2 and Config.tankStage(15) == 3, "large at 15")
	check(Config.tankStage(19) == 3 and Config.tankStage(20) == 4, "sea pen at 20")
	check(Config.tankStage(Config.MAX_SLOTS) == #Config.TANK_STAGES, "max slots = last stage")
end)

test("Buying the 10th slot announces the Medium Tank", function(check)
	local d = newPlayer(now)
	d.slots = 9
	d.coins = Config.slotCost(9)
	local ok, msg = TankService.buySlot(d)
	check(ok and string.find(msg, "Medium Tank", 1, true) ~= nil, tostring(msg))
end)

test("Tank stages never leave their pie slice (8 slices, 10° walkway each side)", function(check)
	local halfSlice = math.rad(45 / 2 - 5)
	local plotRadius = 70
	for i, s in Config.TANK_STAGES do
		local backR = plotRadius + s.backZ
		local backCornerAngle = math.atan(s.halfBack / backR)
		local frontCornerAngle = math.atan(10 / (plotRadius - 5))
		check(backCornerAngle <= halfSlice and frontCornerAngle <= halfSlice, ("stage %d too wide"):format(i))
		if i > 1 then
			local prev = Config.TANK_STAGES[i - 1]
			check(s.backZ > prev.backZ and s.halfBack >= prev.halfBack, ("stage %d not bigger"):format(i))
		end
	end
end)

-- Market ------------------------------------------------------------------
test("50 salmon dumped: price drops", function(check)
	local before = MarketService.getPrice("salmon", now)
	local sizes = table.create(50, 1)
	MarketService.sell("salmon", sizes, now)
	local after = MarketService.getPrice("salmon", now)
	check(after < before * 0.8, ("%.0f -> %.0f"):format(before, after))
	check(after >= Config.ById.salmon.basePrice * MarketMath.MIN_MULT * 0.99, "fell below the price floor")
end)

test("Dumped price pressure fades (half after 20 min)", function(check)
	local p = MarketMath.decay(100, MarketMath.HALF_LIFE)
	check(math.abs(p - 50) < 1, ("pressure %.1f"):format(p))
	check(MarketMath.decay(100, MarketMath.HALF_LIFE * 10) < 1, "never recovers")
end)

test("Selling one big batch pays less per fish than one fish (slippage)", function(check)
	local species = Config.ById.tuna
	local one = MarketMath.quoteSale(species, now, 0, 1, { 1 })
	local ten = MarketMath.quoteSale(species, now, 0, 1, table.create(10, 1))
	check(ten < one * 10, ("1 = %d, 10 = %d"):format(one, ten))
end)

test("Prices stay inside 0.3x-3x of base all day", function(check)
	for _, species in Config.Species do
		for h = 0, 24 do
			local t = now + h * H
			local p = MarketMath.price(species, t, 0, MarketMath.eventMult(MarketMath.eventAt(t, #Config.Species), species.index))
			check(p >= species.basePrice * MarketMath.MIN_MULT - 0.01 and p <= species.basePrice * MarketMath.MAX_MULT + 0.01, species.name .. " out of range at +" .. h .. "h")
		end
	end
end)

test("Egg price rises with demand, capped at 2x", function(check)
	local base = MarketService.getEggPrice("guppy", now)
	for _ = 1, 2000 do
		MarketService.recordEggBuy("guppy")
	end
	local high = MarketService.getEggPrice("guppy", now)
	check(high > base, ("%d -> %d"):format(base, high))
	check(high <= Config.ById.guppy.eggPrice * MarketMath.EGG_MAX_MULT, "above the 2x cap: " .. high)
end)

test("Buying eggs raises the 'growing worldwide' count", function(check)
	local before = MarketService.getGrowing("tuna", now)
	MarketService.recordEggBuy("tuna")
	check(MarketService.getGrowing("tuna", now) >= before + 0.99, "count didn't go up")
end)

-- Tracking ----------------------------------------------------------------
test("Tracking steps happen in the right order", function(check)
	local step = AnalyticsTracker._stepReached
	local d = newPlayer(now)
	check(step(d) == 1, "fresh player step " .. step(d))
	local fish = addFish(d, "guppy", 0, now)
	check(step(d) == 2, "after egg " .. step(d))
	fish.age = 1
	check(step(d) == 3, "after grown " .. step(d))
	d.stats.sold = 1
	d.stats.earned = 20
	check(step(d) == 4, "after sale " .. step(d))
	d.stats.earned = 150
	check(step(d) == 5, "after unlock " .. step(d))
	addFish(d, "clownfish", 0, now)
	check(step(d) == 6, "after 2nd species " .. step(d))
end)

test("Tracking never skips a step (sale without unlock stays at 4)", function(check)
	local d = newPlayer(now)
	d.stats.sold = 3
	d.stats.earned = 40
	addFish(d, "clownfish", 0, now) -- odd save data: 2nd species but no unlock
	check(AnalyticsTracker._stepReached(d) == 4, "step " .. AnalyticsTracker._stepReached(d))
end)

-- Fishing boat ------------------------------------------------------------
test("Boat buys only adults of the wanted species, biggest first, up to its limit", function(check)
	local d = newPlayer(now)
	addFish(d, "clownfish", 1, now)
	addFish(d, "clownfish", Config.MAX_AGE, now)
	addFish(d, "clownfish", 0.5, now) -- baby
	addFish(d, "guppy", 1, now) -- other species
	local coins = d.coins
	local count, paid = TankService.sellToBuyer(d, "clownfish", 1, 100)
	check(count == 1, "sold " .. count)
	check(paid == math.floor(100 * Config.MAX_SIZE + 0.5), "paid " .. paid .. " (should take the biggest)")
	check(d.coins == coins + paid and d.stats.earned == paid, "coins/earned wrong")
	check(#d.fish == 3, "fish left " .. #d.fish)
end)

test("Boat pays nothing if you have no matching adults", function(check)
	local d = newPlayer(now)
	addFish(d, "salmon", 0.9, now)
	local count, paid = TankService.sellToBuyer(d, "salmon", 3, 200)
	check(count == 0 and paid == 0, "sold a baby")
	check(#d.fish == 1, "fish removed")
end)

test("Piers sit in tank gaps facing a straight island edge (0/90/180/270), no duplicates", function(check)
	local seen = {}
	for _, pier in Config.BOAT.piers do
		check(pier.angle % 90 == 0, ("pier at %d° is not on an island edge"):format(pier.angle))
		local key = pier.angle % 360
		check(not seen[key], ("two piers at %d°"):format(pier.angle))
		seen[key] = true
	end
	check(seen[0], "main pier (angle 0) missing: the boat path is built for it")
	-- boats start a moment after the world; wait for the last dock before counting
	local n = #Config.BOAT.piers
	workspace.FishWorld:WaitForChild(if n == 1 then "BoatDock" else "BoatDock" .. n, 10)
	local docks = 0
	for _, child in workspace.FishWorld:GetChildren() do
		if string.sub(child.Name, 1, 8) == "BoatDock" then
			docks += 1
		end
	end
	check(docks == #Config.BOAT.piers, ("%d boat docks for %d piers"):format(docks, #Config.BOAT.piers))
end)

test("Expensive fish events are capped at x2", function(check)
	check(Config.ById.tuna.maxEventMult == 2 and Config.ById.koi.maxEventMult == 2, "cap missing")
end)

-- Harbor Store / patio ------------------------------------------------------
test("Store: buying a coin item costs coins and goes to the inventory", function(check)
	local d = newPlayer(now)
	d.coins = 500
	local ok, msg = PatioService.buy(d, "chair")
	check(ok, tostring(msg))
	check(d.coins == 500 - Config.PatioById.chair.price, "coins " .. d.coins)
	check(d.inventory.chair == 1, "not in inventory")
end)

test("Store: can't buy without coins, can't buy Robux items with coins, junk ids refused", function(check)
	local d = newPlayer(now)
	d.coins = 10
	check(not PatioService.buy(d, "umbrella"), "bought without coins")
	check(d.coins == 10, "coins changed")
	d.coins = 1e9
	check(not PatioService.buy(d, "goldenFish"), "Robux item bought with coins")
	check(not PatioService.buy(d, "nope") and not PatioService.buy(d, 5), "junk id accepted")
end)

test("Patio: place, swap and pick up keep the inventory honest", function(check)
	local d = newPlayer(now)
	d.coins = 1e6
	PatioService.buy(d, "chair")
	PatioService.buy(d, "torch")
	check(not PatioService.place(d, 1, "umbrella"), "placed an item not owned")
	check(PatioService.place(d, 1, "chair"), "place failed")
	check(d.patio.s1 == "chair" and d.inventory.chair == nil, "chair not moved to the patio")
	check(PatioService.place(d, 1, "torch"), "swap failed")
	check(d.patio.s1 == "torch" and d.inventory.chair == 1 and d.inventory.torch == nil, "swap lost an item")
	check(PatioService.pickUp(d, 1), "pick up failed")
	check(d.patio.s1 == nil and d.inventory.torch == 1, "pick up lost the torch")
	check(not PatioService.place(d, 0, "torch") and not PatioService.place(d, Config.PATIO_SPOTS + 1, "torch") and not PatioService.place(d, 1.5, "torch"), "bad spot accepted")
end)

test("Flags: colour is saved, junk colours refused, recolour in place, pick up clears it", function(check)
	local d = newPlayer(now)
	d.coins = 1e6
	PatioService.buy(d, "flag")
	PatioService.buy(d, "chair")
	check(not PatioService.place(d, 1, "flag", "sparkly"), "junk colour accepted")
	check(d.inventory.flag == 1, "flag lost on refused place")
	check(PatioService.place(d, 1, "flag", "red"), "place red failed")
	check(d.patio.s1 == "flag" and d.patioColors.s1 == "red", "colour not saved")
	check(PatioService.place(d, 1, "flag", "green") and d.patioColors.s1 == "green", "recolour failed")
	check((d.inventory.flag or 0) == 0, "recolour changed the inventory")
	check(PatioService.place(d, 2, "chair", "red") and d.patioColors.s2 == nil, "chair got a colour")
	check(PatioService.pickUp(d, 1) and d.patioColors.s1 == nil, "colour left behind")
end)

test("Patio: old saves without patio fields still work", function(check)
	local d = newPlayer(now)
	d.inventory, d.patio = nil, nil
	check(not PatioService.pickUp(d, 1), "picked up from nothing")
	local state = PatioService.publicState(d)
	check(type(state.inventory) == "table" and type(state.patio) == "table", "fields missing")
end)

test("Every store item has a price XOR a Robux id, and a 3D model", function(check)
	for _, item in Config.PATIO_ITEMS do
		check((item.price ~= nil) ~= (item.robuxId ~= nil), item.id .. " needs price OR robuxId")
		local m = PatioModels.build(item.id, CFrame.new(0, -1000, 0))
		check(m ~= nil and #m:GetChildren() > 0, item.id .. " has no model")
		if m then
			m:Destroy()
		end
	end
end)

-- Robux items -------------------------------------------------------------
test("Starter Pack: free egg goes in the tank (no price, no unlock); full tank refuses it", function(check)
	local d = newPlayer(now)
	local coins = d.coins
	check(TankService.giveEgg(d, "clownfish", now), "egg refused")
	check(#d.fish == 1 and d.fish[1].species == "clownfish" and d.coins == coins, "egg wrong or charged")
	d.slots = #d.fish
	check(not TankService.giveEgg(d, "guppy", now), "egg added to a full tank")
	check(not TankService.giveEgg(d, "notAFish", now), "unknown species accepted")
end)

test("Robux ids are filled in and the Starter Pack is one per player", function(check)
	local starter = nil
	for _, item in Config.ROBUX do
		check(item.id ~= 0, item.key .. " has no id")
		if item.key == "starterPack" then
			starter = item
		end
	end
	check(starter ~= nil and starter.once == true and Config.PatioById[starter.item] ~= nil and Config.ById[starter.egg] ~= nil, "starter pack config broken")
	for _, item in Config.PATIO_ITEMS do
		check(item.robuxId == nil or item.robuxId ~= 0, item.id .. " Robux id missing")
	end
end)

test("Auto-Feeder: fish never starve, even a week offline", function(check)
	local d = newPlayer(now)
	d.autoFeeder = true
	d.fedUntil = now
	addFish(d, "guppy", 0, now)
	local died = TankService.settle(d, later(now, 24 * 7))
	check(#died == 0, "fish died with Auto-Feeder")
	check(d.fish[1] and d.fish[1].age > 1, "fish didn't grow")
end)

test("Grow Boost: fish grow 2x during the boost, normal after", function(check)
	local a, b = newPlayer(now), newPlayer(now)
	a.fedUntil, b.fedUntil = later(now, 12), later(now, 12)
	local fa = addFish(a, "salmon", 0, now)
	local fb = addFish(b, "salmon", 0, now)
	b.boostUntil = later(now, 1)
	TankService.settle(a, later(now, 2))
	TankService.settle(b, later(now, 2))
	-- b: 1h boosted (counts 2h) + 1h normal = 3h of growth vs 2h for a
	check(math.abs(fb.age / fa.age - 1.5) < 0.01, ("normal %.3f vs boosted %.3f"):format(fa.age, fb.age))
end)

-- Done --------------------------------------------------------------------
MarketService._restoreForTests(marketBackup)
print("─────────────────────────────────────────────")
if failed == 0 then
	print(("🎉 ALL %d TESTS PASSED"):format(passed))
else
	warn(("%d passed, %d FAILED: %s"):format(passed, failed, table.concat(failures, ", ")))
end
