-- Global Top 100 "Fish Tycoons": ranked by lifetime coins EARNED from selling fish (stats.earned).
-- Robux can't buy it (no coin packs, Rare Egg = cheap species only), so it stays fair.
--   * OrderedDataStore keeps everyone's score across all servers.
--   * Online players are submitted every SUBMIT_SECONDS (only if their score changed).
--   * The top 100 is read every REFRESH_SECONDS, shown as a top-10 board on the plaza and sent to
--     clients for the full 100 list (Top panel).
-- Studio without DataStore access: the list is built from the players on this server only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LeaderboardService = {}

local IS_STUDIO = RunService:IsStudio()
local STORE_NAME = if IS_STUDIO then "TopEarned_studio_v1" else "TopEarned_v1"
local SUBMIT_SECONDS = 60
local REFRESH_SECONDS = 120
local TOP = 100
local BOARD_ROWS = 10

local store = nil
local lastSent = {} -- [userId] = score last written
local names = {} -- [userId] = username cache
local top = {} -- { { rank, userId, name, score } }

local boardRows = {} -- TextLabels on the plaza board

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.Name
		return online.Name
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and name then name else ("Player " .. userId)
	return names[userId]
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	while true do
		local replaced, count = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		s = replaced
		if count == 0 then
			return s
		end
	end
end

local function submit(getData)
	if not store then
		return
	end
	for _, player in Players:GetPlayers() do
		local data = getData(player)
		local score = data and math.floor(data.stats.earned)
		if score and score > 0 and lastSent[player.UserId] ~= score then
			local ok, err = pcall(store.SetAsync, store, tostring(player.UserId), score)
			if ok then
				lastSent[player.UserId] = score
			else
				warn("[Leaderboard] submit failed:", err)
			end
		end
	end
end

local function refresh(getData)
	local entries = {}
	if store then
		local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
		if ok then
			for _, entry in pages:GetCurrentPage() do
				table.insert(entries, { userId = tonumber(entry.key), score = entry.value })
			end
		else
			warn("[Leaderboard] read failed:", pages)
		end
	end
	-- online players always count with their LIVE score (newer than the store)
	local byId = {}
	for _, e in entries do
		if e.userId then
			byId[e.userId] = e
		end
	end
	for _, player in Players:GetPlayers() do
		local data = getData(player)
		local score = data and math.floor(data.stats.earned) or 0
		if score > 0 then
			local e = byId[player.UserId]
			if e then
				e.score = math.max(e.score, score)
			else
				local new = { userId = player.UserId, score = score }
				byId[player.UserId] = new
				table.insert(entries, new)
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.score > b.score
	end)
	local list = {}
	for i = 1, math.min(TOP, #entries) do
		local e = entries[i]
		if e.userId then
			table.insert(list, { rank = #list + 1, userId = e.userId, name = nameOf(e.userId), score = e.score })
		end
	end
	top = list
end

local function renderBoard()
	for i, row in boardRows do
		local e = top[i]
		row.name.Text = if e then ("%d. %s"):format(e.rank, e.name) else ""
		row.score.Text = if e then "$" .. fmt(e.score) else ""
	end
end

-- Top-10 board on the plaza (east side, facing the centre)
local function buildBoard(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "TopBoard"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local floorY = 2.1
	local pos = Vector3.new(36, floorY + 9, 0)
	local cf = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)) -- front faces the plaza centre
	local board = Instance.new("Part")
	board.Name = "Board"
	board.Size = Vector3.new(16, 14, 0.6)
	board.CFrame = cf
	board.Color = Color3.fromRGB(14, 28, 44)
	board.Material = Enum.Material.SmoothPlastic
	board.Anchored = true
	board.Parent = model
	for _, x in { -7.5, 7.5 } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Size = Vector3.new(0.6, floorY + 16, 0.6)
		local at = (cf * CFrame.new(x, 0, 0.4)).Position -- behind the board, at its left/right edge
		post.CFrame = CFrame.new(at.X, (floorY + 16) / 2, at.Z)
		post.Color = Color3.fromRGB(110, 78, 48)
		post.Material = Enum.Material.WoodPlanks
		post.Anchored = true
		post.Parent = model
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	local function label(text: string, y: number, h: number, color: Color3, xAlign: Enum.TextXAlignment, x: number, w: number)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(x, y)
		l.Size = UDim2.fromScale(w, h)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextXAlignment = xAlign
		l.TextColor3 = color
		l.Text = text
		l.Parent = gui
		return l
	end
	label("🏆 TOP FISH TYCOONS", 0.03, 0.1, Color3.fromRGB(255, 210, 90), Enum.TextXAlignment.Center, 0.05, 0.9)
	label("coins earned from selling · all servers", 0.13, 0.05, Color3.fromRGB(170, 200, 220), Enum.TextXAlignment.Center, 0.05, 0.9)
	for i = 1, BOARD_ROWS do
		local y = 0.2 + (i - 1) * 0.078
		local color = if i == 1 then Color3.fromRGB(255, 215, 80) elseif i == 2 then Color3.fromRGB(215, 220, 230) elseif i == 3 then Color3.fromRGB(225, 160, 100) else Color3.fromRGB(235, 240, 245)
		table.insert(boardRows, {
			name = label("", y, 0.065, color, Enum.TextXAlignment.Left, 0.06, 0.58),
			score = label("", y, 0.065, color, Enum.TextXAlignment.Right, 0.62, 0.32),
		})
	end
	model.Parent = parent
end

-- deps = { getData: (Player) -> data?, remote: RemoteEvent }
function LeaderboardService.start(parent: Instance, deps)
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, STORE_NAME)
	if ok then
		store = result
	else
		warn("[Leaderboard] no DataStore access (Studio: Game Settings -> Security -> API services). Showing this server only.")
	end
	buildBoard(parent)

	Players.PlayerAdded:Connect(function(player)
		task.wait(5) -- after their data has loaded
		if player.Parent then
			deps.remote:FireClient(player, top)
		end
	end)

	task.spawn(function()
		local lastRefresh = -math.huge
		while true do
			submit(deps.getData)
			if os.clock() - lastRefresh >= REFRESH_SECONDS or #top == 0 then
				lastRefresh = os.clock()
				refresh(deps.getData)
				renderBoard()
				deps.remote:FireAllClients(top)
			end
			task.wait(SUBMIT_SECONDS)
		end
	end)
end

return LeaderboardService
