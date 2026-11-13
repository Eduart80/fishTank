-- Reef Ferry preview: when the ferry is far out at sea the server sends "fade" + the unlock
-- checklist. Screen fades to black, shows the Coral Reef card, then fades back in (by then the
-- server has put the player back on the pier). Later this black moment hides the real teleport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FerryCard = {}

local FADE = 1
local HOLD = 5

function FerryCard.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "FerryCard"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local black = Instance.new("Frame")
	black.BackgroundColor3 = Color3.fromRGB(4, 22, 32)
	black.BackgroundTransparency = 1
	black.Size = UDim2.fromScale(1, 1)
	black.Parent = gui

	local labels = {}
	local function label(y: number, h: number, size: number, color: Color3, bold: boolean)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, y, 0)
		l.Size = UDim2.new(0.9, 0, h, 0)
		l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		l.TextScaled = true
		l.TextColor3 = color
		l.TextTransparency = 1
		l.Text = ""
		l.Parent = black
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = size
		cap.Parent = l
		table.insert(labels, l)
		return l
	end
	local title = label(0.18, 0.14, 64, Color3.fromRGB(120, 240, 230), true)
	local sub = label(0.33, 0.08, 34, Color3.fromRGB(255, 210, 110), true)
	local lines = {
		label(0.5, 0.07, 26, Color3.fromRGB(230, 240, 245), false),
		label(0.58, 0.07, 26, Color3.fromRGB(230, 240, 245), false),
		label(0.66, 0.07, 26, Color3.fromRGB(230, 240, 245), false),
	}
	local foot = label(0.8, 0.06, 20, Color3.fromRGB(150, 190, 200), false)
	title.Text = "CORAL REEF"
	sub.Text = "Coming soon!"
	foot.Text = "Taking you back to the Harbor..."

	local playing = false
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ferry").OnClientEvent:Connect(function(kind, checklist)
		if kind ~= "fade" or playing then
			return
		end
		playing = true
		for i, l in lines do
			l.Text = if type(checklist) == "table" and checklist[i] then tostring(checklist[i]) else ""
		end
		gui.Enabled = true
		local info = TweenInfo.new(FADE)
		TweenService:Create(black, info, { BackgroundTransparency = 0 }):Play()
		for _, l in labels do
			TweenService:Create(l, info, { TextTransparency = 0 }):Play()
		end
		task.wait(FADE + HOLD)
		TweenService:Create(black, info, { BackgroundTransparency = 1 }):Play()
		for _, l in labels do
			TweenService:Create(l, info, { TextTransparency = 1 }):Play()
		end
		task.wait(FADE)
		gui.Enabled = false
		playing = false
	end)
end

return FerryCard
