--!strict
-- HackingUI.luau
-- Modal mini-game: player clicks coloured wires in the correct order.
-- Server sends seed+timeLimit; result fires MiniGameResult.

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared            = ReplicatedStorage:WaitForChild("Shared")
local MiniGameValidator = require(Shared:WaitForChild("MiniGameValidator"))

local HackingUI = {}

-- ---------------------------------------------------------------------------
-- Wire colours and their RGB values
-- ---------------------------------------------------------------------------

local WIRE_RGB: { [string]: Color3 } = {
	red    = Color3.fromRGB(220, 50,  50),
	blue   = Color3.fromRGB(60,  100, 220),
	green  = Color3.fromRGB(50,  200, 80),
	yellow = Color3.fromRGB(230, 200, 30),
	white  = Color3.fromRGB(230, 230, 230),
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _gui: ScreenGui?
local _events: { [string]: RemoteEvent }?
local _seed: number         = 0
local _objectId: string     = ""
local _correctSeq: { string } = {}
local _currentStep: number  = 1
local _mistakes: number     = 0
local _timeLimit: number    = 25
local _timeRemaining: number = 0
local _active: boolean      = false

local _timerBar: Frame?
local _timerLabel: TextLabel?
local _seqFrames: { Frame } = {}
local _feedbackLabel: TextLabel?
local _mistakeLabels: { TextLabel } = {}
local MAX_MISTAKES = 2

-- ---------------------------------------------------------------------------
-- Build GUI
-- ---------------------------------------------------------------------------

local function buildGUI()
	local player    = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui         = Instance.new("ScreenGui")
	gui.Name          = "HackingUI"
	gui.ResetOnSpawn  = false
	gui.Enabled       = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent        = playerGui

	-- Backdrop
	local backdrop             = Instance.new("Frame")
	backdrop.Size              = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.BorderSizePixel   = 0
	backdrop.Parent            = gui

	-- Panel
	local panel                = Instance.new("Frame")
	panel.Name                 = "Panel"
	panel.Size                 = UDim2.fromOffset(380, 300)
	panel.Position             = UDim2.new(0.5, -190, 0.5, -150)
	panel.BackgroundColor3     = Color3.fromRGB(15, 25, 20)
	panel.BorderSizePixel      = 0
	panel.Parent               = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

	-- Title
	local title                = Instance.new("TextLabel")
	title.Size                 = UDim2.new(1, 0, 0, 30)
	title.Position             = UDim2.fromOffset(0, 10)
	title.BackgroundTransparency = 1
	title.Text                 = "BYPASS SECURITY"
	title.TextColor3           = Color3.fromRGB(80, 220, 140)
	title.Font                 = Enum.Font.GothamBold
	title.TextSize             = 17
	title.Parent               = panel

	local instruction          = Instance.new("TextLabel")
	instruction.Size           = UDim2.new(1, 0, 0, 18)
	instruction.Position       = UDim2.fromOffset(0, 40)
	instruction.BackgroundTransparency = 1
	instruction.Text           = "Connect wires in the correct order"
	instruction.TextColor3     = Color3.fromRGB(160, 160, 160)
	instruction.Font           = Enum.Font.Gotham
	instruction.TextSize       = 12
	instruction.Parent         = panel

	-- Timer bar
	local timerBg              = Instance.new("Frame")
	timerBg.Size               = UDim2.new(0.85, 0, 0, 8)
	timerBg.Position           = UDim2.new(0.075, 0, 0, 62)
	timerBg.BackgroundColor3   = Color3.fromRGB(40, 40, 40)
	timerBg.BorderSizePixel    = 0
	timerBg.Parent             = panel
	Instance.new("UICorner", timerBg).CornerRadius = UDim.new(0, 4)

	local timerBar             = Instance.new("Frame")
	timerBar.Size              = UDim2.fromScale(1, 1)
	timerBar.BackgroundColor3  = Color3.fromRGB(80, 220, 140)
	timerBar.BorderSizePixel   = 0
	timerBar.Parent            = timerBg
	Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0, 4)

	local timerLabel           = Instance.new("TextLabel")
	timerLabel.Size            = UDim2.new(1, 0, 0, 16)
	timerLabel.Position        = UDim2.fromOffset(0, 72)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text            = "25.0s"
	timerLabel.TextColor3      = Color3.fromRGB(160, 160, 160)
	timerLabel.Font            = Enum.Font.Gotham
	timerLabel.TextSize        = 12
	timerLabel.Parent          = panel

	-- Sequence display (shows which step we're on)
	local seqFrame = Instance.new("Frame")
	seqFrame.Size  = UDim2.new(0.9, 0, 0, 30)
	seqFrame.Position = UDim2.new(0.05, 0, 0, 92)
	seqFrame.BackgroundTransparency = 1
	seqFrame.Parent = panel

	_seqFrames = {}
	for i = 1, 4 do
		local dot              = Instance.new("Frame")
		dot.Size               = UDim2.fromOffset(28, 28)
		dot.Position           = UDim2.fromOffset((i - 1) * 40, 0)
		dot.BackgroundColor3   = Color3.fromRGB(50, 50, 50)
		dot.BorderSizePixel    = 0
		dot.Parent             = seqFrame
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		table.insert(_seqFrames, dot)
	end

	-- Mistake tracker
	local mistakeContainer = Instance.new("Frame")
	mistakeContainer.Size  = UDim2.fromOffset(100, 20)
	mistakeContainer.Position = UDim2.new(1, -110, 0, 95)
	mistakeContainer.BackgroundTransparency = 1
	mistakeContainer.Parent = panel

	_mistakeLabels = {}
	for i = 1, MAX_MISTAKES do
		local x        = Instance.new("TextLabel")
		x.Size         = UDim2.fromOffset(18, 18)
		x.Position     = UDim2.fromOffset((i - 1) * 24, 0)
		x.BackgroundTransparency = 1
		x.Text         = "✕"
		x.TextColor3   = Color3.fromRGB(80, 80, 80)
		x.Font         = Enum.Font.GothamBold
		x.TextSize     = 14
		x.Parent       = mistakeContainer
		table.insert(_mistakeLabels, x)
	end

	-- Wire buttons (5 wires, horizontal)
	local wireContainer = Instance.new("Frame")
	wireContainer.Size  = UDim2.new(0.9, 0, 0, 120)
	wireContainer.Position = UDim2.new(0.05, 0, 0, 130)
	wireContainer.BackgroundTransparency = 1
	wireContainer.Parent = panel

	local colours = MiniGameValidator.wireColours()
	for i, colourName in colours do
		local wireBtn              = Instance.new("TextButton")
		wireBtn.Name               = "Wire_" .. colourName
		wireBtn.Size               = UDim2.new(0.16, 0, 1, 0)
		wireBtn.Position           = UDim2.fromScale((i - 1) * 0.2, 0)
		wireBtn.BackgroundColor3   = WIRE_RGB[colourName] or Color3.fromRGB(150, 150, 150)
		wireBtn.Text               = colourName
		wireBtn.TextColor3         = Color3.fromRGB(255, 255, 255)
		wireBtn.Font               = Enum.Font.GothamBold
		wireBtn.TextSize           = 10
		wireBtn.BorderSizePixel    = 0
		wireBtn.Parent             = wireContainer
		Instance.new("UICorner", wireBtn).CornerRadius = UDim.new(0, 4)

		local cn = colourName  -- capture for closure
		wireBtn.MouseButton1Click:Connect(function()
			HackingUI._onWireClicked(cn)
		end)
	end

	-- Feedback
	local feedbackLabel        = Instance.new("TextLabel")
	feedbackLabel.Name         = "Feedback"
	feedbackLabel.Size         = UDim2.new(1, 0, 0, 20)
	feedbackLabel.Position     = UDim2.new(0, 0, 1, -30)
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.Text         = ""
	feedbackLabel.TextColor3   = Color3.fromRGB(255, 80, 80)
	feedbackLabel.Font         = Enum.Font.Gotham
	feedbackLabel.TextSize     = 13
	feedbackLabel.Parent       = panel

	_gui           = gui
	_timerBar      = timerBar
	_timerLabel    = timerLabel
	_feedbackLabel = feedbackLabel
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function HackingUI.init(events: { [string]: RemoteEvent })
	_events = events
	buildGUI()

	events.RequestStartMiniGame.OnClientEvent:Connect(function(
		gameType: string,
		objectId: string,
		seed: number,
		timeLimit: number
	)
		if gameType == "hack" then
			HackingUI.open(objectId, seed, timeLimit)
		end
	end)
end

function HackingUI.open(objectId: string, seed: number, timeLimit: number)
	_objectId      = objectId
	_seed          = seed
	_timeLimit     = timeLimit
	_timeRemaining = timeLimit
	_correctSeq    = MiniGameValidator.deriveHackSequence(seed)
	_currentStep   = 1
	_mistakes      = 0
	_active        = true

	-- Reset sequence dots
	for _, dot in _seqFrames do
		dot.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	end

	-- Reset mistake markers
	for _, x in _mistakeLabels do
		x.TextColor3 = Color3.fromRGB(80, 80, 80)
	end

	if _feedbackLabel then (_feedbackLabel :: TextLabel).Text = "" end
	if _timerBar then (_timerBar :: Frame).Size = UDim2.fromScale(1, 1) end
	if _gui then (_gui :: ScreenGui).Enabled = true end
end

function HackingUI.close()
	_active = false
	if _gui then (_gui :: ScreenGui).Enabled = false end
end

function HackingUI.tick(dt: number)
	if not _active then return end

	_timeRemaining = math.max(0, _timeRemaining - dt)

	local ratio = _timeRemaining / _timeLimit
	if _timerBar then
		(_timerBar :: Frame).Size = UDim2.fromScale(ratio, 1)
		local c = ratio > 0.4
			and Color3.fromRGB(80, 220, 140)
			or  Color3.fromRGB(220, 80, 50)
		(_timerBar :: Frame).BackgroundColor3 = c
	end
	if _timerLabel then
		(_timerLabel :: TextLabel).Text = string.format("%.1fs", _timeRemaining)
	end

	if _timeRemaining <= 0 then
		HackingUI._submit()
	end
end

-- ---------------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------------

function HackingUI._onWireClicked(colourName: string)
	if not _active then return end

	local expected = _correctSeq[_currentStep]

	if colourName == expected then
		-- Correct: light up the corresponding sequence dot
		local dot = _seqFrames[_currentStep]
		if dot then
			dot.BackgroundColor3 = WIRE_RGB[colourName] or Color3.fromRGB(200, 200, 200)
		end
		_currentStep += 1

		if _currentStep > #_correctSeq then
			HackingUI._submit()
		end
	else
		-- Wrong wire
		_mistakes += 1
		if _mistakeLabels[_mistakes] then
			_mistakeLabels[_mistakes].TextColor3 = Color3.fromRGB(220, 50, 50)
		end
		if _feedbackLabel then
			(_feedbackLabel :: TextLabel).Text = "Wrong wire! Start over."
		end
		-- Reset sequence progress but keep mistakes
		_currentStep = 1
		for _, dot in _seqFrames do
			dot.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		end

		if _mistakes > MAX_MISTAKES then
			HackingUI._submit()
		end
	end
end

function HackingUI._submit()
	if not _active then return end
	_active = false

	local ev = _events :: { [string]: RemoteEvent }
	ev.MiniGameResult:FireServer("hack", _objectId, {
		sequence = {},    -- server re-derives from seed; sequence is for client UX only
		mistakes = _mistakes,
	})

	HackingUI.close()
end

return HackingUI
