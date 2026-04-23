local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProjectileService = require(script.Parent.Parent.Parent.Parent.Services.ProjectileService)
local TaserConfig = require(ReplicatedStorage.Shared.TaserConfig)

local AttackingState = {}

function AttackingState.Enter(ctrl, _previousState)
	ctrl.pawn:SetAutoRotate(false)
	ctrl.pawn:EquipWeaponVisual()
	local holdAnim = ctrl.pawn.animationTracks["toolhold"] and "toolhold" or "idle"
	ctrl.pawn:PlayAnimation(holdAnim)
end

local function fireTaser(ctrl, targetRoot)
	local now = os.clock()
	if now - ctrl.lastTaserFireTime < TaserConfig.cooldown then
		return
	end

	local npcPos = ctrl.pawn:GetPosition()
	local targetPos = targetRoot.Position
	local direction = (targetPos - npcPos) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then return end
	direction = direction.Unit

	-- LOS check (raycastParams ya excluye al NPC)
	local origin = npcPos + Vector3.new(0, TaserConfig.projectileYOffset or 0, 0)
	local toTarget = targetPos - origin
	local losResult = workspace:Raycast(origin, toTarget, ctrl.raycastParams)
	local hasLOS = not losResult or losResult.Instance:IsDescendantOf(targetRoot.Parent)

	if not hasLOS then
		-- Sin LOS: volver a perseguir para reposicionar
		ctrl:ChangeState("Chasing")
		return
	end

	ctrl.lastTaserFireTime = now
	ctrl.pawn:PlayAnimationOnce("shoot")
	ProjectileService.Fire(npcPos, direction, TaserConfig, ctrl.pawn:GetInstance())
end

function AttackingState.Update(ctrl)
	ctrl.pawn:StopMovement()

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
	local disengageDistance = ctrl.weaponType == "taser"
		and (ctrl.taserEngageDistance + 5)
		or (ctrl.combatSystem.attackRange + 1)
	if distance > disengageDistance then
		ctrl:ChangeState("Chasing")
		return
	end

	-- Rotacion suave con interpolacion hacia el target
	local targetDirection = (targetRoot.Position - ctrl.pawn:GetPosition()) * Vector3.new(1, 0, 1)
	if targetDirection.Magnitude > 0.1 then
		local targetCFrame = CFrame.lookAt(ctrl.pawn:GetPosition(), ctrl.pawn:GetPosition() + targetDirection)
		ctrl.pawn:LerpCFrame(targetCFrame, ctrl.attackRotationSpeed)
	end

	if ctrl.weaponType == "taser" then
		fireTaser(ctrl, targetRoot)
	else
		ctrl.combatSystem:TryAttack(ctrl.target)
	end
end

function AttackingState.Exit(ctrl)
	ctrl.pawn:SetAutoRotate(true)
	ctrl.pawn:UnequipWeaponVisual()
end

return AttackingState
