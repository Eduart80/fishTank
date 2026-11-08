-- Builds the 3D world from code: plaza, 8 aquarium plots in a ring, central market board.
-- The server only publishes a small fish list per plot (FishData JSON); every client draws and
-- animates the fish itself (see client/FishRenderer), so the server never moves fish parts.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local WorldService = {}

local PLOT_COUNT = 8
local PLOT_RADIUS = 70
local FLOOR_Y = 0.4
local TANK_W, TANK_H, TANK_D = 20, 12, 10
local STAND_H = 3

local COLORS = {
	floor = Color3.fromRGB(196, 178, 140),
	wood = Color3.fromRGB(110, 78, 50),
	sand = Color3.fromRGB(230, 210, 160),
	water = Color3.fromRGB(60, 140, 220),
	glass = Color3.fromRGB(200, 235, 255),
	board = Color3.fromRGB(14, 28, 44),
	rock = Color3.fromRGB(110, 110, 120),
	weed = Color3.fromRGB(60, 160, 80),
	up = Color3.fromRGB(80, 210, 120),
	down = Color3.fromRGB(240, 90, 90),
	text = Color3.fromRGB(235, 242, 250),
}

local plots = {} -- [i] = { model, owner, spawnCFrame, fishValue, label, prompt, lastJson }
local plotOf = {} -- [player] = plot
local boardRows = {} -- [speciesId] = { price, change }
local boardEvent = nil

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			p[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function textLabel(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = COLORS.text
	for key, value in props do
		if key ~= "Parent" then
			l[key] = value
		end
	end
	l.Parent = props.Parent
	return l
end

local function buildTank(index: number, cf: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("OwnerId", 0)

	part({ Name = "Stand", Size = Vector3.new(TANK_W + 2, STAND_H, TANK_D + 2), CFrame = cf * CFrame.new(0, STAND_H / 2, 0), Material = Enum.Material.WoodPlanks, Color = COLORS.wood, Parent = model })
	part({ Name = "Sand", Size = Vector3.new(TANK_W, 1, TANK_D), CFrame = cf * CFrame.new(0, STAND_H + 0.5, 0), Material = Enum.Material.Sand, Color = COLORS.sand, Parent = model })
	local waterH = TANK_H - 1
	part({
		Name = "Water",
		Size = Vector3.new(TANK_W, waterH, TANK_D),
		CFrame = cf * CFrame.new(0, STAND_H + 1 + waterH / 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = COLORS.water,
		Transparency = 0.75,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})

	-- glass: front faces the plaza centre (local -Z)
	local midY = STAND_H + TANK_H / 2
	local glass = { Material = Enum.Material.Glass, Color = COLORS.glass, Transparency = 0.8, CastShadow = false }
	local function pane(name, size, offset)
		local props = table.clone(glass)
		props.Name = name
		props.Size = size
		props.CFrame = cf * offset
		props.Parent = model
		return part(props)
	end
	local front = pane("GlassFront", Vector3.new(TANK_W + 0.8, TANK_H, 0.4), CFrame.new(0, midY, -(TANK_D / 2 + 0.2)))
	pane("GlassBack", Vector3.new(TANK_W + 0.8, TANK_H, 0.4), CFrame.new(0, midY, TANK_D / 2 + 0.2))
	pane("GlassLeft", Vector3.new(0.4, TANK_H, TANK_D), CFrame.new(-(TANK_W / 2 + 0.2), midY, 0))
	pane("GlassRight", Vector3.new(0.4, TANK_H, TANK_D), CFrame.new(TANK_W / 2 + 0.2, midY, 0))
	local lid = pane("Lid", Vector3.new(TANK_W + 0.8, 0.4, TANK_D + 0.8), CFrame.new(0, STAND_H + TANK_H + 0.2, 0))
	lid.Transparency = 0.9

	-- a little decor so empty tanks don't look dead
	local rng = Random.new(index * 31)
	for _ = 1, 2 do
		local size = rng:NextNumber(1.5, 3)
		part({ Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = cf * CFrame.new(rng:NextNumber(-8, 8), STAND_H + 1 + size * 0.3, rng:NextNumber(-3, 3)), Material = Enum.Material.Slate, Color = COLORS.rock, CanCollide = false, Parent = model })
	end
	for _ = 1, 4 do
		local h = rng:NextNumber(3, 7)
		part({ Name = "Seaweed", Size = Vector3.new(0.4, h, 0.4), CFrame = cf * CFrame.new(rng:NextNumber(-9, 9), STAND_H + 1 + h / 2, rng:NextNumber(-4, 4)), Material = Enum.Material.Grass, Color = COLORS.weed, CanCollide = false, Parent = model })
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(16, 2.5) -- in studs, so far-away signs shrink naturally
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.MaxDistance = 120
	billboard.Parent = lid
	local label = textLabel({ Name = "OwnerLabel", Size = UDim2.fromScale(1, 1), Text = "Empty tank", TextStrokeTransparency = 0.4, Parent = billboard })

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TankPrompt"
	prompt.ActionText = "Open Tank"
	prompt.ObjectText = "Empty"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = front

	local fishValue = Instance.new("StringValue")
	fishValue.Name = "FishData"
	fishValue.Value = "[]"
	fishValue.Parent = model

	model.Parent = parent

	local standPos = (cf * CFrame.new(0, 3, -(TANK_D / 2 + 10))).Position
	return {
		model = model,
		owner = nil,
		spawnCFrame = CFrame.lookAt(standPos, Vector3.new(cf.Position.X, standPos.Y, cf.Position.Z)),
		fishValue = fishValue,
		label = label,
		prompt = prompt,
		lastJson = "[]",
	}
end

local function buildMarket(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Market"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local boardCF = CFrame.new(0, FLOOR_Y + 14, -38) * CFrame.Angles(0, math.pi, 0) -- front face looks at the plaza
	local board = part({ Name = "Board", Size = Vector3.new(44, 24, 1), CFrame = boardCF, Material = Enum.Material.SmoothPlastic, Color = COLORS.board, Parent = model })
	for _, x in { -20, 20 } do
		part({ Name = "Post", Size = Vector3.new(1.5, FLOOR_Y + 26, 1.5), CFrame = CFrame.new(x, (FLOOR_Y + 26) / 2, -38.6), Material = Enum.Material.WoodPlanks, Color = COLORS.wood, Parent = model })
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = board

	textLabel({ Text = "FISH MARKET", Position = UDim2.fromScale(0.05, 0.02), Size = UDim2.fromScale(0.9, 0.12), Parent = gui })

	-- columns: name | sell price | 1h change | egg price | growing worldwide
	local COLS = {
		{ x = 0.07, w = 0.24, align = Enum.TextXAlignment.Left, header = "FISH" },
		{ x = 0.31, w = 0.14, align = Enum.TextXAlignment.Right, header = "PRICE" },
		{ x = 0.46, w = 0.14, align = Enum.TextXAlignment.Right, header = "1H" },
		{ x = 0.61, w = 0.14, align = Enum.TextXAlignment.Right, header = "EGG" },
		{ x = 0.76, w = 0.19, align = Enum.TextXAlignment.Right, header = "GROWING" },
	}
	local headerColor = Color3.fromRGB(150, 172, 196)
	for _, col in COLS do
		textLabel({ Text = col.header, TextColor3 = headerColor, TextXAlignment = col.align, Position = UDim2.fromScale(col.x, 0.16), Size = UDim2.fromScale(col.w, 0.05), Parent = gui })
	end

	for i, species in Config.Species do
		local y = 0.23 + (i - 1) * 0.12
		local swatch = Instance.new("Frame")
		swatch.BackgroundColor3 = species.color
		swatch.BorderSizePixel = 0
		swatch.Position = UDim2.fromScale(0.05, y + 0.015)
		swatch.Size = UDim2.fromScale(0.01, 0.07)
		swatch.Parent = gui
		local cells = {}
		for c, col in COLS do
			cells[c] = textLabel({ Text = if c == 1 then species.name else "-", TextXAlignment = col.align, Position = UDim2.fromScale(col.x, y), Size = UDim2.fromScale(col.w, 0.1), Parent = gui })
		end
		boardRows[species.id] = { price = cells[2], change = cells[3], egg = cells[4], growing = cells[5] }
	end
	boardEvent = textLabel({ Text = "", TextColor3 = Color3.fromRGB(220, 160, 255), Position = UDim2.fromScale(0.05, 0.86), Size = UDim2.fromScale(0.9, 0.1), Parent = gui })

	local counter = part({ Name = "Counter", Size = Vector3.new(24, 4, 4), CFrame = CFrame.new(0, FLOOR_Y + 2, -30), Material = Enum.Material.WoodPlanks, Color = COLORS.wood, Parent = model })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MarketPrompt"
	prompt.ActionText = "Trade"
	prompt.ObjectText = "Fish Market"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	model.Parent = parent
end

function WorldService.start()
	local world = Instance.new("Folder")
	world.Name = "FishWorld"

	part({ Name = "Plaza", Size = Vector3.new(190, 0.4, 190), CFrame = CFrame.new(0, FLOOR_Y - 0.2, 0), Material = Enum.Material.Concrete, Color = COLORS.floor, Parent = world })

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = world
	for i = 1, PLOT_COUNT do
		local angle = math.rad(22.5 + (i - 1) * (360 / PLOT_COUNT))
		local pos = Vector3.new(math.sin(angle) * PLOT_RADIUS, FLOOR_Y, math.cos(angle) * PLOT_RADIUS)
		plots[i] = buildTank(i, CFrame.lookAt(pos, Vector3.new(0, FLOOR_Y, 0)), plotsFolder)
	end

	buildMarket(world)
	world.Parent = workspace
end

local function sendHome(player: Player, plot)
	local character = player.Character
	if character and plotOf[player] == plot then
		character:PivotTo(plot.spawnCFrame)
	end
end

function WorldService.assign(player: Player)
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			plotOf[player] = plot
			plot.model:SetAttribute("OwnerId", player.UserId)
			plot.label.Text = player.DisplayName .. "'s Tank"
			plot.prompt.ObjectText = player.DisplayName
			player.CharacterAdded:Connect(function()
				task.wait(0.1)
				sendHome(player, plot)
			end)
			sendHome(player, plot)
			return plot
		end
	end
	warn("[World] no free plot for", player.Name)
	return nil
end

function WorldService.release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	plot.owner = nil
	plot.model:SetAttribute("OwnerId", 0)
	plot.label.Text = "Empty tank"
	plot.prompt.ObjectText = "Empty"
	plot.fishValue.Value = "[]"
	plot.lastJson = "[]"
end

-- Publishes the visible fish list for this player's tank (only if it changed).
function WorldService.updateFish(player: Player, data, now: number)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local hungry = now >= data.fedUntil
	local list = {}
	for _, fish in data.fish do
		table.insert(list, { u = fish.uid, s = fish.species, a = math.floor(fish.age * 100) / 100, h = hungry })
	end
	local json = HttpService:JSONEncode(list)
	if json ~= plot.lastJson then
		plot.lastJson = json
		plot.fishValue.Value = json
	end
end

function WorldService.updateBoard(snapshot)
	for _, species in Config.Species do
		local row = boardRows[species.id]
		local price = snapshot.prices[species.id]
		local hist = snapshot.history[species.id]
		local first = (hist and hist[1]) or price
		local pct = (price - first) / first * 100
		row.price.Text = tostring(math.floor(price + 0.5))
		row.change.Text = ("%s%.1f%%"):format(if pct >= 0 then "+" else "", pct)
		row.change.TextColor3 = if pct >= 0 then COLORS.up else COLORS.down
		local egg = snapshot.eggPrices[species.id]
		row.egg.Text = tostring(egg)
		row.egg.TextColor3 = if egg > species.eggPrice then COLORS.down else COLORS.text -- red = pricier than normal
		row.growing.Text = tostring(snapshot.growing[species.id])
	end
	boardEvent.Text = if snapshot.event then (snapshot.event.title .. ": " .. snapshot.event.text) else ""
end

return WorldService
