local StunService = require(script.Parent.Parent.Parent.Parent.Services.StunService)

local StunnedState = {}

function StunnedState.Enter(ctrl, _previousState)
	ctrl.stunStartTime = os.clock()
	ctrl.pawn:StopMovement()
	ctrl.pawn:SetAutoRotate(false)
	ctrl.pawn:PlayAnimation("idle")

	-- Inmovilizar via StunService
	local humanoid = ctrl.pawn:GetHumanoid()
	if humanoid then
		StunService.Apply(humanoid, math.huge)
	end

	-- Limpiar debug visuals de sensores (evita que queden congelados)
	ctrl.visionSensor:ClearRangeCircle()
	ctrl.visionSensor:ClearConeBoundaries()
	ctrl.visionSensor:ClearLineOfSight()

	ctrl.target = nil
	ctrl.lastSeenPosition = nil
	ctrl.pathFollower:ClearPath()
end

function StunnedState.Update(ctrl)
	if os.clock() - ctrl.stunStartTime >= ctrl.stunDuration then
		ctrl:ChangeState("Returning")
	end
end

function StunnedState.Exit(ctrl)
	local humanoid = ctrl.pawn:GetHumanoid()
	if humanoid then
		StunService.Remove(humanoid)
	end
	ctrl.pawn:SetAutoRotate(true)
end

return StunnedState
