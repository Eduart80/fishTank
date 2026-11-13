-- Robux shop (server side). Roblox handles the payment; we only GIVE the item, exactly once.
--   Game Pass (Auto-Feeder): Roblox remembers ownership. We check it on join and right after purchase.
--   Developer Product (Grow Boost): Roblox calls ProcessReceipt. We grant it, remember the
--   PurchaseId (so a retry never grants twice), SAVE, and only then tell Roblox "granted".
--   If anything fails we return NotProcessedYet and Roblox retries later: never charged without item.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local DataService = require(script.Parent.DataService)
local TankService = require(script.Parent.TankService)
local PatioService = require(script.Parent.PatioService)

local ShopService = {}

local MAX_RECEIPTS = 50 -- recent purchase ids kept per player

local byKey, byProductId, byPassId = {}, {}, {}
for _, item in Config.ROBUX do
	byKey[item.key] = item
	if item.id ~= 0 then
		if item.kind == "product" then
			byProductId[item.id] = item
		else
			byPassId[item.id] = item
		end
	end
end
-- Robux patio items (Harbor Store) are Developer Products too
for _, item in Config.PATIO_ITEMS do
	if item.robuxId and item.robuxId ~= 0 then
		byProductId[item.robuxId] = { key = "patio", patioId = item.id, name = item.name }
	end
end

local onChanged = function(_player: Player, _msg: string?, _fx: string?) end

-- One-time / visible pass perks, applied after ownership is known (join or purchase).
--   Bigger Tank: +2 slots, given once (data.bigTankGiven).  VIP: player attribute for the tag.
local function applyPassPerks(player: Player, data)
	if data.bigTank and not data.bigTankGiven then
		data.bigTankGiven = true
		data.slots += Config.BIG_TANK_SLOTS
	end
	player:SetAttribute("VIP", data.vip == true)
end
ShopService.applyPassPerks = applyPassPerks

-- Checks Game Pass ownership with Roblox and stores it on the data (e.g. data.autoFeeder). Yields.
function ShopService.refreshPasses(player: Player, data)
	for id, item in byPassId do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		if ok then
			data[item.key] = owns
		else
			warn("[Shop] pass check failed:", owns) -- keep the saved value
		end
	end
	applyPassPerks(player, data)
end

local function grantProduct(item, data, now: number)
	if item.key == "growBoost" then
		TankService.settle(data, now) -- growth up to now at the normal speed first
		local before = data.boostUntil or 0
		data.boostUntil = math.max(now, before) + Config.real(item.seconds)
		return function()
			data.boostUntil = before
		end, "Grow Boost active: your fish grow 2x faster!"
	elseif item.key == "starterPack" then
		-- 500 coins + Beach Umbrella + a Clownfish egg (if the tank is full: the egg's price in coins).
		-- If someone somehow buys it twice they still get it: they paid, we never keep Robux for nothing.
		TankService.settle(data, now)
		local before = { coins = data.coins, owned = data.starterPack, fishCount = #data.fish, nextUid = data.nextUid, fedUntil = data.fedUntil }
		data.coins += item.coins
		data.inventory = data.inventory or {}
		data.inventory[item.item] = (data.inventory[item.item] or 0) + 1
		local gotEgg = TankService.giveEgg(data, item.egg, now)
		local eggSpecies = Config.ById[item.egg]
		if not gotEgg then
			data.coins += eggSpecies.eggPrice
		end
		data.starterPack = true
		return function()
			data.coins = before.coins
			data.starterPack = before.owned
			PatioService.take(data, item.item)
			while #data.fish > before.fishCount do
				table.remove(data.fish)
			end
			data.nextUid = before.nextUid
			data.fedUntil = before.fedUntil
		end, if gotEgg then ("Starter Pack: +%d coins, a Beach Umbrella and a %s egg in your tank!"):format(item.coins, eggSpecies.name)
			else ("Starter Pack: +%d coins and a Beach Umbrella! Tank full, so +%d coins instead of the egg."):format(item.coins, eggSpecies.eggPrice)
	elseif item.key == "rareEgg" then
		-- random unlocked species, always Albino or Golden; full tank = waits in the Egg Incubator
		TankService.settle(data, now)
		local speciesId, variant = TankService.rollRareEgg(data)
		local species, v = Config.ById[speciesId], Config.VARIANTS[variant]
		local before = { fishCount = #data.fish, nextUid = data.nextUid, fedUntil = data.fedUntil }
		local label = ("%s %s %s"):format(v.icon, v.name, species.name)
		if TankService.giveEgg(data, speciesId, now, variant) then
			return function()
				while #data.fish > before.fishCount do
					table.remove(data.fish)
				end
				data.nextUid = before.nextUid
				data.fedUntil = before.fedUntil
			end, ("Rare Egg: a %s is growing in your tank! It sells for %sx."):format(label, tostring(v.mult))
		end
		data.incubator = data.incubator or {}
		table.insert(data.incubator, { species = speciesId, variant = variant })
		return function()
			table.remove(data.incubator)
		end, ("Rare Egg: a %s! Your tank is full, so it waits in the Egg Incubator until a slot is free."):format(label)
	elseif item.key == "patio" then
		-- goes to the inventory like a coin purchase; if it's full (10 of that item) we still grant
		-- it: they paid Robux, so the cap must never eat a purchase
		data.inventory = data.inventory or {}
		data.inventory[item.patioId] = (data.inventory[item.patioId] or 0) + 1
		return function()
			PatioService.take(data, item.patioId)
		end, item.name .. " is yours! Go to your tank and press E on a sand circle to place it."
	end
	return nil
end

local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local data = player and DataService.get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- not loaded here; Roblox retries later
	end
	data.receipts = data.receipts or {}
	if table.find(data.receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already given earlier
	end
	local item = byProductId[info.ProductId]
	if not item then
		warn("[Shop] unknown product id", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local undo, msg = grantProduct(item, data, os.time())
	if not undo then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.receipts, info.PurchaseId)
	while #data.receipts > MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end

	if not DataService.saveNow(player) then
		-- could not store it safely: take it back, Roblox will retry the receipt
		undo()
		table.remove(data.receipts, table.find(data.receipts, info.PurchaseId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	onChanged(player, msg, if item.key == "rareEgg" then "rare" else nil) -- rare = golden sparkle burst on the tank
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- opts.onChanged(player, msg?) is called after a purchase so Main can push the new state.
function ShopService.start(opts)
	onChanged = opts.onChanged
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local item = byPassId[passId]
		local data = DataService.get(player)
		if purchased and item and data then
			data[item.key] = true
			applyPassPerks(player, data)
			onChanged(player, item.name .. " is yours. Thank you!")
		end
	end)
end

ShopService.byKey = byKey

return ShopService
