-- Draws and animates every tank's fish on THIS device only.
-- The server publishes a small list per plot (FishData: uid, species, age, hungry);
-- we turn it into simple ellipsoid parts and swim them around with one BulkMoveTo per frame.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FishRenderer = {}

local BODY = Vector3.new(0.45, 0.6, 1.2) -- width, height, length at scale 1
local TAIL = Vector3.new(0.06, 0.6, 0.5)
local TURN_RATE = 2.5
local rng = Random.new()

local container = nil
local tanks = {} -- [plotModel] = { water = Part, fish = { [uid] = fishObj } }

local function newPart(name: string, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = container
	return p
end

-- Babies start small; adults keep getting a bit bigger with size.
local function visualScale(species, age: number): number
	local growth
	if age < 1 then
		growth = 0.35 + 0.65 * age
	else
		growth = 1 + (Config.sizeFromAge(age) - 1) * 0.6
	end
	return species.visual.scale * growth
end

local function applySize(fish)
	local s = fish.scale
	fish.body.Size = BODY * s
	fish.tail.Size = TAIL * s
	if fish.stripe then
		fish.stripe.Size = Vector3.new(BODY.X * 1.08, BODY.Y * 1.08, BODY.Z * 0.18) * s
	end
end

local function randomPoint(water: BasePart, margin: number): Vector3
	local half = water.Size / 2
	local hx = math.max(0, half.X - margin)
	local hy = math.max(0, half.Y - margin * 0.6)
	local hz = math.max(0, half.Z - margin)
	return water.CFrame * Vector3.new(rng:NextNumber(-hx, hx), rng:NextNumber(-hy, hy), rng:NextNumber(-hz, hz))
end

local function margin(fish): number
	return BODY.Z * fish.scale * 0.6 + 0.4
end

local function createFish(tank, entry)
	local species = Config.ById[entry.s]
	if not species then
		return nil
	end
	local v = species.visual
	local fish = {
		species = species,
		body = newPart("FishBody", species.color),
		tail = newPart("FishTail", v.tail),
		stripe = if v.stripe then newPart("FishStripe", v.stripe) else nil,
		scale = visualScale(species, entry.a),
		hungry = entry.h,
		phase = rng:NextNumber(0, math.pi * 2),
		dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit,
	}
	applySize(fish)
	fish.pos = randomPoint(tank.water, margin(fish))
	fish.target = randomPoint(tank.water, margin(fish))
	return fish
end

local function destroyFish(fish)
	fish.body:Destroy()
	fish.tail:Destroy()
	if fish.stripe then
		fish.stripe:Destroy()
	end
end

local function syncTank(tank, json: string)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(list) ~= "table" then
		return
	end
	local seen = {}
	for _, entry in list do
		seen[entry.u] = true
		local fish = tank.fish[entry.u]
		if fish then
			local scale = visualScale(fish.species, entry.a)
			if math.abs(scale - fish.scale) > 0.01 then
				fish.scale = scale
				applySize(fish)
			end
			fish.hungry = entry.h
		else
			tank.fish[entry.u] = createFish(tank, entry)
		end
	end
	for uid, fish in tank.fish do
		if not seen[uid] then
			destroyFish(fish)
			tank.fish[uid] = nil
		end
	end
end

local function addTank(plot: Instance)
	task.spawn(function()
		local water = plot:WaitForChild("Water", 30)
		local data = plot:WaitForChild("FishData", 30)
		if not water or not data then
			return
		end
		local tank = { water = water, fish = {} }
		tanks[plot] = tank
		syncTank(tank, data.Value)
		data.Changed:Connect(function()
			syncTank(tank, data.Value)
		end)
	end)
end

local parts, cframes = {}, {}

local function step(dt: number)
	dt = math.min(dt, 0.1)
	local t = os.clock()
	table.clear(parts)
	table.clear(cframes)

	for _, tank in tanks do
		for _, fish in tank.fish do
			local speed = fish.species.visual.speed * (if fish.hungry then 0.35 else 1)

			-- new target when reached, or after a few seconds so a fish can never circle forever
			local toTarget = fish.target - fish.pos
			if toTarget.Magnitude < 1.5 or t > (fish.retargetAt or 0) then
				fish.target = randomPoint(tank.water, margin(fish))
				fish.retargetAt = t + rng:NextNumber(3, 6)
				toTarget = fish.target - fish.pos
			end
			if toTarget.Magnitude > 0.001 then
				local want = toTarget.Unit
				want = Vector3.new(want.X, math.clamp(want.Y, -0.35, 0.35), want.Z) -- gentle climbs/dives
				if want.Magnitude > 0.01 then
					local d = fish.dir:Lerp(want.Unit, math.min(1, dt * TURN_RATE))
					if d.Magnitude > 0.01 then
						fish.dir = d.Unit
					end
				end
			end
			fish.pos += fish.dir * speed * dt

			-- hard wall: whatever happens, the fish stays inside the water box
			local water = tank.water
			local m = margin(fish)
			local half = water.Size / 2
			local localPos = water.CFrame:PointToObjectSpace(fish.pos)
			local limX = math.max(0, half.X - m)
			local limY = math.max(0, half.Y - m * 0.6)
			local limZ = math.max(0, half.Z - m)
			local clamped = Vector3.new(math.clamp(localPos.X, -limX, limX), math.clamp(localPos.Y, -limY, limY), math.clamp(localPos.Z, -limZ, limZ))
			if clamped ~= localPos then
				fish.pos = water.CFrame:PointToWorldSpace(clamped)
				fish.target = randomPoint(water, m)
				fish.retargetAt = t + rng:NextNumber(3, 6)
			end

			local length = BODY.Z * fish.scale
			local wiggle = math.sin(t * (if fish.hungry then 4 else 10) + fish.phase) * 0.45
			local cf = CFrame.lookAt(fish.pos, fish.pos + fish.dir)
			if fish.hungry then
				cf *= CFrame.Angles(0, 0, 0.6) -- sad sideways tilt
			end

			table.insert(parts, fish.body)
			table.insert(cframes, cf * CFrame.Angles(0, -wiggle * 0.15, 0))
			table.insert(parts, fish.tail)
			table.insert(cframes, cf * CFrame.new(0, 0, length * 0.45) * CFrame.Angles(0, wiggle, 0) * CFrame.new(0, 0, TAIL.Z * fish.scale * 0.5))
			if fish.stripe then
				table.insert(parts, fish.stripe)
				table.insert(cframes, cf * CFrame.new(0, 0, -length * 0.1))
			end
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function FishRenderer.start()
	container = Instance.new("Folder")
	container.Name = "LocalFish"
	container.Parent = workspace

	RunService.RenderStepped:Connect(step)

	task.spawn(function()
		local plots = workspace:WaitForChild("FishWorld"):WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			addTank(plot)
		end
		plots.ChildAdded:Connect(addTank)
	end)
end

return FishRenderer
