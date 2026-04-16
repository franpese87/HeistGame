local ObservationHelper = require(script.Parent.ObservationHelper)
local Visualizer = require(script.Parent.Parent.Parent.Debug.Visualizer)

local InvestigatingState = {}

function InvestigatingState.Enter(ctrl, _previousState)
	ctrl.investigationStartTime = os.clock()
	ctrl.investigationObservationIndex = 1
	ctrl.investigationObservationTime = 0
	ctrl.investigationIsObserving = false
	ctrl.pawn:SetAutoRotate(true)

	if ctrl.lastSeenPosition then
		ctrl.investigationTarget = ctrl.lastSeenPosition

		ctrl:Log("stateChanges", "Iniciando investigacion (" .. ctrl.investigationDuration .. "s) en posicion " .. tostring(ctrl.investigationTarget))

		if ctrl.debugEnabled and ctrl.debugConfig.showLastSeenPosition then
			Visualizer.DrawLastSeenPosition(ctrl.pawn:GetName(), ctrl.investigationTarget, {
				duration = ctrl.investigationDuration,
			})
		end

		ctrl.pathFollower:CalculatePathTo(ctrl.investigationTarget)
	end
end

function InvestigatingState.Update(ctrl)
	if os.clock() - ctrl.investigationStartTime > ctrl.investigationDuration then
		ctrl:ChangeState("Returning")
		return
	end

	if ctrl.pathFollower:HasPath() then
		-- Navegando hacia la ultima posicion vista
		ctrl.pawn:PlayAnimation("walk")
		ctrl.pathFollower:FollowCurrentPath()
	else
		-- Llego a la posicion: observar usando rotacion por capas
		ctrl.pawn:StopMovement()
		ctrl.pawn:PlayAnimation("idle")

		if not ctrl.investigationIsObserving then
			ctrl.investigationIsObserving = true
			ctrl.investigationObservationTime = os.clock()
			ctrl.pawn:SetAutoRotate(false)

			-- Orientarse hacia la ultima posicion conocida
			local currentPos = ctrl.pawn:GetPosition()
			local directionToTarget = (ctrl.investigationTarget - currentPos) * Vector3.new(1, 0, 1)

			if directionToTarget.Magnitude > 0.1 then
				ctrl.originalCFrame = CFrame.lookAt(currentPos, currentPos + directionToTarget)
			else
				ctrl.originalCFrame = ctrl.pawn:GetCFrame()
			end

			local rotationTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			ctrl.pawn:RotateWithTween(ctrl.originalCFrame, rotationTweenInfo)

			-- Filtrar angulos validos
			ctrl.validInvestigationAngles = ObservationHelper.FilterValidAngles(
				ctrl.observationAngles, ctrl.originalCFrame, currentPos,
				ctrl.raycastParams, ctrl.observationValidationDistance
			)

			-- Iniciar primera rotacion por capas
			ctrl.pawn:RotateLayered(ctrl.validInvestigationAngles[ctrl.investigationObservationIndex], {
				head = ctrl.observationHeadRatio,
				torso = ctrl.observationTorsoRatio,
			}, ctrl.rotationTweenInfo)
		end

		-- Rotar por angulos de observacion
		local currentTime = os.clock()
		if currentTime - ctrl.investigationObservationTime >= ctrl.observationTimePerAngle then
			ctrl.investigationObservationIndex = ctrl.investigationObservationIndex + 1
			if ctrl.investigationObservationIndex > #ctrl.validInvestigationAngles then
				ctrl.investigationObservationIndex = 1
			end
			ctrl.investigationObservationTime = currentTime
			ctrl.pawn:RotateLayered(ctrl.validInvestigationAngles[ctrl.investigationObservationIndex], {
				head = ctrl.observationHeadRatio,
				torso = ctrl.observationTorsoRatio,
			}, ctrl.rotationTweenInfo)
		end
	end
end

function InvestigatingState.Exit(ctrl)
	if ctrl.investigationIsObserving then
		ctrl.pawn:ResetLayeredRotation(ctrl.rotationTweenInfo)
		ctrl.investigationIsObserving = false
	end

	ctrl.investigationStartTime = nil
	ctrl.investigationTarget = nil
	ctrl.investigationObservationIndex = 1
	ctrl.investigationObservationTime = 0
	ctrl.originalCFrame = nil
	ctrl.pawn:SetAutoRotate(true)
	ctrl.pathFollower:ClearPath()

	if ctrl.debugEnabled and ctrl.debugConfig.showLastSeenPosition then
		Visualizer.ClearLastSeenPosition(ctrl.pawn:GetName())
	end
end

return InvestigatingState
