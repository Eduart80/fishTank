-- Builds the 3D world from code: plaza, 8 aquarium plots in a ring, central market board.
-- The server only publishes a small fish list per plot (FishData JSON); every client draws and
-- animates the fish itself (see client/FishRenderer), so the server never moves fish parts.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local MarketMath = require(ReplicatedStorage.Shared.MarketMath)

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
		{ x = 0.61, w = 0.14, align = Enum.TextXAlignment.Right, header = "EGG PRICE" },
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

-- Sea + island (terrain) ---------------------------------------------------
local SEA_LEVEL = -1.5 -- water surface, a small step below the plaza so you can climb out
local SEA_DEPTH = 20
local SEA_SIZE = 1200
local ISLAND_SIZE = 230 -- plaza is 190 → a sand beach strip around it

local function buildSea()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy() -- the grey Studio floor would cover the sea
	end
	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(25, 115, 165)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.5
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 8

	local bottom = SEA_LEVEL - SEA_DEPTH
	terrain:FillBlock(CFrame.new(0, SEA_LEVEL - SEA_DEPTH / 2, 0), Vector3.new(SEA_SIZE, SEA_DEPTH, SEA_SIZE), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, bottom - 4, 0), Vector3.new(SEA_SIZE, 8, SEA_SIZE), Enum.Material.Sand) -- sea floor
	local islandTop = FLOOR_Y - 0.4
	terrain:FillBlock(CFrame.new(0, (islandTop + bottom) / 2, 0), Vector3.new(ISLAND_SIZE, islandTop - bottom, ISLAND_SIZE), Enum.Material.Sand)
end

-- Fishing pier (visual only for now; fishing itself is a phase 3 feature) ----
local PIER_START_Z = 92 -- plaza edge is z = 95; the gap between tanks 1 and 8 faces +Z
local PIER_LEN = 70
local PIER_W = 8
local PLATFORM = 26

local function buildPier(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "FishingPier"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local deckTop = FLOOR_Y + 0.5
	local deckY = deckTop - 0.5
	local endZ = PIER_START_Z + PIER_LEN
	local platZ = endZ + PLATFORM / 2 - 1
	local postColor = Color3.fromRGB(80, 56, 36)
	local wood = { Material = Enum.Material.WoodPlanks, Color = COLORS.wood }

	local function woodPart(name, size, cf, color)
		return part({ Name = name, Size = size, CFrame = cf, Material = wood.Material, Color = color or wood.Color, Parent = model })
	end

	woodPart("Walkway", Vector3.new(PIER_W, 1, PIER_LEN), CFrame.new(0, deckY, PIER_START_Z + PIER_LEN / 2))
	woodPart("Platform", Vector3.new(PLATFORM, 1, PLATFORM), CFrame.new(0, deckY, platZ))

	-- posts down into the sea
	local postH = deckY - (SEA_LEVEL - SEA_DEPTH)
	local function post(x, z)
		woodPart("Post", Vector3.new(1.2, postH, 1.2), CFrame.new(x, deckY - postH / 2, z), postColor)
	end
	for z = PIER_START_Z + 15, endZ, 10 do
		post(-PIER_W / 2 + 0.6, z)
		post(PIER_W / 2 - 0.6, z)
	end
	local half = PLATFORM / 2 - 0.6
	for _, x in { -half, half } do
		for _, z in { platZ - half, platZ + half } do
			post(x, z)
		end
	end

	-- railings: walkway sides (over the water) + platform left/right/far side
	local railH = 3
	local function rail(from: Vector3, to: Vector3)
		local mid = (from + to) / 2
		local len = (to - from).Magnitude
		woodPart("Rail", Vector3.new(0.4, 0.4, len), CFrame.lookAt(mid + Vector3.new(0, railH, 0), to + Vector3.new(0, railH, 0)), postColor)
		local steps = math.max(1, math.floor(len / 5))
		for s = 0, steps do
			local p = from:Lerp(to, s / steps)
			woodPart("Baluster", Vector3.new(0.4, railH, 0.4), CFrame.new(p.X, deckTop + railH / 2, p.Z), postColor)
		end
	end
	local railStart = PIER_START_Z + 15
	for _, x in { -PIER_W / 2 + 0.2, PIER_W / 2 - 0.2 } do
		rail(Vector3.new(x, deckTop, railStart), Vector3.new(x, deckTop, endZ))
	end
	local px, nearZ, farZ = PLATFORM / 2 - 0.2, endZ, platZ + PLATFORM / 2 - 0.2
	rail(Vector3.new(-px, deckTop, nearZ), Vector3.new(-px, deckTop, farZ))
	rail(Vector3.new(px, deckTop, nearZ), Vector3.new(px, deckTop, farZ))
	rail(Vector3.new(-px, deckTop, farZ), Vector3.new(px, deckTop, farZ))

	-- props: crates, barrels, lamps
	part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(-9, deckTop + 1.5, endZ + 4) * CFrame.Angles(0, 0.3, 0), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(150, 110, 70), Parent = model })
	part({ Name = "Crate", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(-8.5, deckTop + 4, endZ + 4) * CFrame.Angles(0, -0.4, 0), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(150, 110, 70), Parent = model })
	for _, pos in { Vector3.new(9, 0, endZ + 3), Vector3.new(10, 0, endZ + 6.5) } do
		part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.5, 2.6, 2.6), CFrame = CFrame.new(pos.X, deckTop + 1.75, pos.Z) * CFrame.Angles(0, 0, math.pi / 2), Material = Enum.Material.Wood, Color = Color3.fromRGB(120, 70, 40), Parent = model })
	end
	for _, x in { -px, px } do
		local lampZ = farZ
		woodPart("LampPost", Vector3.new(0.6, 8, 0.6), CFrame.new(x, deckTop + 4, lampZ), postColor)
		local bulb = part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(x, deckTop + 8.5, lampZ), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 220, 150), CanCollide = false, Parent = model })
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.5
		light.Color = bulb.Color
		light.Parent = bulb
	end

	-- entrance arch with sign, facing the plaza (-Z)
	local archH = 12
	for _, x in { -(PIER_W / 2 + 0.6), PIER_W / 2 + 0.6 } do
		woodPart("ArchPost", Vector3.new(1, archH, 1), CFrame.new(x, deckTop + archH / 2, PIER_START_Z), postColor)
	end
	local sign = woodPart("Sign", Vector3.new(PIER_W + 4, 3.5, 0.6), CFrame.new(0, deckTop + archH - 1.5, PIER_START_Z - 0.2))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = sign
	textLabel({ Text = "FISHING PIER", Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.55), Parent = gui })
	textLabel({ Text = "coming soon", TextColor3 = Color3.fromRGB(255, 220, 150), Position = UDim2.fromScale(0.2, 0.62), Size = UDim2.fromScale(0.6, 0.3), Parent = gui })

	model.Parent = parent
end

function WorldService.start()
	local world = Instance.new("Folder")
	world.Name = "FishWorld"

	buildSea()
	buildPier(world)

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
		local rising = egg > species.eggPrice or (snapshot.eggDemand[species.id] or 0) >= MarketMath.EGG_DEMAND_MARKER
		row.egg.Text = if rising then tostring(egg) .. " ▲" else tostring(egg)
		row.egg.TextColor3 = if rising then COLORS.down else COLORS.text -- red ▲ = people are buying, price going up
		row.growing.Text = tostring(snapshot.growing[species.id])
	end
	local event = snapshot.event
	if event then
		local secs = math.max(0, event.endsAt - snapshot.now)
		local parts = { event.title .. ": " .. event.text }
		if event.orderLeft then
			table.insert(parts, if event.orderLeft > 0 then ("%d of %d left"):format(event.orderLeft, event.orderSize) else "ORDER FILLED")
		end
		table.insert(parts, ("ends in %d:%02d"):format(secs // 60, secs % 60))
		boardEvent.Text = table.concat(parts, " · ")
	else
		boardEvent.Text = ""
	end
end

return WorldService
