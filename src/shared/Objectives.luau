--!strict
-- Objectives.luau
-- Defines mission objectives and tracks their completion status.
--
-- An objective is a named task with a type, target, and optional progress.
-- Examples:
--   • Steal 3 jewels          → type "collect", target "jewel", amount 3
--   • Crack the safe          → type "interact", target "safe_main"
--   • Disable security cameras → type "disable", target "camera", amount 4
--   • Reach the escape van    → type "reach",   target "escape_point"

local Objectives = {}

export type ObjectiveType = "collect" | "interact" | "disable" | "reach" | "neutralize"

export type Objective = {
	id: string,
	description: string,
	objectiveType: ObjectiveType,
	target: string,          -- tag / item id / interaction id
	required: number,        -- how many times it must be satisfied
	progress: number,        -- current count
	completed: boolean,
	optional: boolean,       -- optional objectives give bonus loot
}

export type MissionObjectives = {
	missionId: string,
	objectives: { Objective },
}

--- Creates a fresh objective.
function Objectives.newObjective(
	id: string,
	description: string,
	objectiveType: ObjectiveType,
	target: string,
	required: number,
	optional: boolean?
): Objective
	return {
		id            = id,
		description   = description,
		objectiveType = objectiveType,
		target        = target,
		required      = required,
		progress      = 0,
		completed     = false,
		optional      = optional or false,
	}
end

--- Advances an objective's progress by delta. Marks it complete when met.
--- Returns true if the objective was just completed by this call.
function Objectives.advance(obj: Objective, delta: number?): boolean
	if obj.completed then return false end
	obj.progress = math.clamp(obj.progress + (delta or 1), 0, obj.required)
	if obj.progress >= obj.required then
		obj.completed = true
		return true
	end
	return false
end

--- Returns true when all mandatory objectives are complete.
function Objectives.allMandatoryComplete(mission: MissionObjectives): boolean
	for _, obj in mission.objectives do
		if not obj.optional and not obj.completed then
			return false
		end
	end
	return true
end

--- Returns a count summary: { total, done, optional, optionalDone }
function Objectives.summary(mission: MissionObjectives): { [string]: number }
	local total, done, optional, optDone = 0, 0, 0, 0
	for _, obj in mission.objectives do
		if obj.optional then
			optional += 1
			if obj.completed then optDone += 1 end
		else
			total += 1
			if obj.completed then done += 1 end
		end
	end
	return { total = total, done = done, optional = optional, optionalDone = optDone }
end

-- ---------------------------------------------------------------------------
-- Pre-built mission templates
-- ---------------------------------------------------------------------------

--- Returns the objectives list for "The Bank Job" mission.
function Objectives.bankJob(): MissionObjectives
	return {
		missionId  = "bank_job",
		objectives = {
			Objectives.newObjective(
				"crack_vault",
				"Crack the main vault",
				"interact",
				"vault_main",
				1
			),
			Objectives.newObjective(
				"steal_cash",
				"Fill cash bags (3)",
				"collect",
				"cash_bag",
				3
			),
			Objectives.newObjective(
				"reach_exit",
				"Escape to the getaway van",
				"reach",
				"escape_van",
				1
			),
			-- Optional
			Objectives.newObjective(
				"disable_cameras",
				"Disable all security cameras (4)",
				"disable",
				"camera",
				4,
				true  -- optional
			),
			Objectives.newObjective(
				"steal_manager_keycard",
				"Steal the manager's keycard",
				"collect",
				"keycard",
				1,
				true
			),
		},
	}
end

--- Returns the objectives list for "The Art Heist" mission.
function Objectives.artHeist(): MissionObjectives
	return {
		missionId  = "art_heist",
		objectives = {
			Objectives.newObjective(
				"steal_paintings",
				"Steal target paintings (2)",
				"collect",
				"painting",
				2
			),
			Objectives.newObjective(
				"hack_alarm",
				"Hack the alarm control panel",
				"interact",
				"alarm_panel",
				1
			),
			Objectives.newObjective(
				"reach_exit",
				"Escape via the roof exit",
				"reach",
				"escape_roof",
				1
			),
			Objectives.newObjective(
				"steal_jewels",
				"Grab bonus jewels (3)",
				"collect",
				"jewel",
				3,
				true
			),
		},
	}
end

return Objectives
