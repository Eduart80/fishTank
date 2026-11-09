-- Rising bubbles in every tank, drawn on THIS device only (like the fish).
-- Each tank has a few bubble spots on the sand (more in bigger stages); bubbles wobble up and
-- pop at the surface. Only tanks near the camera bubble, with a global cap, so phones stay smooth.
-- Reads the tank shape from the plot attributes set by the server (WorldService.setStage).

local RunService = game:GetService("RunService")

local Bubbles = {}

local NEAR = 140 -- studs from the camera: farther tanks don't bubble
local MAX_BUBBLES = 140 -- whole game, all tanks together
local SPOTS_PER_STAGE = 3 -- Small 3, Medium 6, Large 9, Sea Pen 12
local RISE_SPEED = { 2.6, 4 } -- studs per second
local SIZE = { 0.35, 0.8 }
local HIDDEN = CFrame.new(0, -500, 0)

local rng = Random.new()
local container
local tanks = {} -- [plot] = { origin, spots = { {x, z, nextAt} }, stage }
local live = {} -- active bubbles: { part, pos, speed, phase, topY, tank }
local pool = {}

local function newBubble(): BasePart
	local p = table.remove(pool)
	if p then
		return p
	end
	p = Instance.new("Part")
	p.Name = "Bubble"
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	-- solid-ish white-blue with a shine: see-through Glass vanished against the sand and water
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(235, 248, 255)
	p.Reflectance = 0.25
	p.Transparency = 0.25
	p.CFrame = HIDDEN
	p.Parent = container
	return p
end

-- Bubble spots on the sand, inside the trapezoid (same shape math as FishRenderer).
local function makeSpots(plot: Instance)
	local stage = plot:GetAttribute("TankStage") or 1
	local zF = plot:GetAttribute("TankFrontZ") or -5
	local zB = plot:GetAttribute("TankBackZ") or 5
	local hf = plot:GetAttribute("TankHalfFront") or 10
	local hb = plot:GetAttribute("TankHalfBack") or 10
	local seeded = Random.new(#plot.Name * 97 + stage * 13 + string.byte(plot.Name, -1))
	local spots = {}
	for _ = 1, SPOTS_PER_STAGE * stage do
		local z = seeded:NextNumber(zF + 1.5, zB - 1.5)
		local hw = hf + (hb - hf) * (z - zF) / (zB - zF) - 1.5
		table.insert(spots, { x = seeded:NextNumber(-hw, hw), z = z, nextAt = 0 })
	end
	return spots
end

local function refresh(tank)
	local plot = tank.plot
	tank.spots = makeSpots(plot)
	tank.bottom = plot:GetAttribute("WaterBottom") or 4
	tank.top = plot:GetAttribute("WaterTop") or 15
end

local function addTank(plot: Instance)
	task.spawn(function()
		local origin = plot:WaitForChild("TankOrigin", 30)
		if not origin then
			return
		end
		local tank = { plot = plot, origin = origin }
		refresh(tank)
		plot.AttributeChanged:Connect(function(name)
			if name == "TankStage" or name == "WaterTop" then
				refresh(tank)
			end
		end)
		tanks[plot] = tank
	end)
end

local parts, cframes = {}, {}

local function step(dt: number)
	dt = math.min(dt, 0.1)
	local t = os.clock()
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero

	-- spawn new bubbles at nearby tanks
	for _, tank in tanks do
		local originCF = tank.origin.CFrame
		if (originCF.Position - camPos).Magnitude > NEAR then
			continue
		end
		for _, spot in tank.spots do
			if t >= spot.nextAt and #live < MAX_BUBBLES then
				-- little bursts: usually 1, sometimes a quick string of 2-3
				spot.nextAt = t + (if rng:NextNumber() < 0.25 then rng:NextNumber(0.12, 0.25) else rng:NextNumber(0.6, 1.6))
				local size = rng:NextNumber(SIZE[1], SIZE[2])
				local part = newBubble()
				part.Size = Vector3.new(size, size, size)
				table.insert(live, {
					part = part,
					pos = originCF * Vector3.new(spot.x + rng:NextNumber(-0.3, 0.3), tank.bottom + 0.3, spot.z + rng:NextNumber(-0.3, 0.3)),
					speed = rng:NextNumber(RISE_SPEED[1], RISE_SPEED[2]) * (0.7 + size * 0.6),
					phase = rng:NextNumber(0, math.pi * 2),
					topY = (originCF * Vector3.new(0, tank.top - 0.2, 0)).Y,
				})
			end
		end
	end

	-- move bubbles up with a little wobble; pop (recycle) at the surface
	table.clear(parts)
	table.clear(cframes)
	local i = 1
	while i <= #live do
		local b = live[i]
		b.pos += Vector3.new(0, b.speed * dt, 0)
		if b.pos.Y >= b.topY then
			table.insert(parts, b.part)
			table.insert(cframes, HIDDEN)
			table.insert(pool, b.part)
			live[i] = live[#live]
			live[#live] = nil
		else
			local wobble = Vector3.new(math.sin(t * 6 + b.phase) * 0.12, 0, math.cos(t * 5 + b.phase) * 0.12)
			table.insert(parts, b.part)
			table.insert(cframes, CFrame.new(b.pos + wobble))
			i += 1
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Bubbles.start()
	container = Instance.new("Folder")
	container.Name = "LocalBubbles"
	container.Parent = workspace
	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		local plots = workspace:WaitForChild("FishWorld"):WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			addTank(plot)
		end
		plots.ChildAdded:Connect(addTank)
		task.wait(3)
		local n = 0
		for _ in tanks do
			n += 1
		end
		print(("[Bubbles] running in %d tanks, %d bubbles now"):format(n, #live))
	end)
end

return Bubbles
