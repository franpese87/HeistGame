--[[
	Controller - Cerebro del NPC (Patrón Pawn-Controller)

	Controla la lógica de IA:
	- FSM (Máquina de Estados Finitos)
	- Sensores (Visión, Audición)
	- Sistema de Combate
	- Navegación y Pathfinding

	Usa el Pawn para interactuar con el mundo físico.
]]

local VisionSensor = require(script.Parent.Parent.Components.VisionSensor)
local Combat = require(script.Parent.Parent.Components.Combat)
local HearingSensor = require(script.Parent.Parent.Components.HearingSensor)
local DebugConfig = require(script.Parent.Parent.Parent.Config.DebugConfig)
local Visualizer = require(script.Parent.Parent.Debug.Visualizer)

local AIState = {
	PATROLLING = "Patrolling",
	OBSERVING = "Observing",
	CHASING = "Chasing",
	ATTACKING = "Attacking",
	INVESTIGATING = "Investigating",
	RETURNING = "Returning"
}

-- Constantes
local ARRIVAL_THRESHOLD = 3

local Controller = {}
Controller.__index = Controller

-- ==============================================================================
-- CONSTRUCTOR
-- ==============================================================================

function Controller.new(pawn, navigationGraph, config)
	local self = setmetatable({}, Controller)

	-- Referencia al Pawn (representación física)
	self.pawn = pawn
	self.graph = navigationGraph

	-- Configuración General
	config = config or {}
	self.patrolWaitTime = config.patrolWaitTime or 2

	-- Navegación (siempre grafo, excepto acercamiento final para atacar)
	self.directApproachDistance = config.directApproachDistance or 8
	self.nodeTimeout = 4

	-- Path Smoothing
	self.enablePathSmoothing = config.enablePathSmoothing ~= false -- default true
	self.agentRadius = config.agentRadius or 1.0

	-- Observación
	self.observationAngles = config.observationAngles or {-45, 0, 45, 0}
	self.observationTimePerAngle = config.observationTimePerAngle or 1.0
	self.rotationTweenInfo = TweenInfo.new(self.observationTimePerAngle * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Investigación (duración = tiempo total de observación en un nodo de patrulla)
	self.investigationDuration = #self.observationAngles * self.observationTimePerAngle

	-- Componentes (Sensores y Combate)
	local npcInstance = pawn:GetInstance()
	self.visionSensor = VisionSensor.new(npcInstance, config)
	self.combatSystem = Combat.new(npcInstance, config)
	self.hearingSensor = HearingSensor.new(npcInstance, config)

	-- Configuración de Debug visual del sensor
	if DebugConfig.visuals then
		self.visionSensor:SetDebug(DebugConfig.visuals.showVisionRays, { showRaycast = DebugConfig.visuals.showVisionRays })
	end

	-- Estado general
	self.currentState = AIState.PATROLLING
	self.isActive = true
	self.stateStartTime = tick()

	-- Target tracking
	self.target = nil
	self.lastSeenPosition = nil
	self.lastMoveCommand = 0
	self.timeStartedMovingToNode = 0

	-- Patrullaje
	self.patrolNodes = config.patrolNodes or {}
	self.currentPatrolIndex = 1
	self.isWaiting = false

	-- Pathfinding/Persecución
	self.currentPath = nil
	self.currentPathIndex = 1
	self.targetLastPosition = nil

	-- Debug logging
	local loggingConfig = config.logging or DebugConfig.logging or {}
	self.logFlags = {
		stateChanges = loggingConfig.stateChanges or false,
		detection = loggingConfig.detection or false,
	}

	-- Observación (estado temporal)
	self.originalCFrame = nil
	self.currentObservationIndex = 1
	self.observationStartTime = 0

	-- Iniciar
	if #self.patrolNodes > 0 then
		self:MoveToNextPatrolNode()
	end

	return self
end

-- ==============================================================================
-- DEBUG LOGGING
-- ==============================================================================

function Controller:Log(category, message)
	if self.logFlags[category] then
		print("[" .. self.pawn:GetName() .. "][" .. category .. "] " .. message)
	end
end

-- ==============================================================================
-- NAVIGATION HELPERS
-- ==============================================================================

function Controller:ClearPath()
	self.currentPath = nil
	self.currentPathIndex = 1
end

function Controller:HasArrivedAt(position)
	return (self.pawn:GetPosition() - position).Magnitude < ARRIVAL_THRESHOLD
end

function Controller:NavigateToPosition(position, mode)
	if mode == "patrol" then
		self.pawn:SetPatrolSpeed()
	else
		self.pawn:SetChaseSpeed()
	end

	if self.currentPath and #self.currentPath > 0 then
		self.pawn:PlayAnimation(mode == "patrol" and "walk" or "run")
		self:FollowCurrentPath()
	else
		self:CalculateGraphPathToPosition(position)
	end
end

-- ==============================================================================
-- MAIN UPDATE LOOP
-- ==============================================================================

function Controller:Update(_deltaTime)
	if not self.isActive or not self.pawn:IsAlive() then
		self.isActive = false
		return
	end

	self:UpdateSenses()

	if self.currentState == AIState.PATROLLING then
		self:UpdatePatrolling()
	elseif self.currentState == AIState.OBSERVING then
		self:UpdateObserving()
	elseif self.currentState == AIState.CHASING then
		self:UpdateChasing()
	elseif self.currentState == AIState.ATTACKING then
		self:UpdateAttacking()
	elseif self.currentState == AIState.INVESTIGATING then
		self:UpdateInvestigating()
	elseif self.currentState == AIState.RETURNING then
		self:UpdateReturning()
	end
end

-- ==============================================================================
-- SENSORY SYSTEM
-- ==============================================================================

function Controller:UpdateSenses()
	-- 1. VISIÓN
	local currentTarget, lastPos, events = self.visionSensor:Scan()

	if currentTarget then
		self.target = currentTarget
	end

	if lastPos then
		self.lastSeenPosition = lastPos
	end

	if events.TargetConfirmed then
		self:Log("detection", "TARGET CONFIRMADO: " .. currentTarget.Name)

		if self.currentState ~= AIState.CHASING and self.currentState ~= AIState.ATTACKING then
			self:ChangeState(AIState.CHASING)
		end
	end

	if events.TargetLost then
		self:Log("detection", "TARGET PERDIDO (Olvido total)")
		self.target = nil

		if self.currentState == AIState.CHASING or self.currentState == AIState.ATTACKING then
			self:ChangeState(AIState.INVESTIGATING)
		end
	end

	-- 2. OÍDO
	local heardNoisePos = self.hearingSensor:CheckForNoise()
	if heardNoisePos then
		if self.currentState == AIState.PATROLLING or self.currentState == AIState.OBSERVING or self.currentState == AIState.RETURNING then
			self:Log("detection", "Ruido oído en " .. tostring(heardNoisePos))
			self.lastSeenPosition = heardNoisePos
			self:ChangeState(AIState.INVESTIGATING)
		end
	end
end

-- ==============================================================================
-- PATROLLING
-- ==============================================================================

function Controller:UpdatePatrolling()
	if #self.patrolNodes == 0 then return end

	local targetNode = self.patrolNodes[self.currentPatrolIndex]

	if self:HasArrivedAt(targetNode.Position) then
		self:ChangeState(AIState.OBSERVING)
		return
	end

	self:NavigateToPosition(targetNode.Position, "patrol")
end

function Controller:MoveToNextPatrolNode()
	if #self.patrolNodes == 0 then return end
	self.currentPatrolIndex = self.currentPatrolIndex + 1
	if self.currentPatrolIndex > #self.patrolNodes then
		self.currentPatrolIndex = 1
	end
	self:ClearPath()
end

-- ==============================================================================
-- OBSERVING
-- ==============================================================================

function Controller:EnterObserving()
	self.currentObservationIndex = 1
	self.observationStartTime = tick()

	local nextPatrolIndex = self.currentPatrolIndex + 1
	if nextPatrolIndex > #self.patrolNodes then
		nextPatrolIndex = 1
	end
	local currentNode = self.patrolNodes[self.currentPatrolIndex]
	local nextNode = self.patrolNodes[nextPatrolIndex]
	local directionToNext = (nextNode.Position - currentNode.Position) * Vector3.new(1,0,1)

	if directionToNext.Magnitude > 0.1 then
		self.originalCFrame = CFrame.lookAt(self.pawn:GetPosition(), self.pawn:GetPosition() + directionToNext)
		self.pawn:SetCFrame(self.originalCFrame)
	else
		self.originalCFrame = self.pawn:GetCFrame()
	end

	self.pawn:StopMovement()
	self.pawn:SetAutoRotate(false)
	self.pawn:PlayAnimation("idle")
	self:RotateToObservationAngle(self.observationAngles[1])
end

function Controller:UpdateObserving()
	local currentTime = tick()
	if currentTime - self.observationStartTime >= self.observationTimePerAngle then
		self.currentObservationIndex = self.currentObservationIndex + 1
		if self.currentObservationIndex > #self.observationAngles then
			self:ChangeState(AIState.PATROLLING)
			return
		end
		self.observationStartTime = currentTime
		self:RotateToObservationAngle(self.observationAngles[self.currentObservationIndex])
	end
end

function Controller:ExitObserving()
	self.pawn:CancelRotationTween()
	self.currentObservationIndex = 1
	self.originalCFrame = nil
	self.pawn:SetAutoRotate(true)
end

function Controller:RotateToObservationAngle(angle)
	if not self.originalCFrame then return end
	local targetCFrame = self.originalCFrame * CFrame.Angles(0, math.rad(angle), 0)
	self.pawn:RotateWithTween(targetCFrame, self.rotationTweenInfo)
end

-- ==============================================================================
-- CHASING
-- ==============================================================================

function Controller:UpdateChasing()
	self.pawn:SetChaseSpeed()
	self.pawn:PlayAnimation("run")

	if not self.target then
		self:ChangeState(AIState.RETURNING)
		return
	end

	local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self.target = nil
		return
	end

	local distance = (self.pawn:GetPosition() - targetRoot.Position).Magnitude
	if distance <= self.combatSystem.attackRange then
		self.currentPath = nil
		self:ChangeState(AIState.ATTACKING)
		return
	end

	self:NavigateToTarget(targetRoot)
end

function Controller:NavigateToTarget(targetRoot)
	local distance = (self.pawn:GetPosition() - targetRoot.Position).Magnitude

	-- Acercamiento directo solo cuando está lo suficientemente cerca para atacar
	if distance <= self.directApproachDistance then
		self.currentPath = nil
		self.pawn:MoveTo(targetRoot.Position)
	else
		-- Siempre usar grafo para navegación a larga distancia
		self:ChaseUsingGraph(targetRoot)
	end
end

function Controller:ChaseUsingGraph(targetRoot)
	local targetPosition = targetRoot.Position

	if not self.currentPath or #self.currentPath == 0 then
		self:CalculateGraphPathToPosition(targetPosition)
		self.targetLastPosition = targetPosition
		return
	end

	local npcPos = self.pawn:GetPosition()
	local currentTargetNode = self.currentPath[self.currentPathIndex]

	if currentTargetNode and self:HasArrivedAt(currentTargetNode.position) then
		local targetMoved = self.targetLastPosition and (targetPosition - self.targetLastPosition).Magnitude > 10

		if targetMoved then
			self:CalculateGraphPathToPosition(targetPosition)
			self.targetLastPosition = targetPosition
		end
	end

	self:FollowCurrentPath()
end

function Controller:CalculateGraphPathToPosition(targetPosition)
	local npcPos = self.pawn:GetPosition()

	local startNode = self.graph:GetNearestNodeTowardsTarget(npcPos, targetPosition)
	local endNode = self.graph:GetNearestNode(targetPosition)

	if not startNode or not endNode then
		self.currentPath = nil
		return
	end

	if startNode.name == endNode.name then
		self.currentPath = nil
		return
	end

	local path = self.graph:GetPathBetweenNodes(startNode, endNode)

	if path and #path > 0 then
		-- Aplicar path smoothing si está habilitado
		if self.enablePathSmoothing then
			path = self.graph:SmoothPath(path, self.agentRadius)
		end

		self.currentPath = path
		self.timeStartedMovingToNode = tick()

		local firstNode = path[1]
		local distToFirst = (npcPos - firstNode.position).Magnitude
		if distToFirst < 2 and #path > 1 then
			self.currentPathIndex = 2
		else
			self.currentPathIndex = 1
		end

		if self.debugEnabled and self.debugConfig.showPath then
			Visualizer.DrawNPCPath(self.pawn:GetName(), path, self.currentPathIndex, {
				color = self.debugConfig.pathColor,
			})
		end
	else
		self.currentPath = nil
	end
end

function Controller:FollowCurrentPath()
	if not self.currentPath or self.currentPathIndex > #self.currentPath then
		self.currentPath = nil
		return
	end

	if tick() - self.timeStartedMovingToNode > self.nodeTimeout then
		self.currentPath = nil
		return
	end

	local targetNode = self.currentPath[self.currentPathIndex]
	self.pawn:MoveTo(targetNode.position)

	if self:HasArrivedAt(targetNode.position) then
		self.currentPathIndex = self.currentPathIndex + 1
		self.timeStartedMovingToNode = tick()
		if self.currentPathIndex > #self.currentPath then
			self.currentPath = nil
		end
	end
end

-- ==============================================================================
-- ATTACKING
-- ==============================================================================

function Controller:UpdateAttacking()
	self.pawn:StopMovement()
	self.pawn:PlayAnimation("idle")

	if not self.target then
		self:ChangeState(AIState.RETURNING)
		return
	end

	local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self.target = nil
		self:ChangeState(AIState.RETURNING)
		return
	end

	local distance = (self.pawn:GetPosition() - targetRoot.Position).Magnitude
	if distance > (self.combatSystem.attackRange + 1) then
		self:ChangeState(AIState.CHASING)
		return
	end

	self.pawn:LookAt(targetRoot.Position)
	self.combatSystem:TryAttack(self.target)
end

-- ==============================================================================
-- INVESTIGATING
-- ==============================================================================

function Controller:EnterInvestigating()
	self.investigationStartTime = tick()
	self.pawn:SetAutoRotate(true)

	if self.lastSeenPosition then
		-- Guardar la posición real donde se vio al target (NO sobrescribir con nodo)
		self.investigationTarget = self.lastSeenPosition

		self:Log("stateChanges", "Iniciando investigación (" .. self.investigationDuration .. "s) en posición " .. tostring(self.investigationTarget))

		if self.debugEnabled and self.debugConfig.showLastSeenPosition then
			Visualizer.DrawLastSeenPosition(self.pawn:GetName(), self.investigationTarget, {
				duration = self.investigationDuration,
				showLabels = self.debugConfig.showDebugLabels,
			})
		end

		-- Calcular ruta hacia la posición real (GetNearestNode se usa internamente para pathfinding)
		self:CalculateGraphPathToPosition(self.investigationTarget)
	end
end

function Controller:UpdateInvestigating()
	if tick() - self.investigationStartTime > self.investigationDuration then
		self:ChangeState(AIState.RETURNING)
		return
	end

	if self.currentPath and #self.currentPath > 0 then
		self.pawn:PlayAnimation("walk")
		self:FollowCurrentPath()
	else
		self.pawn:SetAutoRotate(false)
		self.pawn:StopMovement()
		self.pawn:PlayAnimation("idle")

		local currentPos = self.pawn:GetPosition()

		if self.investigationTarget then
			local directionToTarget = (self.investigationTarget - currentPos)
			directionToTarget = Vector3.new(directionToTarget.X, 0, directionToTarget.Z).Unit

			local timeInState = tick() - self.investigationStartTime
			local lookAngle = math.sin(timeInState * 2) * 45

			local baseCFrame = CFrame.lookAt(currentPos, currentPos + directionToTarget)
			local newCFrame = baseCFrame * CFrame.Angles(0, math.rad(lookAngle), 0)
			self.pawn:LerpCFrame(newCFrame, 0.1)
		end
	end
end

function Controller:ExitInvestigating()
	self.investigationStartTime = nil
	self.investigationTarget = nil
	self.pawn:SetAutoRotate(true)
	self:ClearPath()

	if self.debugEnabled and self.debugConfig.showLastSeenPosition then
		Visualizer.ClearLastSeenPosition(self.pawn:GetName())
	end
end

-- ==============================================================================
-- RETURNING
-- ==============================================================================

function Controller:EnterReturning()
	self.target = nil
	self.lastSeenPosition = nil

	self.returnTargetNode = self:GetNearestPatrolNode()
	if not self.returnTargetNode then return end
	self:CalculateGraphPathToPosition(self.returnTargetNode.Position)
end

function Controller:UpdateReturning()
	if not self.returnTargetNode or self:HasArrivedAt(self.returnTargetNode.Position) then
		self:ChangeState(AIState.PATROLLING)
		return
	end

	self:NavigateToPosition(self.returnTargetNode.Position, "patrol")
end

function Controller:ExitReturning()
	self.returnTargetNode = nil
	self:ClearPath()
end

function Controller:GetNearestPatrolNode()
	local nearestNode = nil
	local shortestDistance = math.huge
	for _, node in ipairs(self.patrolNodes) do
		local distance = (self.pawn:GetPosition() - node.Position).Magnitude
		if distance < shortestDistance then
			shortestDistance = distance
			nearestNode = node
		end
	end
	return nearestNode
end

-- ==============================================================================
-- STATE MANAGEMENT
-- ==============================================================================

function Controller:ChangeState(newState)
	if self.currentState == newState then return end

	-- EXIT
	if self.currentState == AIState.OBSERVING then
		self:ExitObserving()
	elseif self.currentState == AIState.INVESTIGATING then
		self:ExitInvestigating()
	elseif self.currentState == AIState.RETURNING then
		self:ExitReturning()
	end

	local oldState = self.currentState
	self.currentState = newState
	self.stateStartTime = tick()
	self:Log("stateChanges", oldState .. " → " .. newState)

	self.pawn:UpdateStateIndicator(newState)

	-- ENTER
	if newState == AIState.PATROLLING then
		if oldState == AIState.OBSERVING then
			self:MoveToNextPatrolNode()
		end
	elseif newState == AIState.OBSERVING then
		self:EnterObserving()
	elseif newState == AIState.INVESTIGATING then
		self:EnterInvestigating()
	elseif newState == AIState.CHASING then
		self:ClearPath()
		self.targetLastPosition = nil
	elseif newState == AIState.RETURNING then
		self:EnterReturning()
	end
end

function Controller:GetState()
	return self.currentState
end

-- ==============================================================================
-- CLEANUP
-- ==============================================================================

function Controller:Destroy()
	self.isActive = false

	if self.hearingSensor then
		self.hearingSensor:Destroy()
	end

	if self.pawn then
		self.pawn:Destroy()
	end
end

return Controller
