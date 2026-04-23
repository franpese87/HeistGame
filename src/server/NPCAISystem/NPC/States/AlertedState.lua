local AlertedState = {}

function AlertedState.Enter(ctrl, _previousState)
	ctrl.alertedStartTime = os.clock()
	ctrl.pawn:StopMovement()
	ctrl.pawn:SetAutoRotate(false)
	ctrl.pawn:PlayAnimation("idle")

	-- Mostrar indicador "!" (ahora vive en Pawn)
	ctrl.pawn:ShowAlertIndicator()

	-- Rotacion por capas head-dominant hacia el target
	if ctrl.target then
		local targetRoot = ctrl.target:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			local currentPos = ctrl.pawn:GetPosition()
			local directionToTarget = (targetRoot.Position - currentPos) * Vector3.new(1, 0, 1)

			if directionToTarget.Magnitude > 0.1 then
				local lookVector = ctrl.pawn:GetLookVector()
				local bodyAngle = math.atan2(lookVector.X, lookVector.Z)
				local targetAngle = math.atan2(directionToTarget.X, directionToTarget.Z)
				local angle = math.deg(targetAngle - bodyAngle)

				if angle > 180 then angle = angle - 360 end
				if angle < -180 then angle = angle + 360 end

				ctrl.originalCFrame = ctrl.pawn:GetCFrame()

				ctrl.pawn:RotateLayered(angle, {
					head = ctrl.alertedHeadRatio,
					torso = ctrl.alertedTorsoRatio,
				}, ctrl.alertedTweenInfo)
			end

			ctrl.lastSeenPosition = targetRoot.Position
		end
	end
end

function AlertedState.Update(ctrl)
	local elapsed = os.clock() - ctrl.alertedStartTime
	local events = ctrl.lastVisionEvents

	-- Actualizar lastSeenPosition mientras lo vemos
	if events and events.TargetVisible and ctrl.target then
		local targetRoot = ctrl.target:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			ctrl.lastSeenPosition = targetRoot.Position
		end
	end

	-- Tiempo de reaccion completado
	if elapsed >= ctrl.reactionTime then
		if events and events.TargetVisible then
			ctrl:ChangeState("Chasing")
		else
			ctrl:ChangeState("Investigating")
		end
	end
end

function AlertedState.Exit(ctrl)
	ctrl.pawn:CancelRotationTween()
	ctrl.pawn:ResetLayeredRotation(ctrl.alertedTweenInfo)
	ctrl.originalCFrame = nil
	ctrl.pawn:SetAutoRotate(true)
	ctrl.pawn:ClearAlertIndicator()
end

return AlertedState
