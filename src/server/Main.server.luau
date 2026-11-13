-- Server entry point: remotes, player lifecycle, the 5-second game tick.
print("[FishMarket] SERVER build 2026-11-13f market hall + hall of fame") -- proves Studio runs the synced script
-- Rule: the client only ASKS. Every coin, fish and price is decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local DayNight = require(ReplicatedStorage.Shared.DayNight)
local IS_STUDIO = game:GetService("RunService"):IsStudio()
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
local LeaderboardService = require(Services.LeaderboardService)

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
local fxRemote = Instance.new("RemoteEvent") -- big visual moments everyone sees (lightning on a tank...)
fxRemote.Name = "Fx"
fxRemote.Parent = remotes
local topRemote = Instance.new("RemoteEvent") -- Top 100 list for the Top panel
topRemote.Name = "Top"
topRemote.Parent = remotes
local ferryRemote = Instance.new("RemoteEvent")
ferryRemote.Name = "Ferry"
ferryRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

MarketService.start()
DataService.start()
WorldService.start()
AmbienceService.start()
LeaderboardService.start(workspace:WaitForChild("FishWorld"), {
	remote = topRemote,
	getData = function(player)
		return DataService.get(player)
	end,
})
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
	-- Weather Radio pass: when the next storm / full moon comes (server-only storm schedule)
	if data.weatherRadio then
		state.forecast = { storm = MarketService.nextEventStart(now, "storm"), fullMoon = DayNight.nextFullMoon(now) }
	end
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

-- Weather right now, for mutations + the storm look. Same on every server (event hash + clock).
-- STUDIO: Workspace attributes TestStorm / TestClock override it.
local function currentWeather(now: number)
	local event = MarketService.currentEvent(now)
	local storm = (event ~= nil and event.def.id == "storm") or (IS_STUDIO and workspace:GetAttribute("TestStorm") == true)
	local test = workspace:GetAttribute("TestClock")
	local clock = if IS_STUDIO and type(test) == "number" and test > 0 then test % 24 else DayNight.clockAt(now)
	local testMoon = workspace:GetAttribute("TestMoon")
	local phase = (IS_STUDIO and type(testMoon) == "string" and DayNight.phaseByKey(testMoon)) or DayNight.moonPhase(now)
	local dark = DayNight.darkness(clock)
	-- night = Moonlit can happen: deep night under a FULL moon only
	return { storm = storm, night = dark >= 0.8 and phase.key == "full", fullMoonRising = dark >= 0.5 and phase.key == "full" }
end

local function settleAndNotify(player: Player, data, now: number)
	-- STUDIO: Workspace attribute TestMutate = true makes every mutation roll succeed
	local forceRoll = if IS_STUDIO and workspace:GetAttribute("TestMutate") == true then function() return 0 end else nil
	local died, mutated = TankService.settle(data, now, currentWeather(now), forceRoll)
	for _, fish in TankService.hatchIncubator(data, now) do
		local v = Config.VARIANTS[fish.variant]
		local species = Config.ById[fish.species]
		notifyRemote:FireClient(player, ("A slot is free: your %s%s egg moved from the Incubator into the tank!"):format(if v then v.icon .. " " .. v.name .. " " else "", species.name), 6)
	end
	for _, fish in mutated do
		local v = Config.VARIANTS[fish.variant]
		local species = Config.ById[fish.species]
		notifyRemote:FireClient(player, ("%s Your %s grew up %s! It sells for %sx."):format(v.icon, species.name, v.name, tostring(v.mult)), 6)
		local top = WorldService.tankTop(player)
		if top then
			fxRemote:FireAllClients(fish.variant, top) -- "storm" = lightning strike, "moon" = moonbeam
		end
		AnalyticsTracker.custom(player, "Variant_" .. v.name, 1)
	end
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
	onChanged = function(player, msg, fx)
		local data = DataService.get(player)
		if data then
			pushState(player, data, os.time())
		end
		local top = fx and WorldService.tankTop(player)
		if top then
			fxRemote:FireAllClients(fx, top)
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

-- VIP name tag (pass): gold "VIP" + name above the head, follows respawns ---------
local function vipTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild("VipTag")
	if player:GetAttribute("VIP") ~= true then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.fromOffset(160, 26)
	gui.StudsOffset = Vector3.new(0, 2.3, 0) -- just above the head (3.2 looked like part of the Hall of Fame board)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 210, 74)
	label.TextStrokeTransparency = 0.3
	label.Text = "👑 VIP " .. player.DisplayName
	label.Parent = gui
	gui.Parent = head
end
local function hookVip(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		vipTag(player)
	end)
	player:GetAttributeChangedSignal("VIP"):Connect(function()
		vipTag(player)
	end)
	vipTag(player)
end
Players.PlayerAdded:Connect(hookVip)
for _, player in Players:GetPlayers() do
	hookVip(player)
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
if IS_STUDIO then
	workspace:SetAttribute("TestStorm", false)
	workspace:SetAttribute("TestMutate", false) -- true = every weather mutation roll succeeds
	workspace:SetAttribute("TestMoon", "")
	-- TestPasses: true = the first player gets all 4 new passes (Lucky Charm, VIP, Bigger Tank,
	-- Weather Radio) in Studio without buying them; false = takes them away again (slots stay)
	-- TestTop: true = Hall of Fame + Top panel filled with 100 sample players (false = real again)
	workspace:SetAttribute("TestTop", false)
	workspace:GetAttributeChangedSignal("TestTop"):Connect(function()
		LeaderboardService.setTest(workspace:GetAttribute("TestTop") == true, function(player)
			return DataService.get(player)
		end)
	end)
	workspace:SetAttribute("TestPasses", false)
	workspace:GetAttributeChangedSignal("TestPasses"):Connect(function()
		local player = Players:GetPlayers()[1]
		local data = player and DataService.get(player)
		if not data then
			return
		end
		local on = workspace:GetAttribute("TestPasses") == true
		for _, key in { "luckyCharm", "vip", "bigTank", "weatherRadio" } do
			data[key] = on
		end
		ShopService.applyPassPerks(player, data)
		pushState(player, data, os.time())
		print("[TestPasses]", on)
	end) -- e.g. full / new / half_waxing: force the moon phase (client/Sky + Moonlit)
	-- TestFx: type storm / moon / rare -> that effect plays on the first player's tank right away
	workspace:SetAttribute("TestFx", "")
	workspace:GetAttributeChangedSignal("TestFx"):Connect(function()
		local kind = workspace:GetAttribute("TestFx")
		local player = Players:GetPlayers()[1]
		local top = player and WorldService.tankTop(player)
		if kind ~= "" and top then
			print("[TestFx]", kind, "at", top)
			fxRemote:FireAllClients(kind, top)
		end
	end)
	workspace:SetAttribute("TestClock", 0) -- 0 = normal day/night cycle; e.g. 22 = night (client/Sky)
end
local stormOn = false
local fullMoonOn = false
local function updateWeather(now: number)
	local weather = currentWeather(now)
	if weather.fullMoonRising ~= fullMoonOn then
		fullMoonOn = weather.fullMoonRising
		if fullMoonOn then
			notifyRemote:FireAllClients("🌕 Full Moon tonight! Fish that grow up under it can turn Moonlit (1.5x)!", 7)
		end
	end
	local storm = weather.storm
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
