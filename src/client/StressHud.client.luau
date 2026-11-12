-- STUDIO ONLY: small counter (FPS / fish / bubbles / parts) shown while Workspace "StressTest" > 0.
-- See server/StudioStress. Never runs on live servers.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "StressHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 4)
label.Size = UDim2.new(0, 560, 0, 26)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.3
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.Code
label.TextSize = 16
label.Text = ""
label.Parent = gui
Instance.new("UICorner", label)

local frames, elapsed = 0, 0
local worst = math.huge
RunService.RenderStepped:Connect(function(dt)
	gui.Enabled = (workspace:GetAttribute("StressTest") or 0) > 0
	if not gui.Enabled then
		worst = math.huge
		return
	end
	frames += 1
	elapsed += dt
	worst = math.min(worst, 1 / math.max(dt, 1e-3))
	if elapsed >= 1 then
		local fps = frames / elapsed
		local fish = workspace:FindFirstChild("LocalFish")
		local bubbles = workspace:FindFirstChild("LocalBubbles")
		local fishParts = fish and #fish:GetChildren() or 0
		local bubbleParts = 0
		if bubbles then
			for _, b in bubbles:GetChildren() do
				if b.Position.Y > -400 then -- pooled bubbles hide far below the map
					bubbleParts += 1
				end
			end
		end
		local off = {}
		for _, n in { "Off_Fish", "Off_Bubbles", "Off_Lights", "Off_Glass", "Off_Water" } do
			if workspace:GetAttribute(n) == true then
				table.insert(off, string.sub(n, 5))
			end
		end
		label.Text = ("FPS %d (worst %d) | fish %d | bubbles %d | OFF: %s"):format(fps, worst, fishParts, bubbleParts, if #off > 0 then table.concat(off, ",") else "none")
		label.TextColor3 = if fps >= 50 then Color3.fromRGB(120, 230, 120) elseif fps >= 30 then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(255, 100, 100)
		frames, elapsed, worst = 0, 0, math.huge
	end
end)

-- Suspect switches (Client side, Studio only): tick one at a time in Workspace -> Attributes and
-- watch the FPS. Whatever makes FPS jump is what we optimise. Local to your screen only.
local SWITCHES = { "Off_Fish", "Off_Bubbles", "Off_Lights", "Off_Glass", "Off_Water" }
for _, name in SWITCHES do
	workspace:SetAttribute(name, false)
end

local function eachPart(test: (BasePart) -> boolean, fn: (BasePart) -> ())
	local world = workspace:FindFirstChild("FishWorld")
	if not world then
		return
	end
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and test(d) then
			fn(d)
		end
	end
end

local function apply(name: string)
	local on = workspace:GetAttribute(name) == true
	if name == "Off_Fish" or name == "Off_Bubbles" then
		local folder = workspace:FindFirstChild(if name == "Off_Fish" then "LocalFish" else "LocalBubbles")
		if folder then
			for _, p in folder:GetDescendants() do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = if on then 1 else 0
				end
			end
		end
	elseif name == "Off_Lights" then
		for _, d in workspace:GetDescendants() do
			if d:IsA("Light") or d:IsA("Fire") or d:IsA("ParticleEmitter") then
				d.Enabled = not on
			end
		end
	elseif name == "Off_Glass" then
		eachPart(function(p)
			return string.sub(p.Name, 1, 5) == "Glass" or p.Name == "Lid"
		end, function(p)
			p.LocalTransparencyModifier = if on then 1 else 0
		end)
	elseif name == "Off_Water" then
		eachPart(function(p)
			return p.Name == "Water"
		end, function(p)
			p.LocalTransparencyModifier = if on then 1 else 0
		end)
	end
	print(("[StressTest] %s = %s"):format(name, tostring(on)))
end

for _, name in SWITCHES do
	workspace:GetAttributeChangedSignal(name):Connect(function()
		apply(name)
	end)
end
