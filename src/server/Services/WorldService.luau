-- Builds the 3D world from code: plaza, 8 aquarium plots in a ring, central market board.
-- The server only publishes a small fish list per plot (FishData JSON); every client draws and
-- animates the fish itself (see client/FishRenderer), so the server never moves fish parts.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local MarketMath = require(ReplicatedStorage.Shared.MarketMath)
local PatioModels = require(script.Parent.PatioModels)

-- Patio spots beside each tank's front glass (plot-local x, z; 2 per side), inside the plot's own
-- pie slice and clear of the widest tank stage, the walkways and the Open/Feed prompts.
local PATIO_SPOTS = {
	Vector3.new(-15, 0, -10),
	Vector3.new(15, 0, -10),
	Vector3.new(-18, 0, -1),
	Vector3.new(18, 0, -1),
}

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

-- The island sand is terrain (4-stud voxels), so its surface sits a bit ABOVE the plaza part in
-- places. Things standing on the ground (patio items, the store) must start on whichever is higher,
-- or their bottom gets buried (the beach chair lost its seat + legs this way).
local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0), params)
	return math.max(FLOOR_Y, if hit then hit.Position.Y else FLOOR_Y)
end

-- cf moved up/down so it sits on the real ground at its own x/z (keeps its rotation)
local function onGround(cf: CFrame): CFrame
	local p = cf.Position
	return cf + Vector3.new(0, groundY(p.X, p.Z) - p.Y, 0)
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

-- Tank geometry (plot-local studs, +z = away from the plaza toward the sea). See Config.TANK_STAGES.
local FRONT_Z = -TANK_D / 2
local HALF_FRONT = TANK_W / 2
local ISLAND_HALF = 115 -- = ISLAND_SIZE / 2 (sea section); stand parts past this get piles
local SEA_FLOOR_Y = -21.5 -- = SEA_LEVEL - SEA_DEPTH (sea section)

-- Flat trapezoid seen from above: a centre box plus a flat wedge on each side.
-- The centre box carries `name`; the wedges are named name .. "Wedge".
local function trapezoid(name: string, model: Instance, cf: CFrame, hf: number, hb: number, zF: number, zB: number, y: number, thick: number, props)
	local depth = zB - zF
	local function apply(p)
		for key, value in props do
			p[key] = value
		end
		p.Parent = model
		return p
	end
	local box = apply(part({ Name = name, Size = Vector3.new(hf * 2, thick, depth), CFrame = cf * CFrame.new(0, y, (zF + zB) / 2) }))
	local extra = hb - hf
	if extra > 0.05 then
		for _, side in { 1, -1 } do
			-- A WedgePart's triangle lives in its local Y/Z plane (right angle at -Y,+Z). Lay it flat:
			-- local Y -> plot ±X (outward), local Z -> plot +Z, local X -> vertical.
			local w = Instance.new("WedgePart")
			w.Anchored = true
			w.TopSurface = Enum.SurfaceType.Smooth
			w.BottomSurface = Enum.SurfaceType.Smooth
			w.Name = name .. "Wedge"
			w.Size = Vector3.new(thick, extra, depth)
			local center = Vector3.new(side * (hf + extra / 2), y, (zF + zB) / 2)
			w.CFrame = cf * CFrame.fromMatrix(center, Vector3.new(0, -side, 0), Vector3.new(side, 0, 0), Vector3.new(0, 0, 1))
			apply(w)
		end
	end
	return box
end

local function halfWidthAt(stage, z: number): number
	local t = (z - FRONT_Z) / (stage.backZ - FRONT_Z)
	return HALF_FRONT + (stage.halfBack - HALF_FRONT) * t
end

-- Everything except the front glass: rebuilt whenever the tank changes stage.
local function buildShape(index: number, cf: CFrame, model: Instance, stageIndex: number)
	local stage = Config.TANK_STAGES[stageIndex]
	local shape = Instance.new("Model")
	shape.Name = "Shape"
	local zF, zB, hf, hb, H = FRONT_Z, stage.backZ, HALF_FRONT, stage.halfBack, stage.height

	trapezoid("Stand", shape, cf, hf + 1, hb + 1, zF - 1, zB + 1, STAND_H / 2, STAND_H, { Material = Enum.Material.WoodPlanks, Color = COLORS.wood })
	trapezoid("Sand", shape, cf, hf, hb, zF, zB, STAND_H + 0.5, 1, { Material = Enum.Material.Sand, Color = COLORS.sand })
	local waterH = H - 1
	trapezoid("Water", shape, cf, hf, hb, zF, zB, STAND_H + 1 + waterH / 2, waterH, {
		Material = Enum.Material.SmoothPlastic,
		Color = COLORS.water,
		Transparency = 0.75,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})

	local midY = STAND_H + H / 2
	local glass = { Material = Enum.Material.Glass, Color = COLORS.glass, Transparency = 0.8, CastShadow = false }
	local function pane(name, size, offset)
		local props = table.clone(glass)
		props.Name = name
		props.Size = size
		props.CFrame = cf * offset
		props.Parent = shape
		return part(props)
	end
	pane("GlassBack", Vector3.new(hb * 2 + 0.8, H, 0.4), CFrame.new(0, midY, zB + 0.2))
	for _, side in { 1, -1 } do
		local a = Vector3.new(side * (hf + 0.2), midY, zF)
		local c = Vector3.new(side * (hb + 0.2), midY, zB)
		pane(if side > 0 then "GlassRight" else "GlassLeft", Vector3.new(0.4, H, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c))
	end
	trapezoid("Lid", shape, cf, hf + 0.4, hb + 0.4, zF - 0.4, zB + 0.4, STAND_H + H + 0.2, 0.4, {
		Material = Enum.Material.Glass,
		Color = COLORS.glass,
		Transparency = 0.9,
		CastShadow = false,
	})

	-- wooden piles under any part of the stand that hangs over the sea
	local function pile(x: number, z: number)
		local world = cf * Vector3.new(x, 0, z)
		if math.abs(world.X) < ISLAND_HALF - 2 and math.abs(world.Z) < ISLAND_HALF - 2 then
			return
		end
		part({ Name = "Pile", Size = Vector3.new(1.4, FLOOR_Y - SEA_FLOOR_Y, 1.4), CFrame = CFrame.new(world.X, (FLOOR_Y + SEA_FLOOR_Y) / 2, world.Z), Material = Enum.Material.Wood, Color = Color3.fromRGB(80, 56, 36), Parent = shape })
	end
	if zB > 20 then
		for z = zF + 10, zB + 9, 10 do
			local zz = math.min(z, zB)
			local hw = halfWidthAt(stage, zz)
			pile(hw, zz)
			pile(-hw, zz)
			if hw > 18 then
				pile(0, zz)
			end
		end
	end

	-- decor scales with the tank so big tanks don't look empty
	local rng = Random.new(index * 31 + stageIndex)
	local function randomSpot(margin: number): (number, number)
		local z = rng:NextNumber(zF + margin, zB - margin)
		local hw = math.max(0, halfWidthAt(stage, z) - margin)
		return rng:NextNumber(-hw, hw), z
	end
	for _ = 1, 2 * stageIndex do
		local size = rng:NextNumber(1.5, 3 + stageIndex * 0.5)
		local x, z = randomSpot(size)
		part({ Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = cf * CFrame.new(x, STAND_H + 1 + size * 0.3, z), Material = Enum.Material.Slate, Color = COLORS.rock, CanCollide = false, Parent = shape })
	end
	for _ = 1, 4 * stageIndex do
		local h = rng:NextNumber(3, math.min(H - 3, 7 + stageIndex))
		local x, z = randomSpot(1)
		part({ Name = "Seaweed", Size = Vector3.new(0.4, h, 0.4), CFrame = cf * CFrame.new(x, STAND_H + 1 + h / 2, z), Material = Enum.Material.Grass, Color = COLORS.weed, CanCollide = false, Parent = shape })
	end

	shape.Parent = model
	return shape
end

-- Builds / rebuilds a plot at a stage. The front glass (prompts, food gauge, owner sign) stays put.
local function setStage(plot, stageIndex: number)
	if plot.stage == stageIndex then
		return
	end
	local grew = plot.stage ~= nil and stageIndex > plot.stage and plot.owner ~= nil
	plot.stage = stageIndex
	if plot.shape then
		plot.shape:Destroy()
	end
	plot.shape = buildShape(plot.index, plot.cf, plot.model, stageIndex)

	local stage = Config.TANK_STAGES[stageIndex]
	local H = stage.height
	plot.front.Size = Vector3.new(TANK_W + 0.8, H, 0.4)
	plot.front.CFrame = plot.cf * CFrame.new(0, STAND_H + H / 2, FRONT_Z - 0.2)
	plot.billboard.StudsOffset = Vector3.new(0, H / 2 + 3.2, 0)

	-- clients swim the fish inside this shape (client/FishRenderer)
	local m = plot.model
	m:SetAttribute("TankStage", stageIndex)
	m:SetAttribute("TankFrontZ", FRONT_Z)
	m:SetAttribute("TankBackZ", stage.backZ)
	m:SetAttribute("TankHalfFront", HALF_FRONT)
	m:SetAttribute("TankHalfBack", stage.halfBack)
	m:SetAttribute("WaterBottom", STAND_H + 1)
	m:SetAttribute("WaterTop", STAND_H + H)

	if grew then
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		burst.Size = NumberSequence.new(1.2, 0)
		burst.Lifetime = NumberRange.new(1, 1.6)
		burst.Speed = NumberRange.new(8, 14)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Rate = 0
		burst.Parent = plot.front
		burst:Emit(80)
		task.delay(2, function()
			burst:Destroy()
		end)
	end
end

local function buildTank(index: number, cf: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("OwnerId", 0)

	-- invisible reference point: clients swim fish in this plot's local space
	part({ Name = "TankOrigin", Size = Vector3.new(1, 1, 1), CFrame = cf, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = model })

	-- front glass faces the plaza centre (local -Z); setStage sizes it
	local front = part({ Name = "GlassFront", Size = Vector3.new(TANK_W + 0.8, TANK_H, 0.4), CFrame = cf * CFrame.new(0, STAND_H + TANK_H / 2, FRONT_Z - 0.2), Material = Enum.Material.Glass, Color = COLORS.glass, Transparency = 0.8, CastShadow = false, Parent = model })

	-- Food gauge on the bottom of the front glass. Clients fill it in every frame-ish from the
	-- plot's FedUntil / FishCount attributes (smooth countdown, no server text updates).
	local foodGui = Instance.new("SurfaceGui")
	foodGui.Name = "FoodGui"
	foodGui.Face = Enum.NormalId.Front
	foodGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	foodGui.PixelsPerStud = 40
	foodGui.LightInfluence = 0
	foodGui.MaxDistance = 90
	foodGui.Parent = front
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, 0.97)
	strip.Size = UDim2.fromScale(0.8, 0.12)
	strip.BackgroundColor3 = Color3.fromRGB(14, 28, 44)
	strip.BackgroundTransparency = 0.15
	strip.Visible = false
	strip.Parent = foodGui
	Instance.new("UICorner", strip).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLORS.up
	fill.BorderSizePixel = 0
	fill.Parent = strip
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local foodText = textLabel({ Name = "Text", Size = UDim2.fromScale(1, 1), Text = "", TextStrokeTransparency = 0.3, ZIndex = 2, Parent = strip })
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = foodText
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(16, 2.5) -- in studs, so far-away signs shrink naturally
	billboard.StudsOffset = Vector3.new(0, TANK_H / 2 + 3.2, 0)
	billboard.MaxDistance = 120
	billboard.Parent = front
	local label = textLabel({ Name = "OwnerLabel", Size = UDim2.fromScale(1, 1), Text = "Empty tank", TextStrokeTransparency = 0.4, Parent = billboard })

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TankPrompt"
	prompt.ActionText = "Open Tank"
	prompt.ObjectText = "Empty"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = front

	-- Feeding happens AT the tank. Every client hides this prompt on tanks that aren't theirs.
	local feedPrompt = Instance.new("ProximityPrompt")
	feedPrompt.Name = "FeedPrompt"
	feedPrompt.ActionText = "Feed fish"
	feedPrompt.ObjectText = "Food"
	feedPrompt.KeyboardKeyCode = Enum.KeyCode.F
	feedPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	feedPrompt.MaxActivationDistance = 12
	feedPrompt.RequiresLineOfSight = false
	feedPrompt.UIOffset = Vector2.new(0, 80) -- sits under the Open Tank prompt
	feedPrompt.Parent = front

	local fishValue = Instance.new("StringValue")
	fishValue.Name = "FishData"
	fishValue.Value = "[]"
	fishValue.Parent = model

	-- patio spots: a faint sand circle while empty; owner gets a "Place item / Pick up" prompt
	-- (every client hides the prompts on tanks that aren't theirs, like the feed prompt)
	local patioSpots = {}
	for spot, offset in PATIO_SPOTS do
		local spotCF = onGround(cf * CFrame.new(offset)) -- on top of the terrain sand, not under it
		local marker = part({
			Name = "PatioSpot",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 5, 5),
			CFrame = spotCF * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(255, 245, 215), -- light circle so it stands out on the sand
			Transparency = 0.45,
			CanCollide = false,
			CanTouch = false,
			Parent = model,
		})
		marker:SetAttribute("Spot", spot)
		local patioPrompt = Instance.new("ProximityPrompt")
		patioPrompt.Name = "PatioPrompt"
		patioPrompt.ActionText = "Place item"
		patioPrompt.ObjectText = "Patio spot"
		patioPrompt.KeyboardKeyCode = Enum.KeyCode.E
		patioPrompt.MaxActivationDistance = 6
		patioPrompt.RequiresLineOfSight = false
		patioPrompt.Parent = marker
		patioSpots[spot] = { marker = marker, prompt = patioPrompt, itemId = nil, model = nil, cf = spotCF }
	end

	model.Parent = parent

	local standPos = (cf * CFrame.new(0, 3, -(TANK_D / 2 + 10))).Position
	local plot = {
		index = index,
		cf = cf,
		patioSpots = patioSpots,
		front = front,
		billboard = billboard,
		stage = nil,
		shape = nil,
		model = model,
		owner = nil,
		spawnCFrame = CFrame.lookAt(standPos, Vector3.new(cf.Position.X, standPos.Y, cf.Position.Z)),
		fishValue = fishValue,
		label = label,
		prompt = prompt,
		feedPrompt = feedPrompt,
		lastJson = "[]",
	}
	setStage(plot, 1)
	return plot
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
	-- Terrain works in 4-stud voxels, so the sand above came out ~1.5 studs HIGHER than the plaza and
	-- buried the bottoms of tank stands and patio items. Clear every voxel from y = 0 up, so the sand
	-- can never rise above the plaza floor (FLOOR_Y = 0.4). Voxel-aligned (0..32) so nothing is half-cleared.
	terrain:FillBlock(CFrame.new(0, 16, 0), Vector3.new(ISLAND_SIZE + 8, 32, ISLAND_SIZE + 8), Enum.Material.Air)
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
	-- title is set per pier in WorldService.start (MAIN / EAST / WEST PIER)
	textLabel({ Name = "PierTitle", Text = "MAIN PIER", Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.55), Parent = gui })
	textLabel({ Name = "PierSubtitle", Text = "🚤 Boats buy fish here", TextColor3 = Color3.fromRGB(255, 220, 150), Position = UDim2.fromScale(0.1, 0.62), Size = UDim2.fromScale(0.8, 0.3), Parent = gui })

	model.Parent = parent
end

-- Palm trees ------------------------------------------------------------------
-- Only where tanks can never grow and piers never go: the 4 island corners (diagonal gaps between
-- tank slices) and the back beach behind the market board. Spots checked against every tank stage
-- (Sea Pen included) and all piers: nearest trunk is 13+ studs away. { angle°, radius, sideways }
local PALM_SPOTS = {}
for _, a in { 45, 135, 225, 315 } do
	for _, spot in { { 141, -5 }, { 149, 6 }, { 157, -1 } } do
		table.insert(PALM_SPOTS, { a, spot[1], spot[2] })
	end
end
table.insert(PALM_SPOTS, { 180, 103, -5 })
table.insert(PALM_SPOTS, { 180, 109, 5 })

local function buildPalm(parent: Instance, base: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "PalmTree"
	local trunkColor = Color3.fromRGB(140, 105, 70)
	local leafColor = Color3.fromRGB(70, 150, 70)
	local height = rng:NextNumber(17, 24)
	local leanDir = rng:NextNumber(0, math.pi * 2)
	local lean = rng:NextNumber(3, 6) -- studs the top leans sideways
	local SEGMENTS = 6

	-- curved trunk: segments bending more toward the top, getting thinner
	local function trunkPoint(f: number): Vector3
		local side = lean * f * f
		return base + Vector3.new(math.cos(leanDir) * side, height * f, math.sin(leanDir) * side)
	end
	for i = 1, SEGMENTS do
		local p0, p1 = trunkPoint((i - 1) / SEGMENTS), trunkPoint(i / SEGMENTS)
		local d = 1.5 - 0.5 * (i / SEGMENTS)
		part({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((p1 - p0).Magnitude + 0.3, d, d),
			CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.pi / 2, 0), -- cylinder axis (X) along the trunk
			Material = Enum.Material.Wood,
			Color = trunkColor:Lerp(Color3.fromRGB(110, 80, 55), (i % 2) * 0.5), -- ringed bark
			Parent = model,
		})
	end
	local top = trunkPoint(1)

	-- coconuts under the leaves
	for k = 1, rng:NextInteger(2, 4) do
		local a = k * 2.1 + rng:NextNumber(0, 0.5)
		part({ Name = "Coconut", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(top + Vector3.new(math.cos(a) * 0.7, -0.8, math.sin(a) * 0.7)), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(95, 70, 40), CanCollide = false, Parent = model })
	end

	-- fronds: each leaf goes up and out, then droops
	local leaves = rng:NextInteger(7, 9)
	for k = 1, leaves do
		local a = (k / leaves) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local len = rng:NextNumber(6, 8)
		local mid = top + out * (len * 0.5) + Vector3.new(0, 1.2, 0)
		local tip = top + out * len + Vector3.new(0, -rng:NextNumber(1.5, 3), 0)
		for _, seg in { { top, mid, 1.8 }, { mid, tip, 1.3 } } do
			local s, e, w = seg[1], seg[2], seg[3]
			part({
				Name = "Leaf",
				Size = Vector3.new(w, 0.15, (e - s).Magnitude + 0.4),
				CFrame = CFrame.lookAt((s + e) / 2, e),
				Material = Enum.Material.Grass,
				Color = leafColor:Lerp(Color3.fromRGB(110, 170, 70), rng:NextNumber(0, 0.5)),
				CanCollide = false,
				CastShadow = true,
				Parent = model,
			})
		end
	end
	model.Parent = parent
end

-- Harbor Store hut ------------------------------------------------------------
-- On the plaza opposite the market counter, facing the centre. Press E at the counter.
local STORE_POS = Vector3.new(0, FLOOR_Y, 30)

local function buildStore(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "HarborStore"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local cf = onGround(CFrame.lookAt(STORE_POS, Vector3.new(0, FLOOR_Y, 0))) -- front (-Z) faces the plaza centre; on the sand
	local W, D, H = 16, 10, 9
	local wood, planks = COLORS.wood, Color3.fromRGB(205, 170, 120)
	local function piece(name, size, offset: CFrame, color, material, collide)
		return part({ Name = name, Size = size, CFrame = cf * offset, Color = color, Material = material or Enum.Material.WoodPlanks, CanCollide = collide ~= false, Parent = model })
	end

	piece("Deck", Vector3.new(W + 2, 0.6, D + 2), CFrame.new(0, 0.3, 0), wood)
	piece("BackWall", Vector3.new(W, H, 0.6), CFrame.new(0, H / 2 + 0.6, D / 2), planks)
	for _, side in { -1, 1 } do
		piece("SideWall", Vector3.new(0.6, H, D), CFrame.new(side * W / 2, H / 2 + 0.6, 0), planks)
		piece("Post", Vector3.new(0.8, H + 1.5, 0.8), CFrame.new(side * (W / 2 + 0.3), (H + 1.5) / 2 + 0.6, -D / 2 - 1.5), wood)
	end
	-- shelves with little goods on the back wall
	for row = 1, 2 do
		piece("Shelf", Vector3.new(W - 2, 0.3, 1.4), CFrame.new(0, 2.5 + row * 2.2, D / 2 - 1), wood)
		for k = 1, 6 do
			local colors = { Color3.fromRGB(230, 80, 70), Color3.fromRGB(70, 160, 230), Color3.fromRGB(250, 200, 60), Color3.fromRGB(90, 190, 110) }
			piece("Goods", Vector3.new(1, 1, 0.8), CFrame.new(-W / 2 + 1.5 + k * 2, 3.2 + row * 2.2, D / 2 - 1), colors[(k + row) % 4 + 1], Enum.Material.SmoothPlastic, false)
		end
	end
	-- counter at the front
	local counter = piece("Counter", Vector3.new(W - 3, 3.4, 1.6), CFrame.new(0, 2.3, -D / 2 + 1.5), wood)
	piece("CounterTop", Vector3.new(W - 2.6, 0.3, 2), CFrame.new(0, 4.1, -D / 2 + 1.5), planks)
	-- roof + striped awning sloping down over the front
	piece("Roof", Vector3.new(W + 2, 0.5, D + 1), CFrame.new(0, H + 0.85, 0.5), wood)
	local stripes = 8
	for k = 0, stripes - 1 do
		local x = -W / 2 - 1 + (k + 0.5) * (W + 2) / stripes
		piece("Awning", Vector3.new((W + 2) / stripes, 0.25, 4), CFrame.new(x, H + 0.1, -D / 2 - 1.2) * CFrame.Angles(math.rad(18), 0, 0), if k % 2 == 0 then Color3.fromRGB(230, 70, 70) else Color3.fromRGB(250, 245, 235), Enum.Material.Fabric, false)
	end

	-- sign above the awning
	local sign = piece("Sign", Vector3.new(W - 2, 2.6, 0.4), CFrame.new(0, H + 2.4, -D / 2 + 0.2), Color3.fromRGB(14, 28, 44), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = sign
	textLabel({ Text = "HARBOR STORE", Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.55), Parent = gui })
	textLabel({ Text = "Patio decor · chairs · torches", TextColor3 = Color3.fromRGB(255, 220, 150), Position = UDim2.fromScale(0.1, 0.62), Size = UDim2.fromScale(0.8, 0.3), Parent = gui })

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StorePrompt"
	prompt.ActionText = "Open Store"
	prompt.ObjectText = "Harbor Store"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	-- show-off display in front of the hut (same models players can buy)
	for _, display in { { "umbrella", -11, -9 }, { "chair", -11, -8.5 }, { "torch", 10.5, -8 }, { "sandcastle", 12, -11 } } do
		local m = PatioModels.build(display[1], onGround(cf * CFrame.new(display[2], 0, display[3])))
		if m then
			m.Parent = model
		end
	end

	model.Parent = parent
end

local function buildPalms(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Palms"
	local rng = Random.new(2026)
	for _, spot in PALM_SPOTS do
		local a = math.rad(spot[1])
		local r, side = spot[2], spot[3]
		local x = math.sin(a) * r + math.cos(a) * side
		local z = math.cos(a) * r - math.sin(a) * side
		buildPalm(folder, Vector3.new(x, FLOOR_Y - 0.4, z), rng) -- beach sand top
	end
	folder.Parent = parent
end

function WorldService.start()
	local world = Instance.new("Folder")
	world.Name = "FishWorld"

	buildSea()
	buildPier(world)
	-- More piers (Config.BOAT.piers): copies of the main one turned around the island centre into
	-- the gaps between tanks (90 = east, between tanks 2/3; -90 = west, between 6/7). Each gets a boat.
	local mainPier = world:FindFirstChild("FishingPier")
	for i, pier in Config.BOAT.piers do
		local model = mainPier
		if pier.angle ~= 0 then
			model = mainPier:Clone()
			model.Name = "FishingPier" .. i
			model:PivotTo(CFrame.Angles(0, math.rad(pier.angle), 0) * model:GetPivot())
			model.Parent = world
		end
		local title = model:FindFirstChild("PierTitle", true)
		if title then
			title.Text = string.upper(pier.name) -- "MAIN PIER", "EAST PIER", "WEST PIER"
		end
	end

	-- the plaza is now the visible ground (terrain sand sits just under it), so it looks like sand
	part({ Name = "Plaza", Size = Vector3.new(190, 0.4, 190), CFrame = CFrame.new(0, FLOOR_Y - 0.2, 0), Material = Enum.Material.Sand, Color = Color3.fromRGB(232, 218, 178), Parent = world })

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = world
	for i = 1, PLOT_COUNT do
		local angle = math.rad(22.5 + (i - 1) * (360 / PLOT_COUNT))
		local pos = Vector3.new(math.sin(angle) * PLOT_RADIUS, FLOOR_Y, math.cos(angle) * PLOT_RADIUS)
		plots[i] = buildTank(i, CFrame.lookAt(pos, Vector3.new(0, FLOOR_Y, 0)), plotsFolder)
	end

	buildMarket(world)
	buildStore(world)
	buildPalms(world)
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
	plot.model:SetAttribute("FedUntil", 0)
	plot.model:SetAttribute("FishCount", 0)
	plot.model:SetAttribute("AutoFeeder", false)
	plot.lastJson = "[]"
	setStage(plot, 1)
	WorldService.showPatio(plot, {}, {})
end

-- Builds / removes patio items so the plot shows exactly `patio` ({ s1 = itemId, ... }) with
-- `colors` ({ s1 = "red" } for flags). Only rebuilds spots that changed.
function WorldService.showPatio(plot, patio, colors)
	for spot, s in plot.patioSpots do
		local want = patio["s" .. spot]
		local wantColor = colors and colors["s" .. spot]
		if s.itemId ~= want or s.color ~= wantColor then
			s.color = wantColor
			if s.model then
				s.model:Destroy()
				s.model = nil
			end
			s.itemId = want
			if want then
				local c = wantColor and Config.PatioColorByKey[wantColor]
				s.model = PatioModels.build(want, s.cf, c and c.color)
				if s.model then
					s.model.Parent = plot.model
				end
			end
			local item = want and Config.PatioById[want]
			s.marker.Transparency = if want then 1 else 0.45
			s.prompt.ActionText = if item then "Pick up" else "Place item"
			s.prompt.ObjectText = if item then item.name else "Patio spot"
		end
	end
end

function WorldService.updatePatio(player: Player, patio, colors)
	local plot = plotOf[player]
	if plot and not plot.stress then
		WorldService.showPatio(plot, patio or {}, colors or {})
	end
end

-- Grows (or, for a new owner, resets) the tank to match the owner's slot count.
function WorldService.updateTankStage(player: Player, slots: number)
	local plot = plotOf[player]
	if plot and not plot.stress then
		setStage(plot, Config.tankStage(slots))
	end
end

-- Feed prompt text on the player's own tank (cost of filling the food up).
function WorldService.updateFeedPrompt(player: Player, state)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local text = if state.autoFeeder then "Auto-Feeder is on"
		elseif #state.fish == 0 then "Feed (no fish yet)"
		elseif state.feedCost > 0 then ("Feed fish (%d coins)"):format(state.feedCost)
		else "Food is full"
	if plot.feedPrompt.ActionText ~= text then
		plot.feedPrompt.ActionText = text
	end
	-- for the food gauge on the glass (drawn by clients)
	plot.model:SetAttribute("FedUntil", state.fedUntil)
	plot.model:SetAttribute("FishCount", #state.fish)
	plot.model:SetAttribute("AutoFeeder", state.autoFeeder)
end

-- callback(player) when a player feeds at THEIR OWN tank.
function WorldService.onFeed(callback)
	for _, plot in plots do
		plot.feedPrompt.Triggered:Connect(function(player)
			if plot.owner == player then
				callback(player)
			end
		end)
	end
end

-- Publishes the visible fish list for this player's tank (only if it changed).
function WorldService.updateFish(player: Player, data, now: number)
	local plot = plotOf[player]
	if not plot or plot.stress then
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

-- STUDIO ONLY worst-case load test (server/StudioStress): every tank becomes a Sea Pen full of
-- fully grown Koi with 3 tiki torches + an umbrella on its patio. 0 = back to normal: unowned
-- tanks reset, owned ones are restored by the next 5-second tick (real player data is untouched).
function WorldService.setStress(fishPerTank: number)
	local on = fishPerTank > 0
	for _, plot in plots do
		plot.stress = on
		if on then
			setStage(plot, #Config.TANK_STAGES)
			local list = {}
			for k = 1, fishPerTank do
				table.insert(list, { u = 900000 + plot.index * 1000 + k, s = "koi", a = Config.MAX_AGE, h = false })
			end
			plot.fishValue.Value = HttpService:JSONEncode(list)
			WorldService.showPatio(plot, { s1 = "torch", s2 = "torch", s3 = "torch", s4 = "umbrella" }, {})
		else
			plot.lastJson = "" -- forces the owner's real fish to be published again
			if not plot.owner then
				plot.fishValue.Value = "[]"
				setStage(plot, 1)
				WorldService.showPatio(plot, {}, {})
			end
		end
	end
end

return WorldService
