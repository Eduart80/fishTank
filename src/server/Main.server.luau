-- Server entry point: remotes, player lifecycle, the 5-second game tick.
-- Rule: the client only ASKS. Every coin, fish and price is decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Services = script.Parent:WaitForChild("Services")
local DataService = require(Services.DataService)
local MarketService = require(Services.MarketService)
local TankService = require(Services.TankService)
local WorldService = require(Services.WorldService)
local AnalyticsTracker = require(Services.AnalyticsTracker)
local BoatService = require(Services.BoatService)
local ShopService = require(Services.ShopService)

local TICK = 5
local ACTION_COOLDOWN = 0.15
local MAX_SELL_UIDS = 50

-- Remotes ------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local actionRemote = Instance.new("RemoteFunction")
actionRemote.Name = "Action"
actionRemote.Parent = remotes
local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "State"
stateRemote.Parent = remotes
local marketRemote = Instance.new("RemoteEvent")
marketRemote.Name = "Market"
marketRemote.Parent = remotes
local notifyRemote = Instance.new("RemoteEvent")
notifyRemote.Name = "Notify"
notifyRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

MarketService.start()
DataService.start()
WorldService.start()

-- Helpers ------------------------------------------------------------------
local function updateLeaderstats(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	stats.Coins.Value = data.coins
	stats.Fish.Value = #data.fish
end

local function pushState(player: Player, data, now: number)
	local state = TankService.publicState(data, now)
	stateRemote:FireClient(player, state)
	WorldService.updateFeedPrompt(player, state)
	updateLeaderstats(player, data)
	WorldService.updateFish(player, data, now)
end

local function settleAndNotify(player: Player, data, now: number)
	local died = TankService.settle(data, now)
	if #died > 0 then
		local names = {}
		for _, fish in died do
			local species = Config.ById[fish.species]
			table.insert(names, if species then species.name else fish.species)
		end
		notifyRemote:FireClient(player, ("%d fish starved: %s. Keep the food topped up!"):format(#died, table.concat(names, ", ")))
		AnalyticsTracker.custom(player, "FishStarved", #died)
	end
	if TankService.rescueIfBroke(data, now) then
		notifyRemote:FireClient(player, ("The harbor gave you %d coins to start again. Keep some coins for food!"):format(Config.RESCUE_COINS))
		AnalyticsTracker.custom(player, "RescueGiven")
		AnalyticsTracker.economy(player, data, "rescue", Config.RESCUE_COINS)
	end
	AnalyticsTracker.check(player, data)
end

-- Actions -----------------------------------------------------------------
local lastAction = {}

local handlers = {
	buyEgg = function(data, now, speciesId)
		if type(speciesId) ~= "string" then
			return false, "Bad request"
		end
		return TankService.buyEgg(data, speciesId, now)
	end,
	feed = function(data, now)
		return TankService.feed(data, now)
	end,
	sell = function(data, now, uids)
		if type(uids) ~= "table" or #uids == 0 or #uids > MAX_SELL_UIDS then
			return false, "Bad request"
		end
		local clean = {}
		for _, uid in uids do
			if type(uid) ~= "number" then
				return false, "Bad request"
			end
			table.insert(clean, uid)
		end
		return TankService.sell(data, clean, now)
	end,
	sellAllAdults = function(data, now)
		return TankService.sell(data, nil, now)
	end,
	buySlot = function(data)
		return TankService.buySlot(data)
	end,
}

local function runAction(player: Player, action, arg)
	local clock = os.clock()
	if lastAction[player] and clock - lastAction[player] < ACTION_COOLDOWN then
		return { ok = false, msg = "Slow down" }
	end
	lastAction[player] = clock

	local handler = type(action) == "string" and handlers[action]
	local data = DataService.get(player)
	if not handler or not data then
		return { ok = false, msg = "Bad request" }
	end

	local now = os.time()
	settleAndNotify(player, data, now)
	local coinsBefore = data.coins
	local ok, msg = handler(data, now, arg)
	if ok then
		AnalyticsTracker.economy(player, data, action, data.coins - coinsBefore, if action == "buyEgg" then arg else nil)
		AnalyticsTracker.check(player, data)
	end
	pushState(player, data, now)
	return { ok = ok, msg = msg }
end

actionRemote.OnServerInvoke = runAction

-- Feeding is done at your own tank (F / prompt), not from a menu button
WorldService.onFeed(function(player)
	local result = runAction(player, "feed")
	if result.msg and result.msg ~= "Slow down" then
		notifyRemote:FireClient(player, result.msg)
	end
end)

-- Fishing boat ------------------------------------------------------------
local boatPrompt = BoatService.start({
	getOnlineData = function()
		local list = {}
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data then
				table.insert(list, data)
			end
		end
		return list
	end,
	notifyAll = function(text)
		notifyRemote:FireAllClients(text)
	end,
})

boatPrompt.Triggered:Connect(function(player)
	local clock = os.clock()
	if lastAction[player] and clock - lastAction[player] < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = clock
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	settleAndNotify(player, data, now)
	local coinsBefore = data.coins
	local ok, msg = BoatService.sell(player, data, now)
	if ok then
		AnalyticsTracker.economy(player, data, "sell", data.coins - coinsBefore, "boat")
		AnalyticsTracker.check(player, data)
	end
	notifyRemote:FireClient(player, msg)
	pushState(player, data, now)
end)

-- Robux shop --------------------------------------------------------------
ShopService.start({
	onChanged = function(player, msg)
		local data = DataService.get(player)
		if data then
			pushState(player, data, os.time())
		end
		if msg then
			notifyRemote:FireClient(player, msg)
		end
	end,
})

-- Player lifecycle --------------------------------------------------------
local function onPlayerAdded(player: Player)
	local data = DataService.load(player)
	if not data then
		if player.Parent then
			player:Kick("Your fish are still being saved on another server. Please rejoin in a minute.")
		end
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	local fish = Instance.new("IntValue")
	fish.Name = "Fish"
	fish.Parent = leaderstats
	leaderstats.Parent = player

	WorldService.assign(player)
	ShopService.refreshPasses(player, data) -- Auto-Feeder etc. (asks Roblox, yields)
	if not player.Parent then
		return
	end
	local now = os.time()
	settleAndNotify(player, data, now)
	pushState(player, data, now)
	marketRemote:FireClient(player, MarketService.snapshot(now))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
	local data = DataService.get(player)
	if data then
		TankService.settle(data, os.time())
	end
	DataService.release(player)
	WorldService.release(player)
end)

-- Game tick ---------------------------------------------------------------
while true do
	task.wait(TICK)
	local now = os.time()
	local snapshot = MarketService.snapshot(now)
	marketRemote:FireAllClients(snapshot)
	WorldService.updateBoard(snapshot)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			settleAndNotify(player, data, now)
			pushState(player, data, now)
		end
	end
end
