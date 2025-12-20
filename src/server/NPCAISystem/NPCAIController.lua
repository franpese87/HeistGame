local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local AIState = {
	PATROLLING = "Patrolling",
	OBSERVING = "Observing",
	CHASING = "Chasing",
	ATTACKING = "Attacking",
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

	-- Configuración
	config = config or {}
	self.detectionRange = config.detectionRange or 50
	self.attackRange = config.attackRange or 5
	self.loseTargetTime = config.loseTargetTime or 3
	self.patrolSpeed = config.patrolSpeed or 16
	self.chaseSpeed = config.chaseSpeed or 24
	self.patrolWaitTime = config.patrolWaitTime or 2
	self.attackCooldown = config.attackCooldown or 1
	self.attackDamage = config.attackDamage or 10
	self.visionHeight = config.visionHeight or 2

	-- Navegación
	self.navigationMode = config.navigationMode or "hybrid"
	self.graphChaseDistance = config.graphChaseDistance or 20
	self.pathRecalculateInterval = config.pathRecalculateInterval or 1.0

	-- Sistema de cono de visión
	self.observationConeRays = config.observationConeRays or 11
	self.observationConeAngle = config.observationConeAngle or 90
	self.minDetectionTime = config.minDetectionTime or 0.3
	self.coneVisualDuration = config.coneVisualDuration or 0.1

	-- 🆕 Sistema de indicadores de estado (debug visual)
	self.showStateIndicator = config.showStateIndicator or false
	self.stateIndicatorOffset = config.stateIndicatorOffset or 4
	self.stateIndicator = nil

	-- Sistema de observación (ahora como estado independiente)
	self.observationAngles = config.observationAngles or {-45, 0, 45, 0}
	self.observationTimePerAngle = config.observationTimePerAngle or 1.0
	self.currentObservationIndex = 1
	self.observationStartTime = 0
	self.originalCFrame = nil
	self.targetObservationCFrame = nil
	self.currentRotationTween = nil
	self.rotationTweenInfo = TweenInfo.new(
		self.observationTimePerAngle * 0.3,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	-- Estado
	self.currentState = AIState.PATROLLING
	self.target = nil
	self.lastSeenPosition = nil
	self.lastSeenTime = 0
	self.isActive = true
	self.stateStartTime = tick()
	self.lastAttackTime = 0
	self.lastMoveCommand = 0

	-- Patrullaje
	self.patrolNodes = config.patrolNodes or {}
	self.currentPatrolIndex = 1
	self.isWaiting = false

	-- Pathfinding
	self.currentPath = nil
	self.currentPathIndex = 1
	self.lastPathCalculation = 0
	self.targetLastPosition = nil
	
	-- fperease
	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.FilterDescendantsInstances = {self.npc}

	-- Detección simplificada (sin gracia)
	self.detectionFrameCount = nil
	self.lostDetectionTime = nil

	-- Debug visual (raycast)
	self.debugEnabled = false
	self.debugConfig = {}

	-- Debug logging (console)
	local loggingConfig = config.logging or {}
	self.logFlags = {
		stateChanges = loggingConfig.stateChanges or false,
		detection = loggingConfig.detection or false,
		pathfinding = loggingConfig.pathfinding or false,
		returning = loggingConfig.returning or false,
	}

	-- 🆕 Sistema de animaciones custom
	local NPCAnimator = require(script.Parent.NPCAnimator)
	self.animator = NPCAnimator.new(self.humanoid)

	-- Iniciar patrullaje
	if #self.patrolNodes > 0 then
		self:MoveToNextPatrolNode()
	end

	-- 🆕 Crear indicador de estado si está habilitado
	if self.showStateIndicator then
		self:CreateStateIndicator()
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

function NPCAIController:Update(_deltaTime )
	if not self.isActive or not self.humanoid or self.humanoid.Health <= 0 then
		self.isActive = false
		return
	end

	self:DetectTargets()

	if self.currentState == AIState.PATROLLING then
		self:UpdatePatrolling()
	elseif self.currentState == AIState.OBSERVING then
		self:UpdateObserving()  -- 🆕 Nuevo estado
	elseif self.currentState == AIState.CHASING then
		self:UpdateChasing()
	elseif self.currentState == AIState.ATTACKING then
		self:UpdateAttacking()
	elseif self.currentState == AIState.RETURNING then
		self:UpdateReturning()
	end
end

-- ==============================================================================
-- DETECTION SYSTEM (CONE RAYCAST - SIN GRACIA)
-- ==============================================================================

function NPCAIController:DetectTargets()
	local nearestTarget = nil
	local nearestDistance = self.detectionRange
	local currentTime = tick()

	for _, player in ipairs(game.Players:GetPlayers()) do
		if player.Character then
			local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = player.Character:FindFirstChildOfClass("Humanoid")

			if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
				-- ✅ OPTIMIZACIÓN: Verificar distancia primero (barato)
				local distance = (self.rootPart.Position - targetRoot.Position).Magnitude

				if distance < nearestDistance then
					-- ✅ DETECCIÓN: Disparar cono de raycast
					if self:HasLineOfSightWithCone(targetRoot) then
						nearestDistance = distance
						nearestTarget = player.Character
						self.lastSeenTime = currentTime
					end
				end
			end
		end
	end

	self:ProcessDetectionResult(nearestTarget, currentTime)
end

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

-- fperease
function NPCAIController:HasLineOfSightWithCone(targetPart)
	local origin = self.rootPart.Position + Vector3.new(0, self.visionHeight, 0)
	local targetPos = targetPart.Position
	local directionVector = (targetPos - origin)
	local distance = directionVector.Magnitude

	-- 1. CHEQUEO DE DISTANCIA (Rango máximo)
	if distance > self.detectionRange then 
		return false 
	end

	-- 2. CÁLCULO DE ÁNGULO HORIZONTAL (Planar Check)
	-- Aplanamos los vectores anulando la altura (Y = 0)
	-- Esto convierte el cono en una "rebanada de pizza" infinita hacia arriba y abajo
	local lookVectorFlat = (self.rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local directionFlat = (directionVector * Vector3.new(1, 0, 1)).Unit

	-- Calculamos el ángulo solo en el plano del suelo
	local dotProduct = lookVectorFlat:Dot(directionFlat)
	local halfAngleRad = math.rad(self.observationConeAngle / 2)
	local threshold = math.cos(halfAngleRad)

	-- Si estás detrás o a los lados (fuera del ángulo horizontal), no te ve.
	-- Esto PRESERVA EL SIGILO por la espalda.
	if dotProduct < threshold then
		return false 
	end

	-- 3. RAYCAST DE OCLUSIÓN (Físico)
	-- Aquí sí usamos 3D. Si hay un muro, una caja, o un techo entre los dos, el rayo fallará.
	return self:CheckOcclusion(origin, directionVector, targetPart)
end

-- fperease
-- Función auxiliar (se mantiene igual, pero asegúrate de tenerla)
function NPCAIController:CheckOcclusion(origin, direction, targetPart)
	if not self.raycastParams then
		self.raycastParams = RaycastParams.new()
		self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		self.raycastParams.FilterDescendantsInstances = {self.npc}
	end

	local result = workspace:Raycast(origin, direction, self.raycastParams)
	local canSee = false

	if result and result.Instance:IsDescendantOf(targetPart.Parent) then
		canSee = true
	end

	-- DEBUG VISUAL
	if self.debugEnabled and self.debugConfig.showRaycast then
		-- Verde = Te veo claro | Rojo = Sé que estás ahí, pero algo te tapa
		local debugColor = canSee and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
		local DebugUtilities = require(script.Parent.DebugUtilities)
		DebugUtilities.VisualizeRaycast(origin, direction, result, {
			hitColor = debugColor,
			missColor = debugColor,
			duration = 0.1,
			width = 0.1
		})
	end

	return canSee
end

-- fperease
function NPCAIController:ProcessDetectionResult(nearestTarget, currentTime)
	-- CONFIGURACIÓN DEL BUFFER
	-- Tiempo (en segundos) que el NPC "recuerda" haberte visto aunque el raycast falle.
	-- 0.5s es ideal: elimina el parpadeo pero no permite que el jugador cruce pasillos sin ser visto.
	local COYOTE_TIME = 0.5 

	-- Calcular delta time
	local deltaTime = 0
	if self.lastDetectionUpdate then
		deltaTime = currentTime - self.lastDetectionUpdate
	else
		deltaTime = 0.03 
	end
	self.lastDetectionUpdate = currentTime

	-- 🧠 CÁLCULO DE "VISIÓN EFECTIVA"
	-- El NPC te ve si el Raycast acierta (nearestTarget) O SI acertó hace menos de 0.5s (Coyote Time)
	local timeSinceLastSight = currentTime - (self.lastSeenTime or 0)
	local inCoyoteTime = timeSinceLastSight < COYOTE_TIME

	-- ¿Estamos viendo al objetivo? (Física o Mentalmente)
	local isDetecting = nearestTarget ~= nil

	------------------------------------------------------------------------
	-- CASO 1: TE ESTOY VIENDO (Físicamente)
	------------------------------------------------------------------------
	if isDetecting then
		-- INICIO DE DETECCIÓN
		if not self.detectionTimeAccumulator then
			self.detectionTimeAccumulator = 0
		end

		-- Sumar tiempo
		self.detectionTimeAccumulator = self.detectionTimeAccumulator + deltaTime

		-- CONFIRMACIÓN
		if self.detectionTimeAccumulator >= self.minDetectionTime then
			if not self.target then
				self.target = nearestTarget
				self:Log("detection", "TARGET CONFIRMADO: " .. nearestTarget.Name)

				if self.currentState == "Patrolling" or self.currentState == "Observing" then
					self:ChangeState("Chasing")
				end
			end
		end

		-- Reseteamos temporizador de pérdida
		self.lostDetectionTime = nil

		------------------------------------------------------------------------
		-- CASO 2: EL RAYCAST FALLÓ, PERO ESTOY EN "COYOTE TIME" (Buffer)
		-- No sumamos ni restamos detección - "congelamos" la barra de progreso
		------------------------------------------------------------------------

		------------------------------------------------------------------------
		-- CASO 3: REALMENTE TE PERDÍ (Fuera de Buffer)
		------------------------------------------------------------------------
	elseif not (inCoyoteTime and self.detectionTimeAccumulator and self.detectionTimeAccumulator > 0) then
		-- Reset rápido de acumulación
		if self.detectionTimeAccumulator and self.detectionTimeAccumulator > 0 then
			-- Penalización (baja la barra)
			self.detectionTimeAccumulator = self.detectionTimeAccumulator - (deltaTime * 2)

			if self.detectionTimeAccumulator <= 0 then
				self.detectionTimeAccumulator = nil
			end
		end

		-- Sistema de olvidar target confirmado (Memoria a largo plazo)
		if self.target then
			if not self.lostDetectionTime then
				self.lostDetectionTime = currentTime
			end

			local timeLost = currentTime - self.lostDetectionTime

			if timeLost >= self.loseTargetTime then
				self:Log("detection", "TARGET PERDIDO tras " .. string.format("%.1f", timeLost) .. "s")
				self.target = nil
				self.lostDetectionTime = nil
				self.detectionTimeAccumulator = nil

				if self.currentState == "Chasing" or self.currentState == "Attacking" then
					self:ChangeState("Returning")
				end
			end
		end
	end
end

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

function NPCAIController:VisualizeObservationCone(origin, rayHits)
	for _, ray in ipairs(rayHits) do
		local endPoint = origin + ray.direction

		-- Color: Verde si detectó jugador, Rojo si bloqueado, Verde claro si libre
		local color = Color3.fromRGB(0, 200, 0) -- Default: Verde claro (libre)
		if ray.result then
			color = ray.hit and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
		end

		local line = Instance.new("LineHandleAdornment")
		line.Adornee = workspace.Terrain
		line.Color3 = color
		line.Length = ray.direction.Magnitude
		line.Thickness = 3
		line.Transparency = 0.5
		line.AlwaysOnTop = true
		line.ZIndex = 1
		line.CFrame = CFrame.new(origin, endPoint)
		line.Parent = workspace.Terrain

		Debris:AddItem(line, self.coneVisualDuration)
	end
end

-- ==============================================================================
-- PATROLLING (SIMPLIFICADO - SOLO NAVEGACIÓN)
-- ==============================================================================

function NPCAIController:UpdatePatrolling()
	self.humanoid.WalkSpeed = self.patrolSpeed

	-- 🆕 Animación de caminar
	if self.animator then
		self.animator:PlayAnimation("walk")
	end

	if self.target then
		self:ChangeState(AIState.CHASING)
		return
	end

	-- Navegación simple hacia el nodo
	if #self.patrolNodes > 0 then
		local targetNode = self.patrolNodes[self.currentPatrolIndex]
		local distance = (self.rootPart.Position - targetNode.Position).Magnitude

		if distance < 3 then
			-- Llegamos al nodo → Cambiar a OBSERVING
			self:ChangeState(AIState.OBSERVING)
		else
			-- Continuar moviéndose
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
	if self.currentPatrolIndex > #self.patrolNodes then
		self.currentPatrolIndex = 1
	end

	local targetNode = self.patrolNodes[self.currentPatrolIndex]
	self.humanoid:MoveTo(targetNode.Position)
end

-- ==============================================================================
-- OBSERVING (NUEVO ESTADO INDEPENDIENTE)
-- ==============================================================================

function NPCAIController:EnterObserving()
	self.currentObservationIndex = 1
	self.observationStartTime = tick()

	-- Calcular orientación: mirar hacia el SIGUIENTE nodo
	local nextPatrolIndex = self.currentPatrolIndex + 1
	if nextPatrolIndex > #self.patrolNodes then
		nextPatrolIndex = 1
	end

	local currentNode = self.patrolNodes[self.currentPatrolIndex]
	local nextNode = self.patrolNodes[nextPatrolIndex]

	-- Dirección hacia el siguiente nodo
	local directionToNext = (nextNode.Position - currentNode.Position)
	local directionFlat = Vector3.new(directionToNext.X, 0, directionToNext.Z)

	-- Crear CFrame mirando hacia el siguiente nodo
	if directionFlat.Magnitude > 0.1 then
		self.originalCFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + directionFlat)
		self.rootPart.CFrame = self.originalCFrame
	else
		self.originalCFrame = self.rootPart.CFrame
	end

	-- Detener movimiento y auto-rotación
	self.humanoid:MoveTo(self.rootPart.Position)
	self.humanoid.AutoRotate = false

	-- 🆕 Animación idle al observar
	if self.animator then
		self.animator:PlayAnimation("idle")
	end

	-- Aplicar el primer ángulo con tween
	self:RotateToObservationAngle(self.observationAngles[1])
end

function NPCAIController:UpdateObserving()
	-- Interrupción: Si detectamos target, cambiar a CHASING
	if self.target then
		self:ChangeState(AIState.CHASING)
		return
	end

	local currentTime = tick()
	local timeInCurrentAngle = currentTime - self.observationStartTime

	-- Avanzar al siguiente ángulo si pasó el tiempo
	if timeInCurrentAngle >= self.observationTimePerAngle then
		self.currentObservationIndex = self.currentObservationIndex + 1

		-- Terminar secuencia: volver a PATROLLING
		if self.currentObservationIndex > #self.observationAngles then
			self:ChangeState(AIState.PATROLLING)
			return
		end

		-- Rotar al siguiente ángulo
		local nextAngle = self.observationAngles[self.currentObservationIndex]
		self.observationStartTime = currentTime
		self:RotateToObservationAngle(nextAngle)
	end
end

function NPCAIController:ExitObserving()

	-- Cancelar tween en progreso
	if self.currentRotationTween then
		self.currentRotationTween:Cancel()
		self.currentRotationTween = nil
	end

	-- Resetear variables de observación
	self.currentObservationIndex = 1
	self.originalCFrame = nil
	self.targetObservationCFrame = nil

	-- Reactivar auto-rotación
	self.humanoid.AutoRotate = true
end

function NPCAIController:RotateToObservationAngle(angle)
	if not self.originalCFrame then
		return
	end

	-- Cancelar tween anterior
	if self.currentRotationTween then
		self.currentRotationTween:Cancel()
	end

	-- Calcular nueva orientación
	local angleInRadians = math.rad(angle)
	local rotationCFrame = CFrame.Angles(0, angleInRadians, 0)
	self.targetObservationCFrame = self.originalCFrame * rotationCFrame

	-- Crear tween
	local tweenGoal = {CFrame = self.targetObservationCFrame}
	self.currentRotationTween = TweenService:Create(
		self.rootPart, 
		self.rotationTweenInfo, 
		tweenGoal
	)

	self.currentRotationTween:Play()
end

-- ==============================================================================
-- CHASING
-- ==============================================================================

function NPCAIController:UpdateChasing()
	self.humanoid.WalkSpeed = self.chaseSpeed

	-- 🆕 Animación de correr
	if self.animator then
		self.animator:PlayAnimation("run")
	end

	if not self.target then
		self:ChangeState(AIState.RETURNING)
		return
	end

	local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self.target = nil
		return
	end

	local distance = (self.rootPart.Position - targetRoot.Position).Magnitude

	if distance <= self.attackRange then
		self.currentPath = nil
		self:ChangeState(AIState.ATTACKING)
		return
	end

	self.lastSeenPosition = targetRoot.Position
	self:NavigateToTarget(targetRoot)
end

function NPCAIController:NavigateToTarget(targetRoot)
	local distance = (self.rootPart.Position - targetRoot.Position).Magnitude

	if self.navigationMode == "graph" then
		self:ChaseUsingGraph(targetRoot)
	elseif self.navigationMode == "pathfinding" then
		self:ChaseUsingPathfinding(targetRoot)
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

	local targetMoved = self.targetLastPosition
		and (targetPosition - self.targetLastPosition).Magnitude > 15

	local needsRecalculation = not self.currentPath
		or currentTime - self.lastPathCalculation > self.pathRecalculateInterval
		or targetMoved

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
		self:Log("pathfinding", "PATH FALLIDO: startNode=" .. tostring(startNode and startNode.name) .. ", endNode=" .. tostring(endNode and endNode.name))
		self.currentPath = nil
		return
	end

	local path = self.graph:GetPathBetweenNodes(startNode, endNode)

	if path and #path > 0 then
		self.currentPath = path

		-- Encontrar el mejor punto de inicio en el path
		-- En lugar de siempre empezar en índice 1, buscar el nodo más cercano
		-- que esté "adelante" en la dirección del objetivo
		local bestIndex = 1
		local npcPos = self.rootPart.Position
		local bestScore = math.huge

		for i, node in ipairs(path) do
			local distToNode = (npcPos - node.position).Magnitude
			-- Penalizar nodos que están más lejos del objetivo final
			local distNodeToEnd = (node.position - targetPosition).Magnitude
			-- Score: queremos estar cerca del nodo Y que ese nodo esté cerca del final
			local score = distToNode + distNodeToEnd * 0.1

			if distToNode < 5 and score < bestScore then
				bestScore = score
				bestIndex = i
			end
		end

		-- Si estamos muy cerca del nodo en bestIndex, avanzar al siguiente
		if bestIndex < #path then
			local distToBest = (npcPos - path[bestIndex].position).Magnitude
			if distToBest < 2 then
				bestIndex = bestIndex + 1
			end
		end

		self.currentPathIndex = bestIndex
		self:Log("pathfinding", "PATH CALCULADO: " .. startNode.name .. " → " .. endNode.name .. " (" .. #path .. " nodos, inicio=" .. bestIndex .. ")")
	else
		self:Log("pathfinding", "PATH NO ENCONTRADO: " .. startNode.name .. " → " .. endNode.name .. " (nodos desconectados?)")
		self.currentPath = nil
	end
end

function NPCAIController:FollowCurrentPath()
	if not self.currentPath or self.currentPathIndex > #self.currentPath then
		self.currentPath = nil
		return
	end

	local targetNode = self.currentPath[self.currentPathIndex]
	local distance = (self.rootPart.Position - targetNode.position).Magnitude

	self.humanoid:MoveTo(targetNode.position)

	if distance < 3 then
		self.currentPathIndex = self.currentPathIndex + 1

		if self.currentPathIndex > #self.currentPath then
			self.currentPath = nil
		end
	end
end

function NPCAIController:ChaseUsingPathfinding(targetRoot)
	self.humanoid:MoveTo(targetRoot.Position)
end

-- NavigateToPosition: Usado para persecución (objetivo dinámico)
-- Para objetivos estáticos (retorno), usar EnterReturning + FollowCurrentPath
function NPCAIController:NavigateToPosition(position)
	if self.navigationMode == "graph" or self.navigationMode == "hybrid" then
		local currentTime = tick()

		-- Recalcular si no hay path o pasó el intervalo
		if not self.currentPath or currentTime - self.lastPathCalculation > self.pathRecalculateInterval then
			self:CalculateGraphPathToPosition(position)
			self.lastPathCalculation = currentTime
		end

		if self.currentPath and #self.currentPath > 0 then
			self:FollowCurrentPath()
		else
			self.humanoid:MoveTo(position)
		end
	else
		self.humanoid:MoveTo(position)
	end
end

-- ==============================================================================
-- ATTACKING
-- ==============================================================================

function NPCAIController:UpdateAttacking()
	self.humanoid:MoveTo(self.rootPart.Position)

	-- 🆕 Idle mientras ataca
	if self.animator then
		self.animator:PlayAnimation("idle")
	end

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

	local distance = (self.rootPart.Position - targetRoot.Position).Magnitude

	-- Buffer zone para evitar thrashing
	if distance > (self.attackRange + 1) then
		self:ChangeState(AIState.CHASING)
		return
	end

	-- Mirar al target
	local direction = (targetRoot.Position - self.rootPart.Position) * Vector3.new(1, 0, 1)
	if direction.Magnitude > 0 then
		self.rootPart.CFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + direction)
	end

	if tick() - self.lastAttackTime >= self.attackCooldown then
		self:PerformAttack()
		self.lastAttackTime = tick()
	end
end

function NPCAIController:PerformAttack()
	if not self.target then return end

	local targetHumanoid = self.target:FindFirstChildOfClass("Humanoid")
	if targetHumanoid then
		targetHumanoid:TakeDamage(self.attackDamage)
	end
end

-- ==============================================================================
-- RETURNING (Arquitectura Enter/Update separada)
-- ==============================================================================

function NPCAIController:EnterReturning()
	-- Limpiar estado de persecución
	self.target = nil
	self.lastSeenPosition = nil
	self.detectionFrameCount = nil
	self.lostDetectionTime = nil

	-- Determinar destino de retorno (se calcula UNA vez al entrar)
	self.returnTargetNode = self:GetNearestPatrolNode()

	if not self.returnTargetNode then
		warn("[" .. self.npc.Name .. "] No se encontró nodo de patrulla para retorno")
		return
	end

	-- Calcular ruta completa UNA sola vez
	self:CalculateGraphPathToPosition(self.returnTargetNode.Position)

	self:Log("returning", "Iniciando retorno a " .. self.returnTargetNode.Name ..
		" (dist=" .. string.format("%.1f", (self.rootPart.Position - self.returnTargetNode.Position).Magnitude) .. ")" ..
		(self.currentPath and (" [" .. #self.currentPath .. " nodos]") or " [directo]"))
end

function NPCAIController:UpdateReturning()
	self.humanoid.WalkSpeed = self.patrolSpeed

	if self.animator then
		self.animator:PlayAnimation("walk")
	end

	-- Interrupción: Si detectamos target, volver a CHASING
	if self.target then
		self:Log("returning", "Target detectado durante retorno, volviendo a CHASING")
		self:ChangeState(AIState.CHASING)
		return
	end

	-- Verificar si llegamos al destino
	if self.returnTargetNode then
		local distance = (self.rootPart.Position - self.returnTargetNode.Position).Magnitude

		if distance < 3 then
			self:Log("returning", "Llegué a nodo patrulla: " .. self.returnTargetNode.Name)
			self:ChangeState(AIState.PATROLLING)
			return
		end
	end

	-- Ejecutar el plan: seguir el path pre-calculado
	if self.currentPath and #self.currentPath > 0 then
		self:FollowCurrentPath()
	elseif self.returnTargetNode then
		-- Fallback: movimiento directo si no hay path
		self.humanoid:MoveTo(self.returnTargetNode.Position)
	else
		-- Sin destino válido, volver a patrullar
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
-- STATE INDICATOR SYSTEM (DEBUG VISUAL)
-- ==============================================================================

local STATE_VISUALS = {
	[AIState.PATROLLING] = {
		emoji = "🚶",
		text = "PATROLLING",
		color = Color3.fromRGB(0, 255, 0),  -- Verde
	},
	[AIState.OBSERVING] = {
		emoji = "👁️",
		text = "OBSERVING",
		color = Color3.fromRGB(100, 150, 255),  -- Azul
	},
	[AIState.CHASING] = {
		emoji = "🏃",
		text = "CHASING",
		color = Color3.fromRGB(255, 0, 0),  -- Rojo
	},
	[AIState.ATTACKING] = {
		emoji = "⚔️",
		text = "ATTACKING",
		color = Color3.fromRGB(255, 100, 0),  -- Naranja
	},
	[AIState.RETURNING] = {
		emoji = "🔄",
		text = "RETURNING",
		color = Color3.fromRGB(255, 255, 0),  -- Amarillo
	}
}

function NPCAIController:CreateStateIndicator()
	-- BillboardGui simple con emoji + texto
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StateIndicator"
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffset = Vector3.new(0, self.stateIndicatorOffset, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = self.rootPart

	-- Label con emoji + texto
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1  -- Sin fondo
	label.Text = "🚶 PATROLLING"
	label.TextSize = 18
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.fromRGB(0, 255, 0)  -- Verde inicial
	label.TextStrokeTransparency = 0.5  -- Contorno para legibilidad
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard

	self.stateIndicator = {
		billboard = billboard,
		label = label
	}
end

function NPCAIController:UpdateStateIndicator()
	if not self.showStateIndicator then return end

	local visual = STATE_VISUALS[self.currentState]
	if not visual then
		return
	end

	-- Actualizar emoji + texto + color
	if self.stateIndicator then
		self.stateIndicator.label.Text = visual.emoji .. " " .. visual.text
		self.stateIndicator.label.TextColor3 = visual.color
	end
end

function NPCAIController:DestroyStateIndicator()
	if self.stateIndicator and self.stateIndicator.billboard then
		self.stateIndicator.billboard:Destroy()
		self.stateIndicator = nil
	end
end

-- ==============================================================================
-- STATE MANAGEMENT (REFACTORIZADO CON ENTER/EXIT)
-- ==============================================================================

function NPCAIController:ChangeState(newState)
	if self.currentState == newState then return end

	-- EXIT del estado anterior
	if self.currentState == AIState.OBSERVING then
		self:ExitObserving()
	elseif self.currentState == AIState.RETURNING then
		self:ExitReturning()
	end

	local oldState = self.currentState
	self.currentState = newState
	self.stateStartTime = tick()

	-- Debug: Log transición de estado
	self:Log("stateChanges", oldState .. " → " .. newState)

	-- Actualizar indicador visual de estado
	if self.showStateIndicator then
		self:UpdateStateIndicator()
	end

	-- ENTER del nuevo estado
	if newState == AIState.PATROLLING then
		-- Solo avanzar nodo si venimos de OBSERVING
		if oldState == AIState.OBSERVING then
			self:MoveToNextPatrolNode()
		end
		self.detectionFrameCount = nil

	elseif newState == AIState.OBSERVING then
		self:EnterObserving()

	elseif newState == AIState.CHASING then
		self.currentPath = nil
		self.currentPathIndex = 1
		self.lastPathCalculation = 0
		self.targetLastPosition = nil

	elseif newState == AIState.RETURNING then
		self:EnterReturning()
	end
end

function NPCAIController:Destroy()
	self.isActive = false

	if self.currentRotationTween then
		self.currentRotationTween:Cancel()
	end

	-- Limpiar indicador de estado
	self:DestroyStateIndicator()

	-- 🆕 Limpiar animador
	if self.animator then
		self.animator:Destroy()
		self.animator = nil
	end
end

return NPCAIController