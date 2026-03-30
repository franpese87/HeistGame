--!strict
-- init.client.luau
-- Client entry point for HeistGame.
-- Boot order:
--   1. Wait for the Events folder created by init.server
--   2. Require + init all client modules
--   3. Start per-frame loops

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ---------------------------------------------------------------------------
-- 1. Wait for Events folder
-- ---------------------------------------------------------------------------

local Events = ReplicatedStorage:WaitForChild("Events")

local function getEvent(name: string): RemoteEvent
	return Events:WaitForChild(name) :: RemoteEvent
end

local events: { [string]: RemoteEvent } = {
	DetectionUpdated      = getEvent("DetectionUpdated"),
	AlarmTriggered        = getEvent("AlarmTriggered"),
	PhaseChanged          = getEvent("PhaseChanged"),
	ObjectiveUpdated      = getEvent("ObjectiveUpdated"),
	AllObjectivesComplete = getEvent("AllObjectivesComplete"),
	EscapeTimerSync       = getEvent("EscapeTimerSync"),
	MissionComplete       = getEvent("MissionComplete"),
	RequestInteract       = getEvent("RequestInteract"),
	InteractResult        = getEvent("InteractResult"),
	RequestStartMiniGame  = getEvent("RequestStartMiniGame"),
	MiniGameResult        = getEvent("MiniGameResult"),
	UpdateStealthState    = getEvent("UpdateStealthState"),
}

-- ---------------------------------------------------------------------------
-- 2. Require + init client modules
-- ---------------------------------------------------------------------------

local Client = script.Parent

local StealthHUD            = require(Client.StealthHUD)
local ObjectivesHUD         = require(Client.ObjectivesHUD)
local InteractionController = require(Client.InteractionController)
local SafeCrackingUI        = require(Client.SafeCrackingUI)
local HackingUI             = require(Client.HackingUI)

StealthHUD.init(events)
ObjectivesHUD.init(events)
InteractionController.init(events)
SafeCrackingUI.init(events)
HackingUI.init(events)

-- ---------------------------------------------------------------------------
-- Escape timer HUD
-- ---------------------------------------------------------------------------

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local EscapeTimer = require(Shared:WaitForChild("EscapeTimer"))

local _escapeTimerGui: ScreenGui
do
	local player    = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui        = Instance.new("ScreenGui")
	gui.Name         = "EscapeTimerHUD"
	gui.ResetOnSpawn = false
	gui.Enabled      = false
	gui.Parent       = playerGui

	local label            = Instance.new("TextLabel")
	label.Size             = UDim2.fromOffset(200, 50)
	label.Position         = UDim2.new(0.5, -100, 0, 10)
	label.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	label.BackgroundTransparency = 0.2
	label.Text             = "ESCAPE: 2:00"
	label.TextColor3       = Color3.fromRGB(255, 255, 255)
	label.Font             = Enum.Font.GothamBold
	label.TextSize         = 22
	label.BorderSizePixel  = 0
	label.Parent           = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)

	events.EscapeTimerSync.OnClientEvent:Connect(function(timeRemaining: number)
		local state = EscapeTimer.fromSync(timeRemaining)
		label.Text  = "ESCAPE: " .. EscapeTimer.format(state)
		gui.Enabled = true
	end)

	events.PhaseChanged.OnClientEvent:Connect(function(phase: string)
		if phase ~= "Escape" then gui.Enabled = false end
	end)

	_escapeTimerGui = gui
end

-- ---------------------------------------------------------------------------
-- 3. Per-frame loops
-- ---------------------------------------------------------------------------

local _stealthAccumulator = 0.0
local STEALTH_PUSH_RATE   = 0.1

local StealthSystem = require(Shared:WaitForChild("StealthSystem"))

RunService.RenderStepped:Connect(function(dt: number)
	InteractionController.tick()
	SafeCrackingUI.tick(dt)
	HackingUI.tick(dt)

	local player   = Players.LocalPlayer
	local char     = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid then
		local isCrouching = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		local noise       = StealthSystem.calculateNoise(humanoid.WalkSpeed, isCrouching)
		StealthHUD.setNoiseLevel(noise)

		_stealthAccumulator += dt
		if _stealthAccumulator >= STEALTH_PUSH_RATE then
			_stealthAccumulator = 0
			events.UpdateStealthState:FireServer(isCrouching, false, false)
		end
	end
end)

print("[HeistGame] Client initialised.")
