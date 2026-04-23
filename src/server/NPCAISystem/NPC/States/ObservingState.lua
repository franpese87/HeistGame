local ObservationHelper = require(script.Parent.ObservationHelper)

local ObservingState = {}

function ObservingState.Enter(ctrl, _previousState)
	ctrl.currentObservationIndex = 1
	ctrl.observationStartTime = os.clock()

	ctrl.pawn:StopMovement()
	ctrl.pawn:SetAutoRotate(false)
	ctrl.pawn:PlayAnimation("idle")

	-- Obtener orientacion y angulos (con cache por nodo de patrulla)
	local orientation, validAngles = ObservationHelper.GetOrComputeOrientation(ctrl, ctrl.currentPatrolIndex)
	ctrl.originalCFrame = orientation
	ctrl.validObservationAngles = validAngles

	-- Rotar suavemente hacia la orientacion
	local rotationTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	ctrl.pawn:RotateWithTween(ctrl.originalCFrame, rotationTweenInfo)

	-- Iniciar primera rotacion por capas
	ctrl.pawn:RotateLayered(ctrl.validObservationAngles[1], {
		head = ctrl.observationHeadRatio,
		torso = ctrl.observationTorsoRatio,
	}, ctrl.rotationTweenInfo)
end

function ObservingState.Update(ctrl)
	local currentTime = os.clock()
	if currentTime - ctrl.observationStartTime >= ctrl.observationTimePerAngle then
		ctrl.currentObservationIndex = ctrl.currentObservationIndex + 1
		if ctrl.currentObservationIndex > #ctrl.validObservationAngles then
			ctrl:ChangeState("Patrolling")
			return
		end
		ctrl.observationStartTime = currentTime
		ctrl.pawn:RotateLayered(ctrl.validObservationAngles[ctrl.currentObservationIndex], {
			head = ctrl.observationHeadRatio,
			torso = ctrl.observationTorsoRatio,
		}, ctrl.rotationTweenInfo)
	end
end

function ObservingState.Exit(ctrl)
	ctrl.pawn:CancelRotationTween()
	ctrl.pawn:ResetLayeredRotation(ctrl.rotationTweenInfo)
	ctrl.currentObservationIndex = 1
	ctrl.originalCFrame = nil
	ctrl.pawn:SetAutoRotate(true)
end

return ObservingState
