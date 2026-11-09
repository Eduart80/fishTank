-- Fishing boats: every so often (only when players are online) a boat sails to a pier and
-- asks for some adult fish of one species at a price near the market (sometimes better, sometimes
-- worse: check the board!). Each player has a PERSONAL quota, so nobody can steal your share.
-- One boat per pier (Config.BOAT.piers), each on its own timer with its own offer.
-- The server only keeps the logic + a static prompt at each dock; clients draw the moving boats
-- (client/BoatRenderer) from the State / PhaseStart / PierAngle attributes on each BoatDock part.
-- Every pier is the main (+Z) pier turned around the island centre, so the path is shared
-- (BoatPath, built for the +Z pier) and simply rotated by the pier's angle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BoatPath = require(Shared.BoatPath)
local MarketService = require(script.Parent.MarketService)
local TankService = require(script.Parent.TankService)

local BoatService = {}

local rng = Random.new()

-- Pick what a boat wants: a species someone online has adults of (else any unlocked one).
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

local function setState(boat, state: string)
	boat.dock:SetAttribute("State", state)
	boat.dock:SetAttribute("PhaseStart", workspace:GetServerTimeNow())
end

local function updateSign(boat)
	local offer = boat.offer
	if not offer then
		return
	end
	local secs = math.max(0, offer.endsAt - os.time())
	boat.signLabel.Text = ("🚤 Wants %d × %s from each player\n%d coins each · %d:%02d"):format(offer.perPlayer, offer.name, offer.price, secs // 60, secs % 60)
end

-- Everyone online has filled their share at this boat (nobody left to wait for).
local function everyoneDone(boat): boolean
	for _, player in Players:GetPlayers() do
		if (boat.offer.sold[player.UserId] or 0) < boat.offer.perPlayer then
			return false
		end
	end
	return true
end

local function visit(boat, newOffer, notifyAll)
	setState(boat, "arriving")
	task.wait(BoatPath.ARRIVE_SECONDS)

	newOffer.endsAt = os.time() + Config.BOAT.staySeconds
	boat.offer = newOffer
	setState(boat, "docked")
	boat.prompt.ActionText = "Sell " .. newOffer.name
	boat.prompt.Enabled = true
	notifyAll(("🚤 A fishing boat docked at the %s! It wants %d %s from each player, %d coins each."):format(boat.pierName, newOffer.perPlayer, newOffer.name, newOffer.price))
	while not everyoneDone(boat) and os.time() < newOffer.endsAt do
		updateSign(boat)
		task.wait(1)
	end

	boat.prompt.Enabled = false
	boat.signLabel.Text = if everyoneDone(boat) then "⛵ Full load, thanks!" else "⛵ Leaving..."
	boat.offer = nil
	setState(boat, "leaving")
	task.wait(BoatPath.LEAVE_SECONDS)
	boat.signLabel.Text = ""
	setState(boat, "away")
end

local function createBoat(index: number, pier, parent: Instance)
	local rot = CFrame.Angles(0, math.rad(pier.angle), 0)

	local dock = Instance.new("Part")
	dock.Name = if index == 1 then "BoatDock" else "BoatDock" .. index
	dock.Anchored = true
	dock.CanCollide = false
	dock.CanTouch = false
	dock.Transparency = 1
	dock.Size = Vector3.new(1, 4, 20)
	dock.CFrame = rot * CFrame.new(BoatPath.DOCK.X - 4.7, 2.5, BoatPath.DOCK.Z) -- hull edge facing the platform
	dock:SetAttribute("State", "away")
	dock:SetAttribute("PhaseStart", 0)
	dock:SetAttribute("PierAngle", pier.angle)

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
	signPart.CFrame = rot * CFrame.new(BoatPath.DOCK + Vector3.new(0, 19, 0))
	signPart.Parent = dock
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(18, 4.5) -- studs
	billboard.MaxDistance = 250
	billboard.Parent = signPart
	local signLabel = Instance.new("TextLabel")
	signLabel.BackgroundTransparency = 1
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Text = ""
	signLabel.Parent = billboard

	dock.Parent = parent
	return { dock = dock, prompt = prompt, signLabel = signLabel, pierName = pier.name, offer = nil }
end

local boats = {}

-- opts.getOnlineData(): { data } of players online; opts.notifyAll(text)
-- Returns { [prompt] = boat } so Main can connect every boat's prompt to player data.
function BoatService.start(opts)
	local parent = workspace:WaitForChild("FishWorld")
	local prompts = {}
	for i, pier in Config.BOAT.piers do
		local boat = createBoat(i, pier, parent)
		boats[i] = boat
		prompts[boat.prompt] = boat
	end

	-- ONE schedule for all piers, so boats arrive one after another instead of together.
	-- Arrivals are spaced interval / #piers apart (same total boats as one timer per pier),
	-- each goes to a random pier that has no boat right now, never the same pier twice in a row.
	task.spawn(function()
		local cfg = Config.BOAT
		local busy, last = {}, nil
		while true do
			task.wait(rng:NextNumber(cfg.intervalMin, cfg.intervalMax) / #boats)
			local free = {}
			for i in boats do
				if not busy[i] and (i ~= last or #boats == 1) then
					table.insert(free, i)
				end
			end
			local newOffer = if #free > 0 then makeOffer(opts.getOnlineData(), os.time()) else nil
			if newOffer then
				local i = free[rng:NextInteger(1, #free)]
				busy[i], last = true, i
				task.spawn(function()
					visit(boats[i], newOffer, opts.notifyAll)
					busy[i] = nil
				end)
			end
		end
	end)
	return prompts
end

-- A player sells to a docked boat (biggest adults of the wanted species first), up to what
-- is left of their own share at THAT boat.
function BoatService.sell(boat, player: Player, data, now: number)
	local offer = boat.offer
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
