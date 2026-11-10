-- STUDIO ONLY worst-case load test. Never runs on live servers. Player data is never touched.
--
-- While playing, Server side: Explorer -> Workspace -> Properties -> Attributes -> "StressTest"
--   24 = all 8 tanks become Sea Pens with 24 fully grown Koi each (192 fish, ~576 moving parts)
--        + 3 tiki torches (fire + light) and an umbrella on every patio (24 lights)
--   0  = back to normal (your own tank comes back within ~5 seconds)
-- Or the command bar (Server side):  workspace:SetAttribute("StressTest", 24)
--
-- Read the numbers: the small counter top-centre (FPS / fish / bubbles), View -> Performance Stats,
-- Ctrl+F6 = MicroProfiler. Studio's phone emulator does NOT emulate phone speed: for the real
-- answer publish privately and play on a phone (F9 = Developer Console).

local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local WorldService = require(script.Parent:WaitForChild("Services"):WaitForChild("WorldService"))

workspace:WaitForChild("FishWorld", 30)
workspace:SetAttribute("StressTest", 0)

workspace:GetAttributeChangedSignal("StressTest"):Connect(function()
	local n = math.clamp(math.floor(tonumber(workspace:GetAttribute("StressTest")) or 0), 0, 60)
	WorldService.setStress(n)
	local parts, lights = 0, 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	if n > 0 then
		print(("[StressTest] ON: 8 Sea Pens x %d Koi = %d fish | server world: %d parts, %d lights (fish + bubbles are drawn on each client, not counted here)"):format(n, n * 8, parts, lights))
	else
		print(("[StressTest] OFF | server world: %d parts, %d lights"):format(parts, lights))
	end
end)
