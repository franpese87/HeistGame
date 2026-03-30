--!strict
-- EscapeTimer.luau
-- Countdown timer that starts once all mandatory objectives are complete.
-- The server owns the authoritative TimerState; clients receive sync ticks
-- via the EscapeTimerSync RemoteEvent and use this module only for display.

local EscapeTimer = {}

export type TimerState = {
	duration: number,       -- total seconds configured at start
	remaining: number,      -- seconds left (authoritative on server)
	running: boolean,
	expired: boolean,
}

--- Creates a new timer ready to run.
function EscapeTimer.new(duration: number): TimerState
	return {
		duration  = duration,
		remaining = duration,
		running   = false,
		expired   = false,
	}
end

--- Starts the timer (sets running = true).
function EscapeTimer.start(state: TimerState): TimerState
	local s = table.clone(state)
	s.running = true
	return s
end

--- Advances the timer by dt seconds (immutable: returns a new state).
--- Returns true as a second value if the timer just expired this tick.
function EscapeTimer.tick(state: TimerState, dt: number): (TimerState, boolean)
	if not state.running or state.expired then
		return state, false
	end
	local s = table.clone(state)
	s.remaining = math.max(0, state.remaining - dt)
	local justExpired = s.remaining <= 0 and not state.expired
	if justExpired then
		s.expired = true
		s.running = false
	end
	return s, justExpired
end

--- Builds a display-only state from a server sync packet (client use).
function EscapeTimer.fromSync(timeRemaining: number): TimerState
	return {
		duration  = timeRemaining, -- not meaningful on client
		remaining = timeRemaining,
		running   = true,
		expired   = timeRemaining <= 0,
	}
end

--- Formats remaining time as "M:SS".
function EscapeTimer.format(state: TimerState): string
	local secs = math.ceil(state.remaining)
	local m    = math.floor(secs / 60)
	local s    = secs % 60
	return string.format("%d:%02d", m, s)
end

return EscapeTimer
