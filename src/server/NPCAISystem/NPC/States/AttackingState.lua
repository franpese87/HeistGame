local AttackingState = {}

function AttackingState.Enter(ctrl, _previousState)
	ctrl.pawn:SetAutoRotate(false)
end

function AttackingState.Update(ctrl)
	ctrl.pawn:StopMovement()
	ctrl.pawn:PlayAnimation("idle")

	if not ctrl.target then
		ctrl:ChangeState("Returning")
		return
	end

	local targetRoot = ctrl.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		ctrl.target = nil
		ctrl:ChangeState("Returning")
		return
	end

	local distance = (ctrl.pawn:GetPosition() - targetRoot.Position).Magnitude
	if distance > (ctrl.combatSystem.attackRange + 1) then
		ctrl:ChangeState("Chasing")
		return
	end

	-- Rotacion suave con interpolacion hacia el target
	local targetDirection = (targetRoot.Position - ctrl.pawn:GetPosition()) * Vector3.new(1, 0, 1)
	if targetDirection.Magnitude > 0.1 then
		local targetCFrame = CFrame.lookAt(ctrl.pawn:GetPosition(), ctrl.pawn:GetPosition() + targetDirection)
		ctrl.pawn:LerpCFrame(targetCFrame, ctrl.attackRotationSpeed)
	end

	ctrl.combatSystem:TryAttack(ctrl.target)
end

function AttackingState.Exit(ctrl)
	ctrl.pawn:SetAutoRotate(true)
end

return AttackingState
