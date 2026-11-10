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
label.Size = UDim2.new(0, 420, 0, 26)
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
		label.Text = ("FPS %d (worst %d) | fish parts %d | bubbles %d"):format(fps, worst, fishParts, bubbleParts)
		label.TextColor3 = if fps >= 50 then Color3.fromRGB(120, 230, 120) elseif fps >= 30 then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(255, 100, 100)
		frames, elapsed, worst = 0, 0, math.huge
	end
end)
