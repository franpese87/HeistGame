--!strict
-- MiniGameValidator.luau
-- Deterministic validation for safe-cracking and hacking mini-games.
-- Runs identically on server (authoritative) and client (immediate feedback).
-- Uses a simple LCG so both sides derive the same answer from the same seed.

local MiniGameValidator = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type SafeAttempt = {
	seed: number,
	combination: { number }, -- 3 digits 1-9 chosen by the player
	elapsedSeconds: number,  -- client-reported, re-checked server-side
}

export type HackAttempt = {
	seed: number,
	sequence: { string },    -- wire-colour names in click order
	elapsedSeconds: number,
	mistakes: number,
}

export type ValidationResult = {
	success: boolean,
	reason: string?,         -- nil on success; "timeout"|"wrong"|"too_many_mistakes"
	bonusScore: number,      -- 0-100: faster completion → higher bonus
}

-- ---------------------------------------------------------------------------
-- Deterministic RNG (LCG)
-- ---------------------------------------------------------------------------

-- Returns a pseudo-random integer in [lo, hi] seeded deterministically.
local function lcg(seed: number, lo: number, hi: number): (number, number)
	local next = (1664525 * seed + 1013904223) % (2 ^ 32)
	local value = lo + (next % (hi - lo + 1))
	return value, next
end

-- ---------------------------------------------------------------------------
-- Safe combination
-- ---------------------------------------------------------------------------

local SAFE_DIGITS      = 3
local SAFE_DIGIT_MIN   = 1
local SAFE_DIGIT_MAX   = 9
local SAFE_TIME_LIMIT  = 30 -- seconds default

--- Derives a deterministic 3-digit combination from a seed.
function MiniGameValidator.deriveSafeCombination(seed: number): { number }
	local combo: { number } = {}
	local s = seed
	for _ = 1, SAFE_DIGITS do
		local digit
		digit, s = lcg(s, SAFE_DIGIT_MIN, SAFE_DIGIT_MAX)
		table.insert(combo, digit)
	end
	return combo
end

--- Validates a safe-cracking attempt.
--- timeLimit: override in seconds (default SAFE_TIME_LIMIT).
function MiniGameValidator.validateSafe(attempt: SafeAttempt, timeLimit: number?): ValidationResult
	local limit  = timeLimit or SAFE_TIME_LIMIT
	local correct = MiniGameValidator.deriveSafeCombination(attempt.seed)

	if attempt.elapsedSeconds > limit then
		return { success = false, reason = "timeout", bonusScore = 0 }
	end

	if #attempt.combination ~= SAFE_DIGITS then
		return { success = false, reason = "wrong", bonusScore = 0 }
	end

	for i, digit in attempt.combination do
		if digit ~= correct[i] then
			return { success = false, reason = "wrong", bonusScore = 0 }
		end
	end

	return {
		success    = true,
		reason     = nil,
		bonusScore = MiniGameValidator.speedBonus(attempt.elapsedSeconds, limit),
	}
end

-- ---------------------------------------------------------------------------
-- Hack sequence
-- ---------------------------------------------------------------------------

local WIRE_COLOURS    = { "red", "blue", "green", "yellow", "white" }
local HACK_SEQ_LENGTH = 4   -- wires to click in order
local HACK_MAX_MISTAKES = 2
local HACK_TIME_LIMIT  = 25 -- seconds default

--- Derives a deterministic wire sequence from a seed.
--- Returns a list of wire-colour names (length HACK_SEQ_LENGTH).
function MiniGameValidator.deriveHackSequence(seed: number): { string }
	local seq: { string } = {}
	local s = seed
	for _ = 1, HACK_SEQ_LENGTH do
		local idx
		idx, s = lcg(s, 1, #WIRE_COLOURS)
		table.insert(seq, WIRE_COLOURS[idx])
	end
	return seq
end

--- Returns all available wire colours (for building the UI).
function MiniGameValidator.wireColours(): { string }
	return table.clone(WIRE_COLOURS)
end

--- Validates a hacking attempt.
function MiniGameValidator.validateHack(attempt: HackAttempt, timeLimit: number?, maxMistakes: number?): ValidationResult
	local limit   = timeLimit   or HACK_TIME_LIMIT
	local maxErr  = maxMistakes or HACK_MAX_MISTAKES
	local correct = MiniGameValidator.deriveHackSequence(attempt.seed)

	if attempt.elapsedSeconds > limit then
		return { success = false, reason = "timeout", bonusScore = 0 }
	end

	if attempt.mistakes > maxErr then
		return { success = false, reason = "too_many_mistakes", bonusScore = 0 }
	end

	if #attempt.sequence ~= HACK_SEQ_LENGTH then
		return { success = false, reason = "wrong", bonusScore = 0 }
	end

	for i, colour in attempt.sequence do
		if colour ~= correct[i] then
			return { success = false, reason = "wrong", bonusScore = 0 }
		end
	end

	return {
		success    = true,
		reason     = nil,
		bonusScore = MiniGameValidator.speedBonus(attempt.elapsedSeconds, limit),
	}
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Returns a 0-100 bonus score (100 = instant, 0 = at time limit).
function MiniGameValidator.speedBonus(elapsed: number, timeLimit: number): number
	local ratio = math.clamp(elapsed / timeLimit, 0, 1)
	return math.floor((1 - ratio) * 100)
end

return MiniGameValidator
