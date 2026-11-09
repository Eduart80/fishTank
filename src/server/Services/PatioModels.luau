-- 3D models for Harbor Store patio items, built from simple parts (no assets needed).
-- PatioModels.build(itemId, cf) -> Model. cf = the spot on the floor; the item's front faces cf's
-- LookVector (toward the plaza). Everything except trunks/poles/seats is non-collidable.

local PatioModels = {}

local WOOD = Color3.fromRGB(150, 110, 70)
local DARK_WOOD = Color3.fromRGB(100, 70, 45)
local RED = Color3.fromRGB(220, 60, 50)
local WHITE = Color3.fromRGB(245, 245, 240)
local GOLD = Color3.fromRGB(255, 200, 60)

local function p(model: Model, props)
	local part = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		part[key] = value
	end
	part.Parent = model
	return part
end

-- vertical cylinder centred at `at` (cf-relative offset), height h, diameter d
local function vcyl(model, cf: CFrame, at: Vector3, h: number, d: number, props)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(h, d, d)
	props.CFrame = cf * CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	return p(model, props)
end

local function ball(model, cf: CFrame, at: Vector3, d: number, props)
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(d, d, d)
	props.CFrame = cf * CFrame.new(at)
	return p(model, props)
end

local builders = {}

builders.flag = function(m, cf, color: Color3?)
	vcyl(m, cf, Vector3.new(0, 5, 0), 10, 0.35, { Color = WHITE, CanCollide = true })
	ball(m, cf, Vector3.new(0, 10.1, 0), 0.6, { Color = GOLD })
	-- cloth sticks out sideways from the pole, flat face toward the plaza
	p(m, { Size = Vector3.new(3.8, 2.4, 0.1), CFrame = cf * CFrame.new(2.05, 8.6, 0), Color = color or Color3.fromRGB(40, 110, 220), Material = Enum.Material.Fabric, Name = "Cloth" })
	p(m, { Size = Vector3.new(3.8, 0.6, 0.12), CFrame = cf * CFrame.new(2.05, 8.6, 0), Color = WHITE, Material = Enum.Material.Fabric })
end

builders.chair = function(m, cf)
	local seat = p(m, { ClassName = "Seat", Size = Vector3.new(2.6, 0.4, 2.6), CFrame = cf * CFrame.new(0, 1.3, 0), Color = Color3.fromRGB(40, 120, 200), Material = Enum.Material.Fabric, CanCollide = true })
	seat.Name = "Seat"
	-- backrest tilted back (behind the seat = +Z, the front faces the plaza)
	p(m, { Size = Vector3.new(2.6, 3, 0.3), CFrame = cf * CFrame.new(0, 2.6, 1.35) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(40, 120, 200), Material = Enum.Material.Fabric })
	for _, x in { -0.9, 0, 0.9 } do -- white stripes
		p(m, { Size = Vector3.new(0.3, 3.02, 0.32), CFrame = cf * CFrame.new(x, 2.6, 1.35) * CFrame.Angles(math.rad(-20), 0, 0), Color = WHITE, Material = Enum.Material.Fabric })
	end
	for _, x in { -1.3, 1.3 } do
		for _, z in { -1.2, 1.2 } do
			p(m, { Size = Vector3.new(0.2, 1.2, 0.2), CFrame = cf * CFrame.new(x, 0.6, z), Color = WOOD })
		end
		p(m, { Size = Vector3.new(0.2, 0.2, 2.6), CFrame = cf * CFrame.new(x, 2, 0), Color = WOOD }) -- armrest
	end
end

builders.torch = function(m, cf)
	vcyl(m, cf, Vector3.new(0, 3, 0), 6, 0.45, { Color = Color3.fromRGB(190, 160, 90), Material = Enum.Material.Wood, CanCollide = true })
	for y = 1, 5, 1.3 do -- bamboo rings
		vcyl(m, cf, Vector3.new(0, y, 0), 0.15, 0.55, { Color = Color3.fromRGB(150, 120, 60) })
	end
	local cup = vcyl(m, cf, Vector3.new(0, 6.3, 0), 0.8, 1, { Color = DARK_WOOD, Material = Enum.Material.Wood })
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 150, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = cup
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = cup
end

builders.lifebuoy = function(m, cf)
	p(m, { Size = Vector3.new(0.5, 5, 0.5), CFrame = cf * CFrame.new(0, 2.5, 0.4), Color = WOOD, CanCollide = true })
	-- ring of 12 blocks, alternating red/white, standing up facing the plaza
	local center = cf * CFrame.new(0, 3.6, 0)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		p(m, { Size = Vector3.new(0.75, 0.75, 0.5), CFrame = center * CFrame.new(math.cos(a) * 1.3, math.sin(a) * 1.3, 0) * CFrame.Angles(0, 0, a), Color = if (i // 3) % 2 == 0 then RED else WHITE })
	end
end

builders.umbrella = function(m, cf)
	vcyl(m, cf, Vector3.new(0, 4, 0), 8, 0.3, { Color = WHITE, CanCollide = true })
	-- canopy: 3 stacked discs, red / white / red, getting smaller = a low cone
	vcyl(m, cf, Vector3.new(0, 7.6, 0), 0.3, 8, { Color = RED, Material = Enum.Material.Fabric })
	vcyl(m, cf, Vector3.new(0, 7.9, 0), 0.3, 5.6, { Color = WHITE, Material = Enum.Material.Fabric })
	vcyl(m, cf, Vector3.new(0, 8.2, 0), 0.3, 3, { Color = RED, Material = Enum.Material.Fabric })
	ball(m, cf, Vector3.new(0, 8.5, 0), 0.5, { Color = WHITE })
	-- a towel on the sand under it
	p(m, { Size = Vector3.new(2.4, 0.1, 4.4), CFrame = cf * CFrame.new(0.4, 0.05, 0) * CFrame.Angles(0, 0.3, 0), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Fabric })
end

local function miniPalm(m, cf, trunkColor: Color3, leafColor: Color3, leafMaterial: Enum.Material, height: number)
	for i = 0, 3 do
		vcyl(m, cf, Vector3.new(0.08 * i * i, 1.8 + i * (height / 4), 0), height / 4 + 0.1, 0.6 - i * 0.08, { Color = trunkColor, Material = Enum.Material.Wood })
	end
	local top = cf * CFrame.new(0.72, 1.6 + height, 0)
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local s, e = top.Position, top.Position + out * 3 + Vector3.new(0, -1, 0)
		p(m, { Size = Vector3.new(1, 0.12, 3.3), CFrame = CFrame.lookAt((s + e) / 2, e), Color = leafColor, Material = leafMaterial })
	end
end

builders.pottedPalm = function(m, cf)
	vcyl(m, cf, Vector3.new(0, 0.8, 0), 1.6, 2.2, { Color = Color3.fromRGB(190, 100, 60), CanCollide = true })
	vcyl(m, cf, Vector3.new(0, 1.65, 0), 0.2, 1.9, { Color = Color3.fromRGB(90, 60, 40) }) -- soil
	miniPalm(m, cf, Color3.fromRGB(140, 105, 70), Color3.fromRGB(70, 150, 70), Enum.Material.Grass, 4)
end

builders.neonPalm = function(m, cf)
	vcyl(m, cf, Vector3.new(0, 0.8, 0), 1.6, 2.2, { Color = Color3.fromRGB(40, 40, 60), CanCollide = true })
	miniPalm(m, cf, Color3.fromRGB(255, 80, 200), Color3.fromRGB(60, 255, 200), Enum.Material.Neon, 5)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(80, 255, 220)
	glow.Range = 16
	glow.Parent = m:FindFirstChildWhichIsA("BasePart")
end

builders.sandcastle = function(m, cf)
	local sand = Color3.fromRGB(225, 200, 145)
	p(m, { Size = Vector3.new(4, 1.4, 4), CFrame = cf * CFrame.new(0, 0.7, 0), Color = sand, Material = Enum.Material.Sand, CanCollide = true })
	p(m, { Size = Vector3.new(2.4, 1.2, 2.4), CFrame = cf * CFrame.new(0, 2, 0), Color = sand, Material = Enum.Material.Sand })
	for _, x in { -1.7, 1.7 } do
		for _, z in { -1.7, 1.7 } do
			vcyl(m, cf, Vector3.new(x, 1.3, z), 2.6, 1.1, { Color = sand, Material = Enum.Material.Sand })
		end
	end
	vcyl(m, cf, Vector3.new(0, 3.3, 0), 1.6, 1.2, { Color = sand, Material = Enum.Material.Sand })
	p(m, { Size = Vector3.new(0.08, 1.4, 0.08), CFrame = cf * CFrame.new(0, 4.6, 0), Color = WHITE })
	p(m, { Size = Vector3.new(0.05, 0.5, 0.8), CFrame = cf * CFrame.new(0, 5, 0.4), Color = RED, Material = Enum.Material.Fabric })
	p(m, { Size = Vector3.new(0.8, 0.8, 0.1), CFrame = cf * CFrame.new(0, 0.7, -2.02), Color = Color3.fromRGB(120, 95, 60) }) -- gate
end

builders.treasure = function(m, cf)
	p(m, { Size = Vector3.new(3, 1.6, 2), CFrame = cf * CFrame.new(0, 0.8, 0), Color = DARK_WOOD, Material = Enum.Material.Wood, CanCollide = true })
	for _, x in { -1.1, 1.1 } do
		p(m, { Size = Vector3.new(0.2, 1.65, 2.05), CFrame = cf * CFrame.new(x, 0.8, 0), Color = GOLD, Material = Enum.Material.Metal })
	end
	-- open lid tilted back, gold heap inside
	p(m, { Size = Vector3.new(3, 0.3, 2), CFrame = cf * CFrame.new(0, 1.9, 1.3) * CFrame.Angles(math.rad(-70), 0, 0), Color = DARK_WOOD, Material = Enum.Material.Wood })
	local heap = ball(m, cf, Vector3.new(0, 1.55, 0), 1.8, { Color = GOLD, Material = Enum.Material.Foil, Reflectance = 0.3 })
	heap.Size = Vector3.new(2.6, 1, 1.6)
	for i = 1, 6 do
		ball(m, cf, Vector3.new((i - 3.5) * 0.4, 2 + (i % 2) * 0.15, (i % 3 - 1) * 0.4), 0.45, { Color = Color3.fromRGB(255, 225, 90), Material = Enum.Material.Neon })
	end
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = GOLD
	sparkle.Parent = heap
end

builders.goldenFish = function(m, cf)
	local stone = Color3.fromRGB(170, 170, 175)
	p(m, { Size = Vector3.new(2.6, 0.6, 2.6), CFrame = cf * CFrame.new(0, 0.3, 0), Color = stone, Material = Enum.Material.Slate, CanCollide = true })
	vcyl(m, cf, Vector3.new(0, 1.8, 0), 2.4, 1.4, { Color = stone, Material = Enum.Material.Slate, CanCollide = true })
	p(m, { Size = Vector3.new(2, 0.4, 2), CFrame = cf * CFrame.new(0, 3.2, 0), Color = stone, Material = Enum.Material.Slate })
	-- leaping fish: body + tail, tilted up
	local fishCF = cf * CFrame.new(0, 4.9, 0) * CFrame.Angles(math.rad(35), math.pi / 2, 0)
	local gold = { Color = GOLD, Material = Enum.Material.Foil, Reflectance = 0.35 }
	local body = p(m, table.clone(gold))
	body.Size = Vector3.new(1, 1.4, 3)
	body.CFrame = fishCF
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	local tail = p(m, table.clone(gold))
	tail.Size = Vector3.new(0.15, 1.3, 1)
	tail.CFrame = fishCF * CFrame.new(0, 0, 1.8)
	local shine = Instance.new("Sparkles")
	shine.SparkleColor = Color3.fromRGB(255, 240, 150)
	shine.Parent = body
end

-- Builds the item at cf (floor spot, front = cf.LookVector). Unknown id -> nil.
-- NICER MODELS: in Studio put a Model in ServerStorage > PatioModels named exactly like the item id
-- (e.g. "chair"). Its pivot should sit on the floor, front facing the model's -Z (LookVector), about
-- 5x5 studs wide. If it's there it is used instead of the simple built-in shape (no code change).
-- Keep a Seat inside a chair model if players should be able to sit.
function PatioModels.build(itemId: string, cf: CFrame, color: Color3?): Model?
	local custom = game:GetService("ServerStorage"):FindFirstChild("PatioModels")
	custom = custom and custom:FindFirstChild(itemId)
	if custom and custom:IsA("Model") then
		local copy = custom:Clone()
		copy.Name = "Patio_" .. itemId
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		copy:PivotTo(cf)
		if color then -- custom colourable models: name the coloured parts "Cloth"
			for _, d in copy:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Cloth" then
					d.Color = color
				end
			end
		end
		return copy
	end
	local builder = builders[itemId]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Patio_" .. itemId
	builder(model, cf, color)
	return model
end

PatioModels.builders = builders
return PatioModels
