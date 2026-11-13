-- Big moments on a tank, seen by everyone (server fires Remotes.Fx with a kind + the tank top):
--   "storm" -> lightning bolt from the sky onto the tank + flash + thunder (fish became Stormborn)
--   "moon"  -> soft moonbeam + sparkles (fish became Moonlit)
--   "rare"  -> golden sparkle burst (Rare Egg arrived)
-- Built locally and removed after a few seconds, so it costs the server nothing.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TankFx = {}

local function neon(size: Vector3, cf: CFrame, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

local function sparkles(at: Vector3, color: Color3, count: number, seconds: number)
	local holder = neon(Vector3.new(1, 1, 1), CFrame.new(at), color, 1)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(8, 18)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, seconds)
end

-- One jagged lightning bolt from `from` to `to` (+ a few thinner side branches), with a light burst
-- where it lands. Flickers on/off/on and fades. Used for tank strikes and the storm's sky bolts.
local BOLT_COLOR = Color3.fromRGB(200, 230, 255)

function TankFx.bolt(from: Vector3, to: Vector3, thickness: number, lightRange: number?)
	local rng = Random.new()
	local parts = {}
	local function chain(a: Vector3, b: Vector3, width: number, steps: number, jitter: number, branches: number)
		local points = { a }
		for i = 1, steps - 1 do
			table.insert(points, a:Lerp(b, i / steps) + Vector3.new(rng:NextNumber(-jitter, jitter), 0, rng:NextNumber(-jitter, jitter)))
		end
		table.insert(points, b)
		for i = 1, #points - 1 do
			local p0, p1 = points[i], points[i + 1]
			table.insert(parts, neon(Vector3.new(width, width, (p1 - p0).Magnitude + width), CFrame.lookAt((p0 + p1) / 2, p1), BOLT_COLOR))
		end
		-- side branches from the upper/middle part of the bolt, going down and out
		for _ = 1, branches do
			local i = rng:NextInteger(2, math.max(2, #points - 3))
			local origin = points[i]
			local len = (b - a).Magnitude * rng:NextNumber(0.15, 0.3)
			local dir = Vector3.new(rng:NextNumber(-1, 1), -rng:NextNumber(0.6, 1.2), rng:NextNumber(-1, 1)).Unit
			chain(origin, origin + dir * len, width * 0.5, 4, jitter * 0.6, 0)
		end
	end
	local length = (to - from).Magnitude
	chain(from, to, thickness, math.clamp(math.floor(length / 18), 6, 16), math.max(3, length / 25), 3)

	local glow = neon(Vector3.new(1, 1, 1), CFrame.new(to), BOLT_COLOR, 1)
	local light = Instance.new("PointLight")
	light.Color = BOLT_COLOR
	light.Range = lightRange or 40
	light.Brightness = 8
	light.Parent = glow

	task.spawn(function()
		task.wait(0.08)
		for _, p in parts do
			p.Transparency = 1
		end
		task.wait(0.06)
		for _, p in parts do
			p.Transparency = 0
		end
		task.wait(0.12)
		local info = TweenInfo.new(0.35)
		for _, p in parts do
			TweenService:Create(p, info, { Transparency = 1 }):Play()
		end
		TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	end)
	for _, p in parts do
		Debris:AddItem(p, 1.5)
	end
	Debris:AddItem(glow, 1.5)
end

local function thunder()
	if Config.THUNDER_SOUND_ID ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = Config.THUNDER_SOUND_ID
		s.Volume = 1
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 10)
	end
end
TankFx.thunder = thunder

-- tank strike: thick bolt from high above, sparks + thunder
local function lightning(top: Vector3)
	local rng = Random.new()
	TankFx.bolt(top + Vector3.new(rng:NextNumber(-25, 25), 160, rng:NextNumber(-25, 25)), top, 1.1, 45)
	sparkles(top, BOLT_COLOR, 40, 3)
	thunder()
end

local function moonbeam(top: Vector3, tint: Color3?)
	local color = tint or Color3.fromRGB(215, 222, 255)
	local height = 60
	-- a soft vertical beam (cylinder lying along Y) that fades in and out
	local beam = neon(Vector3.new(height, 8, 8), CFrame.new(top + Vector3.new(0, height / 2 - 4, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, 1)
	beam.Shape = Enum.PartType.Cylinder
	TweenService:Create(beam, TweenInfo.new(0.8), { Transparency = 0.7 }):Play()
	task.delay(1.6, function()
		TweenService:Create(beam, TweenInfo.new(1.2), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(beam, 3.2)
	sparkles(top, color, 30, 3)
end

function TankFx.start()
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx").OnClientEvent:Connect(function(kind, top)
		if typeof(top) ~= "Vector3" then
			return
		end
		if kind == "storm" then
			lightning(top)
		elseif kind == "moon" then
			moonbeam(top)
		elseif kind == "blood" then
			moonbeam(top, Color3.fromRGB(230, 50, 60))
		elseif kind == "rare" then
			sparkles(top, Color3.fromRGB(255, 205, 70), 60, 3)
		end
	end)
end

return TankFx
