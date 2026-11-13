-- Player saves with a session lock: a player's data can only be "open" on one server at a time.
-- This is what stops the classic duplication exploit (join server B before server A finished saving).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = {}

local IS_STUDIO = RunService:IsStudio()
-- Studio NEVER writes to the live store (it would save 30x-speed test data into real profiles)
local STORE_NAME = if IS_STUDIO then "PlayerData_studio_v1" else "PlayerData_v1"
local LOCK_TTL = 150 -- a lock older than this is considered abandoned (crashed server)
local AUTOSAVE_INTERVAL = 60
local LOAD_ATTEMPTS = 6

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStore unavailable:", result)
	end
end

-- [player] = { data = table, saveEnabled = bool }
local profiles = {}

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

function DataService.defaultData(now: number)
	return {
		version = 1,
		created = now, -- first join (invite rewards only go to brand-new players)
		coins = Config.STARTING_COINS,
		slots = Config.STARTING_SLOTS,
		fedUntil = now + Config.real(Config.STARTING_FEED_HOURS * 3600),
		fish = {},
		nextUid = 1,
		stats = { earned = 0, sold = 0, died = 0 },
	}
end

local function tryLoad(key: string)
	local lockedBy = nil
	local data = store:UpdateAsync(key, function(old)
		lockedBy = nil
		local now = os.time()
		if type(old) == "table" and old.lock and old.lock.job ~= game.JobId and now - old.lock.time < LOCK_TTL then
			lockedBy = old.lock.job
			return nil -- cancel: still open on another server
		end
		local d = if type(old) == "table" then old else DataService.defaultData(now)
		d.lock = { job = game.JobId, time = now }
		return d
	end)
	return data, lockedBy
end

-- Yields. Returns the data table, or nil if the player should be kicked.
function DataService.load(player: Player)
	if not store then
		if IS_STUDIO then
			warn("[Data] Studio without DataStore access: progress will NOT save")
			profiles[player] = { data = DataService.defaultData(os.time()), saveEnabled = false }
			return profiles[player].data
		end
		return nil
	end

	local key = keyFor(player)
	for attempt = 1, LOAD_ATTEMPTS do
		local ok, data, lockedBy = pcall(tryLoad, key)
		if ok and data then
			if not player.Parent then
				-- left while we were loading: release the lock we just took
				data.lock = nil
				pcall(function()
					store:SetAsync(key, data)
				end)
				return nil
			end
			profiles[player] = { data = data, saveEnabled = true }
			return data
		end
		if not ok then
			warn(("[Data] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(data)))
			if IS_STUDIO then
				break -- unpublished place or API access off; go to the Studio fallback below
			end
		end
		task.wait(if lockedBy then 5 else 2)
	end

	if IS_STUDIO then
		warn("[Data] Studio fallback: enable Game Settings > Security > 'Enable Studio Access to API Services' to test saving")
		profiles[player] = { data = DataService.defaultData(os.time()), saveEnabled = false }
		return profiles[player].data
	end
	return nil
end

function DataService.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

-- Returns true when the data is safely stored (or saving is off, e.g. Studio without API access).
local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not profile.saveEnabled then
		return true
	end
	local data = profile.data
	local written = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if type(old) == "table" and old.lock and old.lock.job ~= game.JobId then
				return nil -- another server took over this session; never overwrite it
			end
			data.lock = if release then nil else { job = game.JobId, time = os.time() }
			written = true
			return data
		end)
	end)
	if not ok then
		warn(("[Data] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return ok and written
end

-- Save right now (used after Robux purchases, so a paid item is never lost). Yields.
function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

function DataService.release(player: Player)
	save(player, true)
	profiles[player] = nil
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		for player in profiles do
			remaining += 1
			task.spawn(function()
				save(player, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
