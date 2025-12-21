local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local NoiseService = require(script.Parent.NoiseService)
local VisionSensor = require(script.Parent.Components.VisionSensor)
local CombatSystem = require(script.Parent.Components.CombatSystem)
local HearingSensor = require(script.Parent.Components.HearingSensor)
local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)

local AIState = {
	PATROLLING = "Patrolling",
	OBSERVING = "Observing",
	CHASING = "Chasing",
	ATTACKING = "Attacking",
	INVESTIGATING = "Investigating",
	RETURNING = "Returning"
}

local NPCAIController = {}
NPCAIController.__index = NPCAIController

-- ==============================================================================
-- CONSTRUCTOR
-- ==============================================================================

function NPCAIController.new(npc, navigationGraph, config)
	local self = setmetatable({}, NPCAIController)

	self.npc = npc
	self.humanoid = npc:FindFirstChildOfClass("Humanoid")
	self.rootPart = npc:FindFirstChild("HumanoidRootPart")
	self.graph = navigationGraph

	if not self.humanoid or not self.rootPart then
		warn("⚠️ NPC " .. npc.Name .. " no tiene Humanoid o HumanoidRootPart")
		return nil
	end

	-- Configuración General
	config = config or {}
	self.patrolSpeed = config.patrolSpeed or 16
	self.chaseSpeed = config.chaseSpeed or 24
	self.patrolWaitTime = config.patrolWaitTime or 2
	
	-- Navegación
	self.navigationMode = config.navigationMode or "hybrid"
	self.graphChaseDistance = config.graphChaseDistance or 20
	self.pathRecalculateInterval = config.pathRecalculateInterval or 1.0
	self.nodeTimeout = 4

	-- Observación
	self.observationAngles = config.observationAngles or {-45, 0, 45, 0}
	self.observationTimePerAngle = config.observationTimePerAngle or 1.0
	self.rotationTweenInfo = TweenInfo.new(self.observationTimePerAngle * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- 🆕 COMPONENTES (Ojos, Músculos y Oídos)
	self.visionSensor = VisionSensor.new(npc, config)
	self.combatSystem = CombatSystem.new(npc, config)
	self.hearingSensor = HearingSensor.new(npc, config)
	
	-- Configuración de Debug visual del sensor
	if DebugConfig.visuals then
		self.visionSensor:SetDebug(DebugConfig.visuals.showVisionRays, { showRaycast = DebugConfig.visuals.showVisionRays })
	end

	-- Estado
	self.currentState = AIState.PATROLLING
	self.target = nil
	self.lastSeenPosition = nil
	self.isActive = true
	self.stateStartTime = tick()
	self.lastMoveCommand = 0
	self.timeStartedMovingToNode = 0

	-- Patrullaje
	self.patrolNodes = config.patrolNodes or {}
	self.currentPatrolIndex = 1
	self.isWaiting = false

	-- Pathfinding
	self.currentPath = nil
	self.currentPathIndex = 1
	self.lastPathCalculation = 0
	self.targetLastPosition = nil
	
	-- Debug logging
	local loggingConfig = config.logging or DebugConfig.logging or {}
	self.logFlags = {
		stateChanges = loggingConfig.stateChanges or false,
		detection = loggingConfig.detection or false,
		pathfinding = loggingConfig.pathfinding or false,
		returning = loggingConfig.returning or false,
	}

	-- 🆕 Sistema de animaciones custom
	local NPCAnimator = require(script.Parent.NPCAnimator)
	self.animator = NPCAnimator.new(self.humanoid)

	-- 🆕 Sistema de indicadores de estado
	self.showStateIndicator = config.showStateIndicator or false
	self.stateIndicatorOffset = config.stateIndicatorOffset or 4
	if self.showStateIndicator then
		self:CreateStateIndicator()
	end

	-- Iniciar
	if #self.patrolNodes > 0 then
		self:MoveToNextPatrolNode()
	end

	return self
end

-- ==============================================================================
-- DEBUG LOGGING
-- ==============================================================================

function NPCAIController:Log(category, message)
	if self.logFlags[category] then
		print("[" .. self.npc.Name .. "][" .. category .. "] " .. message)
	end
end

-- ==============================================================================
-- MAIN UPDATE LOOP
-- ==============================================================================

function NPCAIController:Update(_deltaTime)
	if not self.isActive or not self.humanoid or self.humanoid.Health <= 0 then
		self.isActive = false
		return
	end

	self:UpdateSenses() -- 🆕 Fase 1: Percibir

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
-- SENSORY SYSTEM (REFACTORIZADO)
-- ==============================================================================

function NPCAIController:UpdateSenses()
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
		
		-- Prioridad absoluta: Si vemos a alguien y no estamos ya atacando/persiguiendo, cambiar.
		if self.currentState ~= AIState.CHASING and self.currentState ~= AIState.ATTACKING then
			self:ChangeState(AIState.CHASING)
		end
	end

	if events.TargetLost then
		self:Log("detection", "TARGET PERDIDO (Olvido total)")
		self.target = nil
		
		-- Si estábamos ocupados con el target, ahora pasamos a investigar su última posición
		if self.currentState == AIState.CHASING or self.currentState == AIState.ATTACKING then
			self:ChangeState(AIState.INVESTIGATING)
		end
	end

	-- 2. OÍDO (Nueva implementación)
	local heardNoisePos = self.hearingSensor:CheckForNoise()
	if heardNoisePos then
		-- Solo reaccionamos al ruido si NO estamos ocupados (Prioridad baja vs visión)
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

function NPCAIController:UpdatePatrolling()
	self.humanoid.WalkSpeed = self.patrolSpeed
	if self.animator then self.animator:PlayAnimation("walk") end

	-- Interrupciones por visión ahora manejadas en UpdateSenses()

	-- Navegación simple
	if #self.patrolNodes > 0 then
		local targetNode = self.patrolNodes[self.currentPatrolIndex]
		local distance = (self.rootPart.Position - targetNode.Position).Magnitude

		if distance < 3 then
			self:ChangeState(AIState.OBSERVING)
		else
			if not self.lastMoveCommand or tick() - self.lastMoveCommand > 0.5 then
				self.humanoid:MoveTo(targetNode.Position)
				self.lastMoveCommand = tick()
			end
		end
	end
end

function NPCAIController:MoveToNextPatrolNode()
	if #self.patrolNodes == 0 then return end
	self.currentPatrolIndex = self.currentPatrolIndex + 1
	if self.currentPatrolIndex > #self.patrolNodes then self.currentPatrolIndex = 1 end
	local targetNode = self.patrolNodes[self.currentPatrolIndex]
	self.humanoid:MoveTo(targetNode.Position)
end

-- ==============================================================================
-- OBSERVING
-- ==============================================================================

function NPCAIController:EnterObserving()
	self.currentObservationIndex = 1
	self.observationStartTime = tick()

	-- Orientación hacia el siguiente nodo
	local nextPatrolIndex = self.currentPatrolIndex + 1
	if nextPatrolIndex > #self.patrolNodes then nextPatrolIndex = 1 end
	local currentNode = self.patrolNodes[self.currentPatrolIndex]
	local nextNode = self.patrolNodes[nextPatrolIndex]
	local directionToNext = (nextNode.Position - currentNode.Position) * Vector3.new(1,0,1)

	if directionToNext.Magnitude > 0.1 then
		self.originalCFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + directionToNext)
		self.rootPart.CFrame = self.originalCFrame
	else
		self.originalCFrame = self.rootPart.CFrame
	end

	self.humanoid:MoveTo(self.rootPart.Position)
	self.humanoid.AutoRotate = false
	if self.animator then self.animator:PlayAnimation("idle") end
	self:RotateToObservationAngle(self.observationAngles[1])
end

function NPCAIController:UpdateObserving()
	-- Interrupciones manejadas en UpdateSenses()

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

function NPCAIController:ExitObserving()
	if self.currentRotationTween then self.currentRotationTween:Cancel() end
	self.currentObservationIndex = 1
	self.originalCFrame = nil
	self.targetObservationCFrame = nil
	self.humanoid.AutoRotate = true
end

function NPCAIController:RotateToObservationAngle(angle)
	if not self.originalCFrame then return end
	if self.currentRotationTween then self.currentRotationTween:Cancel() end
	
	local targetCFrame = self.originalCFrame * CFrame.Angles(0, math.rad(angle), 0)
	self.currentRotationTween = TweenService:Create(self.rootPart, self.rotationTweenInfo, {CFrame = targetCFrame})
	self.currentRotationTween:Play()
end

-- ==============================================================================
-- CHASING
-- ==============================================================================

function NPCAIController:UpdateChasing()
	self.humanoid.WalkSpeed = self.chaseSpeed
	if self.animator then self.animator:PlayAnimation("run") end

	if not self.target then
		self:ChangeState(AIState.RETURNING)
		return
	end

	local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self.target = nil
		return
	end

	-- Verificar rango de ataque usando el CombatSystem (consultar solamente)
	local distance = (self.rootPart.Position - targetRoot.Position).Magnitude
	if distance <= self.combatSystem.attackRange then -- Accedemos a config del combat system
		self.currentPath = nil
		self:ChangeState(AIState.ATTACKING)
		return
	end

	-- El VisionSensor ya actualiza lastSeenPosition en UpdateSenses
	self:NavigateToTarget(targetRoot)
end

function NPCAIController:NavigateToTarget(targetRoot)
	local distance = (self.rootPart.Position - targetRoot.Position).Magnitude
	
	-- Lógica de navegación (Graph vs Direct)
	if self.navigationMode == "graph" then
		self:ChaseUsingGraph(targetRoot)
	elseif self.navigationMode == "pathfinding" then
		self.humanoid:MoveTo(targetRoot.Position)
	else -- hybrid
		if distance <= self.graphChaseDistance then
			self.currentPath = nil
			self.humanoid:MoveTo(targetRoot.Position)
		else
			self:ChaseUsingGraph(targetRoot)
		end
	end
end

function NPCAIController:ChaseUsingGraph(targetRoot)
	local currentTime = tick()
	local targetPosition = targetRoot.Position
	local targetMoved = self.targetLastPosition and (targetPosition - self.targetLastPosition).Magnitude > 15
	local needsRecalculation = not self.currentPath or currentTime - self.lastPathCalculation > self.pathRecalculateInterval or targetMoved

	if needsRecalculation then
		self:CalculateGraphPathToPosition(targetPosition)
		self.lastPathCalculation = currentTime
		self.targetLastPosition = targetPosition
	end

	if self.currentPath and #self.currentPath > 0 then
		self:FollowCurrentPath()
	else
		self.humanoid:MoveTo(targetPosition)
	end
end

function NPCAIController:CalculateGraphPathToPosition(targetPosition)
	local startNode = self.graph:GetNearestNode(self.rootPart.Position)
	local endNode = self.graph:GetNearestNode(targetPosition)

	if not startNode or not endNode then
		self.currentPath = nil
		return
	end

	local path = self.graph:GetPathBetweenNodes(startNode, endNode)

	if path and #path > 0 then
		self.currentPath = path
		self.timeStartedMovingToNode = tick()
		
		-- Optimización de inicio de path
		local bestIndex = 1
		local npcPos = self.rootPart.Position
		local bestScore = math.huge
		for i, node in ipairs(path) do
			local distToNode = (npcPos - node.position).Magnitude
			local distNodeToEnd = (node.position - targetPosition).Magnitude
			local score = distToNode + distNodeToEnd * 0.1
			if distToNode < 5 and score < bestScore then
				bestScore = score
				bestIndex = i
			end
		end
		if bestIndex < #path then
			if (npcPos - path[bestIndex].position).Magnitude < 2 then bestIndex = bestIndex + 1 end
		end
		self.currentPathIndex = bestIndex
	else
		self.currentPath = nil
	end
end

function NPCAIController:FollowCurrentPath()
	if not self.currentPath or self.currentPathIndex > #self.currentPath then
		self.currentPath = nil
		return
	end

	if tick() - self.timeStartedMovingToNode > self.nodeTimeout then
		self.currentPath = nil
		return
	end

	local targetNode = self.currentPath[self.currentPathIndex]
	local distance = (self.rootPart.Position - targetNode.position).Magnitude
	self.humanoid:MoveTo(targetNode.position)

	if distance < 3 then
		self.currentPathIndex = self.currentPathIndex + 1
		self.timeStartedMovingToNode = tick()
		if self.currentPathIndex > #self.currentPath then self.currentPath = nil end
	end
end

-- ==============================================================================
-- ATTACKING (REFACTORIZADO)
-- ==============================================================================

function NPCAIController:UpdateAttacking()
	self.humanoid:MoveTo(self.rootPart.Position)
	if self.animator then self.animator:PlayAnimation("idle") end

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

	-- Verificar rango + buffer
	local distance = (self.rootPart.Position - targetRoot.Position).Magnitude
	if distance > (self.combatSystem.attackRange + 1) then
		self:ChangeState(AIState.CHASING)
		return
	end

	-- Mirar al target
	local direction = (targetRoot.Position - self.rootPart.Position) * Vector3.new(1, 0, 1)
	if direction.Magnitude > 0 then
		self.rootPart.CFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + direction)
	end

	-- 🆕 USAR COMBAT SYSTEM
	self.combatSystem:TryAttack(self.target)
end

-- ==============================================================================
-- INVESTIGATING
-- ==============================================================================

function NPCAIController:EnterInvestigating()
	self:Log("stateChanges", "Iniciando investigación en " .. tostring(self.lastSeenPosition))
	self.investigationStartTime = tick()
	self.investigationDuration = 15
	self.humanoid.AutoRotate = true
    if self.lastSeenPosition then
	    self:CalculateGraphPathToPosition(self.lastSeenPosition)
    end
end

function NPCAIController:UpdateInvestigating()
	if tick() - self.investigationStartTime > self.investigationDuration then
		self:ChangeState(AIState.RETURNING)
		return
	end
	
	-- Vision check es en UpdateSenses

	if self.currentPath and #self.currentPath > 0 then
		if self.animator then self.animator:PlayAnimation("walk") end
		self:FollowCurrentPath()
	else
		self.humanoid.AutoRotate = false
		self.humanoid:MoveTo(self.rootPart.Position)
		if self.animator then self.animator:PlayAnimation("idle") end
		
		-- Comportamiento de mirar alrededor
		local timeInState = tick() - self.stateStartTime
		local lookAngle = math.sin(timeInState * 2) * 45
		local lookDirection = self.rootPart.CFrame.LookVector
		local newCFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + lookDirection) * CFrame.Angles(0, math.rad(lookAngle), 0)
		self.rootPart.CFrame = self.rootPart.CFrame:Lerp(newCFrame, 0.1)
	end
end

function NPCAIController:ExitInvestigating()
	self.investigationStartTime = nil
	self.humanoid.AutoRotate = true
	self.currentPath = nil
	self.currentPathIndex = 1
end

-- ==============================================================================
-- RETURNING
-- ==============================================================================

function NPCAIController:EnterReturning()
	self.target = nil
	self.lastSeenPosition = nil
	-- Resetear sensor al iniciar retorno para evitar "fantasmas"
	-- self.visionSensor:Reset() -- TODO: Implementar si fuera necesario

	self.returnTargetNode = self:GetNearestPatrolNode()
	if not self.returnTargetNode then return end
	self:CalculateGraphPathToPosition(self.returnTargetNode.Position)
end

function NPCAIController:UpdateReturning()
	self.humanoid.WalkSpeed = self.patrolSpeed
	if self.animator then self.animator:PlayAnimation("walk") end
	
	-- Interrupción por visión en UpdateSenses

	if self.returnTargetNode and (self.rootPart.Position - self.returnTargetNode.Position).Magnitude < 3 then
		self:ChangeState(AIState.PATROLLING)
		return
	end

	if self.currentPath and #self.currentPath > 0 then
		self:FollowCurrentPath()
	elseif self.returnTargetNode then
		self.humanoid:MoveTo(self.returnTargetNode.Position)
	else
		self:ChangeState(AIState.PATROLLING)
	end
end

function NPCAIController:ExitReturning()
	self.returnTargetNode = nil
	self.currentPath = nil
	self.currentPathIndex = 1
end

function NPCAIController:GetNearestPatrolNode()
	local nearestNode = nil
	local shortestDistance = math.huge
	for _, node in ipairs(self.patrolNodes) do
		local distance = (self.rootPart.Position - node.Position).Magnitude
		if distance < shortestDistance then
			shortestDistance = distance
			nearestNode = node
		end
	end
	return nearestNode
end

-- ==============================================================================
-- STATE MANAGEMENT & INDICATORS
-- ==============================================================================

local STATE_VISUALS = {
	[AIState.PATROLLING] = {emoji = "🚶", text = "PATROLLING", color = Color3.fromRGB(0, 255, 0)},
	[AIState.OBSERVING] = {emoji = "👁️", text = "OBSERVING", color = Color3.fromRGB(100, 150, 255)},
	[AIState.CHASING] = {emoji = "🏃", text = "CHASING", color = Color3.fromRGB(255, 0, 0)},
	[AIState.ATTACKING] = {emoji = "⚔️", text = "ATTACKING", color = Color3.fromRGB(255, 100, 0)},
	[AIState.INVESTIGATING] = {emoji = "❓", text = "INVESTIGATING", color = Color3.fromRGB(255, 165, 0)},
	[AIState.RETURNING] = {emoji = "🔄", text = "RETURNING", color = Color3.fromRGB(255, 255, 0)}
}

function NPCAIController:CreateStateIndicator()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StateIndicator"
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffset = Vector3.new(0, self.stateIndicatorOffset, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = self.rootPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🚶 PATROLLING"
	label.TextSize = 18
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.fromRGB(0, 255, 0)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard

	self.stateIndicator = {billboard = billboard, label = label}
end

function NPCAIController:UpdateStateIndicator()
	if not self.showStateIndicator or not self.stateIndicator then return end
	local visual = STATE_VISUALS[self.currentState]
	if visual then
		self.stateIndicator.label.Text = visual.emoji .. " " .. visual.text
		self.stateIndicator.label.TextColor3 = visual.color
	end
end

function NPCAIController:ChangeState(newState)
	if self.currentState == newState then return end

	-- EXIT
	if self.currentState == AIState.OBSERVING then self:ExitObserving()
	elseif self.currentState == AIState.INVESTIGATING then self:ExitInvestigating()
	elseif self.currentState == AIState.RETURNING then self:ExitReturning() end

	local oldState = self.currentState
	self.currentState = newState
	self.stateStartTime = tick()
	self:Log("stateChanges", oldState .. " → " .. newState)

	if self.showStateIndicator then self:UpdateStateIndicator() end

	-- ENTER
	if newState == AIState.PATROLLING then
		if oldState == AIState.OBSERVING then self:MoveToNextPatrolNode() end
	elseif newState == AIState.OBSERVING then self:EnterObserving()
	elseif newState == AIState.INVESTIGATING then self:EnterInvestigating()
	elseif newState == AIState.CHASING then
		self.currentPath = nil
		self.currentPathIndex = 1
		self.lastPathCalculation = 0
		self.targetLastPosition = nil
	elseif newState == AIState.RETURNING then self:EnterReturning()
	end
end

function NPCAIController:Destroy()
	self.isActive = false
	if self.currentRotationTween then self.currentRotationTween:Cancel() end
	if self.stateIndicator then self.stateIndicator.billboard:Destroy() end
	if self.animator then self.animator:Destroy() end
	
	-- Limpiar sensores
	if self.hearingSensor then self.hearingSensor:Destroy() end
end

return NPCAIController