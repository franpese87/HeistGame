--!strict
-- GameState.luau
-- Central state machine for the heist. Tracks the current phase and
-- exposes helpers so both server and client can react to phase changes.

local GameState = {}

export type Phase =
	"Lobby"       -- waiting for players
	| "Planning"  -- pre-heist briefing / tool selection
	| "Active"    -- heist in progress, stealth possible
	| "Alarmed"   -- alarm triggered, guards alerted
	| "Escape"    -- objectives complete, reach the exit
	| "Complete"  -- all players escaped or caught

-- Internal state
local _phase: Phase = "Lobby"
local _listeners: { (Phase) -> () } = {}

--- Returns the current phase.
function GameState.getPhase(): Phase
	return _phase
end

--- Transitions to a new phase and notifies all listeners.
--- Only the server should call this; clients receive updates via RemoteEvents.
function GameState.setPhase(newPhase: Phase)
	if _phase == newPhase then return end
	_phase = newPhase
	for _, fn in _listeners do
		fn(newPhase)
	end
end

--- Register a callback that fires whenever the phase changes.
function GameState.onPhaseChanged(callback: (Phase) -> ())
	table.insert(_listeners, callback)
end

--- Returns true while a heist is actively running (Active or Alarmed).
function GameState.isHeistRunning(): boolean
	return _phase == "Active" or _phase == "Alarmed"
end

--- Returns true once the alarm has been triggered.
function GameState.isAlarmed(): boolean
	return _phase == "Alarmed" or _phase == "Escape"
end

return GameState
