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

function Sky.start()
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "NightTint"
	tint.Parent = workspace.CurrentCamera

	local shownPhase = nil
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
			-- moon phase of tonight (8-night cycle). A phase without an uploaded texture (or the new
			-- moon) shows no moon at all, so a non-full night never shows the full moon by mistake.
			local testMoon = workspace:GetAttribute("TestMoon")
			local phase = (IS_STUDIO and type(testMoon) == "string" and DayNight.phaseByKey(testMoon)) or DayNight.moonPhase(workspace:GetServerTimeNow())
			-- only touch the sky when the phase CHANGES (setting the texture every loop made Studio
			-- reload it twice a second -> freezes)
			local sky = Lighting:FindFirstChildOfClass("Sky")
			if sky and phase.key ~= shownPhase then
				shownPhase = phase.key
				if phase.texture ~= "" then
					sky.MoonTextureId = phase.texture
					sky.MoonAngularSize = Config.MOON_SIZE
				else
					sky.MoonAngularSize = 0
				end
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
