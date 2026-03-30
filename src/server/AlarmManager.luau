--!strict
-- AlarmManager.luau
-- Converts NPC detections into global game-phase consequences.
--
-- Integration with the NPC AI system (feature/npc_ai_system):
--   The existing Controller.lua transitions to CHASING when it spots a player.
--   To wire AlarmManager, add this call inside Controller's ALERTED→CHASING
--   transition block (after merging branches):
--
--       local AlarmManager = require(ServerScriptService.Server.AlarmManager)
--       AlarmManager.onNPCDetectedPlayer(self.id, targetPlayer)
--
--   Alternatively, fire a BindableEvent "NPCDetectedPlayer" from Controller.lua
--   and let AlarmManager listen to it — see AlarmManager.init() below.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameState  = require(Shared:WaitForChild("GameState"))

local AlarmManager = {}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local _alarmEvent: RemoteEvent?           = nil
local _phaseEvent: RemoteEvent?           = nil

-- How many unique players need to be "detected" before the alarm fires.
-- 1 means the first detection triggers it immediately.
local DETECTIONS_TO_TRIGGER = 1

local _detectionCount: { [number]: number } = {} -- userId → consecutive detections
local _alarmTriggered = false

-- Optional: BindableEvent bridge from NPC system (set up in init).
local _npcDetectedBridge: BindableEvent?  = nil

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Call from init.server after RemoteEvents are created.
--- npcDetectedBridge: optional BindableEvent that Controller.lua fires when
---   it transitions to CHASING. AlarmManager subscribes to it automatically.
function AlarmManager.init(
	alarmEvent: RemoteEvent,
	phaseEvent: RemoteEvent,
	npcDetectedBridge: BindableEvent?
)
	_alarmEvent = alarmEvent
	_phaseEvent = phaseEvent

	if npcDetectedBridge then
		_npcDetectedBridge = npcDetectedBridge
		npcDetectedBridge.Event:Connect(function(player: Player)
			AlarmManager.onNPCDetectedPlayer("npc", player)
		end)
	end

	-- Reset detection counters when a player leaves mid-heist
	Players.PlayerRemoving:Connect(function(player)
		_detectionCount[player.UserId] = nil
	end)
end

--- Called when an NPC confirms it is chasing a player (or when security
--- cameras detect the player on the server). npcId is for logging only.
function AlarmManager.onNPCDetectedPlayer(_npcId: string, player: Player)
	if _alarmTriggered then return end
	if not GameState.isHeistRunning() then return end

	local uid = player.UserId
	_detectionCount[uid] = (_detectionCount[uid] or 0) + 1

	if _detectionCount[uid] >= DETECTIONS_TO_TRIGGER then
		AlarmManager.triggerAlarm()
	end
end

--- Fires the alarm unconditionally. Transitions phase to "Alarmed".
--- Can be called directly from init.server for testing.
function AlarmManager.triggerAlarm()
	if _alarmTriggered then return end
	_alarmTriggered = true

	GameState.setPhase("Alarmed")

	if _alarmEvent then
		_alarmEvent:FireAllClients()
	end

	if _phaseEvent then
		_phaseEvent:FireAllClients("Alarmed")
	end
end

--- Resets alarm state (e.g. at start of new heist).
function AlarmManager.reset()
	_alarmTriggered  = false
	_detectionCount  = {}
end

--- Returns whether the alarm is currently active.
function AlarmManager.isAlarmed(): boolean
	return _alarmTriggered
end

return AlarmManager
