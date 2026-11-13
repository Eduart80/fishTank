-- STUDIO ONLY test panel: buttons for every test switch, used from the normal CLIENT view.
-- (Typing attributes in the Server view left the character uncontrollable - this replaces that.)
-- Sends Remotes.DevCmd; the server only creates that remote in Studio, so this does nothing live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevPanel = {}

function DevPanel.start()
	if not RunService:IsStudio() then
		return
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevCmd", 10)
	if not remote then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Text = "🛠 Test"
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.BackgroundColor3 = Color3.fromRGB(120, 60, 160)
	toggle.AnchorPoint = Vector2.new(1, 1)
	toggle.Position = UDim2.new(1, -12, 1, -12)
	toggle.Size = UDim2.fromOffset(80, 30)
	toggle.Parent = gui
	Instance.new("UICorner").Parent = toggle

	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
	panel.BackgroundTransparency = 0.1
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -12, 1, -50)
	panel.Size = UDim2.fromOffset(300, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local order = 0
	local refreshers = {}
	local function row(title: string, buttons)
		order += 1
		local r = Instance.new("Frame")
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, 26)
		r.LayoutOrder = order
		r.Parent = panel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0, 64, 1, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(190, 200, 220)
		label.Text = title
		label.Parent = r
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.new(0, 66, 0, 0)
		holder.Size = UDim2.new(1, -66, 1, 0)
		holder.Parent = r
		local h = Instance.new("UIListLayout")
		h.FillDirection = Enum.FillDirection.Horizontal
		h.Padding = UDim.new(0, 4)
		h.Parent = holder
		for _, b in buttons do
			local btn = Instance.new("TextButton")
			btn.Text = b.text
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 12
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Size = UDim2.new(1 / #buttons, -4, 1, 0)
			btn.Parent = holder
			Instance.new("UICorner").Parent = btn
			btn.Activated:Connect(function()
				remote:FireServer(b.attr, b.value)
			end)
			-- highlight the button that matches the current switch value
			table.insert(refreshers, function()
				local on = b.attr ~= "TestFx" and workspace:GetAttribute(b.attr) == b.value
				btn.BackgroundColor3 = if on then Color3.fromRGB(40, 160, 90) else Color3.fromRGB(55, 65, 90)
			end)
		end
	end

	row("Storm", { { text = "On", attr = "TestStorm", value = true }, { text = "Off", attr = "TestStorm", value = false } })
	row("Mutate", { { text = "Always", attr = "TestMutate", value = true }, { text = "Normal", attr = "TestMutate", value = false } })
	row("Clock", {
		{ text = "Real", attr = "TestClock", value = 0 },
		{ text = "14", attr = "TestClock", value = 14 },
		{ text = "17.5", attr = "TestClock", value = 17.5 },
		{ text = "18.5", attr = "TestClock", value = 18.5 },
		{ text = "22", attr = "TestClock", value = 22 },
		{ text = "6.5", attr = "TestClock", value = 6.5 },
	})
	row("Moon", {
		{ text = "Real", attr = "TestMoon", value = "" },
		{ text = "Full", attr = "TestMoon", value = "full" },
		{ text = "Half", attr = "TestMoon", value = "half_waxing" },
		{ text = "New", attr = "TestMoon", value = "new" },
		{ text = "Blood", attr = "TestMoon", value = "blood" },
	})
	row("Effect", {
		{ text = "⚡", attr = "TestFx", value = "storm" },
		{ text = "🌙", attr = "TestFx", value = "moon" },
		{ text = "✨", attr = "TestFx", value = "rare" },
		{ text = "🎆", attr = "TestFx", value = "fireworks" },
		{ text = "🔊", attr = "TestFx", value = "harborSound" },
	})
	row("Passes", { { text = "All 4", attr = "TestPasses", value = true }, { text = "None", attr = "TestPasses", value = false } })
	row("Top 100", { { text = "Sample", attr = "TestTop", value = true }, { text = "Real", attr = "TestTop", value = false } })
	row("Rich", {
		{ text = "1.5k", attr = "TestRich", value = 1500 },
		{ text = "8k", attr = "TestRich", value = 8000 },
		{ text = "30k", attr = "TestRich", value = 30000 },
		{ text = "100k", attr = "TestRich", value = 100000 },
	})
	row("Tank", {
		{ text = "6", attr = "SetSlots", value = 6 },
		{ text = "10", attr = "SetSlots", value = 10 },
		{ text = "15", attr = "SetSlots", value = 15 },
		{ text = "20", attr = "SetSlots", value = 20 },
	})

	local function refreshAll()
		for _, f in refreshers do
			f()
		end
	end
	workspace.AttributeChanged:Connect(refreshAll)
	refreshAll()
end

return DevPanel
