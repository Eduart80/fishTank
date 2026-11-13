-- Client UI. Shows what the server sends and asks the server to act. It never decides anything.
-- v1 is UI-only (no 3D tank yet) so we can test whether the market loop is fun.

print("[FishMarket] client build 2026-11-13j blood moon") -- proves Studio runs the synced script

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MarketMath = require(Shared:WaitForChild("MarketMath"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = Remotes:WaitForChild("Action")

local player = Players.LocalPlayer

-- The default player list sits on top of our Feed / Sell / Slot buttons.
-- Hidden for now; a proper "Top Traders" board replaces it later.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- Theme ---------------------------------------------------------------------
-- See-through Market / My Tank windows (0 = solid, 1 = invisible). Window = the big panel,
-- card = each fish row on it. Cards stay darker than the window so the text stays readable.
local GLASS_WINDOW = 0.55
local GLASS_CARD = 0.3

local C = {
	bg = Color3.fromRGB(14, 28, 44),
	panel = Color3.fromRGB(22, 42, 64),
	row = Color3.fromRGB(30, 56, 84),
	text = Color3.fromRGB(235, 242, 250),
	dim = Color3.fromRGB(150, 172, 196),
	up = Color3.fromRGB(80, 210, 120),
	down = Color3.fromRGB(240, 90, 90),
	warn = Color3.fromRGB(255, 190, 70),
	button = Color3.fromRGB(40, 130, 200),
	buttonOff = Color3.fromRGB(70, 82, 96),
	event = Color3.fromRGB(150, 70, 200),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

-- Helpers -------------------------------------------------------------------
local function make(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

local function label(props)
	local maxText = props.MaxText or 20
	props.MaxText = nil -- ours, not an Instance property
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.text
	props.TextScaled = true
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, { make("UITextSizeConstraint", { MaxTextSize = maxText }) })
end

local function button(props)
	props.Font = FONT_BOLD
	props.TextColor3 = C.text
	props.TextScaled = true
	props.AutoButtonColor = true
	props.BackgroundColor3 = props.BackgroundColor3 or C.button
	return make("TextButton", props, { corner(6), make("UITextSizeConstraint", { MaxTextSize = 16 }), make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }) })
end

local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%dh %dm"):format(seconds // 3600, (seconds % 3600) // 60)
	elseif seconds >= 60 then
		return ("%dm %ds"):format(seconds // 60, seconds % 60)
	end
	return ("%ds"):format(seconds)
end

-- Layout --------------------------------------------------------------------
local gui = make("ScreenGui", { Name = "FishMarketUI", ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })

-- Coins: top right, in the same row and pill shape as Roblox's own menu buttons (top left).
-- Separate ScreenGui that ignores the top-bar inset so it can sit up in that row.
local topGui = make("ScreenGui", { Name = "FishMarketTopUI", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
local coinsBox = make("Frame", {
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.3,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 0, 0, 34), -- was 44 (user: shrink vertically)
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = topGui,
}, {
	make("UICorner", { CornerRadius = UDim.new(1, 0) }), -- full pill, like the Roblox menu button
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16) }),
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})
-- coin icon drawn from shapes (emoji coins don't render in Roblox fonts)
make("Frame", { LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(245, 190, 40), Size = UDim2.new(0, 24, 0, 24), Parent = coinsBox }, {
	make("UICorner", { CornerRadius = UDim.new(1, 0) }),
	make("UIStroke", { Color = Color3.fromRGB(190, 130, 20), Thickness = 2 }),
	make("Frame", { BackgroundColor3 = Color3.fromRGB(255, 220, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62) }, {
		make("UICorner", { CornerRadius = UDim.new(1, 0) }),
	}),
})
local coinsLabel = make("TextLabel", {
	LayoutOrder = 2,
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	Text = "0",
	TextSize = 19,
	TextColor3 = C.text,
	Size = UDim2.new(0, 0, 0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = coinsBox,
})

-- Daily streak badge under the coins pill (hidden until the first daily reward)
local streakLabel = make("TextLabel", {
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.3,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 50), -- under the slimmer coins pill
	Size = UDim2.new(0, 0, 0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT_BOLD,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 190, 90),
	Text = "",
	Visible = false,
	Parent = topGui,
}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }) })

-- Weather Radio pass: forecast badge under the streak badge
local forecastLabel = make("TextButton", {
	AutoButtonColor = true,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.3,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 78), -- ends above the windows' X close button
	Size = UDim2.new(0, 0, 0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT_BOLD,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(170, 215, 255),
	Text = "",
	Visible = false,
	Parent = topGui,
}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }) })

-- Food status lives on each tank's front glass (see renderFoodGauges); feed at the tank with F.

-- Market / My Tank: round icon buttons, middle of the left side
-- One column holds all icons, so a single UIScale shrinks buttons AND the gaps between them.
local ICON_GAP = 14
local iconColumn = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.new(0, 68, 0, 5 * 86 + 4 * ICON_GAP), Parent = gui }, {
	make("UIListLayout", { Padding = UDim.new(0, ICON_GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local iconColumnScale = make("UIScale", { Parent = iconColumn })
local iconCount = 0
local function iconButton(icon: string, caption: string, _yOffset: number)
	iconCount += 1
	local holder = make("Frame", { BackgroundTransparency = 1, LayoutOrder = iconCount, Size = UDim2.new(0, 68, 0, 86), Parent = iconColumn })
	local b = make("TextButton", {
		Text = icon,
		Font = FONT_BOLD,
		TextScaled = true,
		TextColor3 = C.text,
		AutoButtonColor = true,
		BackgroundColor3 = C.event,
		Size = UDim2.new(0, 68, 0, 68),
		Parent = holder,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIStroke", { Color = C.text, Thickness = 2, Transparency = 0.4 }), make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }) })
	label({ Font = FONT_BOLD, Text = caption, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, Position = UDim2.new(0, -6, 0, 70), Size = UDim2.new(1, 12, 0, 16), MaxText = 14, Parent = holder })
	return b
end
local marketToggle = iconButton("🛒", "Market", -100)
local tankToggle = iconButton("🐟", "My Tank", 0)
local shopToggle = iconButton("R$", "Shop", 100)
shopToggle.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
-- Invite: Roblox friend-invite prompt. The inviter id goes into LaunchData (server also reads
-- ReferredByPlayerId); a brand-new friend who joins gets a gift, the inviter gets coins.
local topToggle = iconButton("🏆", "Top", 150)
topToggle.BackgroundColor3 = Color3.fromRGB(200, 150, 30)
local inviteToggle = iconButton("👥", "Invite", 200)
inviteToggle.BackgroundColor3 = Color3.fromRGB(230, 140, 40)
inviteToggle.Activated:Connect(function()
	local SocialService = game:GetService("SocialService")
	local okCan, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if not okCan or not canInvite then
		return
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = ("Invite friends: they get %d coins + a free %s egg, you get %d coins!"):format(
		Config.INVITE.newPlayerGift.coins or 0, Config.ById[Config.INVITE.newPlayerGift.egg].name, Config.INVITE.inviterCoins)
	options.LaunchData = tostring(player.UserId)
	pcall(SocialService.PromptGameInvite, SocialService, player, options)
end)


-- x / leftOffset: the market panel starts right of the icon buttons
local function panel(x: number, leftOffset: number, title: string)
	local frame = make("Frame", { BackgroundColor3 = C.panel, Position = UDim2.new(x, leftOffset, 0, 64), Size = UDim2.new(0.47, -leftOffset, 1, -76), Parent = gui }, { corner() })
	-- round X on the top-right corner (sits half outside, so it never covers header buttons)
	local close = make("TextButton", {
		Name = "Close",
		Text = "X", -- plain letter: the ✕ symbol is missing from the font (showed as a box)
		Font = FONT_BOLD,
		TextScaled = true,
		TextColor3 = C.text,
		BackgroundColor3 = C.down,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.new(0, 30, 0, 30),
		ZIndex = 5,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }), make("UIStroke", { Color = C.text, Thickness = 1.5, Transparency = 0.3 }) })
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	local titleLabel = label({ Font = FONT_BOLD, Text = title, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(0.5, 0, 0, 28), MaxText = 22, Parent = frame })
	local list = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 42),
		Size = UDim2.new(1, -16, 1, -50),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	return frame, titleLabel, list
end

local marketFrame, _, marketList = panel(0, 96, "Fish Market")
local tankFrame, tankTitle, tankList = panel(0.51, 0, "Your Tank")
marketFrame.BackgroundTransparency = GLASS_WINDOW
tankFrame.BackgroundTransparency = GLASS_WINDOW
local shopFrame, _, shopList = panel(0, 96, "Robux Shop")
local storeFrame, storeTitle, storeList = panel(0, 96, "Harbor Store")
local topFrame, _, topList = panel(0, 96, "🏆 Top 100 Fish Tycoons")
topFrame.Visible = false
-- store header: title | Store | My items | R$ Shop tabs, then a hint line, then the list
storeTitle.Size = UDim2.new(0.4, -12, 0, 28)
local storeTabAll = button({ Text = "Store", Position = UDim2.new(0.4, 0, 0, 6), Size = UDim2.new(0.2, -4, 0, 28), Parent = storeFrame })
local storeTabMine = button({ Text = "My items", Position = UDim2.new(0.6, 0, 0, 6), Size = UDim2.new(0.2, -4, 0, 28), Parent = storeFrame })
local storeTabRobux = button({ Text = "R$ Shop", BackgroundColor3 = Color3.fromRGB(40, 160, 90), Position = UDim2.new(0.8, 0, 0, 6), Size = UDim2.new(0.2, -8, 0, 28), Parent = storeFrame })
local storeHint = label({ Text = "", TextColor3 = C.warn, Position = UDim2.new(0, 12, 0, 38), Size = UDim2.new(1, -24, 0, 18), MaxText = 14, Parent = storeFrame })
local storeEmpty = label({ Text = "Nothing yet. Buy decor in the Store tab!", TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 12, 0, 80), Size = UDim2.new(1, -24, 0, 24), MaxText = 16, Visible = false, Parent = storeFrame })
storeList.Position = UDim2.new(0, 8, 0, 60)
storeList.Size = UDim2.new(1, -16, 1, -68)
-- the Robux shop links to the decor store too (so it opens without walking to the hut)
local shopToStore = button({ Text = "Decor Store", BackgroundColor3 = C.warn, Position = UDim2.new(0.6, 0, 0, 6), Size = UDim2.new(0.4, -8, 0, 28), Parent = shopFrame })
-- panels are pop-ups now so the 3D world stays visible
marketFrame.Visible = false
tankFrame.Visible = false
shopFrame.Visible = false
storeFrame.Visible = false
local sellAllButton = button({ Text = "Sell all adults", Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.new(0.27, -4, 0, 28), Parent = tankFrame })
local slotButton = button({ Text = "+ Slot", Position = UDim2.new(0.77, 0, 0, 6), Size = UDim2.new(0.23, -8, 0, 28), Parent = tankFrame })
-- one line under the header: what the next slot buys you (button is too narrow for it)
local slotHint = label({ Text = "", TextColor3 = Color3.fromRGB(255, 215, 120), Position = UDim2.new(0, 12, 0, 36), Size = UDim2.new(1, -24, 0, 18), MaxText = 15, Parent = tankFrame })
tankList.Position = UDim2.new(0, 8, 0, 58)
tankList.Size = UDim2.new(1, -16, 1, -66)

local toast = label({
	Font = FONT_BOLD,
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundTransparency = 0.15,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0.6, 0, 0, 36),
	Visible = false,
	Parent = gui,
})
corner(8).Parent = toast

local toastToken = 0
local function showToast(text: string, seconds: number?)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.15
	toast.Visible = true
	task.delay(seconds or 3.5, function()
		if token ~= toastToken then
			return
		end
		local info = TweenInfo.new(0.5)
		TweenService:Create(toast, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

local busy = false
local function act(action: string, arg)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(actionRemote.InvokeServer, actionRemote, action, arg)
	busy = false
	if not ok then
		showToast("Connection problem, try again")
	elseif result and result.msg then
		showToast(result.msg)
	end
end

-- Weather Radio badge: tap to fold / unfold (saved on the server)
forecastLabel.Activated:Connect(function()
	act("toggleRadio")
end)

sellAllButton.Activated:Connect(function()
	act("sellAllAdults")
end)
slotButton.Activated:Connect(function()
	act("buySlot")
end)
-- Small screens (phones): windows go full width and only one is open at a time.
-- Big screens: Market/Shop on the left half, Tank on the right half, both can be open.
local SMALL_SCREEN_WIDTH = 900
local allPanels = { marketFrame, shopFrame, tankFrame, storeFrame, topFrame }

-- Phone = touch screen that is wide (sideways phone ~2:1; tablets are ~4:3) or just short.
-- Pixel width alone fails: high-res phones (Samsung) report PC-sized viewports.
local function isPhone(): boolean
	local camera = workspace.CurrentCamera
	if not camera then return false end
	local v = camera.ViewportSize
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return v.Y < 500 or (touchOnly and v.X / math.max(v.Y, 1) >= 1.7)
end

local function isSmall(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.ViewportSize.X < SMALL_SCREEN_WIDTH or isPhone())
end

local shopMaxHeight = make("UISizeConstraint", { Parent = shopFrame })

local function layoutPanels()
	local small = isSmall()
	local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 800)
	-- phone sideways = short screen: shrink the icon column a lot; small/tablet a bit
	local phone = isPhone()
	-- phone: 42px circles = same size as the Roblox menu button in the top bar
	iconColumnScale.Scale = if phone then 42 / 68 elseif small then 0.75 else 1
	-- phone: pin icons to the top-left under the Roblox menu, clear of the thumbstick (bottom-left)
	if phone then
		iconColumn.AnchorPoint = Vector2.new(0, 0)
		iconColumn.Position = UDim2.new(0, 10, 0, 6) -- gui respects the top-bar inset, so 6 = just under it
	else
		iconColumn.AnchorPoint = Vector2.new(0, 0.5)
		iconColumn.Position = UDim2.new(0, 12, 0.5, 0)
	end
	local left = math.floor(12 + 68 * iconColumnScale.Scale + 10) -- windows start right of the icons
	-- shop is only as tall as its cards, but never taller than the screen (phones): the
	-- size constraint caps the height, the list inside then scrolls
	local shopHeight = 64 + #Config.ROBUX * 90
	shopMaxHeight.MaxSize = Vector2.new(math.huge, shopHeight)
	if small then
		for _, frame in allPanels do
			frame.Position = UDim2.new(0, left, 0, 64)
			frame.Size = UDim2.new(1, -left - 12, 1, -76)
		end
	else
		marketFrame.Position = UDim2.new(0, left, 0, 64)
		marketFrame.Size = UDim2.new(0.47, -left, 1, -76)
		shopFrame.Position = UDim2.new(0, left, 0, 64)
		shopFrame.Size = UDim2.new(0.47, -left, 1, -76)
		storeFrame.Position = UDim2.new(0, left, 0, 64)
		storeFrame.Size = UDim2.new(0.47, -left, 1, -76)
		topFrame.Position = UDim2.new(0, left, 0, 64)
		topFrame.Size = UDim2.new(0.47, -left, 1, -76)
		tankFrame.Position = UDim2.new(0.51, 0, 0, 64)
		tankFrame.Size = UDim2.new(0.47, 0, 1, -76)
	end
end

-- Opens/closes one window. On small screens, or when they share a spot (Market/Shop), others close.
local function setPanel(frame: Frame, visible: boolean)
	if visible then
		for _, other in allPanels do
			if other ~= frame and (isSmall() or (frame ~= tankFrame and other ~= tankFrame)) then
				other.Visible = false
			end
		end
	end
	frame.Visible = visible
end

marketToggle.Activated:Connect(function()
	setPanel(marketFrame, not marketFrame.Visible)
end)
shopToggle.Activated:Connect(function()
	setPanel(shopFrame, not shopFrame.Visible)
end)
tankToggle.Activated:Connect(function()
	setPanel(tankFrame, not tankFrame.Visible)
end)
topToggle.Activated:Connect(function()
	setPanel(topFrame, not topFrame.Visible)
end)

layoutPanels()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutPanels)

-- Phones: play sideways like most Roblox games (portrait squeezes every window)
pcall(function()
	player.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end)

-- Press E at the market counter or at a tank
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "MarketPrompt" then
		setPanel(marketFrame, true)
	elseif prompt.Name == "TankPrompt" then
		local plot = prompt:FindFirstAncestorWhichIsA("Model")
		local ownerId = plot and plot:GetAttribute("OwnerId")
		if ownerId == player.UserId then
			setPanel(tankFrame, true)
		elseif ownerId and ownerId ~= 0 then
			showToast("This is " .. prompt.ObjectText .. "'s tank. Nice fish!")
		else
			showToast("This tank is empty")
		end
	end
end)

-- State from server ---------------------------------------------------------
local tank = nil -- latest State payload
local tankAt = 0 -- os.clock() when it arrived
local market = nil
local marketAt = 0

local function serverNow(): number
	if tank then
		return tank.now + (os.clock() - tankAt)
	elseif market then
		return market.now + (os.clock() - marketAt)
	end
	return os.time()
end

-- Market rows ---------------------------------------------------------------
local BARS = 30
local marketRows = {}

for i, species in Config.Species do
	local row = make("Frame", { BackgroundColor3 = C.row, BackgroundTransparency = GLASS_CARD, Size = UDim2.new(1, -6, 0, 74), LayoutOrder = i, Parent = marketList }, { corner(6) })
	make("Frame", { BackgroundColor3 = species.color, Size = UDim2.new(0, 6, 1, 0), Parent = row }, { corner(3) })
	label({ Font = FONT_BOLD, Text = species.name, Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(0.3, 0, 0, 22), Parent = row })
	local price = label({ Font = FONT_BOLD, Text = "-", Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(0.18, 0, 0, 24), MaxText = 22, Parent = row })
	local change = label({ Text = "", Position = UDim2.new(0.2, 0, 0, 32), Size = UDim2.new(0.14, 0, 0, 20), MaxText = 16, Parent = row })
	-- eggs bought recently that are still growing = future supply of this fish
	local growing = label({ Text = "", TextColor3 = C.dim, Position = UDim2.new(0, 14, 0, 54), Size = UDim2.new(0.34, 0, 0, 16), MaxText = 13, Parent = row })
	local chart = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.36, 0, 0, 6), Size = UDim2.new(0.38, 0, 1, -12), Parent = row })
	local bars = {}
	for b = 1, BARS do
		bars[b] = make("Frame", { BorderSizePixel = 0, BackgroundColor3 = C.dim, Position = UDim2.new((b - 1) / BARS, 0, 1, 0), Size = UDim2.new(1 / BARS, -1, 0, 0), AnchorPoint = Vector2.new(0, 1), Parent = chart })
	end
	local buy = button({ Text = ("Egg %d"):format(species.eggPrice), Position = UDim2.new(0.76, 0, 0, 10), Size = UDim2.new(0.24, -8, 1, -20), Parent = row })
	buy.Activated:Connect(function()
		act("buyEgg", species.id)
	end)
	marketRows[species.id] = { price = price, change = change, bars = bars, buy = buy, growing = growing }
end


local function renderMarket()
	if not market then
		return
	end
	for _, species in Config.Species do
		local row = marketRows[species.id]
		local current = market.prices[species.id]
		local hist = market.history[species.id] or {}
		row.price.Text = "$" .. fmt(current)
		local growingCount = (market.growing and market.growing[species.id]) or 0
		row.growing.Text = if growingCount > 0 then ("%s growing worldwide"):format(fmt(growingCount)) else "none growing"

		-- locked species show what you need to earn
		local earned = if tank and tank.stats then tank.stats.earned else 0
		local need = species.unlockEarned or 0
		if earned < need then
			row.buy.Text = ("Sell %s/%s"):format(fmt(earned), fmt(need))
			row.buy.BackgroundColor3 = C.buttonOff
		else
			local eggPrice = (market.eggPrices and market.eggPrices[species.id]) or species.eggPrice
			local demand = (market.eggDemand and market.eggDemand[species.id]) or 0
			local rising = eggPrice > species.eggPrice or demand >= MarketMath.EGG_DEMAND_MARKER
			row.buy.Text = ("Egg %s%s"):format(fmt(eggPrice), if rising then " ▲" else "")
			row.buy.BackgroundColor3 = C.button
		end

		local first = hist[1] or current
		local pct = (current - first) / first * 100
		row.change.Text = ("%s%.1f%%"):format(if pct >= 0 then "+" else "", pct)
		local color = if pct >= 0 then C.up else C.down
		row.change.TextColor3 = color

		-- last BARS points, scaled min..max
		local startIndex = math.max(1, #hist - BARS + 1)
		local lo, hi = math.huge, -math.huge
		for i = startIndex, #hist do
			lo = math.min(lo, hist[i])
			hi = math.max(hi, hist[i])
		end
		local span = math.max(hi - lo, current * 0.02)
		for b = 1, BARS do
			local value = hist[startIndex + b - 1]
			local bar = row.bars[b]
			if value then
				bar.Visible = true
				bar.Size = UDim2.new(1 / BARS, -1, 0.15 + 0.85 * (value - lo) / span, 0)
				bar.BackgroundColor3 = color
			else
				bar.Visible = false
			end
		end
	end

	-- events are shown only on the plaza market board (with timer), no pop-up banner
end

-- Tank rows -----------------------------------------------------------------
local fishRows = {} -- [uid] = row parts

local function makeFishRow(fish)
	local species = Config.ById[fish.species]
	local color = if species then species.color else C.dim
	local row = make("Frame", { BackgroundColor3 = C.row, BackgroundTransparency = GLASS_CARD, Size = UDim2.new(1, -6, 0, 54), Parent = tankList }, { corner(6) })
	make("Frame", { BackgroundColor3 = color, Size = UDim2.new(0, 6, 1, 0), Parent = row }, { corner(3) })
	local name = label({ Font = FONT_BOLD, Text = if species then species.name else fish.species, Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(0.32, 0, 0, 20), Parent = row })
	local barBack = make("Frame", { BackgroundColor3 = C.bg, Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(0.32, 0, 0, 14), Parent = row }, { corner(4) })
	local barFill = make("Frame", { BackgroundColor3 = color, Size = UDim2.new(0, 0, 1, 0), Parent = barBack }, { corner(4) })
	local info = label({ Text = "", Position = UDim2.new(0.38, 0, 0, 4), Size = UDim2.new(0.36, 0, 0, 22), MaxText = 16, Parent = row })
	local status = label({ Text = "", Position = UDim2.new(0.38, 0, 0, 28), Size = UDim2.new(0.36, 0, 0, 20), MaxText = 15, Parent = row })
	local sell = button({ Text = "Sell", Position = UDim2.new(0.76, 0, 0, 10), Size = UDim2.new(0.24, -8, 1, -20), Parent = row })
	sell.Activated:Connect(function()
		act("sell", { fish.uid })
	end)
	return { frame = row, name = name, barFill = barFill, info = info, status = status, sell = sell }
end

local function renderTank()
	if not tank then
		return
	end
	local now = serverNow()
	coinsLabel.Text = fmt(tank.coins)
	streakLabel.Visible = (tank.streak or 0) > 0
	streakLabel.Text = ("🔥 Day %d streak"):format(tank.streak or 0)
	local forecast = tank.forecast
	forecastLabel.Visible = forecast ~= nil
	if forecast then
		local function when(t)
			if not t then
				return "none soon"
			end
			return if t <= now + 1 then "NOW" else "in " .. fmtTime(t - now)
		end
		-- tap the badge to fold it to just the radio icon (saved per player)
		forecastLabel.Text = if tank.radioHidden then "📻" else ("📻 Storm %s · 🌕 Full moon %s"):format(when(forecast.storm), when(forecast.fullMoon))
	end


	tankTitle.Text = ("%s %d/%d"):format(Config.TANK_STAGES[Config.tankStage(tank.slots)].name, #tank.fish, tank.slots)
		.. (if (tank.incubator or 0) > 0 then (" · 🥚%d waiting"):format(tank.incubator) else "")
	slotButton.Text = if tank.slots >= tank.maxSlots then "Max Slots" else ("+1 Slot: %s"):format(fmt(tank.slotCost))
	local stage = Config.tankStage(tank.slots)
	local nextStage = Config.TANK_STAGES[stage + 1]
	if nextStage then
		local more = nextStage.minSlots - tank.slots
		slotHint.Text = ("%d more slot%s to unlock the %s"):format(more, if more == 1 then "" else "s", nextStage.name)
	elseif tank.slots < tank.maxSlots then
		slotHint.Text = ("Biggest tank! %d more slot%s for fish"):format(tank.maxSlots - tank.slots, if tank.maxSlots - tank.slots == 1 then "" else "s")
	else
		slotHint.Text = "Biggest tank, every slot bought"
	end

	local seen = {}
	for order, fish in tank.fish do
		seen[fish.uid] = true
		local row = fishRows[fish.uid] or makeFishRow(fish)
		-- weather variant: "⚡ Stormborn Salmon" in the variant colour
		local variant = fish.variant and Config.VARIANTS[fish.variant]
		local speciesName = if Config.ById[fish.species] then Config.ById[fish.species].name else fish.species
		row.name.Text = if variant then ("%s %s %s"):format(variant.icon, variant.name, speciesName) else speciesName
		row.name.TextColor3 = if variant then variant.color else C.text
		fishRows[fish.uid] = row
		row.frame.LayoutOrder = order

		local species = Config.ById[fish.species]
		-- predict growth since the last server update (server stays the authority)
		local age = fish.age
		if species then
			local growEnd = math.min(now, tank.fedUntil)
			if growEnd > tank.now then
				local boosted = math.max(0, math.min(growEnd, tank.boostUntil or 0) - tank.now)
				age = math.min(age + ((growEnd - tank.now) + boosted * (Config.GROW_BOOST_MULT - 1)) * Config.TIME_SCALE / species.growSeconds * Config.growMult(fish), Config.MAX_AGE)
			end
		end

		if age < 1 then
			row.barFill.Size = UDim2.new(age, 0, 1, 0)
			row.info.Text = ("Growing %d%%"):format(math.floor(age * 100))
			row.info.TextColor3 = C.dim
			row.sell.BackgroundColor3 = C.buttonOff
		else
			local size = Config.sizeFromAge(age)
			row.barFill.Size = UDim2.new((age - 1) / Config.EXTRA_GROWTH_PERIODS, 0, 1, 0)
			local price = market and species and market.prices[fish.species]
			if price then
				row.info.Text = ("Size %.2fx · sells ~$%s"):format(size, fmt(price * size * Config.variantMult(fish) * (1 - Config.MARKET_FEE)))
			else
				row.info.Text = ("Size %.2fx"):format(size)
			end
			row.info.TextColor3 = C.text
			row.sell.BackgroundColor3 = C.button
		end

		if fish.starveAt and now >= tank.fedUntil then
			row.status.Text = "Starving! Dies in " .. fmtTime(fish.starveAt - now)
			row.status.TextColor3 = C.down
		elseif age >= Config.MAX_AGE then
			row.status.Text = "Fully grown"
			row.status.TextColor3 = C.up
		else
			row.status.Text = if age >= 1 then "Still growing bigger" else ""
			row.status.TextColor3 = C.dim
		end
	end
	for uid, row in fishRows do
		if not seen[uid] then
			row.frame:Destroy()
			fishRows[uid] = nil
		end
	end
end

-- Robux shop ----------------------------------------------------------------
-- Roblox shows its own purchase window; the server gives the item (server/ShopService).
local MarketplaceService = game:GetService("MarketplaceService")
local shopCards = {}

for i, item in Config.ROBUX do
	local card = make("Frame", { LayoutOrder = i, BackgroundColor3 = C.row, Size = UDim2.new(1, -6, 0, 84), Parent = shopList }, { corner(6) })
	label({ Font = FONT_BOLD, Text = item.name, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(0.68, -12, 0, 24), MaxText = 20, Parent = card })
	local info = label({ Text = item.text, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(0.68, -12, 0, 44), MaxText = 15, Parent = card })
	local buy = button({ Text = "...", BackgroundColor3 = Color3.fromRGB(40, 160, 90), Position = UDim2.new(0.7, 0, 0, 18), Size = UDim2.new(0.3, -10, 0, 48), Parent = card })
	local cardState = { item = item, info = info, buy = buy, price = nil }
	shopCards[item.key] = cardState

	if item.id ~= 0 then
		task.spawn(function()
			local infoType = if item.kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			local ok, product = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.id, infoType)
			if ok and product and product.PriceInRobux then
				cardState.price = product.PriceInRobux
			end
		end)
	end

	buy.Activated:Connect(function()
		if item.id == 0 then
			showToast("This item is not set up yet")
		elseif item.kind == "pass" then
			if tank and tank[item.key] then
				showToast("You already own " .. item.name)
			else
				MarketplaceService:PromptGamePassPurchase(player, item.id)
			end
		elseif item.once and tank and tank[item.key] then
			showToast("You already got the " .. item.name) -- one per player
		else
			MarketplaceService:PromptProductPurchase(player, item.id)
		end
	end)
end

local function renderShop()
	local now = serverNow()
	for key, card in shopCards do
		local item = card.item
		local owned = (item.kind == "pass" or item.once) and tank ~= nil and tank[key] == true
		if item.id == 0 then
			card.buy.Text = "Not set up"
			card.buy.BackgroundColor3 = C.buttonOff
		elseif owned then
			card.buy.Text = "Owned ✓"
			card.buy.BackgroundColor3 = C.buttonOff
		else
			card.buy.Text = if card.price then ("R$ %d"):format(card.price) else "Buy"
			card.buy.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
		end
		if key == "growBoost" and tank and (tank.boostUntil or 0) > now then
			card.info.Text = "ACTIVE: " .. fmtTime(tank.boostUntil - now) .. " left. Buy again to add time."
			card.info.TextColor3 = C.up
		else
			card.info.Text = item.text
			card.info.TextColor3 = C.dim
		end
	end
end

-- Harbor Store (patio decor) --------------------------------------------------
-- Open at the store hut (browse + buy) or from an empty patio spot next to your tank (buy + place).
-- Coin items: the server buys them (PatioService). Robux items: Roblox's purchase window, then
-- the server grants them (ShopService). Everything you own is saved and comes back next visit.
local storeRows = {}
local placeSpot = nil -- patio spot number we're choosing an item for, or nil when just browsing
local storeMode = "all" -- "all" = everything for sale, "mine" = only what you own / have placed

-- Colour picker for colorable items (flags): pops up over the store list when you press Place.
local colorPicker = make("Frame", {
	BackgroundColor3 = C.bg,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -20, 0, 104),
	Visible = false,
	ZIndex = 10,
	Parent = storeFrame,
}, { corner(8), make("UIStroke", { Color = C.warn, Thickness = 2 }) })
local pickerTitle = label({ Font = FONT_BOLD, Text = "Pick a colour", TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 8, 0, 6), Size = UDim2.new(1, -16, 0, 22), MaxText = 16, ZIndex = 11, Parent = colorPicker })
local swatchRow = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 8, 0, 36), Size = UDim2.new(1, -16, 0, 56), ZIndex = 11, Parent = colorPicker }, {
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local pickerItem = nil -- the item waiting for a colour
for i, c in Config.PATIO_COLORS do
	local swatch = make("TextButton", {
		LayoutOrder = i,
		Text = "",
		BackgroundColor3 = c.color,
		AutoButtonColor = true,
		Size = UDim2.new(1 / #Config.PATIO_COLORS, -6, 1, 0),
		ZIndex = 12,
		Parent = swatchRow,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIStroke", { Color = C.text, Thickness = 2, Transparency = 0.2 }), make("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	swatch.Activated:Connect(function()
		if placeSpot and pickerItem then
			act("placeDecor", { spot = placeSpot, item = pickerItem.id, color = c.key })
			colorPicker.Visible = false
			storeFrame.Visible = false
			placeSpot, pickerItem = nil, nil
		end
	end)
end

for i, item in Config.PATIO_ITEMS do
	local isRobux = item.robuxId ~= nil
	local row = make("Frame", { LayoutOrder = i, BackgroundColor3 = C.row, Size = UDim2.new(1, -6, 0, 64), Parent = storeList }, { corner(6) })
	make("Frame", { BackgroundColor3 = if isRobux then Color3.fromRGB(40, 160, 90) else C.warn, Size = UDim2.new(0, 6, 1, 0), Parent = row }, { corner(3) })
	label({ Font = FONT_BOLD, Text = item.name, Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(0.5, -14, 0, 22), MaxText = 18, Parent = row })
	label({ Text = item.text, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 14, 0, 26), Size = UDim2.new(0.5, -14, 0, 34), MaxText = 13, Parent = row })
	local owned = label({ Text = "", TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0.14, 0, 1, -8), MaxText = 14, Parent = row })
	local buy = button({ Text = "...", BackgroundColor3 = if isRobux then Color3.fromRGB(40, 160, 90) else C.button, Position = UDim2.new(0.64, 0, 0, 12), Size = UDim2.new(0.18, -4, 1, -24), Parent = row })
	local place = button({ Text = "Place", BackgroundColor3 = C.warn, Position = UDim2.new(0.82, 0, 0, 12), Size = UDim2.new(0.18, -8, 1, -24), Visible = false, Parent = row })
	local state = { frame = row, item = item, owned = owned, buy = buy, place = place, robuxPrice = nil }
	storeRows[item.id] = state

	if isRobux and item.robuxId ~= 0 then
		task.spawn(function()
			local ok, product = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.robuxId, Enum.InfoType.Product)
			if ok and product and product.PriceInRobux then
				state.robuxPrice = product.PriceInRobux
			end
		end)
	end

	buy.Activated:Connect(function()
		if not isRobux then
			act("buyDecor", item.id)
		elseif item.robuxId == 0 then
			showToast("This item is not set up yet")
		else
			MarketplaceService:PromptProductPurchase(player, item.robuxId)
		end
	end)
	place.Activated:Connect(function()
		if not placeSpot then
			return
		end
		local have = tank and tank.inventory and tank.inventory[item.id] or 0
		local here = tank and tank.patio and tank.patio["s" .. placeSpot]
		if item.colorable and (have > 0 or here == item.id) then
			-- flags: choose a colour first (also works to recolour the flag already on this spot)
			pickerItem = item
			pickerTitle.Text = ("Pick a colour for your %s"):format(item.name)
			colorPicker.Visible = true
			return
		end
		act("placeDecor", { spot = placeSpot, item = item.id })
		storeFrame.Visible = false
		placeSpot = nil
	end)
end

local function renderStore()
	if not storeFrame.Visible then
		return
	end
	local inventory = (tank and tank.inventory) or {}
	local placedCount = {}
	for _, id in (tank and tank.patio) or {} do
		placedCount[id] = (placedCount[id] or 0) + 1
	end
	local coins = (tank and tank.coins) or 0
	local mine = storeMode == "mine"
	storeTitle.Text = if placeSpot then "Patio spot" elseif mine then "My items" else "Harbor Store"
	storeHint.Text = if placeSpot then "Press Place on an item you own (buy it first if needed)"
		elseif mine then "To place: go to your tank, press E on a sand circle"
		else "Buy here, then press E on a sand circle next to your tank"
	storeTabAll.BackgroundColor3 = if mine then C.buttonOff else C.button
	storeTabMine.BackgroundColor3 = if mine then C.button else C.buttonOff
	local shown = 0
	for id, row in storeRows do
		local item = row.item
		local have = inventory[id] or 0
		local placed = placedCount[id] or 0
		row.frame.Visible = not mine or have > 0 or placed > 0
		if row.frame.Visible then
			shown += 1
		end
		local parts = {}
		if have > 0 then
			table.insert(parts, ("Owned %d"):format(have))
		end
		if placed > 0 then
			table.insert(parts, ("Placed %d"):format(placed))
		end
		row.owned.Text = table.concat(parts, "\n")
		if item.price then
			row.buy.Text = fmt(item.price)
			row.buy.BackgroundColor3 = if coins >= item.price then C.button else C.buttonOff
		elseif item.robuxId == 0 then
			row.buy.Text = "Not set up"
			row.buy.BackgroundColor3 = C.buttonOff
		else
			row.buy.Text = if row.robuxPrice then ("R$ %d"):format(row.robuxPrice) else "R$"
			row.buy.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
		end
		row.place.Visible = placeSpot ~= nil
		row.place.BackgroundColor3 = if have > 0 then C.warn else C.buttonOff
	end
	storeEmpty.Visible = shown == 0
end

local function openStore(spot: number?, mode: string?)
	placeSpot = spot
	colorPicker.Visible = false
	pickerItem = nil
	storeMode = mode or "all"
	setPanel(storeFrame, true)
	renderStore()
end

storeTabAll.Activated:Connect(function()
	openStore(placeSpot, "all")
end)
storeTabMine.Activated:Connect(function()
	openStore(placeSpot, "mine")
end)
storeTabRobux.Activated:Connect(function()
	placeSpot = nil
	setPanel(shopFrame, true)
end)
shopToStore.Activated:Connect(function()
	openStore(nil, "all")
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "StorePrompt" then
		openStore(nil)
	elseif prompt.Name == "PatioPrompt" then
		local plot = prompt:FindFirstAncestorWhichIsA("Model")
		if not plot or plot:GetAttribute("OwnerId") ~= player.UserId then
			return
		end
		local spot = prompt.Parent:GetAttribute("Spot")
		local placed = tank and tank.patio and tank.patio["s" .. tostring(spot)]
		if placed then
			act("pickUpDecor", spot)
		else
			openStore(spot)
		end
	end
end)

Remotes:WaitForChild("State").OnClientEvent:Connect(function(payload)
	tank = payload
	tankAt = os.clock()
	renderTank()
	renderStore()
end)

Remotes:WaitForChild("Market").OnClientEvent:Connect(function(payload)
	market = payload
	marketAt = os.clock()
	renderMarket()
	renderTank()
end)

-- Top 100 panel: rebuilt when the server sends a new list (every ~2 min)
Remotes:WaitForChild("Top").OnClientEvent:Connect(function(list)
	for _, child in topList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if type(list) ~= "table" or #list == 0 then
		label({ Text = "No one yet. Sell fish to get on the board!", TextColor3 = C.dim, Size = UDim2.new(1, -6, 0, 30), Parent = topList })
		return
	end
	for _, e in list do
		local mine = e.userId == player.UserId
		local row = make("Frame", { LayoutOrder = e.rank, BackgroundColor3 = if mine then Color3.fromRGB(60, 90, 40) else C.row, BackgroundTransparency = GLASS_CARD, Size = UDim2.new(1, -6, 0, 30), Parent = topList }, { corner(6) })
		local color = if e.rank == 1 then Color3.fromRGB(255, 215, 80) elseif e.rank == 2 then Color3.fromRGB(215, 220, 230) elseif e.rank == 3 then Color3.fromRGB(225, 160, 100) else C.text
		label({ Font = FONT_BOLD, Text = ("%d. %s"):format(e.rank, tostring(e.name)), TextColor3 = color, Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(0.6, -10, 1, -8), Parent = row })
		label({ Font = FONT_BOLD, Text = "$" .. fmt(e.score), TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0.6, 0, 0, 4), Size = UDim2.new(0.4, -10, 1, -8), Parent = row })
	end
end)

-- VIP pass: [VIP] in front of their chat messages (the server sets the VIP player attribute)
do
	local TextChatService = game:GetService("TextChatService")
	TextChatService.OnIncomingMessage = function(message)
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("VIP") == true then
			local props = Instance.new("TextChatMessageProperties")
			props.PrefixText = "<font color=\"#FFD24A\">[VIP]</font> " .. message.PrefixText
			return props
		end
		return nil
	end
end

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, seconds)
	showToast(text, seconds)
end)

require(script.Parent:WaitForChild("FishRenderer")).start()
require(script.Parent:WaitForChild("Seagulls")).start()
require(script.Parent:WaitForChild("FerryCard")).start()
require(script.Parent:WaitForChild("Weather")).start()
require(script.Parent:WaitForChild("Sky")).start()
require(script.Parent:WaitForChild("TankFx")).start()
task.spawn(require(script.Parent:WaitForChild("DevPanel")).start) -- Studio only
require(script.Parent:WaitForChild("BoatRenderer")).start()
require(script.Parent:WaitForChild("Bubbles")).start()

-- Feed prompts: only show the one on MY tank (each client hides the others locally)
local function updateFeedPrompts()
	local plotsFolder = workspace:FindFirstChild("FishWorld") and workspace.FishWorld:FindFirstChild("Plots")
	if not plotsFolder then
		return
	end
	for _, plot in plotsFolder:GetChildren() do
		local mine = plot:GetAttribute("OwnerId") == player.UserId
		local feedPrompt = plot:FindFirstChild("FeedPrompt", true)
		if feedPrompt and feedPrompt.Enabled ~= mine then
			feedPrompt.Enabled = mine
		end
		-- patio spots: only the owner can place / pick up
		for _, d in plot:GetChildren() do
			local patioPrompt = d.Name == "PatioSpot" and d:FindFirstChild("PatioPrompt")
			if patioPrompt and patioPrompt.Enabled ~= mine then
				patioPrompt.Enabled = mine
			end
		end
	end
end

-- Food gauge on the bottom of every tank's glass (everyone sees everyone's food)
local MAX_FOOD = Config.real(Config.MAX_FEED_HOURS * 3600)
local LOW_FOOD = Config.real(3600)
local function renderFoodGauges()
	local plotsFolder = workspace:FindFirstChild("FishWorld") and workspace.FishWorld:FindFirstChild("Plots")
	if not plotsFolder then
		return
	end
	local now = serverNow()
	for _, plot in plotsFolder:GetChildren() do
		local strip = plot:FindFirstChild("Strip", true)
		if not strip then
			continue
		end
		local mine = plot:GetAttribute("OwnerId") == player.UserId
		local fishCount = plot:GetAttribute("FishCount") or 0
		local fedLeft = (plot:GetAttribute("FedUntil") or 0) - now
		local fill, text = strip.Fill, strip.Text
		if (plot:GetAttribute("OwnerId") or 0) == 0 or (fishCount == 0 and not mine) then
			strip.Visible = false
		elseif fishCount == 0 then
			strip.Visible = true
			fill.Size = UDim2.fromScale(0, 1)
			text.Text = "Empty: buy an egg at the Market"
			text.TextColor3 = C.dim
		elseif plot:GetAttribute("AutoFeeder") then
			strip.Visible = true
			fill.Size = UDim2.fromScale(1, 1)
			fill.BackgroundColor3 = C.up
			text.Text = "Auto-Feeder: always full"
			text.TextColor3 = C.text
		elseif fedLeft > 0 then
			strip.Visible = true
			local low = fedLeft < LOW_FOOD
			fill.Size = UDim2.fromScale(math.clamp(fedLeft / MAX_FOOD, 0.04, 1), 1)
			fill.BackgroundColor3 = if low then C.warn else C.up
			text.Text = "Food " .. fmtTime(fedLeft) .. (if low and mine then " · press F" else "")
			text.TextColor3 = C.text
		else
			strip.Visible = true
			fill.Size = UDim2.fromScale(0, 1)
			text.Text = if mine then "HUNGRY! Press F to feed" else "HUNGRY!"
			text.TextColor3 = C.down
		end
	end
end

-- smooth countdowns between server updates
while true do
	task.wait(0.5)
	updateFeedPrompts()
	renderFoodGauges()
	renderShop()
	renderStore()
	renderTank()
	renderMarket()
end
