-- Look & feel of the world: a warm, sunny harbor afternoon. Visual only.
-- Lighting set on the server replicates to every player. Tweak the numbers here.
-- (Lighting.Technology can't be set from scripts: in Studio, Lighting -> Technology -> Future
-- looks best for glass/water; ShadowMap is cheaper on phones.)

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local AmbienceService = {}

local function get(parent: Instance, className: string): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local new = Instance.new(className)
	new.Parent = parent
	return new
end

local function set(instance: Instance, props)
	for key, value in props do
		instance[key] = value
	end
end

-- Weather looks: only the values that change between clear and storm (tweened between them).
-- Keys: "Lighting.X", "Atmosphere.X", "Clouds.X", "ColorCorrectionEffect.X", "SunRaysEffect.X", "Terrain.X"
local LOOKS = {
	clear = {
		["Lighting.Brightness"] = 2.6,
		["Lighting.Ambient"] = Color3.fromRGB(110, 115, 130),
		["Lighting.OutdoorAmbient"] = Color3.fromRGB(150, 160, 175),
		["Lighting.ExposureCompensation"] = 0.15,
		["Atmosphere.Density"] = 0.28,
		["Atmosphere.Color"] = Color3.fromRGB(200, 222, 238),
		["Atmosphere.Decay"] = Color3.fromRGB(110, 160, 195),
		["Atmosphere.Glare"] = 0.35,
		["Atmosphere.Haze"] = 1.4,
		["Clouds.Cover"] = 0.55,
		["Clouds.Density"] = 0.55,
		["Clouds.Color"] = Color3.fromRGB(255, 255, 255),
		["ColorCorrectionEffect.Saturation"] = 0.12,
		["ColorCorrectionEffect.TintColor"] = Color3.fromRGB(255, 250, 240),
		["SunRaysEffect.Intensity"] = 0.04,
		["Terrain.WaterWaveSize"] = 0.15,
		["Terrain.WaterWaveSpeed"] = 10,
	},
	storm = {
		["Lighting.Brightness"] = 0.9,
		["Lighting.Ambient"] = Color3.fromRGB(70, 75, 88),
		["Lighting.OutdoorAmbient"] = Color3.fromRGB(95, 102, 115),
		["Lighting.ExposureCompensation"] = -0.1,
		["Atmosphere.Density"] = 0.45,
		["Atmosphere.Color"] = Color3.fromRGB(140, 150, 162),
		["Atmosphere.Decay"] = Color3.fromRGB(70, 80, 95),
		["Atmosphere.Glare"] = 0,
		["Atmosphere.Haze"] = 2.6,
		["Clouds.Cover"] = 0.92,
		["Clouds.Density"] = 0.85,
		["Clouds.Color"] = Color3.fromRGB(105, 110, 122),
		["ColorCorrectionEffect.Saturation"] = -0.15,
		["ColorCorrectionEffect.TintColor"] = Color3.fromRGB(205, 215, 230),
		["SunRaysEffect.Intensity"] = 0,
		["Terrain.WaterWaveSize"] = 0.6,
		["Terrain.WaterWaveSpeed"] = 28,
	},
}

local function target(key: string): Instance?
	local owner = string.split(key, ".")[1]
	if owner == "Lighting" then
		return Lighting
	elseif owner == "Terrain" then
		return workspace.Terrain
	elseif owner == "Clouds" then
		return workspace.Terrain:FindFirstChildOfClass("Clouds")
	end
	return Lighting:FindFirstChildOfClass(owner)
end

local currentWeather = "clear"

-- Smoothly change the whole world look ("clear" | "storm") over `seconds`. Replicates to everyone.
function AmbienceService.setWeather(kind: string, seconds: number?)
	local look = LOOKS[kind]
	if not look or kind == currentWeather then
		return
	end
	currentWeather = kind
	local info = TweenInfo.new(seconds or 10, Enum.EasingStyle.Sine)
	local groups = {} -- [instance] = { prop = value }
	for key, value in look do
		local instance = target(key)
		if instance then
			groups[instance] = groups[instance] or {}
			groups[instance][string.split(key, ".")[2]] = value
		end
	end
	for instance, props in groups do
		local ok = pcall(function()
			TweenService:Create(instance, info, props):Play()
		end)
		if not ok then -- some property cannot tween (e.g. terrain water on old clients): just set it
			pcall(function()
				for prop, value in props do
					(instance :: any)[prop] = value
				end
			end)
		end
	end
	workspace:SetAttribute("Weather", kind) -- clients: rain, lightning, gulls leave
end

function AmbienceService.start()
	-- sun a little past noon, slightly south: soft long-ish shadows, bright sea
	set(Lighting, {
		ClockTime = 14.5,
		GeographicLatitude = 25,
		Brightness = 2.6,
		Ambient = Color3.fromRGB(110, 115, 130),
		OutdoorAmbient = Color3.fromRGB(150, 160, 175),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ExposureCompensation = 0.15,
		GlobalShadows = true,
		ShadowSoftness = 0.35,
	})

	-- sea haze: far water fades to a light blue horizon (plaza stays clear)
	set(get(Lighting, "Atmosphere"), {
		Density = 0.28,
		Offset = 0.2,
		Color = Color3.fromRGB(200, 222, 238),
		Decay = Color3.fromRGB(110, 160, 195),
		Glare = 0.35,
		Haze = 1.4,
	})

	set(get(Lighting, "Sky"), {
		SunAngularSize = 7, -- was 14: a giant white ball at sunset
		MoonAngularSize = 24, -- big full moon (was 9: too small to notice; Moonlit fish need a visible moon)
		MoonTextureId = "rbxasset://sky/moon.jpg",
		StarCount = 3000,
		CelestialBodiesShown = true,
	})

	-- soft glow on bright things (sun on water, glass, pier lamps)
	set(get(Lighting, "BloomEffect"), { Intensity = 0.35, Size = 22, Threshold = 1.6 })
	-- slightly warmer, a touch more colourful
	set(get(Lighting, "ColorCorrectionEffect"), {
		Brightness = 0.02,
		Contrast = 0.06,
		Saturation = 0.12,
		TintColor = Color3.fromRGB(255, 250, 240),
	})
	set(get(Lighting, "SunRaysEffect"), { Intensity = 0.04, Spread = 0.6 })

	-- drifting clouds (must live under Terrain)
	set(get(workspace.Terrain, "Clouds"), {
		Cover = 0.55,
		Density = 0.55,
		Color = Color3.fromRGB(255, 255, 255),
	})
	workspace:SetAttribute("Weather", "clear")
end

return AmbienceService
