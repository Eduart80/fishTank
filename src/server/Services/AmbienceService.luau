-- Look & feel of the world: a warm, sunny harbor afternoon. Visual only.
-- Lighting set on the server replicates to every player. Tweak the numbers here.
-- (Lighting.Technology can't be set from scripts: in Studio, Lighting -> Technology -> Future
-- looks best for glass/water; ShadowMap is cheaper on phones.)

local Lighting = game:GetService("Lighting")

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
		SunAngularSize = 14,
		MoonAngularSize = 9,
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
end

return AmbienceService
