-- Draws the fishing boat on this client and moves it smoothly every frame from the server's
-- State / PhaseStart attributes (on FishWorld.BoatDock). Boat front = local -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BoatPath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoatPath"))

local BoatRenderer = {}

local HIDDEN = CFrame.new(0, -500, 0)

local function build(parent)
	local pieces = {} -- { part, offset }
	local function add(name, size, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = HIDDEN
		p.Parent = parent
		table.insert(pieces, { part = p, offset = offset })
		return p
	end

	local hullColor = Color3.fromRGB(35, 70, 120)
	local deck = Color3.fromRGB(150, 110, 70)
	local white = Color3.fromRGB(240, 240, 235)
	-- hull: body + narrowing bow + red waterline stripe
	add("Hull", Vector3.new(10, 4, 22), CFrame.new(0, 0, 2), hullColor)
	add("Bow", Vector3.new(7, 4, 5), CFrame.new(0, 0.2, -10.5), hullColor)
	add("BowTip", Vector3.new(4, 3.6, 3), CFrame.new(0, 0.4, -14), hullColor)
	add("Stripe", Vector3.new(10.1, 0.5, 22.1), CFrame.new(0, -1.2, 2), Color3.fromRGB(200, 50, 40))
	add("Deck", Vector3.new(9.4, 0.3, 26), CFrame.new(0, 2.1, 0), deck, Enum.Material.WoodPlanks)
	-- cabin at the back
	add("Cabin", Vector3.new(7, 5, 7), CFrame.new(0, 4.7, 7), white)
	add("Window", Vector3.new(5, 1.5, 0.2), CFrame.new(0, 5.5, 3.45), Color3.fromRGB(120, 190, 230), Enum.Material.Glass)
	add("Roof", Vector3.new(8, 0.6, 8), CFrame.new(0, 7.5, 7), Color3.fromRGB(200, 50, 40))
	add("Chimney", Vector3.new(1, 2, 1), CFrame.new(2, 8.8, 9), Color3.fromRGB(60, 60, 60))
	-- mast, boom, net, flag
	add("Mast", Vector3.new(0.6, 14, 0.6), CFrame.new(0, 9, -3), deck, Enum.Material.Wood)
	add("Boom", Vector3.new(0.4, 0.4, 10), CFrame.new(0, 7, -7) * CFrame.Angles(math.rad(20), 0, 0), deck, Enum.Material.Wood)
	add("Net", Vector3.new(3, 3, 0.2), CFrame.new(0, 4.6, -11.5), Color3.fromRGB(90, 110, 90), Enum.Material.Fabric)
	add("Flag", Vector3.new(0.1, 1.5, 2.5), CFrame.new(0, 15.2, -1.8), Color3.fromRGB(255, 200, 40), Enum.Material.Fabric)
	-- cargo
	add("Crate", Vector3.new(2.5, 2, 2.5), CFrame.new(-2.5, 3.2, -4), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	add("Barrel", Vector3.new(2.2, 2, 2), CFrame.new(2.6, 3.2, -6) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 70, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
	add("Buoy", Vector3.new(1.4, 1.4, 1.4), CFrame.new(5.2, 1.5, 0), Color3.fromRGB(255, 120, 40), nil, Enum.PartType.Ball)
	local lamp = add("Lamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 8.4, 3.2), Color3.fromRGB(255, 220, 150), Enum.Material.Neon, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Color = lamp.Color
	light.Parent = lamp
	return pieces
end

-- One boat per BoatDock part. Every pier is the main pier turned by PierAngle around the island
-- centre, so the shared path (built for the main pier) is turned the same way.
local function drive(dock: BasePart, folder: Folder)
	local pieces = build(folder)
	local rot = CFrame.Angles(0, math.rad(dock:GetAttribute("PierAngle") or 0), 0)

	local parts, cframes = {}, {}
	for i, piece in pieces do
		parts[i] = piece.part
	end
	local visible = false

	RunService.RenderStepped:Connect(function()
		local cf = BoatPath.cframeAt(dock:GetAttribute("State") or "away", dock:GetAttribute("PhaseStart") or 0, workspace:GetServerTimeNow())
		if cf then
			cf = rot * cf
		end
		if not cf then
			if visible then
				visible = false
				for i in pieces do
					cframes[i] = HIDDEN
				end
				workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end
			return
		end
		visible = true
		for i, piece in pieces do
			cframes[i] = cf * piece.offset
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

function BoatRenderer.start()
	local world = workspace:WaitForChild("FishWorld")
	world:WaitForChild("BoatDock") -- the main dock; the others are created right after it
	local folder = Instance.new("Folder")
	folder.Name = "LocalBoat"
	folder.Parent = workspace
	local started = {}
	local function try(child: Instance)
		if child:IsA("BasePart") and string.sub(child.Name, 1, 8) == "BoatDock" and not started[child] then
			started[child] = true
			drive(child, folder)
		end
	end
	for _, child in world:GetChildren() do
		try(child)
	end
	world.ChildAdded:Connect(try)
end

return BoatRenderer
