--!strict
-- MissionManager.luau
-- Central orchestrator of a heist session.
-- Loads objectives, tracks progress, transitions GameState phases,
-- drives the EscapeTimer, and tallies loot score.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameState   = require(Shared:WaitForChild("GameState"))
local Objectives  = require(Shared:WaitForChild("Objectives"))
local EscapeTimer = require(Shared:WaitForChild("EscapeTimer"))
local Inventory   = require(Shared:WaitForChild("Inventory"))

local MissionManager = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

type RemoteTable = {
	PhaseChanged:          RemoteEvent,
	ObjectiveUpdated:      RemoteEvent,
	AllObjectivesComplete: RemoteEvent,
	EscapeTimerSync:       RemoteEvent,
	MissionComplete:       RemoteEvent,
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _remotes: RemoteTable?                        = nil
local _mission: Objectives.MissionObjectives?      = nil
local _escapeTimer: EscapeTimer.TimerState?        = nil
local _escapeDuration    = 120                      -- seconds
local _totalScore        = 0
local _playerScores: { [number]: number }          = {}

-- Item id → loot score value
local LOOT_SCORES: { [string]: number } = {
	cash_bag   = 500,
	jewel      = 300,
	painting   = 800,
	hard_drive = 400,
}

-- How often (seconds) to broadcast EscapeTimerSync
local TIMER_SYNC_INTERVAL = 1.0
local _syncAccumulator    = 0.0

-- Players currently in the heist (haven't escaped yet)
local _activePlayers: { [number]: boolean } = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function fireAll(event: RemoteEvent, ...)
	event:FireAllClients(...)
end

local function ensureRemotes(): RemoteTable
	assert(_remotes, "MissionManager.init() must be called first")
	return _remotes :: RemoteTable
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Call from init.server after RemoteEvents are created.
function MissionManager.init(remotes: RemoteTable)
	_remotes = remotes

	Players.PlayerAdded:Connect(function(player)
		_playerScores[player.UserId] = 0
		_activePlayers[player.UserId] = GameState.isHeistRunning()
	end)

	Players.PlayerRemoving:Connect(function(player)
		_playerScores[player.UserId] = nil
		_activePlayers[player.UserId] = nil
	end)
end

--- Loads a mission by id and transitions to Planning phase.
--- escapeDuration: seconds the player has to reach the exit once
---   all mandatory objectives are complete.
function MissionManager.loadMission(missionId: string, escapeDuration: number?)
	_escapeDuration = escapeDuration or 120

	if missionId == "bank_job" then
		_mission = Objectives.bankJob()
	elseif missionId == "art_heist" then
		_mission = Objectives.artHeist()
	else
		error("Unknown missionId: " .. missionId)
	end

	_totalScore     = 0
	_playerScores   = {}
	_activePlayers  = {}
	_escapeTimer    = nil
	_syncAccumulator = 0

	GameState.setPhase("Planning")

	local r = ensureRemotes()
	-- Payload includes the serialised objectives so the client HUD can populate.
	fireAll(r.PhaseChanged, "Planning", {
		missionId  = _mission.missionId,
		objectives = _mission.objectives,
	})
end

--- Begins the active heist. Transitions phase to Active.
function MissionManager.startMission()
	assert(_mission, "loadMission() must be called before startMission()")
	GameState.setPhase("Active")

	-- Register all current players as active
	for _, player in Players:GetPlayers() do
		_activePlayers[player.UserId] = true
		_playerScores[player.UserId]  = _playerScores[player.UserId] or 0
	end

	local r = ensureRemotes()
	fireAll(r.PhaseChanged, "Active", {
		missionId  = (_mission :: Objectives.MissionObjectives).missionId,
		objectives = (_mission :: Objectives.MissionObjectives).objectives,
	})
end

--- Reports progress on an objective. Called by SafeCrackingServer,
--- InteractionController handler, loot-pickup handler, etc.
--- delta defaults to 1.
function MissionManager.reportObjectiveProgress(objectiveId: string, delta: number?)
	local mission = _mission
	if not mission then return end
	if not GameState.isHeistRunning() then return end

	for _, obj in mission.objectives do
		if obj.id == objectiveId then
			local justCompleted = Objectives.advance(obj, delta or 1)
			local r = ensureRemotes()
			fireAll(r.ObjectiveUpdated, objectiveId, obj.progress, obj.completed)

			if justCompleted and Objectives.allMandatoryComplete(mission) then
				MissionManager._startEscape()
			end
			return
		end
	end
end

--- Reports that a player picked up a loot item.
--- Adds score and advances the matching "collect" objective if one exists.
function MissionManager.reportLootCollected(player: Player, itemId: string)
	local value = LOOT_SCORES[itemId] or 100
	_totalScore = _totalScore + value
	_playerScores[player.UserId] = (_playerScores[player.UserId] or 0) + value

	-- Try to advance a "collect" objective that targets this item
	local mission = _mission
	if mission then
		for _, obj in mission.objectives do
			if obj.objectiveType == "collect" and obj.target == itemId and not obj.completed then
				MissionManager.reportObjectiveProgress(obj.id)
				break
			end
		end
	end
end

--- Called when a player reaches the escape exit.
function MissionManager.onPlayerReachedExit(player: Player)
	if GameState.getPhase() ~= "Escape" then return end

	_activePlayers[player.UserId] = nil

	-- Check if all active players have escaped
	local anyLeft = false
	for _, active in _activePlayers do
		if active then
			anyLeft = true
			break
		end
	end

	if not anyLeft then
		MissionManager._endMission("success")
	end
end

--- Per-frame update for the escape timer. Called by RunService.Heartbeat.
function MissionManager.tick(dt: number)
	local timer = _escapeTimer
	if not timer then return end

	local newTimer, justExpired = EscapeTimer.tick(timer, dt)
	_escapeTimer = newTimer

	_syncAccumulator += dt
	if _syncAccumulator >= TIMER_SYNC_INTERVAL then
		_syncAccumulator = 0
		local r = ensureRemotes()
		fireAll(r.EscapeTimerSync, newTimer.remaining)
	end

	if justExpired then
		MissionManager._endMission("fail")
	end
end

--- Returns the current total score.
function MissionManager.getScore(): number
	return _totalScore
end

-- ---------------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------------

function MissionManager._startEscape()
	_escapeTimer = EscapeTimer.start(EscapeTimer.new(_escapeDuration))
	GameState.setPhase("Escape")

	local r = ensureRemotes()
	fireAll(r.AllObjectivesComplete)
	fireAll(r.PhaseChanged, "Escape")
	fireAll(r.EscapeTimerSync, _escapeDuration)
end

function MissionManager._endMission(outcome: "success" | "fail")
	GameState.setPhase("Complete")
	_escapeTimer = nil

	local r = ensureRemotes()
	fireAll(r.PhaseChanged, "Complete", { outcome = outcome })
	fireAll(r.MissionComplete, _totalScore, outcome)
end

return MissionManager
