--!strict
-- InteractionController.luau
-- Detects nearby interactable objects (tagged "Interactable" via CollectionService),
-- shows a BillboardGui prompt, and fires RequestInteract when E is pressed.
--
-- Each interactable Part must have these children:
--   StringValue "InteractionId"    — objectId sent to server (matches objective target)
--   StringValue "InteractionLabel" — text shown in the prompt (e.g. "Crack Safe")
--   StringValue "InteractionType"  — "safe" | "alarm_panel" | "camera" | "loot" | "exit"
--   StringValue "RequiredItem"     — optional: inventory item id required to interact

local CollectionService = game:GetService("CollectionService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameState  = require(Shared:WaitForChild("GameState"))
local Inventory  = require(Shared:WaitForChild("Inventory"))

local InteractionController = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local INTERACTION_RANGE = 8    -- studs
local INTERACTION_TAG   = "Interactable"

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _events: { [string]: RemoteEvent }?
local _currentTarget: BasePart?
local _pendingInteraction: boolean = false
local _cooldown: number            = 0   -- seconds remaining

-- Active BillboardGui attached to the current target
local _billboard: BillboardGui?

-- ---------------------------------------------------------------------------
-- Prompt helpers
-- ---------------------------------------------------------------------------

local function showPrompt(part: BasePart, label: string)
	if _billboard then
		(_billboard :: BillboardGui):Destroy()
		_billboard = nil
	end

	local bb                     = Instance.new("BillboardGui")
	bb.Name                      = "InteractionPrompt"
	bb.Size                      = UDim2.fromOffset(160, 40)
	bb.StudsOffset               = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop               = true
	bb.ResetOnSpawn              = false
	bb.Parent                    = part

	local bg                     = Instance.new("Frame")
	bg.Size                      = UDim2.fromScale(1, 1)
	bg.BackgroundColor3          = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency    = 0.3
	bg.BorderSizePixel           = 0
	bg.Parent                    = bb
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)

	local keyHint                = Instance.new("TextLabel")
	keyHint.Size                 = UDim2.fromOffset(28, 28)
	keyHint.Position             = UDim2.fromOffset(6, 6)
	keyHint.BackgroundColor3     = Color3.fromRGB(60, 60, 100)
	keyHint.Text                 = "E"
	keyHint.TextColor3           = Color3.fromRGB(255, 255, 255)
	keyHint.Font                 = Enum.Font.GothamBold
	keyHint.TextSize             = 14
	keyHint.BorderSizePixel      = 0
	keyHint.Parent               = bg
	Instance.new("UICorner", keyHint).CornerRadius = UDim.new(0, 4)

	local actionLabel            = Instance.new("TextLabel")
	actionLabel.Size             = UDim2.new(1, -44, 1, 0)
	actionLabel.Position         = UDim2.fromOffset(38, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Text             = label
	actionLabel.TextColor3       = Color3.fromRGB(230, 230, 230)
	actionLabel.Font             = Enum.Font.Gotham
	actionLabel.TextSize         = 13
	actionLabel.TextXAlignment   = Enum.TextXAlignment.Left
	actionLabel.TextTruncate     = Enum.TextTruncate.AtEnd
	actionLabel.Parent           = bg

	_billboard = bb
end

local function hidePrompt()
	if _billboard then
		(_billboard :: BillboardGui):Destroy()
		_billboard = nil
	end
end

-- ---------------------------------------------------------------------------
-- Helper: get a StringValue child from a part
-- ---------------------------------------------------------------------------

local function getStringValue(part: BasePart, name: string): string?
	local sv = part:FindFirstChild(name)
	if sv and sv:IsA("StringValue") then
		return (sv :: StringValue).Value
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function InteractionController.init(events: { [string]: RemoteEvent })
	_events = events

	-- Handle E key press
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode ~= Enum.KeyCode.E then return end
		InteractionController._onEPressed()
	end)

	-- Handle server response
	events.InteractResult.OnClientEvent:Connect(function(
		objectId: string,
		success: boolean,
		reason: string?
	)
		_pendingInteraction = false
		if not success and reason then
			-- Show brief error feedback via the billboard
			if _currentTarget then
				showPrompt(_currentTarget :: BasePart, reason)
				task.delay(2, function()
					-- Restore normal prompt if still on same target
					if _currentTarget then
						local label = getStringValue(
							_currentTarget :: BasePart, "InteractionLabel"
						) or "Interact"
						showPrompt(_currentTarget :: BasePart, label)
					end
				end)
			end
		end
	end)
end

--- Called each RenderStepped from init.client.
--- Finds the nearest interactable within INTERACTION_RANGE.
function InteractionController.tick()
	local dt = 1 / 60   -- approximate; full dt not needed for range checks
	if _cooldown > 0 then _cooldown -= dt end

	if not GameState.isHeistRunning() then
		hidePrompt()
		_currentTarget = nil
		return
	end

	local player   = Players.LocalPlayer
	local char     = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		hidePrompt()
		_currentTarget = nil
		return
	end

	local playerPos  = rootPart.Position
	local nearest: BasePart? = nil
	local nearestDist = INTERACTION_RANGE

	for _, part in CollectionService:GetTagged(INTERACTION_TAG) do
		if not part:IsA("BasePart") then continue end
		local dist = (part.Position - playerPos).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = part :: BasePart
		end
	end

	if nearest ~= _currentTarget then
		hidePrompt()
		_currentTarget = nearest

		if nearest then
			local label = getStringValue(nearest, "InteractionLabel") or "Interact"
			showPrompt(nearest, label)
		end
	end
end

function InteractionController._onEPressed()
	local target = _currentTarget
	if not target then return end
	if _pendingInteraction then return end
	if _cooldown > 0 then return end

	local objectId   = getStringValue(target, "InteractionId") or target.Name
	local objectType = getStringValue(target, "InteractionType") or "unknown"

	_pendingInteraction = true
	_cooldown = 0.5  -- brief debounce

	local ev = _events :: { [string]: RemoteEvent }
	ev.RequestInteract:FireServer(objectType, objectId)
end

return InteractionController
