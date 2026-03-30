--!strict
-- SafeCrackingServer.luau
-- Server-side handler for safe-cracking and hacking mini-games.
-- Generates seeds, sends challenges to clients, validates submissions.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Shared             = ReplicatedStorage:WaitForChild("Shared")
local MiniGameValidator  = require(Shared:WaitForChild("MiniGameValidator"))
local Inventory          = require(Shared:WaitForChild("Inventory"))
local GameState          = require(Shared:WaitForChild("GameState"))

local SafeCrackingServer = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

type PendingSession = {
	player:      Player,
	objectId:    string,
	gameType:    "safe" | "hack",
	seed:        number,
	timeLimit:   number,
	openedAt:    number,   -- os.clock() snapshot
}

type RemoteTable = {
	InteractResult:       RemoteEvent,
	RequestStartMiniGame: RemoteEvent,
	MiniGameResult:       RemoteEvent,
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _remotes: RemoteTable? = nil
local _missionManager: any?  = nil

-- Active sessions keyed by objectId (one player per object at a time)
local _sessions: { [string]: PendingSession } = {}

-- Retry cooldowns: userId → os.clock() when they may retry
local _cooldowns: { [number]: number } = {}

local SAFE_TIME_LIMIT    = 30  -- seconds
local HACK_TIME_LIMIT    = 25
local RETRY_COOLDOWN     = 3   -- seconds before a player can retry after failure

-- Tool required per interaction type
local REQUIRED_TOOL: { [string]: string } = {
	safe           = "drill",
	alarm_panel    = "hack_device",
	camera         = "hack_device",
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Call from init.server.
function SafeCrackingServer.init(remotes: RemoteTable, missionManager: any)
	_remotes        = remotes
	_missionManager = missionManager

	remotes.MiniGameResult.OnServerEvent:Connect(
		SafeCrackingServer._onMiniGameResult
	)
end

--- Opens a mini-game session for a player on a specific object.
--- Called from the InteractRequest handler in init.server.
--- gameType: "safe" | "hack"
function SafeCrackingServer.openSession(player: Player, objectId: string, gameType: "safe" | "hack")
	if not GameState.isHeistRunning() then return end

	-- Check cooldown
	local now = os.clock()
	local cooldownEnd = _cooldowns[player.UserId] or 0
	if now < cooldownEnd then
		local r = _remotes :: RemoteTable
		r.InteractResult:FireClient(player, objectId, false,
			string.format("Wait %.1f seconds", cooldownEnd - now))
		return
	end

	-- Only one session per object at a time
	if _sessions[objectId] then
		local r = _remotes :: RemoteTable
		r.InteractResult:FireClient(player, objectId, false, "Already in use")
		return
	end

	-- Build session
	local timeLimit = if gameType == "safe" then SAFE_TIME_LIMIT else HACK_TIME_LIMIT
	local seed      = math.random(1, 2 ^ 30)

	_sessions[objectId] = {
		player   = player,
		objectId = objectId,
		gameType = gameType,
		seed     = seed,
		timeLimit = timeLimit,
		openedAt = now,
	}

	local r = _remotes :: RemoteTable
	r.RequestStartMiniGame:FireClient(player, gameType, objectId, seed, timeLimit)
end

-- ---------------------------------------------------------------------------
-- Internal handlers
-- ---------------------------------------------------------------------------

--- Handles MiniGameResult from the client.
function SafeCrackingServer._onMiniGameResult(
	player: Player,
	gameType: string,
	objectId: string,
	payload: { [string]: any }
)
	local session = _sessions[objectId]
	if not session or session.player ~= player then return end

	-- Validate server-side elapsed time (don't trust the client's value)
	local serverElapsed = os.clock() - session.openedAt
	local timeLimit     = session.timeLimit

	local result: MiniGameValidator.ValidationResult

	if gameType == "safe" then
		local attempt: MiniGameValidator.SafeAttempt = {
			seed            = session.seed,
			combination     = payload.combination or {},
			elapsedSeconds  = serverElapsed,
		}
		result = MiniGameValidator.validateSafe(attempt, timeLimit)
	else
		local attempt: MiniGameValidator.HackAttempt = {
			seed           = session.seed,
			sequence       = payload.sequence or {},
			elapsedSeconds = serverElapsed,
			mistakes       = payload.mistakes or 0,
		}
		result = MiniGameValidator.validateHack(attempt, timeLimit, nil)
	end

	_sessions[objectId] = nil

	local r = _remotes :: RemoteTable

	if result.success then
		SafeCrackingServer._unlockObject(objectId)
		if _missionManager then
			-- Find and advance the objective matching this object
			_missionManager.reportObjectiveProgress(objectId)
		end
		r.InteractResult:FireClient(player, objectId, true, nil)
	else
		_cooldowns[player.UserId] = os.clock() + RETRY_COOLDOWN
		r.InteractResult:FireClient(player, objectId, false, result.reason)
	end
end

--- Visually unlocks/opens the object tagged with objectId in the workspace.
--- Expects the model to be tagged via CollectionService with the objectId string.
--- Attempts a simple door-like rotation tween if a PrimaryPart is present.
function SafeCrackingServer._unlockObject(objectId: string)
	for _, instance in CollectionService:GetTagged(objectId) do
		if not instance:IsA("Model") then continue end
		local model = instance :: Model

		-- Set an "Unlocked" BoolValue if present (for game logic elsewhere)
		local flag = model:FindFirstChild("Unlocked")
		if flag and flag:IsA("BoolValue") then
			(flag :: BoolValue).Value = true
		end

		-- Simple open animation: tween the primary part's CFrame by 90° on Y
		local primary = model.PrimaryPart
		if primary then
			local goal = { CFrame = primary.CFrame * CFrame.Angles(0, math.rad(90), 0) }
			TweenService:Create(primary, TweenInfo.new(0.5, Enum.EasingStyle.Quad), goal):Play()
		end
	end
end

return SafeCrackingServer
