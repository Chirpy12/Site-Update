local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if playerGui:GetAttribute("PetMarketUI_Loaded") then
	return
end
playerGui:SetAttribute("PetMarketUI_Loaded", true)

local ReplicationReciever = require(ReplicatedStorage.Modules.ReplicationReciever)
local TradeBoothsData = require(ReplicatedStorage.Data.TradeBoothsData)
local BuyItemController = require(ReplicatedStorage.Modules.TradeBoothControllers.TradeBoothBuyItemController)
local TradeEvents = ReplicatedStorage.GameEvents.TradeEvents

local ItemNameFinder = require(ReplicatedStorage.Modules.ItemNameFinder)
local ItemRarityFinder = require(ReplicatedStorage.Modules.ItemRarityFinder)
local GGStaticData = require(ReplicatedStorage.Modules.GardenGuideModules.DataModules.GGStaticData)
local NumberUtil = require(ReplicatedStorage.Modules.NumberUtil)

local PetUtilities = require(ReplicatedStorage.Modules.PetServices.PetUtilities)
local DecimalFormat = require(ReplicatedStorage.Data.DecimalNumberFormat)
local PetList = require(ReplicatedStorage.Data.PetRegistry.PetList)

local boothsReceiver = ReplicationReciever.new("Booths")

local petNameMap = {}
local petNameMapLower = {}
local petItems = {}
for petType, _ in pairs(PetList) do
	local displayName = ItemNameFinder(petType, "Pet")
	petNameMap[displayName] = petType
	petNameMapLower[string.lower(displayName)] = petType
	table.insert(petItems, { petType = petType, displayName = displayName })
end
table.sort(petItems, function(a, b)
	return a.displayName < b.displayName
end)

local COLORS = {
	GreenHeader = Color3.fromRGB(60, 66, 79),
	GreenLight = Color3.fromRGB(92, 100, 120),
	BrownOuter = Color3.fromRGB(24, 26, 31),
	BrownInner = Color3.fromRGB(30, 32, 38),
	BrownDark = Color3.fromRGB(36, 39, 46),
	BrownTile = Color3.fromRGB(44, 48, 58),
	BeigeText = Color3.fromRGB(230, 232, 238),
	RedClose = Color3.fromRGB(200, 70, 70),
	Shadow = Color3.fromRGB(12, 13, 16),
	Accent = Color3.fromRGB(110, 170, 255)
}

local PetRegistry = require(ReplicatedStorage.Data.PetRegistry)
local PetRegistryList = PetRegistry.PetList

local RARITY_EMOJI = {
	Common = "🟢",
	Uncommon = "🔵",
	Rare = "🟣",
	Epic = "🟪",
	Legendary = "🟨",
	Mythical = "🟥",
	Divine = "✨",
	Prismatic = "🌈"
}

local function toDiscordImageUrl(asset)
	if not asset or asset == "" then
		return nil
	end
	local id = tostring(asset):match("rbxassetid://(%d+)")
	if id then
		return "https://assetdelivery.roblox.com/v1/asset?id=" .. id
	end
	if tostring(asset):match("^https?://") then
		return asset
	end
	return nil
end

local function getPetIcon(petType)
	local icon = PetRegistryList[petType] and PetRegistryList[petType].Icon or nil
	return toDiscordImageUrl(icon)
end

local function getRarityEmoji(petType)
	local rarity = PetRegistryList[petType] and PetRegistryList[petType].Rarity or "Common"
	return (RARITY_EMOJI[rarity] or "⚪") .. " " .. rarity
end

local function roundify(guiObj, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = guiObj
end

local function stroke(guiObj, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1.5
	s.Transparency = 0.4
	s.Parent = guiObj
	return s
end

local function applyGradient(guiObj, c1, c2)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(1, c2)
	})
	grad.Rotation = 90
	grad.Parent = guiObj
end

local function applySoftPanelGradient(guiObj)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 215, 225))
	})
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.88),
		NumberSequenceKeypoint.new(1, 1)
	})
	grad.Parent = guiObj
end

local function applyGameButtonStyle(btn)
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 16
	btn.TextColor3 = Color3.new(1, 1, 1)
	roundify(btn, 10)
	stroke(btn, Color3.fromRGB(15, 16, 20), 2)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 170, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 90, 130))
	})
	grad.Rotation = 90
	grad.Parent = btn
end

local function resolvePlayerFromBoothId(playerId)
	if type(playerId) ~= "string" then
		return nil
	end
	local userId = tonumber(playerId:match("^Player_(%d+)$"))
	if not userId then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

local function getScreenGui(instance)
	return instance:FindFirstAncestorOfClass("ScreenGui")
end

local function getDropdownTextNodes(btn)
	return btn:FindFirstChild("Label"), btn:FindFirstChild("Placeholder")
end

-- Local settings (client-only)
local SETTINGS_FILE = "PetMarketSettings.json"

local function loadLocalSettings()
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(SETTINGS_FILE))
	end)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

local function saveLocalSettings(settings)
	pcall(function()
		writefile(SETTINGS_FILE, HttpService:JSONEncode(settings))
	end)
end

local settings = loadLocalSettings()

-- Webhook helper
local webhookInput

local function getRequestFunction()
	return (syn and syn.request)
		or (http and http.request)
		or (fluxus and fluxus.request)
		or (krnl and krnl.request)
		or http_request
		or request
end

local function sendWebhookEmbed(embed)
	local url = (webhookInput and webhookInput.Text) or (settings and settings.webhookUrl) or playerGui:GetAttribute("WebhookUrl")
	if not url or url == "" then
		return
	end

	local req = getRequestFunction()
	if not req then
		return
	end

	local payload = {
		username = "The Sniper",
		avatar_url = "https://cdn.dribbble.com/userupload/4992412/file/original-c9c1e9a0a294e0d3d07709ec0f6fe643.jpg?resize=752x&vertical=center",
		embeds = { embed }
	}

	pcall(function()
		req({
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload)
		})
	end)
end

local pendingPurchases = {}

local function registerPendingPurchase(listingObj)
	if not listingObj or not listingObj.data then
		return
	end

	table.insert(pendingPurchases, {
		time = os.clock(),
		displayName = ItemNameFinder(listingObj.data.PetType or "", "Pet"),
		petType = listingObj.data.PetType,
		baseWeight = listingObj.data.PetData and listingObj.data.PetData.BaseWeight,
		price = listingObj.listingPrice
	})
end

local buyDebounce = false

local function promptBuyWithRetry(listing, marketFrame)
	if buyDebounce then
		return
	end
	buyDebounce = true

	local screenGui = getScreenGui(marketFrame)
	if not screenGui then
		buyDebounce = false
		return
	end

	registerPendingPurchase(listing)

	local ok = BuyItemController:PromptBuyListing(listing, screenGui)
	if ok then
		task.delay(0.2, function()
			buyDebounce = false
		end)
		return
	end

	task.delay(0.2, function()
		BuyItemController:PromptBuyListing(listing, screenGui)
		buyDebounce = false
	end)
end

local autoBuyCooldown = false
local autoBuyCooldownTime = 0.4
local autoBuyMaxRetries = 2

local function tryAutoBuyDirect(listingObj, marketFrame)
	if autoBuyCooldown then
		return false
	end
	autoBuyCooldown = true
	task.delay(autoBuyCooldownTime, function()
		autoBuyCooldown = false
	end)

	if not listingObj or not listingObj.listingOwner or not listingObj.listingUUID then
		return false
	end

	for attempt = 1, autoBuyMaxRetries do
		local success, message = TradeEvents.Booths.BuyListing:InvokeServer(
			listingObj.listingOwner,
			listingObj.listingUUID
		)

		if success then
			registerPendingPurchase(listingObj)
			return true
		end

		warn(("Auto-buy failed (attempt %d): %s"):format(attempt, tostring(message)))
		task.wait(0.15)
	end

	if marketFrame then
		promptBuyWithRetry(listingObj, marketFrame)
	end

	return false
end

-- Server hop logic (min player filter)
local PlaceID = game.PlaceId
local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour
local Deleted = false
local MIN_PLAYERS = 10

local File = pcall(function()
	AllIDs = HttpService:JSONDecode(readfile("NotSameServers.json"))
end)

if not File then
	table.insert(AllIDs, actualHour)
	writefile("NotSameServers.json", HttpService:JSONEncode(AllIDs))
end

local function TPReturner()
	local Site
	if foundAnything == "" then
		Site = HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100'))
	else
		Site = HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100&cursor=' .. foundAnything))
	end

	local ID = ""
	if Site.nextPageCursor and Site.nextPageCursor ~= "null" and Site.nextPageCursor ~= nil then
		foundAnything = Site.nextPageCursor
	end

	local num = 0
	for _, v in pairs(Site.data) do
		local Possible = true
		ID = tostring(v.id)
		if tonumber(v.playing) >= MIN_PLAYERS and tonumber(v.maxPlayers) > tonumber(v.playing) then
			for _, Existing in pairs(AllIDs) do
				if num ~= 0 then
					if ID == tostring(Existing) then
						Possible = false
					end
				else
					if tonumber(actualHour) ~= tonumber(Existing) then
						pcall(function()
							delfile("NotSameServers.json")
							AllIDs = {}
							table.insert(AllIDs, actualHour)
						end)
					end
				end
				num = num + 1
			end
			if Possible == true then
				table.insert(AllIDs, ID)
				wait()
				pcall(function()
					writefile("NotSameServers.json", HttpService:JSONEncode(AllIDs))
					wait()
					TeleportService:TeleportToPlaceInstance(PlaceID, ID, Players.LocalPlayer)
				end)
				wait(4)
			end
		end
	end
end

local function TeleportOnce()
	pcall(function()
		TPReturner()
		if foundAnything ~= "" then
			TPReturner()
		end
	end)
end

-- UI
local gui = Instance.new("ScreenGui")
gui.Name = "PetMarketUI"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = gui

local function updateUIScale()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local scale = math.min(viewport.X / 1280, viewport.Y / 720)
	uiScale.Scale = math.clamp(scale, 0.7, 1.35)
end

updateUIScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
end

local openBtn = Instance.new("TextButton")
openBtn.Name = "OpenPetMarket"
openBtn.Size = UDim2.new(0, 180, 0, 48)
openBtn.Position = UDim2.new(0, 20, 0, 80)
openBtn.Text = "Pet Market"
openBtn.BackgroundColor3 = COLORS.GreenHeader
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBlack
openBtn.TextSize = 18
openBtn.Parent = gui
applyGameButtonStyle(openBtn)

-- Draggable button
local dragging = false
local dragStart
local startPos

openBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = openBtn.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		openBtn.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

local marketFrame = Instance.new("Frame")
marketFrame.Name = "MarketFrame"
marketFrame.Size = UDim2.new(0.9, 0, 0.85, 0)
marketFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
marketFrame.AnchorPoint = Vector2.new(0.5, 0.5)
marketFrame.BackgroundColor3 = COLORS.BrownOuter
marketFrame.Visible = false
marketFrame.Parent = gui
roundify(marketFrame, 12)
stroke(marketFrame, Color3.fromRGB(10, 10, 12), 2)

local marketSizeClamp = Instance.new("UISizeConstraint")
marketSizeClamp.MinSize = Vector2.new(820, 520)
marketSizeClamp.MaxSize = Vector2.new(1400, 900)
marketSizeClamp.Parent = marketFrame

local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, -12, 0, 52)
headerFrame.Position = UDim2.new(0, 6, 0, 6)
headerFrame.BackgroundColor3 = COLORS.GreenHeader
headerFrame.Parent = marketFrame
roundify(headerFrame, 10)
stroke(headerFrame, Color3.fromRGB(40, 44, 60), 1)
headerFrame.ZIndex = 50
applyGradient(headerFrame, COLORS.GreenHeader, COLORS.Accent)
applySoftPanelGradient(headerFrame)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.Text = "Pet Market"
title.TextColor3 = Color3.new(1, 1, 1)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 26
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = headerFrame
title.ZIndex = 51

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 46, 0, 40)
closeBtn.Position = UDim2.new(1, -52, 0.5, -20)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 20
closeBtn.BackgroundColor3 = COLORS.RedClose
closeBtn.Parent = headerFrame
roundify(closeBtn, 8)
stroke(closeBtn, Color3.fromRGB(120, 24, 20), 1)
closeBtn.ZIndex = 52

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -12, 1, -64)
contentFrame.Position = UDim2.new(0, 6, 0, 60)
contentFrame.BackgroundColor3 = COLORS.BrownInner
contentFrame.Parent = marketFrame
roundify(contentFrame, 10)
stroke(contentFrame, Color3.fromRGB(18, 20, 25), 2)
contentFrame.ClipsDescendants = false
contentFrame.ZIndex = 1

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 170, 1, -12)
sidebar.Position = UDim2.new(0, 6, 0, 6)
sidebar.BackgroundColor3 = COLORS.BrownDark
sidebar.Parent = contentFrame
roundify(sidebar, 10)
stroke(sidebar, Color3.fromRGB(20, 22, 26), 1.5)
sidebar.ZIndex = 2
applySoftPanelGradient(sidebar)

local sidebarList = Instance.new("UIListLayout")
sidebarList.Padding = UDim.new(0, 8)
sidebarList.SortOrder = Enum.SortOrder.LayoutOrder
sidebarList.Parent = sidebar

local tabs = {}
local function makeSidebarButton(text, selected)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -16, 0, 44)
	btn.Position = UDim2.new(0, 8, 0, 0)
	btn.Text = text
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 16
	btn.BackgroundColor3 = selected and COLORS.GreenLight or COLORS.BrownTile
	btn.Parent = sidebar
	roundify(btn, 8)
	stroke(btn, COLORS.Shadow, 1)
	btn.ZIndex = 3
	tabs[text] = btn
	return btn
end

makeSidebarButton("Pets", true)
makeSidebarButton("Auto-buy", false)
makeSidebarButton("Webhooks", false)
makeSidebarButton("Settings", false)
makeSidebarButton("Server Hop", false)

local function setTab(name)
	for tabName, btn in pairs(tabs) do
		btn.BackgroundColor3 = (tabName == name) and COLORS.GreenLight or COLORS.BrownTile
	end
end

-- Tabs content
local petsTab = Instance.new("Frame")
petsTab.Name = "PetsTab"
petsTab.Size = UDim2.new(1, 0, 1, 0)
petsTab.BackgroundTransparency = 1
petsTab.Parent = contentFrame
petsTab.Visible = true
petsTab.ZIndex = 1

local autoBuyTab = Instance.new("Frame")
autoBuyTab.Name = "AutoBuyTab"
autoBuyTab.Size = UDim2.new(1, 0, 1, 0)
autoBuyTab.BackgroundTransparency = 1
autoBuyTab.Parent = contentFrame
autoBuyTab.Visible = false
autoBuyTab.ZIndex = 1

local webhooksTab = Instance.new("Frame")
webhooksTab.Name = "WebhooksTab"
webhooksTab.Size = UDim2.new(1, 0, 1, 0)
webhooksTab.BackgroundTransparency = 1
webhooksTab.Parent = contentFrame
webhooksTab.Visible = false
webhooksTab.ZIndex = 1

local settingsTab = Instance.new("Frame")
settingsTab.Name = "SettingsTab"
settingsTab.Size = UDim2.new(1, 0, 1, 0)
settingsTab.BackgroundTransparency = 1
settingsTab.Parent = contentFrame
settingsTab.Visible = false
settingsTab.ZIndex = 1

local serverHopTab = Instance.new("Frame")
serverHopTab.Name = "ServerHopTab"
serverHopTab.Size = UDim2.new(1, 0, 1, 0)
serverHopTab.BackgroundTransparency = 1
serverHopTab.Parent = contentFrame
serverHopTab.Visible = false
serverHopTab.ZIndex = 1

tabs["Pets"].MouseButton1Click:Connect(function()
	petsTab.Visible = true
	autoBuyTab.Visible = false
	webhooksTab.Visible = false
	settingsTab.Visible = false
	serverHopTab.Visible = false
	setTab("Pets")
end)

tabs["Auto-buy"].MouseButton1Click:Connect(function()
	petsTab.Visible = false
	autoBuyTab.Visible = true
	webhooksTab.Visible = false
	settingsTab.Visible = false
	serverHopTab.Visible = false
	setTab("Auto-buy")
end)

tabs["Webhooks"].MouseButton1Click:Connect(function()
	petsTab.Visible = false
	autoBuyTab.Visible = false
	webhooksTab.Visible = true
	settingsTab.Visible = false
	serverHopTab.Visible = false
	setTab("Webhooks")
end)

tabs["Settings"].MouseButton1Click:Connect(function()
	petsTab.Visible = false
	autoBuyTab.Visible = false
	webhooksTab.Visible = false
	settingsTab.Visible = true
	serverHopTab.Visible = false
	setTab("Settings")
end)

tabs["Server Hop"].MouseButton1Click:Connect(function()
	petsTab.Visible = false
	autoBuyTab.Visible = false
	webhooksTab.Visible = false
	settingsTab.Visible = false
	serverHopTab.Visible = true
	setTab("Server Hop")
end)

-- Icon headers
local function makeTabHeader(parent, text, iconId)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -200, 0, 42)
	header.Position = UDim2.new(0, 186, 0, 10)
	header.BackgroundTransparency = 1
	header.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 26, 0, 26)
	icon.Position = UDim2.new(0, 0, 0.5, -13)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://" .. tostring(iconId)
	icon.Parent = header

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -36, 1, 0)
	label.Position = UDim2.new(0, 34, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.BeigeText
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = header

	return header
end

makeTabHeader(petsTab, "Pet Market", 6031280882)
makeTabHeader(autoBuyTab, "Auto-buy", 6031280884)
makeTabHeader(webhooksTab, "Webhooks", 6031280886)
makeTabHeader(settingsTab, "Settings", 6031280887)
makeTabHeader(serverHopTab, "Server Hop", 6031280888)

local hopBtn = Instance.new("TextButton")
hopBtn.Size = UDim2.new(0, 180, 0, 44)
hopBtn.Position = UDim2.new(0, 186, 0, 60)
hopBtn.Text = "Hop Now"
hopBtn.TextColor3 = Color3.new(1, 1, 1)
hopBtn.Font = Enum.Font.GothamBlack
hopBtn.TextSize = 14
hopBtn.BackgroundColor3 = COLORS.GreenLight
hopBtn.Parent = serverHopTab
applyGameButtonStyle(hopBtn)

local autoToggle = Instance.new("TextButton")
autoToggle.Size = UDim2.new(0, 200, 0, 44)
autoToggle.Position = UDim2.new(0, 376, 0, 60)
autoToggle.Text = "Auto Hop: OFF"
autoToggle.TextColor3 = Color3.new(1, 1, 1)
autoToggle.Font = Enum.Font.GothamBlack
autoToggle.TextSize = 14
autoToggle.BackgroundColor3 = COLORS.BrownTile
autoToggle.Parent = serverHopTab
roundify(autoToggle, 8)
stroke(autoToggle, COLORS.Shadow, 1)

local hopIntervalBox = Instance.new("TextBox")
hopIntervalBox.Size = UDim2.new(0, 160, 0, 44)
hopIntervalBox.Position = UDim2.new(0, 586, 0, 60)
hopIntervalBox.PlaceholderText = "Interval (sec)"
hopIntervalBox.Text = tostring(settings.hopInterval or 30)
hopIntervalBox.BackgroundColor3 = COLORS.BrownTile
hopIntervalBox.TextColor3 = COLORS.BeigeText
hopIntervalBox.PlaceholderColor3 = Color3.fromRGB(220, 210, 190)
hopIntervalBox.Font = Enum.Font.GothamBold
hopIntervalBox.TextSize = 14
hopIntervalBox.ClearTextOnFocus = false
hopIntervalBox.Parent = serverHopTab
roundify(hopIntervalBox, 8)
stroke(hopIntervalBox, COLORS.Shadow, 1)

local hopStatus = Instance.new("TextLabel")
hopStatus.Size = UDim2.new(1, -200, 0, 22)
hopStatus.Position = UDim2.new(0, 186, 0, 110)
hopStatus.Text = ""
hopStatus.TextColor3 = Color3.fromRGB(180, 255, 180)
hopStatus.BackgroundTransparency = 1
hopStatus.Font = Enum.Font.GothamBold
hopStatus.TextSize = 12
hopStatus.TextXAlignment = Enum.TextXAlignment.Left
hopStatus.Parent = serverHopTab

local function parseInterval()
	local n = tonumber(hopIntervalBox.Text)
	if not n or n < 5 then
		return 30
	end
	return n
end

local autoHopOn = settings.autoHopOn or false
local autoHopThread = nil

hopBtn.MouseButton1Click:Connect(function()
	hopStatus.Text = "Hopping..."
	TeleportOnce()
end)

autoToggle.MouseButton1Click:Connect(function()
	autoHopOn = not autoHopOn
	autoToggle.Text = autoHopOn and "Auto Hop: ON" or "Auto Hop: OFF"
	autoToggle.BackgroundColor3 = autoHopOn and COLORS.GreenLight or COLORS.BrownTile
	settings.autoHopOn = autoHopOn
	settings.hopInterval = parseInterval()
	saveLocalSettings(settings)

	if autoHopOn then
		if autoHopThread then
			task.cancel(autoHopThread)
		end
		autoHopThread = task.spawn(function()
			while autoHopOn do
				task.wait(parseInterval())
				if autoHopOn then
					hopStatus.Text = "Auto hopping..."
					TeleportOnce()
				end
			end
		end)
	else
		if autoHopThread then
			task.cancel(autoHopThread)
			autoHopThread = nil
		end
	end
end)

hopIntervalBox.FocusLost:Connect(function()
	if hopIntervalBox.Text == "" then
		hopIntervalBox.Text = "30"
	end
	settings.hopInterval = parseInterval()
	saveLocalSettings(settings)
end)

if autoHopOn then
	autoToggle.Text = "Auto Hop: ON"
	autoToggle.BackgroundColor3 = COLORS.GreenLight
	autoHopThread = task.spawn(function()
		while autoHopOn do
			task.wait(parseInterval())
			if autoHopOn then
				hopStatus.Text = "Auto hopping..."
				TeleportOnce()
			end
		end
	end)
end

-- Auto-buy UI
local autoBuyToggle = Instance.new("TextButton")
autoBuyToggle.Size = UDim2.new(0, 180, 0, 40)
autoBuyToggle.Position = UDim2.new(0, 186, 0, 58)
autoBuyToggle.Text = "Auto-buy: OFF"
autoBuyToggle.TextColor3 = Color3.new(1, 1, 1)
autoBuyToggle.Font = Enum.Font.GothamBlack
autoBuyToggle.TextSize = 14
autoBuyToggle.BackgroundColor3 = COLORS.BrownTile
autoBuyToggle.Parent = autoBuyTab
roundify(autoBuyToggle, 8)
stroke(autoBuyToggle, COLORS.Shadow, 1)

local autoBuyIntervalBox = Instance.new("TextBox")
autoBuyIntervalBox.Size = UDim2.new(0, 140, 0, 40)
autoBuyIntervalBox.Position = UDim2.new(0, 376, 0, 58)
autoBuyIntervalBox.PlaceholderText = "Interval (sec)"
autoBuyIntervalBox.Text = tostring(settings.autoBuyInterval or 5)
autoBuyIntervalBox.BackgroundColor3 = COLORS.BrownTile
autoBuyIntervalBox.TextColor3 = COLORS.BeigeText
autoBuyIntervalBox.PlaceholderColor3 = Color3.fromRGB(220, 210, 190)
autoBuyIntervalBox.Font = Enum.Font.GothamBold
autoBuyIntervalBox.TextSize = 14
autoBuyIntervalBox.ClearTextOnFocus = false
autoBuyIntervalBox.Parent = autoBuyTab
roundify(autoBuyIntervalBox, 8)
stroke(autoBuyIntervalBox, COLORS.Shadow, 1)

local addEntryBtn = Instance.new("TextButton")
addEntryBtn.Size = UDim2.new(0, 120, 0, 40)
addEntryBtn.Position = UDim2.new(0, 526, 0, 58)
addEntryBtn.Text = "Add Entry"
addEntryBtn.TextColor3 = Color3.new(1, 1, 1)
addEntryBtn.Font = Enum.Font.GothamBlack
addEntryBtn.TextSize = 14
addEntryBtn.BackgroundColor3 = COLORS.GreenLight
addEntryBtn.Parent = autoBuyTab
roundify(addEntryBtn, 8)
stroke(addEntryBtn, COLORS.Shadow, 1)

local autoBuyStatus = Instance.new("TextLabel")
autoBuyStatus.Size = UDim2.new(1, -200, 0, 22)
autoBuyStatus.Position = UDim2.new(0, 186, 0, 104)
autoBuyStatus.Text = ""
autoBuyStatus.TextColor3 = Color3.fromRGB(180, 255, 180)
autoBuyStatus.BackgroundTransparency = 1
autoBuyStatus.Font = Enum.Font.GothamBold
autoBuyStatus.TextSize = 12
autoBuyStatus.TextXAlignment = Enum.TextXAlignment.Left
autoBuyStatus.Parent = autoBuyTab

local entryHeader = Instance.new("TextLabel")
entryHeader.Size = UDim2.new(1, -200, 0, 20)
entryHeader.Position = UDim2.new(0, 186, 0, 130)
entryHeader.Text = "Pet (name/type) | Min BaseWt | Max Budget"
entryHeader.TextColor3 = COLORS.BeigeText
entryHeader.BackgroundTransparency = 1
entryHeader.Font = Enum.Font.GothamBold
entryHeader.TextSize = 12
entryHeader.TextXAlignment = Enum.TextXAlignment.Left
entryHeader.Parent = autoBuyTab

local autoBuyList = Instance.new("ScrollingFrame")
autoBuyList.Size = UDim2.new(1, -200, 1, -170)
autoBuyList.Position = UDim2.new(0, 186, 0, 150)
autoBuyList.BackgroundColor3 = COLORS.BrownDark
autoBuyList.ScrollBarThickness = 8
autoBuyList.CanvasSize = UDim2.new(0, 0, 0, 0)
autoBuyList.Parent = autoBuyTab
roundify(autoBuyList, 10)
stroke(autoBuyList, COLORS.Shadow, 2)
autoBuyList.ClipsDescendants = true

local autoBuyListLayout = Instance.new("UIListLayout")
autoBuyListLayout.Padding = UDim.new(0, 6)
autoBuyListLayout.Parent = autoBuyList

local autoBuyEntries = {}
local autoBuyEntryId = 0
local autoBuyEnabled = settings.autoBuyEnabled or false
local autoBuyThread = nil
local autoBuySeen = {}

local function parseAutoBuyInterval()
	local n = tonumber(autoBuyIntervalBox.Text)
	if not n or n < 2 then
		return 5
	end
	return n
end

local function normalizePetTypeInput(text)
	local t = tostring(text or "")
	t = t:gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" then
		return nil
	end
	local lower = string.lower(t)
	if petNameMapLower[lower] then
		return petNameMapLower[lower]
	end
	return t
end

local function saveAutoBuySettings()
	settings.autoBuyEnabled = autoBuyEnabled
	settings.autoBuyInterval = parseAutoBuyInterval()
	settings.autoBuyEntries = autoBuyEntries
	saveLocalSettings(settings)
end

local function addAutoBuyEntry(entryData)
	autoBuyEntryId += 1
	local entry = {
		id = autoBuyEntryId,
		petText = entryData and entryData.petText or "",
		minBaseWt = entryData and entryData.minBaseWt or "",
		maxBudget = entryData and entryData.maxBudget or ""
	}
	table.insert(autoBuyEntries, entry)

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 36)
	row.BackgroundColor3 = COLORS.BrownTile
	row.Parent = autoBuyList
	roundify(row, 8)
	stroke(row, COLORS.Shadow, 1)

	local petBox = Instance.new("TextButton")
	petBox.Size = UDim2.new(0.45, -6, 1, -8)
	petBox.Position = UDim2.new(0, 6, 0, 4)
	petBox.Text = ""
	petBox.BackgroundColor3 = COLORS.BrownDark
	petBox.Parent = row
	roundify(petBox, 6)
	stroke(petBox, COLORS.Shadow, 1)

	local petLabel = Instance.new("TextLabel")
	petLabel.Name = "Label"
	petLabel.Size = UDim2.new(1, -10, 1, 0)
	petLabel.Position = UDim2.new(0, 6, 0, 0)
	petLabel.BackgroundTransparency = 1
	petLabel.Text = entry.petText or ""
	petLabel.TextColor3 = COLORS.BeigeText
	petLabel.Font = Enum.Font.GothamBold
	petLabel.TextSize = 12
	petLabel.TextXAlignment = Enum.TextXAlignment.Left
	petLabel.Parent = petBox

	local petPlaceholder = Instance.new("TextLabel")
	petPlaceholder.Name = "Placeholder"
	petPlaceholder.Size = UDim2.new(1, -10, 1, 0)
	petPlaceholder.Position = UDim2.new(0, 6, 0, 0)
	petPlaceholder.BackgroundTransparency = 1
	petPlaceholder.Text = "Pet"
	petPlaceholder.TextColor3 = Color3.fromRGB(220, 210, 190)
	petPlaceholder.Font = Enum.Font.GothamBold
	petPlaceholder.TextSize = 12
	petPlaceholder.TextXAlignment = Enum.TextXAlignment.Left
	petPlaceholder.Visible = (petLabel.Text == "")
	petPlaceholder.Parent = petBox

	local minBox = Instance.new("TextBox")
	minBox.Size = UDim2.new(0.2, -6, 1, -8)
	minBox.Position = UDim2.new(0.45, 4, 0, 4)
	minBox.PlaceholderText = "Min BaseWt"
	minBox.Text = entry.minBaseWt
	minBox.BackgroundColor3 = COLORS.BrownDark
	minBox.TextColor3 = COLORS.BeigeText
	minBox.Font = Enum.Font.GothamBold
	minBox.TextSize = 12
	minBox.ClearTextOnFocus = false
	minBox.Parent = row
	roundify(minBox, 6)
	stroke(minBox, COLORS.Shadow, 1)

	local budgetBox = Instance.new("TextBox")
	budgetBox.Size = UDim2.new(0.2, -6, 1, -8)
	budgetBox.Position = UDim2.new(0.65, 4, 0, 4)
	budgetBox.PlaceholderText = "Max Budget"
	budgetBox.Text = entry.maxBudget
	budgetBox.BackgroundColor3 = COLORS.BrownDark
	budgetBox.TextColor3 = COLORS.BeigeText
	budgetBox.Font = Enum.Font.GothamBold
	budgetBox.TextSize = 12
	budgetBox.ClearTextOnFocus = false
	budgetBox.Parent = row
	roundify(budgetBox, 6)
	stroke(budgetBox, COLORS.Shadow, 1)

	local removeBtn = Instance.new("TextButton")
	removeBtn.Size = UDim2.new(0.15, -10, 1, -8)
	removeBtn.Position = UDim2.new(0.85, 6, 0, 4)
	removeBtn.Text = "Remove"
	removeBtn.TextColor3 = Color3.new(1, 1, 1)
	removeBtn.Font = Enum.Font.GothamBlack
	removeBtn.TextSize = 12
	removeBtn.BackgroundColor3 = Color3.fromRGB(200, 52, 45)
	removeBtn.Parent = row
	roundify(removeBtn, 6)
	stroke(removeBtn, COLORS.Shadow, 1)

	local dropdown = Instance.new("ScrollingFrame")
	dropdown.Size = UDim2.new(0.45, -6, 0, 180)
	dropdown.Position = UDim2.new(0, 6, 1, 2)
	dropdown.BackgroundColor3 = COLORS.BrownDark
	dropdown.Visible = false
	dropdown.Parent = row
	dropdown.ScrollBarThickness = 6
	dropdown.AutomaticCanvasSize = Enum.AutomaticSize.Y
	dropdown.CanvasSize = UDim2.new(0, 0, 0, 0)
	dropdown.ScrollingDirection = Enum.ScrollingDirection.Y
	roundify(dropdown, 6)
	stroke(dropdown, COLORS.Shadow, 2)
	dropdown.ZIndex = 50
	dropdown.ClipsDescendants = true

	local dropdownLayout = Instance.new("UIListLayout")
	dropdownLayout.Parent = dropdown
	dropdownLayout.Padding = UDim.new(0, 4)

	local function addPetOption(labelText)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -8, 0, 22)
		btn.Position = UDim2.new(0, 4, 0, 0)
		btn.Text = labelText
		btn.TextColor3 = COLORS.BeigeText
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.BackgroundColor3 = COLORS.BrownTile
		btn.Parent = dropdown
		roundify(btn, 4)
		stroke(btn, COLORS.Shadow, 1)
		btn.ZIndex = 51
		btn.MouseButton1Click:Connect(function()
			local labelNode, placeholderNode = getDropdownTextNodes(petBox)
			labelNode.Text = labelText
			placeholderNode.Visible = (labelNode.Text == "")
			entry.petText = labelText
			dropdown.Visible = false
			saveAutoBuySettings()
		end)
	end

	for _, entryItem in ipairs(petItems) do
		addPetOption(entryItem.displayName)
	end

	petBox.Activated:Connect(function()
		dropdown.Visible = true
	end)

	minBox.FocusLost:Connect(function()
		entry.minBaseWt = minBox.Text or ""
		saveAutoBuySettings()
	end)
	budgetBox.FocusLost:Connect(function()
		entry.maxBudget = budgetBox.Text or ""
		saveAutoBuySettings()
	end)

	removeBtn.MouseButton1Click:Connect(function()
		for i, e in ipairs(autoBuyEntries) do
			if e.id == entry.id then
				table.remove(autoBuyEntries, i)
				break
			end
		end
		row:Destroy()
		saveAutoBuySettings()
	end)

	task.wait()
	autoBuyList.CanvasSize = UDim2.new(0, 0, 0, autoBuyListLayout.AbsoluteContentSize.Y + 10)
end

addEntryBtn.MouseButton1Click:Connect(function()
	addAutoBuyEntry()
	saveAutoBuySettings()
end)

local function entryMatchesListing(entry, listingObj)
	local petType = normalizePetTypeInput(entry.petText)
	if not petType then
		return false
	end
	if listingObj.data.PetType ~= petType then
		return false
	end

	local minBaseWt = tonumber(entry.minBaseWt) or 0
	if minBaseWt > 0 then
		if not listingObj.baseWeight or listingObj.baseWeight < minBaseWt then
			return false
		end
	end

	local maxBudget = tonumber(entry.maxBudget)
	if not maxBudget then
		return false
	end
	if not listingObj.listingPrice or listingObj.listingPrice > maxBudget then
		return false
	end

	return true
end

local function collectBoothListings()
	local data = boothsReceiver:GetDataAsync()
	if not data or not data.Players then
		return {}
	end

	local entries = {}
	local localPlayerId = TradeBoothsData.getPlayerId(player)

	for playerId, playerData in pairs(data.Players) do
		if playerId ~= localPlayerId and playerData.Listings and playerData.Items then
			for listingUUID, listing in pairs(playerData.Listings) do
				if listing.ItemType == "Pet" then
					local item = playerData.Items[listing.ItemId]
					if item then
						local petData = item.PetData or {}
						local petType = item.PetType
						local age = petData.Level or 0

						local baseWeight = petData.BaseWeight
						local weight = nil
						if baseWeight then
							weight = PetUtilities:CalculateWeight(baseWeight, age, petType)
						end

						local ownerPlayer = resolvePlayerFromBoothId(playerId)
						if ownerPlayer then
							local listingObj = {
								id = listing.ItemId,
								type = listing.ItemType,
								data = item,
								listingOwner = ownerPlayer,
								listingUUID = listingUUID,
								listingPrice = listing.Price,
								age = age,
								baseWeight = baseWeight,
								weight = weight
							}
							table.insert(entries, listingObj)
						end
					end
				end
			end
		end
	end

	return entries
end

local function runAutoBuy(listings)
	if not autoBuyEnabled then
		return
	end

	for _, listingObj in ipairs(listings) do
		if not autoBuySeen[listingObj.listingUUID] then
			for _, entry in ipairs(autoBuyEntries) do
				if entryMatchesListing(entry, listingObj) then
					autoBuySeen[listingObj.listingUUID] = true
					autoBuyStatus.Text = "Auto-buy: " .. (ItemNameFinder(listingObj.data.PetType, "Pet") or "Pet")
					tryAutoBuyDirect(listingObj, contentFrame)
					break
				end
			end
		end
	end
end

local function startAutoBuyLoop()
	if autoBuyThread then
		task.cancel(autoBuyThread)
	end
	autoBuyThread = task.spawn(function()
		while autoBuyEnabled do
			local listings = collectBoothListings()
			runAutoBuy(listings)
			task.wait(parseAutoBuyInterval())
		end
	end)
end

local function stopAutoBuyLoop()
	if autoBuyThread then
		task.cancel(autoBuyThread)
		autoBuyThread = nil
	end
end

autoBuyToggle.MouseButton1Click:Connect(function()
	autoBuyEnabled = not autoBuyEnabled
	autoBuyToggle.Text = autoBuyEnabled and "Auto-buy: ON" or "Auto-buy: OFF"
	autoBuyToggle.BackgroundColor3 = autoBuyEnabled and COLORS.GreenLight or COLORS.BrownTile
	saveAutoBuySettings()
	if autoBuyEnabled then
		startAutoBuyLoop()
	else
		stopAutoBuyLoop()
	end
end)

autoBuyIntervalBox.FocusLost:Connect(function()
	saveAutoBuySettings()
end)

if settings.autoBuyEntries and #settings.autoBuyEntries > 0 then
	for _, entry in ipairs(settings.autoBuyEntries) do
		addAutoBuyEntry(entry)
	end
else
	addAutoBuyEntry()
end

if autoBuyEnabled then
	autoBuyToggle.Text = "Auto-buy: ON"
	autoBuyToggle.BackgroundColor3 = COLORS.GreenLight
	startAutoBuyLoop()
end

-- Filter bar (Pets tab)
local filterBar = Instance.new("Frame")
filterBar.Size = UDim2.new(1, -194, 0, 46)
filterBar.Position = UDim2.new(0, 186, 0, 6)
filterBar.BackgroundColor3 = COLORS.BrownDark
filterBar.Parent = petsTab
roundify(filterBar, 8)
stroke(filterBar, COLORS.Shadow, 1)
filterBar.ZIndex = 10
filterBar.ClipsDescendants = false
applySoftPanelGradient(filterBar)

local function makeDropdownButton(name, size, pos, placeholder)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = size
	btn.Position = pos
	btn.Text = ""
	btn.BackgroundColor3 = COLORS.BrownTile
	btn.Parent = filterBar
	roundify(btn, 6)
	stroke(btn, COLORS.Shadow, 1)
	btn.ZIndex = 11

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -12, 1, 0)
	label.Position = UDim2.new(0, 6, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = COLORS.BeigeText
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = btn

	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.Name = "Placeholder"
	placeholderLabel.Size = UDim2.new(1, -12, 1, 0)
	placeholderLabel.Position = UDim2.new(0, 6, 0, 0)
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.Text = placeholder
	placeholderLabel.TextColor3 = Color3.fromRGB(220, 210, 190)
	placeholderLabel.Font = Enum.Font.GothamBold
	placeholderLabel.TextSize = 14
	placeholderLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeholderLabel.Parent = btn

	return btn
end

local petBox = makeDropdownButton("PetFilter", UDim2.new(0, 200, 1, -12), UDim2.new(0, 8, 0, 6), "Pet")
local rarityBox = makeDropdownButton("RarityFilter", UDim2.new(0, 140, 1, -12), UDim2.new(0, 216, 0, 6), "Rarity")

local minWtBox  = Instance.new("TextBox")
minWtBox.Name = "MinBaseWt"
minWtBox.Size = UDim2.new(0, 110, 1, -12)
minWtBox.Position = UDim2.new(0, 366, 0, 6)
minWtBox.PlaceholderText = "Min BaseWt"
minWtBox.Text = ""
minWtBox.BackgroundColor3 = COLORS.BrownTile
minWtBox.TextColor3 = COLORS.BeigeText
minWtBox.PlaceholderColor3 = Color3.fromRGB(220, 210, 190)
minWtBox.Font = Enum.Font.GothamBold
minWtBox.TextSize = 14
minWtBox.ClearTextOnFocus = false
minWtBox.Parent = filterBar
roundify(minWtBox, 6)
stroke(minWtBox, COLORS.Shadow, 1)
minWtBox.ZIndex = 11

local maxWtBox  = Instance.new("TextBox")
maxWtBox.Name = "MaxBaseWt"
maxWtBox.Size = UDim2.new(0, 110, 1, -12)
maxWtBox.Position = UDim2.new(0, 486, 0, 6)
maxWtBox.PlaceholderText = "Max BaseWt"
maxWtBox.Text = ""
maxWtBox.BackgroundColor3 = COLORS.BrownTile
maxWtBox.TextColor3 = COLORS.BeigeText
maxWtBox.PlaceholderColor3 = Color3.fromRGB(220, 210, 190)
maxWtBox.Font = Enum.Font.GothamBold
maxWtBox.TextSize = 14
maxWtBox.ClearTextOnFocus = false
maxWtBox.Parent = filterBar
roundify(maxWtBox, 6)
stroke(maxWtBox, COLORS.Shadow, 1)
maxWtBox.ZIndex = 11

local sortBtn = Instance.new("TextButton")
sortBtn.Size = UDim2.new(0, 170, 1, -12)
sortBtn.Position = UDim2.new(1, -320, 0, 6)
sortBtn.Text = "Sort: Price (Desc)"
sortBtn.TextColor3 = Color3.new(1, 1, 1)
sortBtn.Font = Enum.Font.GothamBlack
sortBtn.TextSize = 14
sortBtn.BackgroundColor3 = COLORS.GreenLight
sortBtn.Parent = filterBar
roundify(sortBtn, 6)
stroke(sortBtn, COLORS.Shadow, 1)
sortBtn.ZIndex = 11

-- Pet dropdown
local petDropdown = Instance.new("ScrollingFrame")
petDropdown.Size = UDim2.new(0, 200, 0, 220)
petDropdown.Position = UDim2.new(0, 8, 1, -4)
petDropdown.BackgroundColor3 = COLORS.BrownDark
petDropdown.Visible = false
petDropdown.Parent = filterBar
petDropdown.ScrollBarThickness = 6
petDropdown.AutomaticCanvasSize = Enum.AutomaticSize.Y
petDropdown.CanvasSize = UDim2.new(0, 0, 0, 0)
petDropdown.ScrollingDirection = Enum.ScrollingDirection.Y
roundify(petDropdown, 6)
stroke(petDropdown, COLORS.Shadow, 2)
petDropdown.ZIndex = 50
petDropdown.ClipsDescendants = true

local petListLayout = Instance.new("UIListLayout")
petListLayout.Parent = petDropdown
petListLayout.Padding = UDim.new(0, 4)

local function addPetOption(labelText, petType)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -8, 0, 22)
	btn.Position = UDim2.new(0, 4, 0, 0)
	btn.Text = labelText
	btn.TextColor3 = COLORS.BeigeText
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.BackgroundColor3 = COLORS.BrownTile
	btn.Parent = petDropdown
	roundify(btn, 4)
	stroke(btn, COLORS.Shadow, 1)
	btn.ZIndex = 51
	btn.MouseButton1Click:Connect(function()
		local label, placeholder = getDropdownTextNodes(petBox)
		if petType then
			label.Text = labelText
			petBox:SetAttribute("PetType", petType)
		else
			label.Text = ""
			petBox:SetAttribute("PetType", nil)
		end
		placeholder.Visible = (label.Text == "")
		petDropdown.Visible = false
		buildListings()
	end)
end

addPetOption("Any", nil)
for _, entry in ipairs(petItems) do
	addPetOption(entry.displayName, entry.petType)
end

petBox.Activated:Connect(function()
	petDropdown.Visible = true
end)

-- Rarity dropdown
local rarityDropdown = Instance.new("ScrollingFrame")
rarityDropdown.Size = UDim2.new(0, 140, 0, 160)
rarityDropdown.Position = UDim2.new(0, 216, 1, -4)
rarityDropdown.BackgroundColor3 = COLORS.BrownDark
rarityDropdown.Visible = false
rarityDropdown.Parent = filterBar
rarityDropdown.ScrollBarThickness = 6
rarityDropdown.AutomaticCanvasSize = Enum.AutomaticSize.Y
rarityDropdown.CanvasSize = UDim2.new(0, 0, 0, 0)
rarityDropdown.ScrollingDirection = Enum.ScrollingDirection.Y
roundify(rarityDropdown, 6)
stroke(rarityDropdown, COLORS.Shadow, 2)
rarityDropdown.ZIndex = 50
rarityDropdown.ClipsDescendants = true

local rarityList = Instance.new("UIListLayout")
rarityList.Parent = rarityDropdown
rarityList.Padding = UDim.new(0, 4)

local rarities = { "Any", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine", "Prismatic" }
for _, r in ipairs(rarities) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -8, 0, 22)
	btn.Position = UDim2.new(0, 4, 0, 0)
	btn.Text = r
	btn.TextColor3 = COLORS.BeigeText
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.BackgroundColor3 = COLORS.BrownTile
	btn.Parent = rarityDropdown
	roundify(btn, 4)
	stroke(btn, COLORS.Shadow, 1)
	btn.ZIndex = 51
	btn.MouseButton1Click:Connect(function()
		local label, placeholder = getDropdownTextNodes(rarityBox)
		label.Text = (r == "Any") and "" or r
		placeholder.Visible = (label.Text == "")
		rarityDropdown.Visible = false
		buildListings()
	end)
end

rarityBox.Activated:Connect(function()
	rarityDropdown.Visible = true
end)

minWtBox.FocusLost:Connect(function()
	buildListings()
end)

maxWtBox.FocusLost:Connect(function()
	buildListings()
end)

-- Pets header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -194, 0, 24)
header.Position = UDim2.new(0, 186, 0, 58)
header.BackgroundTransparency = 1
header.Parent = petsTab
header.ZIndex = 5

local function headerLabel(text, size, pos)
	local lbl = Instance.new("TextLabel")
	lbl.Size = size
	lbl.Position = pos
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = COLORS.BeigeText
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 13
	lbl.Text = text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = header
	lbl.ZIndex = 6
end

headerLabel("Name",      UDim2.new(0.22, 0, 1, 0), UDim2.new(0, 0, 0, 0))
headerLabel("Rarity",    UDim2.new(0.12, 0, 1, 0), UDim2.new(0.22, 0, 0, 0))
headerLabel("Price",     UDim2.new(0.12, 0, 1, 0), UDim2.new(0.34, 0, 0, 0))
headerLabel("Age",       UDim2.new(0.10, 0, 1, 0), UDim2.new(0.46, 0, 0, 0))
headerLabel("BaseWt",    UDim2.new(0.12, 0, 1, 0), UDim2.new(0.56, 0, 0, 0))
headerLabel("Weight",    UDim2.new(0.14, 0, 1, 0), UDim2.new(0.68, 0, 0, 0))
headerLabel("Buy",       UDim2.new(0.12, 0, 1, 0), UDim2.new(0.86, 0, 0, 0))

-- Pets list
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, -194, 1, -98)
list.Position = UDim2.new(0, 186, 0, 82)
list.BackgroundColor3 = COLORS.BrownDark
list.ScrollBarThickness = 8
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = petsTab
roundify(list, 10)
stroke(list, COLORS.Shadow, 2)
list.ZIndex = 1
list.ClipsDescendants = true

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

-- Webhooks tab
webhookInput = Instance.new("TextBox")
webhookInput.Size = UDim2.new(0, 520, 0, 44)
webhookInput.Position = UDim2.new(0, 186, 0, 60)
webhookInput.PlaceholderText = "Discord webhook URL (local only)"
webhookInput.Text = settings.webhookUrl or ""
webhookInput.BackgroundColor3 = COLORS.BrownTile
webhookInput.TextColor3 = COLORS.BeigeText
webhookInput.PlaceholderColor3 = Color3.fromRGB(220, 210, 190)
webhookInput.Font = Enum.Font.GothamBold
webhookInput.TextSize = 14
webhookInput.ClearTextOnFocus = false
webhookInput.Parent = webhooksTab
roundify(webhookInput, 8)
stroke(webhookInput, COLORS.Shadow, 1)

local webhookSave = Instance.new("TextButton")
webhookSave.Size = UDim2.new(0, 120, 0, 44)
webhookSave.Position = UDim2.new(0, 714, 0, 60)
webhookSave.Text = "Save"
webhookSave.TextColor3 = Color3.new(1, 1, 1)
webhookSave.Font = Enum.Font.GothamBlack
webhookSave.TextSize = 14
webhookSave.BackgroundColor3 = COLORS.GreenLight
webhookSave.Parent = webhooksTab
applyGameButtonStyle(webhookSave)

local webhookStatus = Instance.new("TextLabel")
webhookStatus.Size = UDim2.new(1, -200, 0, 22)
webhookStatus.Position = UDim2.new(0, 186, 0, 110)
webhookStatus.Text = ""
webhookStatus.TextColor3 = Color3.fromRGB(180, 255, 180)
webhookStatus.BackgroundTransparency = 1
webhookStatus.Font = Enum.Font.GothamBold
webhookStatus.TextSize = 12
webhookStatus.TextXAlignment = Enum.TextXAlignment.Left
webhookStatus.Parent = webhooksTab

webhookSave.MouseButton1Click:Connect(function()
	local url = webhookInput.Text or ""
	playerGui:SetAttribute("WebhookUrl", url)
	webhookStatus.Text = url ~= "" and "Saved locally!" or "Cleared"
	settings.webhookUrl = url
	saveLocalSettings(settings)
end)

-- State
local sortMode = { key = "price", dir = "desc" }
local function parseNumber(text) return tonumber(text) end

local function clearList()
	for _, child in ipairs(list:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function addListingRow(listing)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 44)
	row.BackgroundColor3 = COLORS.BrownTile
	row.Parent = list
	roundify(row, 8)
	stroke(row, COLORS.Shadow, 1)
	row.ZIndex = 2

	local function makeLabel(size, pos)
		local lbl = Instance.new("TextLabel")
		lbl.Size = size
		lbl.Position = pos
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = COLORS.BeigeText
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 14
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row
		lbl.ZIndex = 3
		return lbl
	end

	local nameLabel       = makeLabel(UDim2.new(0.22,0,1,0), UDim2.new(0,0,0,0))
	local rarityLabel     = makeLabel(UDim2.new(0.12,0,1,0), UDim2.new(0.22,0,0,0))
	local priceLabel      = makeLabel(UDim2.new(0.12,0,1,0), UDim2.new(0.34,0,0,0))
	local ageLabel        = makeLabel(UDim2.new(0.10,0,1,0), UDim2.new(0.46,0,0,0))
	local baseWeightLabel = makeLabel(UDim2.new(0.12,0,1,0), UDim2.new(0.56,0,0,0))
	local weightLabel     = makeLabel(UDim2.new(0.14,0,1,0), UDim2.new(0.68,0,0,0))

	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0.12, 0, 0.8, 0)
	buyBtn.Position = UDim2.new(0.86, 0, 0.1, 0)
	buyBtn.Text = "Buy"
	buyBtn.TextColor3 = Color3.new(1, 1, 1)
	buyBtn.Font = Enum.Font.GothamBlack
	buyBtn.TextSize = 14
	buyBtn.BackgroundColor3 = COLORS.GreenLight
	buyBtn.Parent = row
	roundify(buyBtn, 6)
	stroke(buyBtn, COLORS.Shadow, 1)
	buyBtn.ZIndex = 3

	local itemName = ItemNameFinder(
		listing.data.Name or listing.data.ItemName or listing.data.PetType or "Unknown",
		listing.type
	)
	local rarity = ItemRarityFinder(itemName, listing.type)
	local rarityColor = GGStaticData.RarityColorMap[rarity] or COLORS.BeigeText

	nameLabel.Text = itemName
	rarityLabel.Text = rarity or "Unknown"
	rarityLabel.TextColor3 = rarityColor
	priceLabel.Text = listing.listingPrice and NumberUtil.Comma(listing.listingPrice) or "???"
	priceLabel.TextColor3 = Color3.fromRGB(160, 255, 190)

	local petData = listing.data.PetData or {}
	local petType = listing.data.PetType
	local age = petData.Level or 0

	local baseWeight = petData.BaseWeight
	local weight = nil
	if baseWeight then
		weight = PetUtilities:CalculateWeight(baseWeight, age, petType)
	end

	ageLabel.Text = tostring(age)
	baseWeightLabel.Text = baseWeight and (DecimalFormat(baseWeight) .. " KG") or "N/A"
	weightLabel.Text = weight and (DecimalFormat(weight) .. " KG") or "N/A"

	buyBtn.Activated:Connect(function()
		promptBuyWithRetry(listing, contentFrame)
	end)
end

function buildListings()
	clearList()

	local data = boothsReceiver:GetDataAsync()
	if not data or not data.Players then
		return
	end

	local entries = {}
	local localPlayerId = TradeBoothsData.getPlayerId(player)

	for playerId, playerData in pairs(data.Players) do
		if playerId ~= localPlayerId and playerData.Listings and playerData.Items then
			for listingUUID, listing in pairs(playerData.Listings) do
				if listing.ItemType == "Pet" then
					local item = playerData.Items[listing.ItemId]
					if item then
						local petData = item.PetData or {}
						local petType = item.PetType
						local age = petData.Level or 0

						local baseWeight = petData.BaseWeight
						local weight = nil
						if baseWeight then
							weight = PetUtilities:CalculateWeight(baseWeight, age, petType)
						end

						local ownerPlayer = resolvePlayerFromBoothId(playerId)
						if ownerPlayer then
							local listingObj = {
								id = listing.ItemId,
								type = listing.ItemType,
								data = item,
								listingOwner = ownerPlayer,
								listingUUID = listingUUID,
								listingPrice = listing.Price,
								age = age,
								baseWeight = baseWeight,
								weight = weight
							}
							table.insert(entries, listingObj)
						end
					end
				end
			end
		end
	end

	local rarityLabel, _ = getDropdownTextNodes(rarityBox)
	local rarityFilter = string.lower((rarityLabel and rarityLabel.Text or ""))
	local selectedPetType = petBox:GetAttribute("PetType")
	local minBaseWt = parseNumber(minWtBox.Text)
	local maxBaseWt = parseNumber(maxWtBox.Text)

	local filtered = {}
	for _, e in ipairs(entries) do
		local ok = true

		local itemName = ItemNameFinder(e.data.PetType or "", e.type)
		local rarity = ItemRarityFinder(itemName, e.type) or ""

		if selectedPetType and e.data.PetType ~= selectedPetType then
			ok = false
		end
		if rarityFilter ~= "" and string.lower(rarity) ~= rarityFilter then
			ok = false
		end
		if minBaseWt and (not e.baseWeight or e.baseWeight < minBaseWt) then ok = false end
		if maxBaseWt and (not e.baseWeight or e.baseWeight > maxBaseWt) then ok = false end

		if ok then table.insert(filtered, e) end
	end

	table.sort(filtered, function(a, b)
		local av, bv
		if sortMode.key == "price" then
			av, bv = a.listingPrice or 0, b.listingPrice or 0
		elseif sortMode.key == "age" then
			av, bv = a.age or 0, b.age or 0
		else
			av, bv = a.weight or 0, b.weight or 0
		end

		if sortMode.dir == "asc" then
			return av < bv
		else
			return av > bv
		end
	end)

	for _, listingObj in ipairs(filtered) do
		addListingRow(listingObj)
	end

	task.wait()
	list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
end

sortBtn.Activated:Connect(function()
	if sortMode.key == "price" and sortMode.dir == "desc" then
		sortMode = { key = "price", dir = "asc" }
	elseif sortMode.key == "price" and sortMode.dir == "asc" then
		sortMode = { key = "age", dir = "desc" }
	elseif sortMode.key == "age" and sortMode.dir == "desc" then
		sortMode = { key = "age", dir = "asc" }
	elseif sortMode.key == "age" and sortMode.dir == "asc" then
		sortMode = { key = "weight", dir = "desc" }
	elseif sortMode.key == "weight" and sortMode.dir == "desc" then
		sortMode = { key = "weight", dir = "asc" }
	else
		sortMode = { key = "price", dir = "desc" }
	end

	local label = sortMode.key == "price" and "Price" or (sortMode.key == "age" and "Age" or "Weight")
	local dir = sortMode.dir == "asc" and "Asc" or "Desc"
	sortBtn.Text = ("Sort: %s (%s)"):format(label, dir)

	buildListings()
end)

local blur = Lighting:FindFirstChild("PetMarketBlur") or Instance.new("BlurEffect")
blur.Name = "PetMarketBlur"
blur.Size = 0
blur.Parent = Lighting

openBtn.Activated:Connect(function()
	local saved = playerGui:GetAttribute("WebhookUrl")
	if webhookInput then
		webhookInput.Text = saved or webhookInput.Text
	end
	if marketFrame then
		marketFrame.Visible = true
	end
	blur.Size = 8
	pcall(function()
		buildListings()
	end)
end)

closeBtn.Activated:Connect(function()
	marketFrame.Visible = false
	blur.Size = 0
end)

-- Backpack watcher -> webhook
local function parseToolName(toolName)
	local name = toolName:match("^(.-)%s*%[") or toolName
	local weight = toolName:match("%[(%d+%.?%d*)%s*KG%]")
	local age = toolName:match("%[Age%s*(%d+)%]")
	return name, tonumber(weight), tonumber(age)
end

local function findMatchingPending(name)
	for i, entry in ipairs(pendingPurchases) do
		if entry.displayName == name then
			table.remove(pendingPurchases, i)
			return entry
		end
	end
	return nil
end

player.Backpack.ChildAdded:Connect(function(child)
	if not child:IsA("Tool") then
		return
	end

	local petName, weight, age = parseToolName(child.Name)
	local pending = findMatchingPending(petName)
	if not pending then
		return
	end

	local iconUrl = getPetIcon(pending.petType)
	local priceText = pending.price and NumberUtil.Comma(pending.price) or "N/A"

	local embed = {
		title = "✅ Purchase Confirmed",
		description = ("**%s** has been added to your inventory."):format(petName or "Pet"),
		color = 0x6EA8FF,
		fields = {
			{ name = "Pet", value = petName or "Unknown", inline = true },
			{ name = "Rarity", value = getRarityEmoji(pending.petType), inline = true },
			{ name = "Age", value = tostring(age or "N/A"), inline = true },
			{ name = "Weight", value = weight and (tostring(weight) .. " KG") or "N/A", inline = true },
			{ name = "Base Weight", value = pending.baseWeight and (tostring(pending.baseWeight) .. " KG") or "N/A", inline = true },
			{ name = "Price", value = "🟢 **" .. priceText .. "**", inline = true }
		},
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
	}

	if iconUrl then
		embed.thumbnail = { url = iconUrl }
	end

	sendWebhookEmbed(embed)
end)
