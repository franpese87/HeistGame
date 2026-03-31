--!strict
-- GameSession.luau
-- Single source of truth for all per-player and mission-level session state.
--
-- Dependency rule: this module only requires shared modules.
-- MissionManager, AlarmManager, SafeCrackingServer all require this module;
-- GameSession never requires any of them.
--
-- Owns PlayerAdded / PlayerRemoving — all other modules remove their own
-- listeners for those events after this refactor.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local GameState   = require(Shared:WaitForChild("GameState"))
local Objectives  = require(Shared:WaitForChild("Objectives"))
local EscapeTimer = require(Shared:WaitForChild("EscapeTimer"))
local Inventory   = require(Shared:WaitForChild("Inventory"))

-- ---------------------------------------------------------------------------
-- Exported types
-- ---------------------------------------------------------------------------

export type PlayerSession = {
	userId:         number,
	score:          number,
	isActive:       boolean,
	detectionCount: number,
	inventory:      Inventory.PlayerInventory,
}

export type MissionSession = {
	mission:         Objectives.MissionObjectives,
	escapeTimer:     EscapeTimer.TimerState?,
	escapeDuration:  number,
	totalScore:      number,
	alarmTriggered:  boolean,
	syncAccumulator: number,
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _players: { [number]: PlayerSession } = {}
local _mission: MissionSession?             = nil
local _initialised = false

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local GameSession = {}

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

--- Must be called once from init.server before any other module's init().
--- Wires PlayerAdded / PlayerRemoving so every module gets cleanup for free.
function GameSession.init()
	assert(not _initialised, "GameSession.init() called more than once")
	_initialised = true

	-- Handle any players already connected (defensive — server normally starts
	-- before any player can join, but good practice).
	for _, player in Players:GetPlayers() do
		GameSession.addPlayer(player.UserId)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		GameSession.addPlayer(player.UserId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		GameSession.removePlayer(player.UserId)
	end)
end

-- ---------------------------------------------------------------------------
-- Player session CRUD
-- ---------------------------------------------------------------------------

--- Creates a PlayerSession for userId. Safe to call for late-joining players.
function GameSession.addPlayer(userId: number)
	if _players[userId] then return end
	_players[userId] = {
		userId         = userId,
		score          = 0,
		isActive       = GameState.isHeistRunning(),
		detectionCount = 0,
		inventory      = Inventory.newInventory(),
	}
end

--- Removes all state for userId. Called automatically from PlayerRemoving.
function GameSession.removePlayer(userId: number)
	_players[userId] = nil
end

--- Returns the PlayerSession for userId, or nil if not present.
function GameSession.getPlayer(userId: number): PlayerSession?
	return _players[userId]
end

--- Returns a snapshot array of all current PlayerSessions.
function GameSession.getAllPlayers(): { PlayerSession }
	local result: { PlayerSession } = {}
	for _, session in _players do
		table.insert(result, session)
	end
	return result
end

-- ---------------------------------------------------------------------------
-- Per-player mutators
-- ---------------------------------------------------------------------------

--- Adds delta to a player's score and the mission total. No-ops if either
--- the player session or mission session does not exist.
function GameSession.addScore(userId: number, delta: number)
	local ps = _players[userId]
	if not ps then return end
	ps.score += delta
	if _mission then
		_mission.totalScore += delta
	end
end

--- Marks a player as no longer active (reached exit or disconnected mid-heist).
function GameSession.setPlayerInactive(userId: number)
	local ps = _players[userId]
	if ps then
		ps.isActive = false
	end
end

--- Marks all connected players as active and resets per-run counters.
--- Called at mission start.
function GameSession.activateAllPlayers()
	for _, ps in _players do
		ps.isActive       = true
		ps.score          = 0
		ps.detectionCount = 0
	end
end

--- Increments detection count for a player. Returns the new count.
function GameSession.incrementDetection(userId: number): number
	local ps = _players[userId]
	if not ps then return 0 end
	ps.detectionCount += 1
	return ps.detectionCount
end

--- Returns true when no PlayerSession has isActive == true.
function GameSession.noActivePlayers(): boolean
	for _, ps in _players do
		if ps.isActive then return false end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Mission session lifecycle
-- ---------------------------------------------------------------------------

--- Creates a fresh MissionSession and resets all per-player state.
--- Called from MissionManager.loadMission().
function GameSession.startMissionSession(
	mission: Objectives.MissionObjectives,
	escapeDuration: number
)
	_mission = {
		mission          = mission,
		escapeTimer      = nil,
		escapeDuration   = escapeDuration,
		totalScore       = 0,
		alarmTriggered   = false,
		syncAccumulator  = 0,
	}
	for _, ps in _players do
		ps.score          = 0
		ps.isActive       = false
		ps.detectionCount = 0
		ps.inventory      = Inventory.newInventory()
	end
end

--- Clears the current MissionSession. Called from MissionManager._endMission().
function GameSession.endMissionSession()
	_mission = nil
end

--- Returns the active MissionSession, or nil between missions.
function GameSession.getMission(): MissionSession?
	return _mission
end

-- ---------------------------------------------------------------------------
-- Mission-level mutators
-- ---------------------------------------------------------------------------

--- Starts the escape countdown. Called from MissionManager._startEscape().
function GameSession.startEscapeTimer()
	local ms = _mission
	assert(ms, "No active MissionSession")
	ms.escapeTimer = EscapeTimer.start(EscapeTimer.new(ms.escapeDuration))
end

--- Ticks the escape timer by dt. Returns (remaining, justExpired).
--- Returns (0, false) when there is no active timer.
function GameSession.tickEscapeTimer(dt: number): (number, boolean)
	local ms = _mission
	if not ms or not ms.escapeTimer then return 0, false end
	local newTimer, justExpired = EscapeTimer.tick(ms.escapeTimer, dt)
	ms.escapeTimer      = newTimer
	ms.syncAccumulator += dt
	return newTimer.remaining, justExpired
end

--- Returns true (and resets the accumulator) when a sync broadcast is due.
function GameSession.consumeSyncTick(interval: number): boolean
	local ms = _mission
	if not ms then return false end
	if ms.syncAccumulator >= interval then
		ms.syncAccumulator = 0
		return true
	end
	return false
end

--- Sets alarmTriggered on the MissionSession.
function GameSession.triggerAlarm()
	if _mission then
		_mission.alarmTriggered = true
	end
end

--- Returns whether the alarm has fired this mission.
function GameSession.isAlarmed(): boolean
	return _mission ~= nil and (_mission :: MissionSession).alarmTriggered
end

return GameSession
