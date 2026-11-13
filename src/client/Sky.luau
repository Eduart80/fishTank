-- Day / night on THIS client: moves Lighting.ClockTime (sun, moon, stars, shadows) from the
-- shared server clock, and adds a local moonlight tint at night. Local only, so it never fights
-- the server's storm look (which tweens Brightness / Ambient / Atmosphere for everyone).
-- Updates twice a second: smooth enough, and cheaper than re-lighting every frame on phones.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayNight = require(Shared:WaitForChild("DayNight"))
local Config = require(Shared:WaitForChild("Config"))
local RunService = game:GetService("RunService")
local IS_STUDIO = RunService:IsStudio()

local Sky = {}

local NIGHT_TINT = Color3.fromRGB(150, 172, 235) -- moonlight blue
local GOLDEN_TINT = Color3.fromRGB(255, 196, 140) -- sunset / sunrise orange
local WHITE = Color3.new(1, 1, 1)

-- One shooting star: a small glowing streak with a trail, far away high in the sky,
-- crossing in about a second. Local only.
local TweenService = game:GetService("TweenService")
local function shootingStar()
	local camera = workspace.CurrentCamera
	local rng = Random.new()
	local angle = rng:NextNumber(0, math.pi * 2)
	local center = camera.CFrame.Position + Vector3.new(math.cos(angle) * 500, rng:NextNumber(220, 320), math.sin(angle) * 500)
	local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, -0.2), rng:NextNumber(-1, 1)).Unit
	local from, to = center - dir * 120, center + dir * 120
	local star = Instance.new("Part")
	star.Name = "ShootingStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.new(2, 2, 2)
	star.Material = Enum.Material.Neon
	star.Color = Color3.fromRGB(235, 240, 255)
	star.Anchored, star.CanCollide, star.CanQuery, star.CanTouch, star.CastShadow = true, false, false, false, false
	star.CFrame = CFrame.new(from)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = star
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = star
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 240, 255))
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = star
	star.Parent = workspace
	local tween = TweenService:Create(star, TweenInfo.new(1.1, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) })
	tween:Play()
	tween.Completed:Connect(function()
		task.delay(0.6, function()
			star:Destroy()
		end)
	end)
end

function Sky.start()
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "NightTint"
	tint.Parent = workspace.CurrentCamera

	local nextShootingStar = os.clock() + 3
	task.spawn(function()
		while true do
			local test = workspace:GetAttribute("TestClock")
			local clock = if type(test) == "number" and test > 0 then test % 24 else DayNight.clockAt(workspace:GetServerTimeNow())
			Lighting.ClockTime = clock
			local d = DayNight.darkness(clock)
			-- readable night: darker and bluer, never black (fish must stay visible)
			-- storm already darkens the world (server look): at night during a storm we LIFT the
			-- image a little instead of stacking a 3rd darkening (storm + night was nearly black)
			local storm = workspace:GetAttribute("Weather") == "storm"
			tint.Brightness = (if storm then 0.06 else -0.13) * d -- clear night -0.13 (user: sand was too bright at -0.06)
			tint.Contrast = (if storm then -0.05 else 0.08) * d
			tint.Saturation = -0.25 * d
			local w = DayNight.warmth(clock)
			tint.TintColor = WHITE:Lerp(GOLDEN_TINT, w * 0.8):Lerp(NIGHT_TINT, d)
			-- clear nights: thin the clouds so the moon + stars show (storms keep their thick
			-- clouds; the server replicates those and we leave them alone)
			-- (the moon itself is set by the SERVER per phase: AmbienceService.setMoon)
			-- New Moon starry night: shooting stars every 10-25 s while it is dark and clear
			local testMoon = workspace:GetAttribute("TestMoon")
			local phase = (IS_STUDIO and type(testMoon) == "string" and DayNight.phaseByKey(testMoon)) or DayNight.moonPhase(workspace:GetServerTimeNow())
			if phase.key == "new" and d >= 0.8 and not storm and os.clock() >= nextShootingStar then
				nextShootingStar = os.clock() + 10 + math.random() * 15
				shootingStar()
			end
			local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
			if clouds and not storm then
				clouds.Cover = 0.55 - 0.3 * d
			end
			task.wait(0.5)
		end
	end)
end

return Sky
