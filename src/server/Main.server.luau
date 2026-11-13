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
local AmbienceService = require(Services.AmbienceService)
local PatioService = require(Services.PatioService)
local RewardsService = require(Services.RewardsService)
local FerryService = require(Services.FerryService)

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
local ferryRemote = Instance.new("RemoteEvent")
ferryRemote.Name = "Ferry"
ferryRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

MarketService.start()
DataService.start()
WorldService.start()
AmbienceService.start()
FerryService.start(workspace:WaitForChild("FishWorld"), {
	remote = ferryRemote,
	getData = function(player)
		return DataService.get(player)
	end,
	notify = function(player, text)
		notifyRemote:FireClient(player, text)
	end,
})

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
	local patio = PatioService.publicState(data)
	state.inventory, state.patio = patio.inventory, patio.patio
	state.streak = if data.daily then data.daily.streak else 0
	stateRemote:FireClient(player, state)
	WorldService.updateFeedPrompt(player, state)
	WorldService.updateTankStage(player, data.slots)
	WorldService.updatePatio(player, patio.patio, patio.colors)
	updateLeaderstats(player, data)
	WorldService.updateFish(player, data, now)
end

-- STUDIO ONLY test shortcut. Two ways (6 / 10 / 15 / 20 = Small / Medium / Large / Sea Pen):
--   a) While playing: Explorer -> Workspace -> Properties -> Attributes -> "SetSlots" -> type 20
--   b) Command bar on the SERVER side:  workspace:SetAttribute("SetSlots", 20)
-- Changes your saved slots in the _studio DataStore only. Never exists on live servers.
if game:GetService("RunService"):IsStudio() then
	local function setSlots(slots: number)
		local player = Players:GetPlayers()[1]
		local data = player and DataService.get(player)
		if not data then
			return warn("[setSlots] no player data yet")
		end
		data.slots = math.clamp(math.floor(slots), Config.STARTING_SLOTS, Config.MAX_SLOTS)
		pushState(player, data, os.time())
		print(("[setSlots] %s now has %d slots (%s)"):format(player.Name, data.slots, Config.TANK_STAGES[Config.tankStage(data.slots)].name))
	end
	_G.setSlots = setSlots
	workspace:SetAttribute("SetSlots", 0) -- shows up in Workspace's Properties so it can be typed into
	workspace:GetAttributeChangedSignal("SetSlots"):Connect(function()
		local value = tonumber(workspace:GetAttribute("SetSlots"))
		if value and value > 0 then
			setSlots(value)
		end
	end)
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
	-- Harbor Store / patio
	buyDecor = function(data, _now, itemId)
		return PatioService.buy(data, itemId)
	end,
	placeDecor = function(data, _now, arg)
		if type(arg) ~= "table" then
			return false, "Bad request"
		end
		return PatioService.place(data, arg.spot, arg.item, arg.color)
	end,
	pickUpDecor = function(data, _now, spot)
		return PatioService.pickUp(data, spot)
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
		AnalyticsTracker.economy(player, data, action, data.coins - coinsBefore, if action == "buyEgg" or action == "buyDecor" then arg else nil)
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

-- Fishing boats (one per pier) -------------------------------------------
local boatPrompts = BoatService.start({
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

for prompt, boat in boatPrompts do
	prompt.Triggered:Connect(function(player)
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
		local ok, msg = BoatService.sell(boat, player, data, now)
		if ok then
			AnalyticsTracker.economy(player, data, "sell", data.coins - coinsBefore, "boat")
			AnalyticsTracker.check(player, data)
		end
		notifyRemote:FireClient(player, msg)
		pushState(player, data, now)
	end)
end

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

-- Invite a friend ------------------------------------------------------------
-- Roblox fills ReferredByPlayerId when someone joins through an invite or share link; the client
-- invite prompt also puts the inviter id into LaunchData as a fallback.
local function handleInvite(player: Player, data, now: number): string?
	if not RewardsService.isNewPlayer(data, now) or data.invitedBy then
		return nil
	end
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil
	end
	local inviterId = tonumber(joinData.ReferredByPlayerId)
	if not inviterId or inviterId == 0 then
		inviterId = tonumber(joinData.LaunchData)
	end
	if not inviterId or inviterId == 0 or inviterId == player.UserId then
		return nil
	end
	local inviter = Players:GetPlayerByUserId(inviterId)
	local inviterData = inviter and DataService.get(inviter)
	local inviterName = if inviter then inviter.DisplayName else "A friend"
	local inviteeText, inviterText = RewardsService.applyInvite(data, inviterData, inviterName, player.DisplayName, now)
	AnalyticsTracker.custom(player, "JoinedFromInvite", 1)
	if inviter and inviterData and inviterText then
		notifyRemote:FireClient(inviter, inviterText, 7)
		pushState(inviter, inviterData, now)
	end
	return inviteeText
end

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
	local away = TankService.beginReturn(data, now) -- before settle: offline hunger does not count
	settleAndNotify(player, data, now)
	pushState(player, data, now)
	marketRemote:FireClient(player, MarketService.snapshot(now))
	-- join messages, one after another (a toast replaces the previous one)
	local messages = {}
	local summary = TankService.awaySummary(data, now, away)
	if summary then
		table.insert(messages, summary)
	end
	local inviteText = handleInvite(player, data, now)
	if inviteText then
		table.insert(messages, inviteText)
	end
	local dailyText = RewardsService.claimDaily(data, now)
	if dailyText then
		table.insert(messages, dailyText)
		AnalyticsTracker.custom(player, "DailyStreak", data.daily.streak)
	end
	if #messages > 0 then
		pushState(player, data, now)
		task.spawn(function()
			task.wait(3) -- after the loading screen
			for _, text in messages do
				if not player.Parent then
					return
				end
				notifyRemote:FireClient(player, text, 7)
				task.wait(7.5)
			end
		end)
	end
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

-- Weather ------------------------------------------------------------------
-- The "Storm at Sea" market event is a real storm: dark sky, rough sea, rain + thunder on clients,
-- gulls fly off. Same schedule on every server (it comes from the event hash).
-- STUDIO ONLY: Workspace attribute "TestStorm" (tick it in Properties while playing, Server side)
-- forces the storm on/off without waiting for the event.
local IS_STUDIO = game:GetService("RunService"):IsStudio()
if IS_STUDIO then
	workspace:SetAttribute("TestStorm", false)
end
local stormOn = false
local function updateWeather(now: number)
	local event = MarketService.currentEvent(now)
	local storm = (event ~= nil and event.def.id == "storm") or (IS_STUDIO and workspace:GetAttribute("TestStorm") == true)
	if storm == stormOn then
		return
	end
	stormOn = storm
	AmbienceService.setWeather(if storm then "storm" else "clear", if storm then 12 else 20)
	notifyRemote:FireAllClients(if storm then "🌧 Storm at Sea! No boats today, but all fish sell for +40%!" else "🌤 The storm is over. The boats are heading back out!", 6)
end

-- Game tick ---------------------------------------------------------------
while true do
	task.wait(TICK)
	local now = os.time()
	local snapshot = MarketService.snapshot(now)
	marketRemote:FireAllClients(snapshot)
	WorldService.updateBoard(snapshot)
	updateWeather(now)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			settleAndNotify(player, data, now)
			-- new day while playing (only after the join flow has claimed once)
			if data.daily and data.daily.day ~= RewardsService.dayOf(now) then
				local dailyText = RewardsService.claimDaily(data, now)
				if dailyText then
					notifyRemote:FireClient(player, dailyText, 7)
					AnalyticsTracker.custom(player, "DailyStreak", data.daily.streak)
				end
			end
			pushState(player, data, now)
		end
	end
end
