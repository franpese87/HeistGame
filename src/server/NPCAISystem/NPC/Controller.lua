--[[
	Controller - Cerebro del NPC (Patrón Pawn-Controller)

	Controla la lógica de IA:
	- FSM (Máquina de Estados Finitos)
	- Sensores (Visión, Audición)
	- Sistema de Combate
	- Navegación y Pathfinding

	Usa el Pawn para interactuar con el mundo físico.
]]

local TweenService = game:GetService("TweenService")

local VisionSensor = require(script.Parent.Parent.Components.VisionSensor)
local Combat = require(script.Parent.Parent.Components.Combat)
local HearingSensor = require(script.Parent.Parent.Components.HearingSensor)
local DebugConfig = require(script.Parent.Parent.Parent.Config.DebugConfig)
local Visualizer = require(script.Parent.Parent.Debug.Visualizer)

local AIState = {
	PATROLLING = "Patrolling",
	OBSERVING = "Observing",
	ALERTED = "Alerted",
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

	-- RaycastParams reutilizable (observación, validación de ángulos)
	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.FilterDescendantsInstances = {pawn:GetInstance()}

	-- Navegación (siempre grafo, excepto acercamiento final para atacar)
	self.directApproachDistance = config.directApproachDistance or 8
	self.nodeTimeout = 4

	-- Path Smoothing
	self.enablePathSmoothing = config.enablePathSmoothing ~= false -- default true
	self.agentRadius = config.agentRadius or 1.0

	-- Observación
	self.observationAngles = config.observationAngles or {-45, 0, 45, 0}
	self.observationTimePerAngle = config.observationTimePerAngle or 1.0
	self.observationValidationDistance = config.observationValidationDistance or 5
	self.rotationTweenInfo = TweenInfo.new(self.observationTimePerAngle * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Ratios de rotación por capas (deben sumar 1.0)
	self.observationHeadRatio = config.observationHeadRatio or 0.7
	self.observationTorsoRatio = config.observationTorsoRatio or 0.3

	-- Rotación en combate
	self.attackRotationSpeed = config.attackRotationSpeed or 0.15

	-- Reacción (tiempo en estado ALERTED antes de CHASING)
	self.reactionTime = config.reactionTime or 0.8
	self.alertedRotationTime = 0.4  -- Rotación rápida fija (independiente de reactionTime)
	self.alertedTweenInfo = TweenInfo.new(self.alertedRotationTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Ratios de rotación por capas en ALERTED (deben sumar 1.0)
	self.alertedHeadRatio = config.alertedHeadRatio or 0.8
	self.alertedTorsoRatio = config.alertedTorsoRatio or 0.2

	-- Head tracking durante CHASING
	self.enableHeadTrackingDuringChase = config.enableHeadTrackingDuringChase
	if self.enableHeadTrackingDuringChase == nil then
		self.enableHeadTrackingDuringChase = true
	end
	self.headTrackingMaxAngle = config.headTrackingMaxAngle or 90

	-- Investigación (duración = tiempo total de observación en un nodo de patrulla)
	self.investigationDuration = #self.observationAngles * self.observationTimePerAngle

	-- Componentes (Sensores y Combate)
	local npcInstance = pawn:GetInstance()
	self.visionSensor = VisionSensor.new(npcInstance, config)
	self.combatSystem = Combat.new(npcInstance, config)
	self.hearingSensor = HearingSensor.new(npcInstance, config)

	-- Configuración de Debug visual del sensor
	if DebugConfig.visuals and DebugConfig.visuals.showVisionDebug then
		self.visionSensor:SetDebug(true)
	end

	-- Estado general
	self.currentState = AIState.PATROLLING
	self.isActive = true
	self.stateStartTime = tick()

	-- Target tracking
	self.target = nil
	self.lastSeenPosition = nil
	self.lastVisionEvents = nil
	self.senseFrameCounter = 0
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
	self.pathRecalcInterval = config.pathRecalcInterval or 1.5
	self.lastPathCalcTime = 0

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

	-- Alerted (estado temporal)
	self.alertedStartTime = 0
	self.alertIndicator = nil

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

-- Estados que requieren sensores a máxima frecuencia (cada frame)
local HIGH_PRIORITY_STATES = {
	[AIState.CHASING] = true,
	[AIState.ATTACKING] = true,
	[AIState.ALERTED] = true,
}

function Controller:Update(_deltaTime)
	if not self.isActive or not self.pawn:IsAlive() then
		self.isActive = false
		return
	end

	-- Throttle sensores: cada frame en combate, cada 2 frames en estados pasivos
	self.senseFrameCounter = self.senseFrameCounter + 1
	if HIGH_PRIORITY_STATES[self.currentState] or self.senseFrameCounter % 2 == 0 then
		self:UpdateSenses()
	end

	if self.currentState == AIState.PATROLLING then
		self:UpdatePatrolling()
	elseif self.currentState == AIState.OBSERVING then
		self:UpdateObserving()
	elseif self.currentState == AIState.ALERTED then
		self:UpdateAlerted()
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
	self.lastVisionEvents = events

	if currentTarget then
		self.target = currentTarget
	end

	if lastPos then
		self.lastSeenPosition = lastPos
	end

	-- Detección instantánea → ALERTED (solo desde estados no-combate)
	if events.TargetSpotted then
		self:Log("detection", "TARGET DETECTADO: " .. currentTarget.Name)

		if self.currentState ~= AIState.CHASING
		   and self.currentState ~= AIState.ATTACKING
		   and self.currentState ~= AIState.ALERTED then
			self:ChangeState(AIState.ALERTED)
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

-- Encuentra la mejor orientación base: la dirección con mayor espacio libre
function Controller:FindBestObservationOrientation()
	local currentPos = self.pawn:GetPosition()
	local visionHeight = 2
	local rayOrigin = currentPos + Vector3.new(0, visionHeight, 0)

	-- Distancia del raycast (mucho más largo para analizar espacio disponible)
	local scanDistance = 50  -- 50 studs de alcance

	-- Probar direcciones cada 45° (8 direcciones: N, NE, E, SE, S, SW, W, NW)
	local testAngles = {0, 45, 90, 135, 180, 225, 270, 315}
	local raycastResults = {}

	-- Lanzar raycast en cada dirección y medir distancia libre
	for _, angle in ipairs(testAngles) do
		local direction = CFrame.Angles(0, math.rad(angle), 0).LookVector
		local rayDirection = direction * scanDistance

		local result = workspace:Raycast(rayOrigin, rayDirection, self.raycastParams)

		-- Calcular distancia libre (hasta colisión o máxima)
		local freeDistance = result and result.Distance or scanDistance

		table.insert(raycastResults, {
			angle = angle,
			freeDistance = freeDistance,
			hitPosition = result and result.Position or (rayOrigin + rayDirection),
			hasCollision = result ~= nil,
		})
	end

	-- SISTEMA DE AGRUPACIÓN POR FOV (Field of View)
	-- Con observationConeAngle = 90° y rayos cada 45°, cada grupo cubre 3 rayos consecutivos
	-- Evaluamos áreas de visionado completas en lugar de rayos individuales
	local rayGroups = {}

	-- Crear grupos deslizantes de 3 rayos consecutivos
	for i = 1, #raycastResults do
		local group = {
			centerIndex = i,
			rays = {}
		}

		-- Recopilar 3 rayos consecutivos (con wraparound circular)
		for offset = -1, 1 do
			local index = i + offset
			if index < 1 then
				index = index + #raycastResults
			elseif index > #raycastResults then
				index = index - #raycastResults
			end
			table.insert(group.rays, raycastResults[index])
		end

		-- Calcular métricas del grupo
		local distances = {}
		local totalDistance = 0
		local maxDistance = 0
		for _, ray in ipairs(group.rays) do
			local dist = ray.freeDistance
			table.insert(distances, dist)
			totalDistance = totalDistance + dist
			if dist > maxDistance then
				maxDistance = dist
			end
		end

		-- Promedio de distancia
		group.averageDistance = totalDistance / #distances
		group.maxDistance = maxDistance

		-- Score híbrido: priorizar grupos con al menos UNA salida libre (maxDistance)
		-- pero mantener preferencia por promedio alto (área general abierta)
		-- Esto resuelve el caso de pasillos estrechos donde queremos orientar hacia las salidas
		-- en lugar de hacia las paredes laterales
		group.score = (maxDistance * 0.7) + (group.averageDistance * 0.3)

		table.insert(rayGroups, group)
	end

	-- Seleccionar el grupo con mejor score
	local bestGroup = rayGroups[1]
	for _, group in ipairs(rayGroups) do
		if group.score > bestGroup.score then
			bestGroup = group
		end
	end

	-- Usar el rayo central del mejor grupo como dirección de orientación
	local bestDirection = raycastResults[bestGroup.centerIndex]

	-- Crear CFrame orientado hacia la mejor dirección
	local bestCFrame = CFrame.new(currentPos) * CFrame.Angles(0, math.rad(bestDirection.angle), 0)
	return bestCFrame
end

-- Valida si un ángulo de observación es útil (no está bloqueado por pared cercana)
function Controller:IsObservationAngleValid(angle)
	if not self.originalCFrame then
		return true
	end

	local currentPos = self.pawn:GetPosition()

	-- Calcular dirección después de aplicar el ángulo
	local rotatedCFrame = self.originalCFrame * CFrame.Angles(0, math.rad(angle), 0)
	local direction = rotatedCFrame.LookVector

	-- Raycast en esa dirección (a la altura de la vista)
	local visionHeight = 2  -- Altura estándar de visión
	local rayOrigin = currentPos + Vector3.new(0, visionHeight, 0)
	local rayDirection = direction * self.observationValidationDistance

	local result = workspace:Raycast(rayOrigin, rayDirection, self.raycastParams)

	-- Si no hay obstáculo o está lo suficientemente lejos, el ángulo es válido
	return result == nil or result.Distance >= self.observationValidationDistance
end

function Controller:EnterObserving()
	self.currentObservationIndex = 1
	self.observationStartTime = tick()

	self.pawn:StopMovement()
	self.pawn:SetAutoRotate(false)
	self.pawn:PlayAnimation("idle")

	-- Smart Orientation: Encontrar la mejor orientación base para observar
	self.originalCFrame = self:FindBestObservationOrientation()

	-- Rotar suavemente hacia la mejor orientación (similar a movimiento de patrullaje)
	local rotationTweenInfo = TweenInfo.new(
		0.4,  -- Duración: 0.4 segundos (natural y fluida)
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)
	self.pawn:RotateWithTween(self.originalCFrame, rotationTweenInfo)

	-- Filtrar ángulos válidos (no bloqueados por paredes)
	self.validObservationAngles = {}
	for _, angle in ipairs(self.observationAngles) do
		if self:IsObservationAngleValid(angle) then
			table.insert(self.validObservationAngles, angle)
		end
	end

	-- Si todos los ángulos están bloqueados, usar solo el centro (0°)
	if #self.validObservationAngles == 0 then
		self.validObservationAngles = {0}
	end

	self:RotateToObservationAngle(self.validObservationAngles[1])
end

function Controller:UpdateObserving()
	local currentTime = tick()
	if currentTime - self.observationStartTime >= self.observationTimePerAngle then
		self.currentObservationIndex = self.currentObservationIndex + 1
		if self.currentObservationIndex > #self.validObservationAngles then
			self:ChangeState(AIState.PATROLLING)
			return
		end
		self.observationStartTime = currentTime
		self:RotateToObservationAngle(self.validObservationAngles[self.currentObservationIndex])
	end
end

function Controller:ExitObserving()
	self.pawn:CancelRotationTween()
	self.pawn:ResetLayeredRotation(self.rotationTweenInfo)
	self.currentObservationIndex = 1
	self.originalCFrame = nil
	self.pawn:SetAutoRotate(true)
end

function Controller:RotateToObservationAngle(angle)
	if not self.originalCFrame then return end

	-- Rotación por capas: cabeza 70%, torso 30%
	self.pawn:RotateLayered(angle, {
		head = self.observationHeadRatio,
		torso = self.observationTorsoRatio,
	}, self.rotationTweenInfo)
end

-- ==============================================================================
-- ALERTED (Reacción inicial al detectar target)
-- ==============================================================================

function Controller:CreateAlertIndicator()
	local npcInstance = self.pawn:GetInstance()
	local head = npcInstance:FindFirstChild("Head")
	if not head then return end

	-- Crear BillboardGui (empieza en la cabeza)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AlertIndicator"
	billboard.Size = UDim2.fromScale(2, 2)
	billboard.StudsOffset = Vector3.new(0, 0, 0)  -- Empieza en la cabeza
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	-- Crear TextLabel con "!"
	local label = Instance.new("TextLabel")
	label.Name = "ExclamationMark"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextColor3 = Color3.fromRGB(255, 50, 50)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextTransparency = 1  -- Empieza invisible
	label.Parent = billboard

	self.alertIndicator = billboard

	-- Animación: sube desde la cabeza + fadein
	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local positionTween = TweenService:Create(billboard, tweenInfo,
		{StudsOffset = Vector3.new(0, 2, 0)}
	)
	local fadeinTween = TweenService:Create(label, tweenInfo,
		{TextTransparency = 0}
	)

	positionTween:Play()
	fadeinTween:Play()
end

function Controller:ClearAlertIndicator()
	if not self.alertIndicator then return end

	local label = self.alertIndicator:FindFirstChild("ExclamationMark")
	if label then
		-- Fadeout + sube un poco más antes de destruir
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local positionTween = TweenService:Create(self.alertIndicator, tweenInfo,
			{StudsOffset = Vector3.new(0, 2.5, 0)}
		)
		local fadeoutTween = TweenService:Create(label, tweenInfo,
			{TextTransparency = 1}
		)

		positionTween:Play()
		fadeoutTween:Play()

		fadeoutTween.Completed:Connect(function()
			if self.alertIndicator then
				self.alertIndicator:Destroy()
				self.alertIndicator = nil
			end
		end)
	else
		self.alertIndicator:Destroy()
		self.alertIndicator = nil
	end
end

function Controller:EnterAlerted()
	self.alertedStartTime = tick()
	self.pawn:StopMovement()
	self.pawn:SetAutoRotate(false)
	self.pawn:PlayAnimation("idle")

	-- Mostrar indicador "!"
	self:CreateAlertIndicator()

	-- Rotación por capas head-dominant hacia el target
	if self.target then
		local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			local currentPos = self.pawn:GetPosition()
			local directionToTarget = (targetRoot.Position - currentPos) * Vector3.new(1, 0, 1)

			if directionToTarget.Magnitude > 0.1 then
				-- Calcular ángulo hacia el target desde la orientación actual
				local lookVector = self.pawn:GetLookVector()
				local bodyAngle = math.atan2(lookVector.X, lookVector.Z)
				local targetAngle = math.atan2(directionToTarget.X, directionToTarget.Z)
				local angle = math.deg(targetAngle - bodyAngle)

				-- Normalizar ángulo a [-180, 180]
				if angle > 180 then
					angle = angle - 360
				end
				if angle < -180 then
					angle = angle + 360
				end

				-- Guardar CFrame actual como base
				self.originalCFrame = self.pawn:GetCFrame()

				-- Aplicar rotación por capas (cabeza 80%, torso 20%)
				self.pawn:RotateLayered(angle, {
					head = self.alertedHeadRatio,
					torso = self.alertedTorsoRatio,
				}, self.alertedTweenInfo)
			end

			self.lastSeenPosition = targetRoot.Position
		end
	end
end

function Controller:UpdateAlerted()
	local elapsed = tick() - self.alertedStartTime
	local events = self.lastVisionEvents

	-- Actualizar lastSeenPosition mientras lo vemos (usando resultado cacheado de UpdateSenses)
	if events and events.TargetVisible and self.target then
		local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			self.lastSeenPosition = targetRoot.Position
		end
	end

	-- Tiempo de reacción completado → decidir siguiente estado
	if elapsed >= self.reactionTime then
		if events and events.TargetVisible then
			self:ChangeState(AIState.CHASING)
		else
			self:ChangeState(AIState.INVESTIGATING)
		end
	end
end

function Controller:ExitAlerted()
	self.pawn:CancelRotationTween()
	self.pawn:ResetLayeredRotation(self.alertedTweenInfo)
	self.originalCFrame = nil
	self.pawn:SetAutoRotate(true)
	self:ClearAlertIndicator()
end

-- ==============================================================================
-- CHASING
-- ==============================================================================

-- Tracking de cabeza hacia el target durante persecución
function Controller:UpdateHeadTracking()
	if not self.target or not self.enableHeadTrackingDuringChase then
		return
	end

	local targetRoot = self.target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end

	local currentPos = self.pawn:GetPosition()
	local targetPos = targetRoot.Position
	local directionToTarget = (targetPos - currentPos) * Vector3.new(1, 0, 1)

	if directionToTarget.Magnitude < 0.1 then
		return
	end

	-- Calcular ángulo hacia el target relativo al cuerpo
	local bodyLookVector = self.pawn:GetLookVector()
	local targetLookVector = directionToTarget.Unit

	local bodyAngle = math.atan2(bodyLookVector.X, bodyLookVector.Z)
	local targetAngle = math.atan2(targetLookVector.X, targetLookVector.Z)
	local headAngle = math.deg(targetAngle - bodyAngle)

	-- Normalizar a [-180, 180]
	if headAngle > 180 then
		headAngle = headAngle - 360
	end
	if headAngle < -180 then
		headAngle = headAngle + 360
	end

	-- Limitar rotación de cabeza (no más de headTrackingMaxAngle grados)
	headAngle = math.clamp(headAngle, -self.headTrackingMaxAngle, self.headTrackingMaxAngle)

	-- Aplicar rotación solo a la cabeza (instantánea para tracking responsive)
	if self.pawn.neck and self.pawn.neckOriginalC0 then
		local targetC0 = CFrame.Angles(0, math.rad(headAngle), 0) * self.pawn.neckOriginalC0
		self.pawn.neck.C0 = targetC0
	end
end

function Controller:UpdateChasing()
	-- Head tracking del target mientras persigue
	self:UpdateHeadTracking()

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
	local currentTime = tick()

	if not self.currentPath or #self.currentPath == 0 then
		self:CalculateGraphPathToPosition(targetPosition)
		self.targetLastPosition = targetPosition
		self.lastPathCalcTime = currentTime
		return
	end

	-- Recalcular si el target se movió significativamente Y (llegamos a un nodo O expiró el timer)
	local targetMoved = self.targetLastPosition and (targetPosition - self.targetLastPosition).Magnitude > 10
	local timerExpired = (currentTime - self.lastPathCalcTime) >= self.pathRecalcInterval
	local arrivedAtNode = self.currentPath[self.currentPathIndex] and self:HasArrivedAt(self.currentPath[self.currentPathIndex].position)

	if targetMoved and (arrivedAtNode or timerExpired) then
		self:CalculateGraphPathToPosition(targetPosition)
		self.targetLastPosition = targetPosition
		self.lastPathCalcTime = currentTime
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

	-- Rotación suave con interpolación hacia el target
	local targetDirection = (targetRoot.Position - self.pawn:GetPosition()) * Vector3.new(1, 0, 1)
	if targetDirection.Magnitude > 0.1 then
		local targetCFrame = CFrame.lookAt(self.pawn:GetPosition(), self.pawn:GetPosition() + targetDirection)
		self.pawn:LerpCFrame(targetCFrame, self.attackRotationSpeed)
	end

	self.combatSystem:TryAttack(self.target)
end

-- ==============================================================================
-- INVESTIGATING
-- ==============================================================================

function Controller:EnterInvestigating()
	self.investigationStartTime = tick()
	self.investigationObservationIndex = 1
	self.investigationObservationTime = 0
	self.investigationIsObserving = false
	self.pawn:SetAutoRotate(true)

	if self.lastSeenPosition then
		-- Guardar la posición real donde se vio al target (NO sobrescribir con nodo)
		self.investigationTarget = self.lastSeenPosition

		self:Log("stateChanges", "Iniciando investigación (" .. self.investigationDuration .. "s) en posición " .. tostring(self.investigationTarget))

		if self.debugEnabled and self.debugConfig.showLastSeenPosition then
			Visualizer.DrawLastSeenPosition(self.pawn:GetName(), self.investigationTarget, {
				duration = self.investigationDuration,
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
		-- Navegando hacia la última posición vista
		self.pawn:PlayAnimation("walk")
		self:FollowCurrentPath()
	else
		-- Llegó a la posición: observar usando rotación por capas
		self.pawn:StopMovement()
		self.pawn:PlayAnimation("idle")

		-- Iniciar observación si aún no empezó
		if not self.investigationIsObserving then
			self.investigationIsObserving = true
			self.investigationObservationTime = tick()
			self.pawn:SetAutoRotate(false)

			-- Orientarse hacia la última posición conocida del target
			-- En INVESTIGATING el NPC sabe dónde vio al jugador, así que es más natural
			-- orientarse hacia esa posición en lugar de usar Smart Orientation
			local currentPos = self.pawn:GetPosition()
			local directionToTarget = (self.investigationTarget - currentPos) * Vector3.new(1, 0, 1)

			if directionToTarget.Magnitude > 0.1 then
				self.originalCFrame = CFrame.lookAt(currentPos, currentPos + directionToTarget)
			else
				self.originalCFrame = self.pawn:GetCFrame()
			end

			-- Rotar suavemente hacia la última posición conocida
			local rotationTweenInfo = TweenInfo.new(
				0.4,  -- Duración: 0.4 segundos (natural y fluida)
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			self.pawn:RotateWithTween(self.originalCFrame, rotationTweenInfo)

			-- Filtrar ángulos válidos (no bloqueados por paredes)
			self.validInvestigationAngles = {}
			for _, angle in ipairs(self.observationAngles) do
				if self:IsObservationAngleValid(angle) then
					table.insert(self.validInvestigationAngles, angle)
				end
			end

			-- Si todos los ángulos están bloqueados, usar solo el centro (0°)
			if #self.validInvestigationAngles == 0 then
				self.validInvestigationAngles = {0}
			end

			-- Iniciar primera rotación por capas
			self:RotateToObservationAngle(self.validInvestigationAngles[self.investigationObservationIndex])
		end

		-- Rotar por los ángulos de observación
		local currentTime = tick()
		if currentTime - self.investigationObservationTime >= self.observationTimePerAngle then
			self.investigationObservationIndex = self.investigationObservationIndex + 1
			if self.investigationObservationIndex > #self.validInvestigationAngles then
				self.investigationObservationIndex = 1  -- Repetir el ciclo
			end
			self.investigationObservationTime = currentTime
			self:RotateToObservationAngle(self.validInvestigationAngles[self.investigationObservationIndex])
		end
	end
end

function Controller:ExitInvestigating()
	-- Resetear rotación por capas si estaba observando
	if self.investigationIsObserving then
		self.pawn:ResetLayeredRotation(self.rotationTweenInfo)
		self.investigationIsObserving = false
	end

	self.investigationStartTime = nil
	self.investigationTarget = nil
	self.investigationObservationIndex = 1
	self.investigationObservationTime = 0
	self.originalCFrame = nil
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

	-- Si no hay path y estamos cerca del nodo, transicionar directamente
	-- Esto evita quedar atrapado cuando start/end node son el mismo
	local distanceToTarget = (self.pawn:GetPosition() - self.returnTargetNode.Position).Magnitude
	if not self.currentPath and distanceToTarget < 10 then
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
	elseif self.currentState == AIState.ALERTED then
		self:ExitAlerted()
	elseif self.currentState == AIState.INVESTIGATING then
		self:ExitInvestigating()
	elseif self.currentState == AIState.RETURNING then
		self:ExitReturning()
	elseif self.currentState == AIState.CHASING then
		-- Resetear rotación de cabeza al salir de persecución
		if self.enableHeadTrackingDuringChase then
			self.pawn:ResetLayeredRotation(TweenInfo.new(0.2))
		end
	elseif self.currentState == AIState.ATTACKING then
		-- Re-activar AutoRotate al salir de combate
		self.pawn:SetAutoRotate(true)
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
	elseif newState == AIState.ALERTED then
		self:EnterAlerted()
	elseif newState == AIState.INVESTIGATING then
		self:EnterInvestigating()
	elseif newState == AIState.CHASING then
		self:ClearPath()
		self.targetLastPosition = nil
	elseif newState == AIState.ATTACKING then
		-- Desactivar AutoRotate para control manual de rotación
		self.pawn:SetAutoRotate(false)
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
