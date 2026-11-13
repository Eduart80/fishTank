-- Reef Ferry: World 2 teaser at the main pier (left side of the platform; the fishing boat uses the right).
-- Press E -> you sit on the ferry -> after a short boarding countdown it sails out to sea with
-- everyone aboard -> the screen fades to black with a "Coral Reef - coming soon" card (what you
-- need to unlock it) -> while it is black you are put back on the pier and the ferry is back at the dock.
-- When World 2 exists, the black-screen moment becomes TeleportService:TeleportAsync to the Reef place.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local FerryService = {}

local DOCK_POS = Vector3.new(-19.5, -1, 174) -- hull centre; main pier platform spans x -13..13, z ~161..187
local DECK_TOP = 2.6 -- pier deck top (FLOOR_Y 2.1 + 0.5)
local SAIL_DISTANCE = 220
local SAIL_SECONDS = 14
local FADE_AT = 10.5 -- clients start fading to black here (1 s fade)
local BOARD_SECONDS = 6
local RETURN_SPOT = Vector3.new(-6, DECK_TOP + 3, 176) -- on the pier platform

-- front of the ferry (local -Z) points out to sea (+Z)
local dockCF = CFrame.lookAt(DOCK_POS, DOCK_POS + Vector3.new(0, 0, 1))

local model: Model
local seats: { Seat } = {}
local state = "docked" -- docked | boarding | sailing

local function build(parent: Instance)
	model = Instance.new("Model")
	model.Name = "ReefFerry"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, collide: boolean?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = dockCF * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = collide == true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local hull = Color3.fromRGB(240, 240, 235)
	local stripe = Color3.fromRGB(0, 170, 170) -- reef turquoise
	local wood = Color3.fromRGB(160, 120, 80)
	add("Hull", Vector3.new(10, 4, 22), CFrame.new(0, 0, 2), hull)
	add("Bow", Vector3.new(7, 4, 5), CFrame.new(0, 0.2, -10.5), hull)
	add("BowTip", Vector3.new(4, 3.6, 3), CFrame.new(0, 0.4, -14), hull)
	add("Stripe", Vector3.new(10.2, 0.6, 22.2), CFrame.new(0, 0.6, 2), stripe)
	add("BowStripe", Vector3.new(7.2, 0.6, 5.2), CFrame.new(0, 0.8, -10.5), stripe)
	add("Deck", Vector3.new(9, 0.4, 25), CFrame.new(0, 2.2, -0.5), wood, Enum.Material.WoodPlanks, true)
	-- cabin at the back with a turquoise roof
	add("Cabin", Vector3.new(8, 4, 6), CFrame.new(0, 4.4, 9), hull)
	add("CabinRoof", Vector3.new(9, 0.4, 7), CFrame.new(0, 6.6, 9), stripe)
	for _, x in { -2, 2 } do
		add("Window", Vector3.new(1.6, 1.2, 0.1), CFrame.new(x, 4.8, 5.95), Color3.fromRGB(120, 200, 230), Enum.Material.Glass)
	end
	-- side rails
	for _, x in { -4.6, 4.6 } do
		add("Rail", Vector3.new(0.3, 0.3, 18), CFrame.new(x, 3.6, -2), wood)
	end
	-- flag on the roof
	add("FlagPole", Vector3.new(0.25, 4, 0.25), CFrame.new(0, 8.6, 11), Color3.fromRGB(80, 60, 40))
	add("Flag", Vector3.new(0.1, 1.4, 2.2), CFrame.new(0, 9.8, 12.1), Color3.fromRGB(255, 120, 90), Enum.Material.Fabric)

	-- name board on the cabin front
	local board = add("NameBoard", Vector3.new(7, 1.2, 0.2), CFrame.new(0, 6, 5.85), Color3.fromRGB(14, 28, 44))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 240, 230)
	label.Text = "REEF FERRY"
	label.Parent = gui

	-- 6 seats facing the bow
	for _, z in { -7, -3, 1 } do
		for _, x in { -2.2, 2.2 } do
			local seat = Instance.new("Seat")
			seat.Name = "FerrySeat"
			seat.Size = Vector3.new(2, 0.6, 2)
			seat.CFrame = dockCF * CFrame.new(x, 2.7, z)
			seat.Color = stripe
			seat.Material = Enum.Material.Fabric
			seat.Anchored = true
			seat.Parent = model
			table.insert(seats, seat)
		end
	end

	model.PrimaryPart = model:FindFirstChild("Hull") :: BasePart
	model.WorldPivot = dockCF
	model.Parent = parent
end

-- "Coming soon" sign on the pier platform, facing people walking up the pier
local function buildSign(parent: Instance)
	local sign = Instance.new("Model")
	sign.Name = "ReefSign"
	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = sign
		return p
	end
	local x, z = -8, 166
	for _, dx in { -3.2, 3.2 } do
		add("Post", Vector3.new(0.6, 7, 0.6), CFrame.new(x + dx, DECK_TOP + 3.5, z), Color3.fromRGB(80, 56, 36), Enum.Material.Wood)
	end
	-- front face (-Z) looks back toward the plaza
	local board = add("Board", Vector3.new(7.4, 4.2, 0.4), CFrame.lookAt(Vector3.new(x, DECK_TOP + 5, z), Vector3.new(x, DECK_TOP + 5, z - 10)), Color3.fromRGB(0, 110, 120))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	local function line(text: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.05, y)
		l.Size = UDim2.fromScale(0.9, h)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = gui
	end
	line("🔒 CORAL REEF", 0.06, 0.32, Color3.fromRGB(255, 255, 255))
	line("COMING SOON", 0.4, 0.22, Color3.fromRGB(255, 210, 110))
	line("Sell a full-size Koi to unlock", 0.66, 0.18, Color3.fromRGB(190, 245, 240))
	line("Take a preview ride on the ferry!", 0.84, 0.13, Color3.fromRGB(190, 245, 240))
	-- same text on the back, so it reads from the sea side too (SurfaceGui text is not mirrored)
	local backGui = gui:Clone()
	backGui.Face = Enum.NormalId.Back
	backGui.Parent = board
	sign.Parent = parent
end

local function riders(): { Player }
	local list = {}
	for _, seat in seats do
		local hum = seat.Occupant
		local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if player then
			table.insert(list, player)
		end
	end
	return list
end

-- What the card shows: the unlock checklist for this player
local function card(data): { string }
	local u = Config.REEF_UNLOCK
	local koi = Config.ById.koi
	local function mark(done: boolean): string
		return if done then "✓" else "○"
	end
	return {
		("%s Own the %s (%d slots)"):format(mark(data ~= nil and data.slots >= u.slots), Config.TANK_STAGES[#Config.TANK_STAGES].name, u.slots),
		("%s Unlock the Koi and sell a full-size one"):format(mark(data ~= nil and koi ~= nil and data.stats.earned >= (koi.unlockEarned or 0))),
		("%s %s coins for the ferry ticket"):format(mark(data ~= nil and data.coins >= u.ticket), tostring(u.ticket)),
	}
end

local function sail(deps)
	local aboard = riders()
	if #aboard == 0 then
		state = "docked"
		return
	end
	state = "sailing"
	local start = os.clock()
	local faded = false
	while true do
		local t = os.clock() - start
		if t >= SAIL_SECONDS then
			break
		end
		local a = t / SAIL_SECONDS
		local pos = DOCK_POS + Vector3.new(0, math.sin(t * 1.3) * 0.25, SAIL_DISTANCE * a * a) -- speed up away from the pier
		model:PivotTo(CFrame.new(pos) * dockCF.Rotation * CFrame.Angles(0, 0, math.sin(t * 0.9) * 0.04))
		if not faded and t >= FADE_AT then
			faded = true
			for _, player in riders() do
				deps.remote:FireClient(player, "fade", card(deps.getData(player)))
			end
		end
		RunService.Heartbeat:Wait()
	end
	-- screens are black now: everyone back on the pier, ferry back at the dock
	for i, player in riders() do
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Sit = false
		end
		for _, seat in seats do
			local weld = seat:FindFirstChild("SeatWeld")
			if weld and seat.Occupant == hum then
				weld:Destroy()
			end
		end
		if character then
			character:PivotTo(CFrame.new(RETURN_SPOT + Vector3.new((i - 1) % 3 * 2.5, 0, (i - 1) // 3 * 2.5)) * CFrame.Angles(0, math.pi, 0))
		end
	end
	model:PivotTo(dockCF)
	state = "docked"
end

-- deps = { remote: RemoteEvent, getData: (Player) -> data?, notify: (Player, string) -> () }
function FerryService.start(parent: Instance, deps)
	build(parent)
	buildSign(parent)

	-- the prompt sits on the pier edge next to the ferry (not on the moving boat)
	local spot = Instance.new("Part")
	spot.Name = "FerryPromptSpot"
	spot.Size = Vector3.new(1, 1, 1)
	spot.Transparency = 1
	spot.CanCollide = false
	spot.Anchored = true
	spot.CFrame = CFrame.new(-11.5, DECK_TOP + 2, 174)
	spot.Parent = parent -- NOT inside the ferry model, or it would sail away with it
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Board (preview trip)"
	prompt.ObjectText = "Reef Ferry"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot

	prompt.Triggered:Connect(function(player)
		if state == "sailing" then
			deps.notify(player, "The ferry is out at sea. It's back in a few seconds!")
			return
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart then
			return
		end
		local free = nil
		for _, seat in seats do
			if not seat.Occupant then
				free = seat
				break
			end
		end
		if not free then
			deps.notify(player, "The ferry is full. Wait for the next trip!")
			return
		end
		free:Sit(hum)
		if state == "docked" then
			state = "boarding"
			task.delay(BOARD_SECONDS, sail, deps)
		end
		deps.notify(player, "All aboard! The Reef Ferry leaves in a few seconds...")
	end)
end

return FerryService
