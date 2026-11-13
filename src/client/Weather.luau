-- Storm effects on THIS client only (the server sets the dark sky / rough sea and the
-- Workspace "Weather" attribute): rain around the camera, lightning flashes, thunder + rain sound.
-- Phones get fewer raindrops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local TankFx = require(script.Parent:WaitForChild("TankFx"))

local Weather = {}

local RAIN_HEIGHT = 45 -- rain cloud box sits this far above the camera
local RAIN_AREA = 90 -- studs around the camera (smaller = denser for the same drop count)
local RAIN_RATE_PC = 900
local RAIN_RATE_PHONE = 350

local function makeSound(id: string, volume: number, looped: boolean): Sound?
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.Parent = SoundService
	return s
end

function Weather.start()
	local camera = workspace.CurrentCamera

	-- rain: one invisible box above the camera that emits fast, thin, stretched drops downward
	local box = Instance.new("Part")
	box.Name = "LocalRain"
	box.Size = Vector3.new(RAIN_AREA, 1, RAIN_AREA)
	box.Transparency = 1
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Parent = workspace

	local rain = Instance.new("ParticleEmitter")
	rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Shape = Enum.ParticleEmitterShape.Box
	rain.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel -- each drop points along its fall = a streak
	rain.Speed = NumberRange.new(80, 100)
	rain.Lifetime = NumberRange.new(0.6, 0.8)
	rain.Acceleration = Vector3.new(4, 0, 2) -- a bit of wind
	rain.Size = NumberSequence.new(0.35)
	rain.Squash = NumberSequence.new(-3) -- MEASURED: +3 drew sideways streaks; -3 stretches along the fall
	rain.Color = ColorSequence.new(Color3.fromRGB(225, 235, 250))
	rain.Transparency = NumberSequence.new(0.15)
	rain.LightEmission = 0.4 -- a little glow so drops show against the dark storm sky
	rain.LightInfluence = 1
	rain.Rate = 0
	rain.Enabled = true
	rain.Parent = box

	-- lightning: a brightness flash on top of the server's dark look (local ColorCorrection)
	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "LightningFlash"
	flash.Brightness = 0
	flash.Parent = camera

	local rainSound = makeSound(Config.RAIN_SOUND_ID, 0, true)
	local thunderSound = makeSound(Config.THUNDER_SOUND_ID, 0.8, false)

	local stormy = false
	local nextStrike = 0

	local function isPhone(): boolean
		return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	end

	local function apply()
		stormy = workspace:GetAttribute("Weather") == "storm"
		local goal = if stormy then (if isPhone() then RAIN_RATE_PHONE else RAIN_RATE_PC) else 0
		-- ease the rain in / out over a few seconds instead of switching it on at once
		TweenService:Create(rain, TweenInfo.new(if stormy then 6 else 10), { Rate = goal }):Play()
		if rainSound then
			if stormy and not rainSound.IsPlaying then
				rainSound:Play()
			end
			TweenService:Create(rainSound, TweenInfo.new(6), { Volume = if stormy then 0.5 else 0 }):Play()
		end
		nextStrike = os.clock() + 6
	end
	workspace:GetAttributeChangedSignal("Weather"):Connect(apply)
	apply()

	local function strike()
		-- a real bolt in the sky: mostly far out toward the horizon (thick, so it shows through the
		-- storm haze), sometimes close to the island for a jump scare
		local camPos = camera.CFrame.Position
		local angle = math.random() * math.pi * 2
		local close = math.random() < 0.3
		local dist = if close then 70 + math.random() * 60 else 180 + math.random() * 170
		local ground = Vector3.new(camPos.X + math.cos(angle) * dist, -1.5, camPos.Z + math.sin(angle) * dist)
		local sky = ground + Vector3.new(math.random(-30, 30), if close then 170 else 240, math.random(-30, 30))
		TankFx.bolt(sky, ground, if close then 1.6 else 3.2, if close then 80 else 140)
		-- double flash, then thunder a moment later (sound is slower than light)
		local info = TweenInfo.new(0.25)
		flash.Brightness = 0.45
		TweenService:Create(flash, info, { Brightness = 0 }):Play()
		task.delay(0.35, function()
			flash.Brightness = 0.3
			TweenService:Create(flash, TweenInfo.new(0.4), { Brightness = 0 }):Play()
		end)
		if thunderSound then
			task.delay(math.random() * 1.2 + 0.4, function()
				thunderSound.PlaybackSpeed = 0.85 + math.random() * 0.3
				thunderSound:Play()
			end)
		end
	end

	RunService.RenderStepped:Connect(function()
		box.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, RAIN_HEIGHT, 0))
		if stormy and os.clock() >= nextStrike then
			nextStrike = os.clock() + 8 + math.random() * 14
			strike()
		end
		if not stormy and rainSound and rainSound.IsPlaying and rainSound.Volume <= 0.01 then
			rainSound:Stop()
		end
	end)
end

return Weather
