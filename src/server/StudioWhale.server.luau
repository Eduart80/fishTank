-- STUDIO ONLY scale test: drops a whale into YOUR tank so you can see how big it really is.
-- Visual only: not a real fish, not saved, not sold, no market effect. Never runs on live servers.
--
-- While playing, Server side: Explorer -> Workspace -> Properties -> Attributes -> "TestWhale"
--   90 = full-grown blue whale (~25 m)    50 = humpback (~14 m)    28 = orca (~8 m)
--   0  = remove the whale
-- (Roblox scale: 1 stud ~ 0.28 m, a player is ~5 studs tall.)
-- Or the command bar (Server side):  workspace:SetAttribute("TestWhale", 90)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

if not RunService:IsStudio() then
	return
end

local whale = nil

local function ellipsoid(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = model
	return p
end

local function block(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = model
	return p
end

-- Simple blocky-round whale, length L studs, built around `center` facing its -Z (LookVector).
local function buildWhale(L: number, center: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "TestWhale"
	local top = Color3.fromRGB(70, 95, 125)
	local belly = Color3.fromRGB(190, 200, 210)
	local W, H = L * 0.17, L * 0.15
	-- body (front half is fatter), belly, tail stock
	ellipsoid(m, "Body", Vector3.new(W, H, L * 0.62), center * CFrame.new(0, 0, -L * 0.12), top)
	ellipsoid(m, "Belly", Vector3.new(W * 0.85, H * 0.7, L * 0.5), center * CFrame.new(0, -H * 0.18, -L * 0.14), belly)
	ellipsoid(m, "TailStock", Vector3.new(W * 0.55, H * 0.5, L * 0.42), center * CFrame.new(0, H * 0.05, L * 0.22), top)
	-- head + mouth line
	ellipsoid(m, "Head", Vector3.new(W * 0.9, H * 0.75, L * 0.25), center * CFrame.new(0, -H * 0.05, -L * 0.38), top)
	block(m, "Mouth", Vector3.new(W * 0.92, L * 0.004, L * 0.2), center * CFrame.new(0, -H * 0.2, -L * 0.36), Color3.fromRGB(40, 50, 65))
	-- eyes
	for _, side in { 1, -1 } do
		ellipsoid(m, "Eye", Vector3.new(L * 0.012, L * 0.012, L * 0.012), center * CFrame.new(side * W * 0.42, -H * 0.12, -L * 0.3), Color3.fromRGB(15, 15, 20))
		-- pectoral fins, angled down and back
		block(m, "Fin", Vector3.new(L * 0.16, L * 0.01, L * 0.06), center * CFrame.new(side * W * 0.6, -H * 0.3, -L * 0.18) * CFrame.Angles(0, side * 0.5, side * -0.35), top)
	end
	-- dorsal fin (small) and tail flukes (wide, flat)
	block(m, "Dorsal", Vector3.new(L * 0.008, L * 0.035, L * 0.05), center * CFrame.new(0, H * 0.42, L * 0.12) * CFrame.Angles(-0.4, 0, 0), top)
	for _, side in { 1, -1 } do
		block(m, "Fluke", Vector3.new(L * 0.15, L * 0.008, L * 0.07), center * CFrame.new(side * L * 0.07, H * 0.05, L * 0.45) * CFrame.Angles(0, side * -0.35, 0), top)
	end
	-- length label so you can read the size in the world
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(260, 50)
	sign.StudsOffset = Vector3.new(0, H * 0.8, 0)
	sign.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = ("TEST WHALE · %d studs (~%d m)"):format(L, math.floor(L * 0.28 + 0.5))
	label.Parent = sign
	sign.Parent = m.Body
	return m
end

local function myPlot()
	local player = Players:GetPlayers()[1]
	local plots = workspace:FindFirstChild("FishWorld") and workspace.FishWorld:FindFirstChild("Plots")
	if not player or not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot
		end
	end
	return nil
end

local function place(L: number)
	if whale then
		whale:Destroy()
		whale = nil
	end
	if L <= 0 then
		print("[TestWhale] removed")
		return
	end
	local plot = myPlot()
	local origin = plot and plot:FindFirstChild("TankOrigin")
	if not origin then
		return warn("[TestWhale] no tank found for you yet")
	end
	local zF, zB = plot:GetAttribute("TankFrontZ"), plot:GetAttribute("TankBackZ")
	local yLo, yHi = plot:GetAttribute("WaterBottom"), plot:GetAttribute("WaterTop")
	-- centred in the water, lying along the tank's length (head toward the plaza)
	local center = origin.CFrame * CFrame.new(0, (yLo + yHi) / 2, (zF + zB) / 2)
	whale = buildWhale(L, center)
	whale.Parent = workspace

	-- gentle bob so it looks alive
	local base = whale:GetPivot()
	local holder = Instance.new("CFrameValue")
	holder.Value = base
	holder.Changed:Connect(function(cf)
		if whale then
			whale:PivotTo(cf)
		end
	end)
	holder.Parent = whale
	TweenService:Create(holder, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Value = base * CFrame.new(0, L * 0.01, 0) * CFrame.Angles(0, 0, 0.03) }):Play()

	local tankLen = zB - zF
	local tankH = yHi - yLo
	local stage = plot:GetAttribute("TankStage")
	print(("[TestWhale] %d-stud whale in stage %d tank: tank is %d long x %d deep water → whale is %.1fx the tank length, %.1fx the water depth"):format(L, stage, tankLen, tankH, L / tankLen, (L * 0.15) / tankH))
end

workspace:SetAttribute("TestWhale", 0)
workspace:GetAttributeChangedSignal("TestWhale"):Connect(function()
	place(tonumber(workspace:GetAttribute("TestWhale")) or 0)
end)
