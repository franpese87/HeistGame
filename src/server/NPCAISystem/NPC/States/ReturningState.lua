local ReturningState = {}

function ReturningState.Enter(ctrl, _previousState)
	ctrl.target = nil
	ctrl.lastSeenPosition = nil

	ctrl.returnTargetNode = ctrl:GetNearestPatrolNode()
	if ctrl.returnTargetNode then
		ctrl.pathFollower:CalculatePathTo(ctrl.returnTargetNode.Position)
	end
end

function ReturningState.Update(ctrl)
	if not ctrl.returnTargetNode or ctrl.pathFollower:HasArrivedAt(ctrl.returnTargetNode.Position) then
		ctrl:ChangeState("Patrolling")
		return
	end

	-- Si no hay path y estamos cerca del nodo, transicionar directamente
	local distanceToTarget = (ctrl.pawn:GetPosition() - ctrl.returnTargetNode.Position).Magnitude
	if not ctrl.pathFollower:HasPath() and distanceToTarget < 10 then
		ctrl:ChangeState("Patrolling")
		return
	end

	ctrl.pathFollower:NavigateToPosition(ctrl.returnTargetNode.Position, "patrol")
end

function ReturningState.Exit(ctrl)
	ctrl.returnTargetNode = nil
	ctrl.pathFollower:ClearPath()
end

return ReturningState
