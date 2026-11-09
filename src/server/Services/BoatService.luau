-- The fishing boat: every so often (only when players are online) a boat sails to the pier and
-- asks for some adult fish of one species at a price near the market (sometimes better, sometimes
-- worse: check the board!). Each player has a PERSONAL quota, so nobody can steal your share.
-- The server only keeps the logic + a static prompt at the dock; clients draw the moving boat
-- (client/BoatRenderer) from the State / PhaseStart attributes on the BoatDock part.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BoatPath = require(Shared.BoatPath)
local MarketService = require(script.Parent.MarketService)
local TankService = require(script.Parent.TankService)

local BoatService = {}

local rng = Random.new()
local offer = nil -- { speciesId, name, perPlayer, price, endsAt, sold = { [userId] = count } } while docked
local dock, signLabel

local function setState(state: string)
	dock:SetAttribute("State", state)
	dock:SetAttribute("PhaseStart", workspace:GetServerTimeNow())
end

-- Pick what the boat wants: a species someone online has adults of (else any unlocked one).
local function makeOffer(datas, now: number)
	if #datas == 0 then
		return nil
	end
	local withAdults, unlocked = {}, {}
	for _, species in Config.Species do
		local hasAdults, isUnlocked = false, false
		for _, data in datas do
			if data.stats.earned >= (species.unlockEarned or 0) then
				isUnlocked = true
			end
			for _, fish in data.fish do
				if fish.species == species.id and fish.age >= 1 then
					hasAdults = true
				end
			end
		end
		if hasAdults then
			table.insert(withAdults, species)
		end
		if isUnlocked then
			table.insert(unlocked, species)
		end
	end
	local pool = if #withAdults > 0 then withAdults else unlocked
	if #pool == 0 then
		return nil
	end
	local species = pool[rng:NextInteger(1, #pool)]
	local maxWant = math.max(1, math.floor((species.orderSize or 4) / 2))
	local cfg = Config.BOAT
	return {
		speciesId = species.id,
		name = species.name,
		perPlayer = rng:NextInteger(1, maxWant),
		sold = {},
		price = math.max(1, math.floor(MarketService.getPrice(species.id, now) * rng:NextNumber(cfg.priceMin, cfg.priceMax) + 0.5)),
	}
end

local function updateSign()
	if not offer then
		return
	end
	local secs = math.max(0, offer.endsAt - os.time())
	signLabel.Text = ("🚤 Wants %d × %s from each player\n%d coins each · %d:%02d"):format(offer.perPlayer, offer.name, offer.price, secs // 60, secs % 60)
end

-- Everyone online has filled their share (nobody left to wait for).
local function everyoneDone(): boolean
	for _, player in Players:GetPlayers() do
		if (offer.sold[player.UserId] or 0) < offer.perPlayer then
			return false
		end
	end
	return true
end

local function visit(newOffer, notifyAll)
	setState("arriving")
	task.wait(BoatPath.ARRIVE_SECONDS)

	newOffer.endsAt = os.time() + Config.BOAT.staySeconds
	offer = newOffer
	setState("docked")
	dock.Prompt.ActionText = "Sell " .. offer.name
	dock.Prompt.Enabled = true
	notifyAll(("🚤 A fishing boat docked at the pier! It wants %d %s from each player, %d coins each."):format(offer.perPlayer, offer.name, offer.price))
	while not everyoneDone() and os.time() < offer.endsAt do
		updateSign()
		task.wait(1)
	end

	dock.Prompt.Enabled = false
	signLabel.Text = if everyoneDone() then "⛵ Full load, thanks!" else "⛵ Leaving..."
	offer = nil
	setState("leaving")
	task.wait(BoatPath.LEAVE_SECONDS)
	signLabel.Text = ""
	setState("away")
end

-- opts.getOnlineData(): { data } of players online; opts.notifyAll(text)
-- Returns the ProximityPrompt (Main connects it to player data).
function BoatService.start(opts)
	dock = Instance.new("Part")
	dock.Name = "BoatDock"
	dock.Anchored = true
	dock.CanCollide = false
	dock.CanTouch = false
	dock.Transparency = 1
	dock.Size = Vector3.new(1, 4, 20)
	dock.CFrame = CFrame.new(BoatPath.DOCK.X - 4.7, 2.5, BoatPath.DOCK.Z) -- hull edge facing the platform
	dock:SetAttribute("State", "away")
	dock:SetAttribute("PhaseStart", 0)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ObjectText = "Fishing Boat"
	prompt.ActionText = "Sell fish"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = dock

	local signPart = Instance.new("Part")
	signPart.Name = "BoatSign"
	signPart.Anchored = true
	signPart.CanCollide = false
	signPart.CanQuery = false
	signPart.CanTouch = false
	signPart.Transparency = 1
	signPart.Size = Vector3.new(1, 1, 1)
	signPart.CFrame = CFrame.new(BoatPath.DOCK + Vector3.new(0, 19, 0))
	signPart.Parent = dock
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(18, 4.5) -- studs
	billboard.MaxDistance = 250
	billboard.Parent = signPart
	signLabel = Instance.new("TextLabel")
	signLabel.BackgroundTransparency = 1
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Text = ""
	signLabel.Parent = billboard

	dock.Parent = workspace:WaitForChild("FishWorld")

	task.spawn(function()
		local cfg = Config.BOAT
		while true do
			task.wait(rng:NextNumber(cfg.intervalMin, cfg.intervalMax))
			local newOffer = makeOffer(opts.getOnlineData(), os.time())
			if newOffer then
				visit(newOffer, opts.notifyAll)
			end
		end
	end)

	return prompt
end

-- A player sells to the docked boat (biggest adults of the wanted species first), up to what
-- is left of their own share.
function BoatService.sell(player: Player, data, now: number)
	if not offer then
		return false, "The boat isn't buying right now"
	end
	local already = offer.sold[player.UserId] or 0
	local left = offer.perPlayer - already
	if left <= 0 then
		return false, "You already filled your share. The boat thanks you!"
	end
	local count, coins = TankService.sellToBuyer(data, offer.speciesId, left, offer.price)
	if count == 0 then
		return false, ("The boat wants adult %s. You don't have any."):format(offer.name)
	end
	offer.sold[player.UserId] = already + count
	return true, ("Sold %d %s to the boat for %d coins (%d/%d of your share)"):format(count, offer.name, coins, already + count, offer.perPlayer)
end

return BoatService
