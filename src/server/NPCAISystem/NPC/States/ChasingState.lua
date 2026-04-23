local ChasingState = {}

function ChasingState.Enter(ctrl, _previousState)
	ctrl.pathFollower:ClearChaseState()
end

-- Head tracking hacia el target durante persecucion
local function updateHeadTracking(ctrl)
	if not ctrl.target or not ctrl.enableHeadTrackingDuringChase then
		return
	end

	local targetRoot = ctrl.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local currentPos = ctrl.pawn:GetPosition()
	local directionToTarget = (targetRoot.Position - currentPos) * Vector3.new(1, 0, 1)
	if directionToTarget.Magnitude < 0.1 then return end

	local bodyLookVector = ctrl.pawn:GetLookVector()
	local targetLookVector = directionToTarget.Unit

	local bodyAngle = math.atan2(bodyLookVector.X, bodyLookVector.Z)
	local targetAngle = math.atan2(targetLookVector.X, targetLookVector.Z)
	local headAngle = math.deg(targetAngle - bodyAngle)

	if headAngle > 180 then headAngle = headAngle - 360 end
	if headAngle < -180 then headAngle = headAngle + 360 end
	headAngle = math.clamp(headAngle, -ctrl.headTrackingMaxAngle, ctrl.headTrackingMaxAngle)

	-- Aplicar rotacion directa (instantanea para tracking responsive)
	if ctrl.pawn.neck and ctrl.pawn.neckOriginalC0 then
		ctrl.pawn.neck.C0 = CFrame.Angles(0, math.rad(headAngle), 0) * ctrl.pawn.neckOriginalC0
	end
end

function ChasingState.Update(ctrl)
	updateHeadTracking(ctrl)

	ctrl.pawn:SetChaseSpeed()
	ctrl.pawn:PlayAnimation("run")

	if not ctrl.target then
		ctrl:ChangeState("Returning")
		return
	end

	local targetRoot = ctrl.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		ctrl.target = nil
		return
	end

	local distance = (ctrl.pawn:GetPosition() - targetRoot.Position).Magnitude
	local engageDistance = ctrl.weaponType == "taser" and ctrl.taserEngageDistance or ctrl.combatSystem.attackRange
	if distance <= engageDistance then
		ctrl.pathFollower:ClearPath()
		ctrl:ChangeState("Attacking")
		return
	end

	ctrl.pathFollower:NavigateToTarget(targetRoot)
end

function ChasingState.Exit(ctrl)
	if ctrl.enableHeadTrackingDuringChase then
		ctrl.pawn:ResetLayeredRotation(TweenInfo.new(0.2))
	end
end

return ChasingState
