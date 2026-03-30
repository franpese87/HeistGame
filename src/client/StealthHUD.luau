--!strict
-- StealthHUD.luau
-- Persistent detection-level bar shown in the bottom-right corner.
-- Colour-coded by tier; includes a noise pulse indicator.

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local StealthSystem = require(Shared:WaitForChild("StealthSystem"))
local GameState     = require(Shared:WaitForChild("GameState"))

local StealthHUD = {}

-- ---------------------------------------------------------------------------
-- Colours per detection tier
-- ---------------------------------------------------------------------------

local TIER_COLOURS: { [StealthSystem.DetectionTier]: Color3 } = {
	Undetected = Color3.fromRGB(80,  200, 80),
	Suspicious = Color3.fromRGB(220, 180,  0),
	Spotted    = Color3.fromRGB(220, 100, 20),
	Caught     = Color3.fromRGB(200,  30, 30),
}

local TIER_LABELS: { [StealthSystem.DetectionTier]: string } = {
	Undetected = "UNDETECTED",
	Suspicious = "SUSPICIOUS",
	Spotted    = "SPOTTED",
	Caught     = "CAUGHT",
}

-- ---------------------------------------------------------------------------
-- GUI construction
-- ---------------------------------------------------------------------------

local _gui: ScreenGui?
local _barFill: Frame?
local _tierLabel: TextLabel?
local _noiseFrame: Frame?
local _alarmOverlay: Frame?

local function buildGUI()
	local player   = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui         = Instance.new("ScreenGui")
	gui.Name          = "StealthHUD"
	gui.ResetOnSpawn  = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent        = playerGui

	-- Container: bottom-right, 240×70 px
	local container         = Instance.new("Frame")
	container.Name          = "Container"
	container.Size          = UDim2.fromOffset(240, 70)
	container.Position      = UDim2.new(1, -260, 1, -90)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	container.BackgroundTransparency = 0.3
	container.BorderSizePixel = 0
	container.Parent        = gui
	Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)

	-- Tier label
	local tierLabel            = Instance.new("TextLabel")
	tierLabel.Name             = "TierLabel"
	tierLabel.Size             = UDim2.new(1, 0, 0.45, 0)
	tierLabel.Position         = UDim2.fromScale(0, 0)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text             = "UNDETECTED"
	tierLabel.TextColor3       = TIER_COLOURS.Undetected
	tierLabel.Font             = Enum.Font.GothamBold
	tierLabel.TextSize         = 13
	tierLabel.TextXAlignment   = Enum.TextXAlignment.Center
	tierLabel.Parent           = container

	-- Bar background
	local barBg               = Instance.new("Frame")
	barBg.Name                = "BarBackground"
	barBg.Size                = UDim2.new(0.9, 0, 0.28, 0)
	barBg.Position            = UDim2.new(0.05, 0, 0.5, 0)
	barBg.BackgroundColor3    = Color3.fromRGB(60, 60, 60)
	barBg.BorderSizePixel     = 0
	barBg.Parent              = container
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

	-- Bar fill
	local barFill             = Instance.new("Frame")
	barFill.Name              = "BarFill"
	barFill.Size              = UDim2.fromScale(0, 1)
	barFill.Position          = UDim2.fromScale(0, 0)
	barFill.BackgroundColor3  = TIER_COLOURS.Undetected
	barFill.BorderSizePixel   = 0
	barFill.Parent            = barBg
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

	-- Noise indicator (small pulsing circle on the right)
	local noiseFrame           = Instance.new("Frame")
	noiseFrame.Name            = "NoiseIndicator"
	noiseFrame.Size            = UDim2.fromOffset(14, 14)
	noiseFrame.Position        = UDim2.new(1, -20, 0.5, -7)
	noiseFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
	noiseFrame.BackgroundTransparency = 1  -- hidden when quiet
	noiseFrame.BorderSizePixel = 0
	noiseFrame.Parent          = container
	Instance.new("UICorner", noiseFrame).CornerRadius = UDim.new(1, 0)

	-- Alarm overlay (full-screen red flash)
	local alarmOverlay             = Instance.new("Frame")
	alarmOverlay.Name              = "AlarmOverlay"
	alarmOverlay.Size              = UDim2.fromScale(1, 1)
	alarmOverlay.BackgroundColor3  = Color3.fromRGB(200, 0, 0)
	alarmOverlay.BackgroundTransparency = 1
	alarmOverlay.BorderSizePixel   = 0
	alarmOverlay.ZIndex            = 10
	alarmOverlay.Visible           = false
	alarmOverlay.Parent            = gui

	_gui          = gui
	_barFill      = barFill
	_tierLabel    = tierLabel
	_noiseFrame   = noiseFrame
	_alarmOverlay = alarmOverlay
end

-- ---------------------------------------------------------------------------
-- Tween helpers
-- ---------------------------------------------------------------------------

local _fillTween: Tween?
local _colourTween: Tween?

local function updateBar(detection: number)
	local tier   = StealthSystem.getTier(detection)
	local colour = TIER_COLOURS[tier]
	local fill   = math.clamp(detection / 100, 0, 1)

	local fill_ = _barFill :: Frame
	local label = _tierLabel :: TextLabel

	if _fillTween then _fillTween:Cancel() end
	if _colourTween then _colourTween:Cancel() end

	local ti = TweenInfo.new(0.15, Enum.EasingStyle.Linear)
	_fillTween   = TweenService:Create(fill_, ti, { Size = UDim2.fromScale(fill, 1) })
	_colourTween = TweenService:Create(fill_, ti, { BackgroundColor3 = colour })
	_fillTween:Play()
	_colourTween:Play()

	label.Text        = TIER_LABELS[tier]
	label.TextColor3  = colour
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Call once from init.client.
function StealthHUD.init(events: { [string]: RemoteEvent })
	buildGUI()

	events.DetectionUpdated.OnClientEvent:Connect(function(detection: number)
		updateBar(detection)
	end)

	events.AlarmTriggered.OnClientEvent:Connect(function()
		StealthHUD._flashAlarm()
	end)

	events.PhaseChanged.OnClientEvent:Connect(function(phase: string)
		local visible = (phase == "Active" or phase == "Alarmed" or phase == "Escape")
		if _gui then (_gui :: ScreenGui).Enabled = visible end
	end)

	-- Start hidden until Active phase
	if _gui then (_gui :: ScreenGui).Enabled = false end
end

--- Update noise indicator (0-100). Called each frame from init.client.
function StealthHUD.setNoiseLevel(noise: number)
	local frame = _noiseFrame :: Frame
	if not frame then return end
	local transparency = 1 - math.clamp(noise / 100, 0, 1)
	frame.BackgroundTransparency = transparency
end

function StealthHUD._flashAlarm()
	local overlay = _alarmOverlay :: Frame
	overlay.Visible = true
	local ti = TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 3, true)
	TweenService:Create(overlay, ti, { BackgroundTransparency = 0.5 }):Play()
	task.delay(1.5, function()
		overlay.Visible = false
	end)
end

return StealthHUD
