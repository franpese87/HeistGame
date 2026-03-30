--!strict
-- ObjectivesHUD.luau
-- Top-right panel listing mission objectives with real-time checkbox updates.
-- Optional objectives appear below a "BONUS" divider.
-- Completed rows get a strikethrough animation via TextLabel RichText.

local Players     = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local Objectives = require(Shared:WaitForChild("Objectives"))

local ObjectivesHUD = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

type RowData = {
	frame:    Frame,
	checkbox: TextLabel,
	desc:     TextLabel,
	counter:  TextLabel,
}

local _gui: ScreenGui?
local _rows: { [string]: RowData } = {}
local _panel: Frame?

-- ---------------------------------------------------------------------------
-- Build GUI
-- ---------------------------------------------------------------------------

local function makeRow(parent: Frame, obj: Objectives.Objective, yPos: number): RowData
	local row             = Instance.new("Frame")
	row.Name              = "Row_" .. obj.id
	row.Size              = UDim2.new(1, 0, 0, 24)
	row.Position          = UDim2.fromOffset(0, yPos)
	row.BackgroundTransparency = 1
	row.Parent            = parent

	local checkbox         = Instance.new("TextLabel")
	checkbox.Size          = UDim2.fromOffset(18, 18)
	checkbox.Position      = UDim2.fromOffset(6, 3)
	checkbox.BackgroundTransparency = 1
	checkbox.Text          = obj.completed and "☑" or "☐"
	checkbox.TextColor3    = Color3.fromRGB(200, 200, 200)
	checkbox.Font          = Enum.Font.Gotham
	checkbox.TextSize      = 14
	checkbox.Parent        = row

	local desc             = Instance.new("TextLabel")
	desc.Size              = UDim2.new(1, -80, 1, 0)
	desc.Position          = UDim2.fromOffset(28, 0)
	desc.BackgroundTransparency = 1
	desc.Text              = obj.description
	desc.TextColor3        = Color3.fromRGB(220, 220, 220)
	desc.Font              = Enum.Font.Gotham
	desc.TextSize          = 12
	desc.TextXAlignment    = Enum.TextXAlignment.Left
	desc.TextTruncate      = Enum.TextTruncate.AtEnd
	desc.Parent            = row

	local counter          = Instance.new("TextLabel")
	counter.Size           = UDim2.fromOffset(48, 18)
	counter.Position       = UDim2.new(1, -52, 0, 3)
	counter.BackgroundTransparency = 1
	counter.Text           = string.format("(%d/%d)", obj.progress, obj.required)
	counter.TextColor3     = Color3.fromRGB(160, 160, 160)
	counter.Font           = Enum.Font.Gotham
	counter.TextSize       = 11
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.Parent         = row

	return { frame = row, checkbox = checkbox, desc = desc, counter = counter }
end

local function buildPanel(mission: Objectives.MissionObjectives)
	local player    = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Clear previous GUI if any
	if _gui then (_gui :: ScreenGui):Destroy() end
	_rows  = {}

	local gui         = Instance.new("ScreenGui")
	gui.Name          = "ObjectivesHUD"
	gui.ResetOnSpawn  = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled       = false
	gui.Parent        = playerGui

	-- Panel: top-right
	local panel               = Instance.new("Frame")
	panel.Name                = "Panel"
	panel.Size                = UDim2.fromOffset(260, 10) -- grows with rows
	panel.Position            = UDim2.new(1, -270, 0, 10)
	panel.BackgroundColor3    = Color3.fromRGB(15, 15, 15)
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel     = 0
	panel.Parent              = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)

	-- Header
	local header           = Instance.new("TextLabel")
	header.Size            = UDim2.new(1, 0, 0, 24)
	header.Position        = UDim2.fromOffset(0, 4)
	header.BackgroundTransparency = 1
	header.Text            = "OBJECTIVES"
	header.TextColor3      = Color3.fromRGB(255, 200, 50)
	header.Font            = Enum.Font.GothamBold
	header.TextSize        = 13
	header.Parent          = panel

	local yPos = 30

	-- Mandatory objectives
	for _, obj in mission.objectives do
		if not obj.optional then
			_rows[obj.id] = makeRow(panel, obj, yPos)
			yPos += 26
		end
	end

	-- Optional divider + rows
	local hasOptional = false
	for _, obj in mission.objectives do
		if obj.optional then hasOptional = true; break end
	end

	if hasOptional then
		local divider           = Instance.new("Frame")
		divider.Size            = UDim2.new(0.9, 0, 0, 1)
		divider.Position        = UDim2.new(0.05, 0, 0, yPos + 4)
		divider.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		divider.BorderSizePixel = 0
		divider.Parent          = panel

		local bonusLabel         = Instance.new("TextLabel")
		bonusLabel.Size          = UDim2.new(1, 0, 0, 18)
		bonusLabel.Position      = UDim2.fromOffset(0, yPos + 8)
		bonusLabel.BackgroundTransparency = 1
		bonusLabel.Text          = "BONUS"
		bonusLabel.TextColor3    = Color3.fromRGB(180, 180, 180)
		bonusLabel.Font          = Enum.Font.GothamBold
		bonusLabel.TextSize      = 10
		bonusLabel.Parent        = panel

		yPos += 22

		for _, obj in mission.objectives do
			if obj.optional then
				_rows[obj.id] = makeRow(panel, obj, yPos)
				yPos += 26
			end
		end
	end

	panel.Size = UDim2.fromOffset(260, yPos + 8)
	_gui   = gui
	_panel = panel
end

-- ---------------------------------------------------------------------------
-- Update helpers
-- ---------------------------------------------------------------------------

local function updateRow(objectiveId: string, progress: number, required: number, completed: boolean)
	local row = _rows[objectiveId]
	if not row then return end

	row.counter.Text = string.format("(%d/%d)", progress, required)

	if completed then
		row.checkbox.Text      = "☑"
		row.checkbox.TextColor3 = Color3.fromRGB(80, 200, 80)
		-- Fade description to grey
		TweenService:Create(row.desc, TweenInfo.new(0.4), {
			TextColor3 = Color3.fromRGB(100, 100, 100)
		}):Play()
		TweenService:Create(row.counter, TweenInfo.new(0.4), {
			TextColor3 = Color3.fromRGB(80, 80, 80)
		}):Play()
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function ObjectivesHUD.init(events: { [string]: RemoteEvent })
	events.PhaseChanged.OnClientEvent:Connect(function(phase: string, payload: any?)
		if phase == "Active" or phase == "Planning" then
			if payload and payload.objectives then
				-- Reconstruct a minimal MissionObjectives from the payload
				local mission: Objectives.MissionObjectives = {
					missionId  = payload.missionId or "unknown",
					objectives = payload.objectives,
				}
				buildPanel(mission)
			end
			if _gui then
				(_gui :: ScreenGui).Enabled = (phase == "Active")
			end

		elseif phase == "Alarmed" or phase == "Escape" then
			if _gui then (_gui :: ScreenGui).Enabled = true end

		elseif phase == "Lobby" or phase == "Complete" then
			if _gui then (_gui :: ScreenGui).Enabled = false end
		end
	end)

	events.ObjectiveUpdated.OnClientEvent:Connect(function(
		objectiveId: string,
		progress: number,
		completed: boolean
	)
		-- Find required count from existing row data (progress label already shows it)
		local row = _rows[objectiveId]
		if row then
			-- Parse current required from counter text "(x/y)"
			local required = tonumber(row.counter.Text:match("%d+$")) or 1
			updateRow(objectiveId, progress, required, completed)
		end
	end)

	events.AllObjectivesComplete.OnClientEvent:Connect(function()
		-- Show a brief "All objectives complete!" banner
		if not _panel then return end
		local banner           = Instance.new("TextLabel")
		banner.Size            = UDim2.new(1, 0, 0, 22)
		banner.Position        = UDim2.new(0, 0, 1, 4)
		banner.BackgroundTransparency = 1
		banner.Text            = "ESCAPE NOW!"
		banner.TextColor3      = Color3.fromRGB(255, 80, 80)
		banner.Font            = Enum.Font.GothamBold
		banner.TextSize        = 13
		banner.Parent          = _panel :: Frame
	end)
end

return ObjectivesHUD
