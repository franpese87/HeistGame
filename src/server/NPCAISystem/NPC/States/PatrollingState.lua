local PatrollingState = {}

function PatrollingState.Enter(ctrl, previousState)
	if previousState == "Observing" then
		ctrl:MoveToNextPatrolNode()
	end
end

function PatrollingState.Update(ctrl)
	if #ctrl.patrolNodes == 0 then return end

	local targetNode = ctrl.patrolNodes[ctrl.currentPatrolIndex]

	if ctrl.pathFollower:HasArrivedAt(targetNode.Position) then
		ctrl:ChangeState("Observing")
		return
	end

	ctrl.pathFollower:NavigateToPosition(targetNode.Position, "patrol")
end

function PatrollingState.Exit(_ctrl)
end

return PatrollingState
