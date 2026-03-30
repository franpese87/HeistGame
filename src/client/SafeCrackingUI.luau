--!strict
-- SafeCrackingUI.luau
-- Modal mini-game: player dials a 3-digit combination to crack a safe.
-- Controls: press digit buttons 1-9 in the correct sequence.
-- Server sends seed+timeLimit via RequestStartMiniGame; result fires MiniGameResult.

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared           = ReplicatedStorage:WaitForChild("Shared")
local MiniGameValidator = require(Shared:WaitForChild("MiniGameValidator"))

local SafeCrackingUI = {}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _gui: ScreenGui?
local _events: { [string]: RemoteEvent }?
local _currentSeed: number = 0
local _currentObjectId: string = ""
local _selected: { number } = {}
local _timeLimit: number   = 30
local _timeRemaining: number = 0
local _active: boolean     = false
local _timerLabel: TextLabel?
local _timerBar: Frame?
local _digitSlots: { TextLabel } = {}
local _feedbackLabel: TextLabel?
local _submitBtn: TextButton?

-- ---------------------------------------------------------------------------
-- Build GUI (hidden by default)
-- ---------------------------------------------------------------------------

local function buildGUI()
	local player    = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui         = Instance.new("ScreenGui")
	gui.Name          = "SafeCrackingUI"
	gui.ResetOnSpawn  = false
	gui.Enabled       = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent        = playerGui

	-- Full-screen backdrop
	local backdrop             = Instance.new("Frame")
	backdrop.Size              = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.BorderSizePixel   = 0
	backdrop.Parent            = gui

	-- Panel (centered)
	local panel                = Instance.new("Frame")
	panel.Name                 = "Panel"
	panel.Size                 = UDim2.fromOffset(340, 320)
	panel.Position             = UDim2.new(0.5, -170, 0.5, -160)
	panel.BackgroundColor3     = Color3.fromRGB(30, 30, 30)
	panel.BorderSizePixel      = 0
	panel.Parent               = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

	-- Title
	local title                = Instance.new("TextLabel")
	title.Size                 = UDim2.new(1, 0, 0, 32)
	title.Position             = UDim2.fromOffset(0, 10)
	title.BackgroundTransparency = 1
	title.Text                 = "CRACK THE SAFE"
	title.TextColor3           = Color3.fromRGB(255, 200, 50)
	title.Font                 = Enum.Font.GothamBold
	title.TextSize             = 18
	title.Parent               = panel

	-- Timer bar background
	local timerBg              = Instance.new("Frame")
	timerBg.Size               = UDim2.new(0.85, 0, 0, 8)
	timerBg.Position           = UDim2.new(0.075, 0, 0, 48)
	timerBg.BackgroundColor3   = Color3.fromRGB(60, 60, 60)
	timerBg.BorderSizePixel    = 0
	timerBg.Parent             = panel
	Instance.new("UICorner", timerBg).CornerRadius = UDim.new(0, 4)

	local timerBar             = Instance.new("Frame")
	timerBar.Name              = "TimerBar"
	timerBar.Size              = UDim2.fromScale(1, 1)
	timerBar.BackgroundColor3  = Color3.fromRGB(100, 200, 100)
	timerBar.BorderSizePixel   = 0
	timerBar.Parent            = timerBg
	Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0, 4)

	local timerLabel           = Instance.new("TextLabel")
	timerLabel.Name            = "TimerLabel"
	timerLabel.Size            = UDim2.new(1, 0, 0, 16)
	timerLabel.Position        = UDim2.fromOffset(0, 58)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text            = "30.0s"
	timerLabel.TextColor3      = Color3.fromRGB(180, 180, 180)
	timerLabel.Font            = Enum.Font.Gotham
	timerLabel.TextSize        = 12
	timerLabel.Parent          = panel

	-- 3 digit slots
	local slotsFrame = Instance.new("Frame")
	slotsFrame.Size  = UDim2.fromOffset(180, 50)
	slotsFrame.Position = UDim2.new(0.5, -90, 0, 80)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.Parent = panel

	_digitSlots = {}
	for i = 1, 3 do
		local slot              = Instance.new("Frame")
		slot.Size               = UDim2.fromOffset(50, 50)
		slot.Position           = UDim2.fromOffset((i - 1) * 60, 0)
		slot.BackgroundColor3   = Color3.fromRGB(50, 50, 50)
		slot.BorderSizePixel    = 0
		slot.Parent             = slotsFrame
		Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 6)

		local lbl               = Instance.new("TextLabel")
		lbl.Size                = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text                = "?"
		lbl.TextColor3          = Color3.fromRGB(200, 200, 200)
		lbl.Font                = Enum.Font.GothamBold
		lbl.TextSize            = 24
		lbl.Parent              = slot
		table.insert(_digitSlots, lbl)
	end

	-- Digit buttons (1-9) in a 3×3 grid
	local gridFrame  = Instance.new("Frame")
	gridFrame.Size   = UDim2.fromOffset(180, 180)
	gridFrame.Position = UDim2.new(0.5, -90, 0, 140)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = panel

	for i = 1, 9 do
		local col = ((i - 1) % 3)
		local row = math.floor((i - 1) / 3)

		local btn              = Instance.new("TextButton")
		btn.Name               = "Digit_" .. i
		btn.Size               = UDim2.fromOffset(54, 54)
		btn.Position           = UDim2.fromOffset(col * 60, row * 60)
		btn.BackgroundColor3   = Color3.fromRGB(60, 60, 80)
		btn.Text               = tostring(i)
		btn.TextColor3         = Color3.fromRGB(220, 220, 220)
		btn.Font               = Enum.Font.GothamBold
		btn.TextSize           = 20
		btn.BorderSizePixel    = 0
		btn.Parent             = gridFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

		btn.MouseButton1Click:Connect(function()
			SafeCrackingUI._onDigitPressed(i)
		end)
	end

	-- Feedback label
	local feedbackLabel        = Instance.new("TextLabel")
	feedbackLabel.Name         = "FeedbackLabel"
	feedbackLabel.Size         = UDim2.new(1, 0, 0, 20)
	feedbackLabel.Position     = UDim2.new(0, 0, 1, -50)
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.Text         = ""
	feedbackLabel.TextColor3   = Color3.fromRGB(255, 80, 80)
	feedbackLabel.Font         = Enum.Font.Gotham
	feedbackLabel.TextSize     = 13
	feedbackLabel.Parent       = panel

	-- Submit button
	local submitBtn            = Instance.new("TextButton")
	submitBtn.Name             = "SubmitBtn"
	submitBtn.Size             = UDim2.fromOffset(120, 32)
	submitBtn.Position         = UDim2.new(0.5, -60, 1, -38)
	submitBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
	submitBtn.Text             = "Confirm"
	submitBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	submitBtn.Font             = Enum.Font.GothamBold
	submitBtn.TextSize         = 14
	submitBtn.Active           = false
	submitBtn.BorderSizePixel  = 0
	submitBtn.Parent           = panel
	Instance.new("UICorner", submitBtn).CornerRadius = UDim.new(0, 6)

	submitBtn.MouseButton1Click:Connect(function()
		if #_selected == 3 then
			SafeCrackingUI._submit()
		end
	end)

	_gui          = gui
	_timerLabel   = timerLabel
	_timerBar     = timerBar
	_feedbackLabel = feedbackLabel
	_submitBtn    = submitBtn
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function SafeCrackingUI.init(events: { [string]: RemoteEvent })
	_events = events
	buildGUI()

	events.RequestStartMiniGame.OnClientEvent:Connect(function(
		gameType: string,
		objectId: string,
		seed: number,
		timeLimit: number
	)
		if gameType == "safe" then
			SafeCrackingUI.open(objectId, seed, timeLimit)
		end
	end)
end

function SafeCrackingUI.open(objectId: string, seed: number, timeLimit: number)
	_currentObjectId = objectId
	_currentSeed     = seed
	_timeLimit       = timeLimit
	_timeRemaining   = timeLimit
	_selected        = {}
	_active          = true

	-- Reset digit slots
	for _, lbl in _digitSlots do
		lbl.Text = "?"
		lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	end
	if _feedbackLabel then (_feedbackLabel :: TextLabel).Text = "" end
	if _submitBtn then (_submitBtn :: TextButton).Active = false end
	if _timerBar then (_timerBar :: Frame).Size = UDim2.fromScale(1, 1) end

	if _gui then (_gui :: ScreenGui).Enabled = true end
end

function SafeCrackingUI.close()
	_active = false
	if _gui then (_gui :: ScreenGui).Enabled = false end
end

--- Called each RenderStepped from init.client.
function SafeCrackingUI.tick(dt: number)
	if not _active then return end

	_timeRemaining = math.max(0, _timeRemaining - dt)

	local ratio = _timeRemaining / _timeLimit
	if _timerBar then
		(_timerBar :: Frame).Size = UDim2.fromScale(ratio, 1)
		local colour = ratio > 0.4
			and Color3.fromRGB(100, 200, 100)
			or  Color3.fromRGB(220, 80, 50)
		(_timerBar :: Frame).BackgroundColor3 = colour
	end
	if _timerLabel then
		(_timerLabel :: TextLabel).Text = string.format("%.1fs", _timeRemaining)
	end

	if _timeRemaining <= 0 then
		SafeCrackingUI._submit() -- submit with whatever is selected (will fail)
	end
end

-- ---------------------------------------------------------------------------
-- Internal handlers
-- ---------------------------------------------------------------------------

function SafeCrackingUI._onDigitPressed(digit: number)
	if not _active then return end
	if #_selected >= 3 then return end

	table.insert(_selected, digit)
	local slot = _digitSlots[#_selected]
	if slot then
		slot.Text = tostring(digit)
		slot.TextColor3 = Color3.fromRGB(255, 220, 80)
	end

	if #_selected == 3 then
		if _submitBtn then (_submitBtn :: TextButton).Active = true end
	end
end

function SafeCrackingUI._submit()
	if not _active then return end
	_active = false

	local ev = _events :: { [string]: RemoteEvent }
	ev.MiniGameResult:FireServer("safe", _currentObjectId, {
		combination = _selected,
	})

	SafeCrackingUI.close()
end

return SafeCrackingUI
