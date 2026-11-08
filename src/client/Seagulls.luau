-- Ambient seagulls: built and animated only on this client (like the fish), so they cost the
-- server nothing. Each gull circles over the island/pier, flaps, glides, banks into turns and
-- now and then squawks (3D sound, louder when you are close).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Seagulls = {}

local GULL_COUNT = 7
local WHITE = Color3.fromRGB(245, 245, 240)
local GREY = Color3.fromRGB(170, 175, 185)
local TIP = Color3.fromRGB(40, 40, 45)
local BEAK = Color3.fromRGB(240, 190, 40)
local WING_LEN = 4

local function newPart(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function ellipsoid(name, size, color, parent)
	local p = newPart(name, size, color, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function createGull(folder, rng)
	local model = Instance.new("Model")
	model.Name = "Seagull"
	local gull = {
		body = ellipsoid("Body", Vector3.new(1.3, 1.2, 3.2), WHITE, model),
		head = ellipsoid("Head", Vector3.new(0.9, 0.9, 1.1), WHITE, model),
		beak = newPart("Beak", Vector3.new(0.25, 0.25, 0.8), BEAK, model),
		tail = newPart("Tail", Vector3.new(1, 0.15, 1.2), GREY, model),
		wingL = newPart("WingL", Vector3.new(WING_LEN, 0.15, 1.5), GREY, model),
		wingR = newPart("WingR", Vector3.new(WING_LEN, 0.15, 1.5), GREY, model),
		tipL = newPart("TipL", Vector3.new(1.2, 0.16, 1.2), TIP, model),
		tipR = newPart("TipR", Vector3.new(1.2, 0.16, 1.2), TIP, model),
		-- flight path
		center = Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-40, 160)), -- over island + pier
		radius = rng:NextNumber(30, 80),
		height = rng:NextNumber(35, 60),
		speed = rng:NextNumber(0.12, 0.22) * (if rng:NextNumber() < 0.5 then -1 else 1), -- rad/s, sign = direction
		angle = rng:NextNumber(0, math.pi * 2),
		phase = rng:NextNumber(0, 10),
		nextSquawk = os.clock() + rng:NextNumber(3, 20),
	}
	gull.body.CastShadow = true -- a shadow passing over the plaza looks nice

	if Config.SEAGULL_SOUND_ID ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = Config.SEAGULL_SOUND_ID
		sound.Volume = 0.6
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 20
		sound.RollOffMaxDistance = 260
		sound.Parent = gull.body
		gull.sound = sound
	end

	model.Parent = folder
	return gull
end

function Seagulls.start()
	local folder = Instance.new("Folder")
	folder.Name = "LocalSeagulls"
	folder.Parent = workspace

	local rng = Random.new()
	local gulls = {}
	for _ = 1, GULL_COUNT do
		table.insert(gulls, createGull(folder, rng))
	end

	local parts, cframes = {}, {}
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		table.clear(parts)
		table.clear(cframes)

		for _, g in gulls do
			g.angle += g.speed * dt
			local a = g.angle
			local pos = g.center + Vector3.new(math.cos(a) * g.radius, g.height + math.sin(t * 0.3 + g.phase) * 4, math.sin(a) * g.radius)
			local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * math.sign(g.speed)
			local bank = -math.sign(g.speed) * 0.35
			local body = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, bank)

			-- flap for a while, then glide with wings slightly raised
			local flapping = math.sin(t * 0.5 + g.phase) > -0.2
			local flap = if flapping then math.sin(t * 9 + g.phase) * 0.55 else 0.12

			local wingL = body * CFrame.new(-0.5, 0.25, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(-WING_LEN / 2, 0, 0)
			local wingR = body * CFrame.new(0.5, 0.25, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(WING_LEN / 2, 0, 0)

			table.insert(parts, g.body)
			table.insert(cframes, body)
			table.insert(parts, g.head)
			table.insert(cframes, body * CFrame.new(0, 0.35, -1.7))
			table.insert(parts, g.beak)
			table.insert(cframes, body * CFrame.new(0, 0.25, -2.5))
			table.insert(parts, g.tail)
			table.insert(cframes, body * CFrame.new(0, 0.1, 1.9))
			table.insert(parts, g.wingL)
			table.insert(cframes, wingL)
			table.insert(parts, g.wingR)
			table.insert(cframes, wingR)
			table.insert(parts, g.tipL)
			table.insert(cframes, wingL * CFrame.new(-WING_LEN / 2 - 0.5, 0, 0.1))
			table.insert(parts, g.tipR)
			table.insert(cframes, wingR * CFrame.new(WING_LEN / 2 + 0.5, 0, 0.1))

			if g.sound and t >= g.nextSquawk then
				g.nextSquawk = t + rng:NextNumber(8, 25)
				g.sound.PlaybackSpeed = rng:NextNumber(0.9, 1.15) -- each squawk sounds a bit different
				g.sound:Play()
			end
		end

		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return Seagulls
