--!strict
-- MissionManager.luau
-- Central orchestrator of a heist session.
-- Loads objectives, tracks progress, transitions GameState phases,
-- drives the EscapeTimer, and tallies loot score.
--
-- Per-player state (scores, active flags) and mission-level state
-- (timer, alarm, totalScore) live in GameSession. MissionManager reads
-- and mutates them through GameSession's API.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameState   = require(Shared:WaitForChild("GameState"))
local Objectives  = require(Shared:WaitForChild("Objectives"))

local GameSession = require(script.Parent.GameSession)

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
-- (Only wiring/config that has no place in GameSession lives here.)
-- ---------------------------------------------------------------------------

local _remotes: RemoteTable? = nil

-- Item id → loot score value
local LOOT_SCORES: { [string]: number } = {
	cash_bag   = 500,
	jewel      = 300,
	painting   = 800,
	hard_drive = 400,
}

-- How often (seconds) to broadcast EscapeTimerSync
local TIMER_SYNC_INTERVAL = 1.0

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

local function ensureMission(): GameSession.MissionSession
	local ms = GameSession.getMission()
	assert(ms, "No active MissionSession")
	return ms :: GameSession.MissionSession
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Call from init.server after RemoteEvents are created.
--- PlayerAdded/PlayerRemoving are now owned by GameSession.init().
function MissionManager.init(remotes: RemoteTable)
	_remotes = remotes
end

--- Loads a mission by id and transitions to Planning phase.
--- escapeDuration: seconds the player has to reach the exit once
---   all mandatory objectives are complete.
function MissionManager.loadMission(missionId: string, escapeDuration: number?)
	local duration = escapeDuration or 120

	local mission: Objectives.MissionObjectives
	if missionId == "bank_job" then
		mission = Objectives.bankJob()
	elseif missionId == "art_heist" then
		mission = Objectives.artHeist()
	else
		error("Unknown missionId: " .. missionId)
	end

	GameSession.startMissionSession(mission, duration)
	GameState.setPhase("Planning")

	local r = ensureRemotes()
	local ms = ensureMission()
	fireAll(r.PhaseChanged, "Planning", {
		missionId  = ms.mission.missionId,
		objectives = ms.mission.objectives,
	})
end

--- Begins the active heist. Transitions phase to Active.
function MissionManager.startMission()
	local ms = ensureMission()
	GameState.setPhase("Active")
	GameSession.activateAllPlayers()

	local r = ensureRemotes()
	fireAll(r.PhaseChanged, "Active", {
		missionId  = ms.mission.missionId,
		objectives = ms.mission.objectives,
	})
end

--- Reports progress on an objective. Called by SafeCrackingServer,
--- interaction handlers, loot-pickup handler, etc. delta defaults to 1.
function MissionManager.reportObjectiveProgress(objectiveId: string, delta: number?)
	local ms = GameSession.getMission()
	if not ms then return end
	if not GameState.isHeistRunning() then return end

	for _, obj in ms.mission.objectives do
		if obj.id == objectiveId then
			local justCompleted = Objectives.advance(obj, delta or 1)
			local r = ensureRemotes()
			fireAll(r.ObjectiveUpdated, objectiveId, obj.progress, obj.completed)

			if justCompleted and Objectives.allMandatoryComplete(ms.mission) then
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
	GameSession.addScore(player.UserId, value)

	local ms = GameSession.getMission()
	if ms then
		for _, obj in ms.mission.objectives do
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

	GameSession.setPlayerInactive(player.UserId)

	if GameSession.noActivePlayers() then
		MissionManager._endMission("success")
	end
end

--- Per-frame update for the escape timer. Called by RunService.Heartbeat.
function MissionManager.tick(dt: number)
	local ms = GameSession.getMission()
	if not ms or not ms.escapeTimer then return end

	local remaining, justExpired = GameSession.tickEscapeTimer(dt)

	if GameSession.consumeSyncTick(TIMER_SYNC_INTERVAL) then
		local r = ensureRemotes()
		fireAll(r.EscapeTimerSync, remaining)
	end

	if justExpired then
		MissionManager._endMission("fail")
	end
end

--- Returns the current total score.
function MissionManager.getScore(): number
	local ms = GameSession.getMission()
	return if ms then ms.totalScore else 0
end

-- ---------------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------------

function MissionManager._startEscape()
	GameSession.startEscapeTimer()
	GameState.setPhase("Escape")

	local r = ensureRemotes()
	local ms = ensureMission()
	fireAll(r.AllObjectivesComplete)
	fireAll(r.PhaseChanged, "Escape")
	fireAll(r.EscapeTimerSync, ms.escapeDuration)
end

function MissionManager._endMission(outcome: "success" | "fail")
	local score = MissionManager.getScore()
	GameState.setPhase("Complete")
	GameSession.endMissionSession()

	local r = ensureRemotes()
	fireAll(r.PhaseChanged, "Complete", { outcome = outcome })
	fireAll(r.MissionComplete, score, outcome)
end

return MissionManager
