local Players = game:GetService("Players")

local VisionSensor = {}
VisionSensor.__index = VisionSensor

-- ==============================================================================
-- LOCAL HELPERS
-- ==============================================================================

local function getDebugFolder()
	local folder = workspace:FindFirstChild("_VisionDebug")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_VisionDebug"
		folder.Parent = workspace
	end
	return folder
end

local function createDebugPart(name, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = getDebugFolder()
	return part
end

local function rotateVectorXZ(vec, angle)
	local cos = math.cos(angle)
	local sin = math.sin(angle)
	return Vector3.new(
		vec.X * cos - vec.Z * sin,
		0,
		vec.X * sin + vec.Z * cos
	).Unit
end

local function createHorizontalLineCFrame(midpoint, direction)
	local xAxis = direction
	local yAxis = Vector3.new(0, 1, 0)
	local zAxis = xAxis:Cross(yAxis).Unit
	return CFrame.fromMatrix(midpoint, xAxis, yAxis, zAxis)
end

local function createLineCFrame(origin, target)
	local direction = (target - origin).Unit
	local midpoint = (origin + target) / 2
	local length = (target - origin).Magnitude

	-- Manejar caso donde la dirección es casi vertical
	local up = Vector3.new(0, 1, 0)
	if math.abs(direction:Dot(up)) > 0.99 then
		up = Vector3.new(1, 0, 0)
	end

	local xAxis = direction
	local zAxis = xAxis:Cross(up).Unit
	local yAxis = zAxis:Cross(xAxis).Unit

	return CFrame.fromMatrix(midpoint, xAxis, yAxis, zAxis), length
end

-- ==============================================================================
-- CONSTRUCTOR
-- ==============================================================================

function VisionSensor.new(npc, config)
	local self = setmetatable({}, VisionSensor)

	self.rootPart = npc:FindFirstChild("HumanoidRootPart")
	self.head = npc:FindFirstChild("Head")

	config = config or {}
	self.detectionRange = config.detectionRange or 50
	self.visionHeight = config.visionHeight or 2
	self.coneAngle = config.observationConeAngle or 90
	self.loseTargetTime = config.loseTargetTime or 3

	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.FilterDescendantsInstances = {npc}

	-- Estado de detección (simplificado - sin acumulador)
	self.lostTargetTime = nil
	self.lastSeenTime = 0
	self.confirmedTarget = nil
	self.lastSeenPosition = nil

	-- Tabla de eventos reutilizable (evita allocación por frame)
	self.events = {
		TargetSpotted = false,
		TargetVisible = false,
		TargetLost = false,
	}

	-- Debug
	self.debugEnabled = false
	self.debugInstances = {
		rangeCircle = nil,
		coneBoundaryLeft = nil,
		coneBoundaryRight = nil,
		losRaycast = nil,
	}

	return self
end

function VisionSensor:SetDebug(enabled)
	self.debugEnabled = enabled

	-- Limpiar visualizaciones cuando se desactiva el debug
	if not enabled then
		self:ClearRangeCircle()
		self:ClearConeBoundaries()
		self:ClearLineOfSight()
	end
end

-- Obtiene la dirección de visión (usa la cabeza si está disponible)
function VisionSensor:GetLookDirection()
	if self.head then
		return (self.head.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	end
	return (self.rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
end

-- ==============================================================================
-- SCAN - PIPELINE DE DETECCIÓN
-- ==============================================================================
--[[
	Pipeline de detección optimizado (solo procesa el jugador más cercano):
	- FASE 1: Distance Check - Encontrar jugador más cercano en rango
	- FASE 2: Vision Cone Check (dot product) - Solo para el más cercano
	- FASE 3: Line of Sight Check (raycast) - Solo para el más cercano
]]

function VisionSensor:Scan()
	local currentTime = os.clock()

	-- FASE 1: Encontrar el jugador más cercano dentro del rango
	local closestCharacter = nil
	local closestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end
		if not self:IsValidTarget(character) then continue end

		local distance = (self.rootPart.Position - character.HumanoidRootPart.Position).Magnitude
		if distance <= self.detectionRange and distance < closestDistance then
			closestDistance = distance
			closestCharacter = character
		end
	end

	local playerInRange = closestCharacter ~= nil
	local playerInCone = false
	local losData = nil
	local detectedTarget = nil

	if closestCharacter then
		local targetRootPart = closestCharacter.HumanoidRootPart

		-- FASE 2: Vision Cone Check (solo para el más cercano)
		if self:IsInsideVisionCone(targetRootPart) then
			playerInCone = true

			-- FASE 3: Line of Sight Check (solo si pasó Fase 2)
			local hasLOS
			hasLOS, losData = self:CheckLineOfSight(targetRootPart)

			if hasLOS then
				detectedTarget = closestCharacter
			end
		end
	end

	if detectedTarget then
		self.lastSeenTime = currentTime
		self.lastSeenPosition = detectedTarget.HumanoidRootPart.Position
	end

	-- Debug visual
	if self.debugEnabled then
		self:UpdateRangeCircle(playerInRange)
		if playerInRange then
			self:UpdateConeBoundaries(playerInCone)
			if playerInCone and losData then
				self:UpdateLineOfSight(losData)
			else
				self:ClearLineOfSight()
			end
		else
			self:ClearConeBoundaries()
			self:ClearLineOfSight()
		end
	end

	return self:ProcessDetectionLogic(detectedTarget, currentTime)
end

-- ==============================================================================
-- DETECTION PHASES
-- ==============================================================================

function VisionSensor:IsValidTarget(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return humanoid and rootPart and humanoid.Health > 0
end

function VisionSensor:IsInsideVisionCone(targetRootPart)
	local npcPosition = self.rootPart.Position
	local targetPosition = targetRootPart.Position

	local npcLookDirXZ = self:GetLookDirection()
	local toTargetDirXZ = ((targetPosition - npcPosition) * Vector3.new(1, 0, 1)).Unit

	local dotProduct = npcLookDirXZ:Dot(toTargetDirXZ)
	local threshold = math.cos(math.rad(self.coneAngle / 2))

	return dotProduct >= threshold
end

function VisionSensor:CheckLineOfSight(targetRootPart)
	local head = self.rootPart.Parent:FindFirstChild("Head")
	local origin = head and head.Position or (self.rootPart.Position + Vector3.new(0, self.visionHeight, 0))
	local targetPosition = targetRootPart.Position
	local direction = targetPosition - origin

	local result = workspace:Raycast(origin, direction, self.raycastParams)
	local hasLOS = result and result.Instance:IsDescendantOf(targetRootPart.Parent)

	local losData = {
		origin = origin,
		hitPoint = result and result.Position or targetPosition,
		hasLOS = hasLOS,
	}

	return hasLOS, losData
end

-- ==============================================================================
-- DETECTION LOGIC (INSTANT DETECTION)
-- ==============================================================================

function VisionSensor:ProcessDetectionLogic(visibleTarget, currentTime)
	local events = self.events
	events.TargetSpotted = false
	events.TargetVisible = false
	events.TargetLost = false

	if visibleTarget then
		events.TargetVisible = true

		-- Primera vez que vemos este target específico
		if self.confirmedTarget ~= visibleTarget then
			self.confirmedTarget = visibleTarget
			events.TargetSpotted = true
		end

		self.lostTargetTime = nil
	else
		-- Target no visible: lógica de pérdida
		if self.confirmedTarget then
			if not self.lostTargetTime then
				self.lostTargetTime = currentTime
			end

			-- Después de loseTargetTime, olvidar completamente al target
			if currentTime - self.lostTargetTime >= self.loseTargetTime then
				events.TargetLost = true
				self.confirmedTarget = nil
				self.lostTargetTime = nil
			end
		end
	end

	return self.confirmedTarget, self.lastSeenPosition, events
end

-- ==============================================================================
-- DEBUG VISUAL
-- ==============================================================================

-- Fase 1: Círculo de rango de detección (blanco = no detectado, rojo = detectado)
function VisionSensor:UpdateRangeCircle(playerInRange)
	if not self.debugInstances.rangeCircle then
		local circle = createDebugPart("RangeCircle", Enum.PartType.Cylinder)
		circle.Transparency = 0.95
		self.debugInstances.rangeCircle = circle
	end

	local circle = self.debugInstances.rangeCircle
	circle.Color = playerInRange and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
	circle.Size = Vector3.new(0.2, self.detectionRange * 2, self.detectionRange * 2)

	local npcPosition = self.rootPart.Position
	local groundY = npcPosition.Y - (self.rootPart.Size.Y / 2) + 0.1
	circle.CFrame = CFrame.new(npcPosition.X, groundY, npcPosition.Z) * CFrame.Angles(0, 0, math.rad(90))
end

function VisionSensor:ClearRangeCircle()
	if self.debugInstances.rangeCircle then
		self.debugInstances.rangeCircle:Destroy()
		self.debugInstances.rangeCircle = nil
	end
end

-- Fase 2: Límites del cono de visión (blanco = no detectado, rojo = detectado)
function VisionSensor:UpdateConeBoundaries(playerInCone)
	if not self.debugInstances.coneBoundaryLeft then
		local line = createDebugPart("ConeBoundaryLeft", Enum.PartType.Cylinder)
		line.Transparency = 0.3
		self.debugInstances.coneBoundaryLeft = line
	end
	if not self.debugInstances.coneBoundaryRight then
		local line = createDebugPart("ConeBoundaryRight", Enum.PartType.Cylinder)
		line.Transparency = 0.3
		self.debugInstances.coneBoundaryRight = line
	end

	local leftLine = self.debugInstances.coneBoundaryLeft
	local rightLine = self.debugInstances.coneBoundaryRight

	local boundaryColor = playerInCone and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
	leftLine.Color = boundaryColor
	rightLine.Color = boundaryColor

	local npcPosition = self.rootPart.Position
	local groundY = npcPosition.Y - (self.rootPart.Size.Y / 2) + 0.15
	local centerPoint = Vector3.new(npcPosition.X, groundY, npcPosition.Z)

	local npcLookDirXZ = self:GetLookDirection()
	local halfAngle = math.rad(self.coneAngle / 2)

	local leftBoundaryDir = rotateVectorXZ(npcLookDirXZ, halfAngle)
	local rightBoundaryDir = rotateVectorXZ(npcLookDirXZ, -halfAngle)

	local boundaryLength = self.detectionRange
	local leftEndPoint = centerPoint + (leftBoundaryDir * boundaryLength)
	local rightEndPoint = centerPoint + (rightBoundaryDir * boundaryLength)

	local leftMidpoint = (centerPoint + leftEndPoint) / 2
	leftLine.Size = Vector3.new(boundaryLength, 0.15, 0.15)
	leftLine.CFrame = createHorizontalLineCFrame(leftMidpoint, leftBoundaryDir)

	local rightMidpoint = (centerPoint + rightEndPoint) / 2
	rightLine.Size = Vector3.new(boundaryLength, 0.15, 0.15)
	rightLine.CFrame = createHorizontalLineCFrame(rightMidpoint, rightBoundaryDir)
end

function VisionSensor:ClearConeBoundaries()
	if self.debugInstances.coneBoundaryLeft then
		self.debugInstances.coneBoundaryLeft:Destroy()
		self.debugInstances.coneBoundaryLeft = nil
	end
	if self.debugInstances.coneBoundaryRight then
		self.debugInstances.coneBoundaryRight:Destroy()
		self.debugInstances.coneBoundaryRight = nil
	end
end

-- Fase 3: Línea de raycast (blanco = no detectado/bloqueado, rojo = detectado)
function VisionSensor:UpdateLineOfSight(losData)
	if not self.debugInstances.losRaycast then
		local line = createDebugPart("LOSRaycast", Enum.PartType.Cylinder)
		line.Transparency = 0.3
		self.debugInstances.losRaycast = line
	end

	local line = self.debugInstances.losRaycast
	local lineCFrame, lineLength = createLineCFrame(losData.origin, losData.hitPoint)

	line.Size = Vector3.new(lineLength, 0.1, 0.1)
	line.CFrame = lineCFrame
	line.Color = losData.hasLOS and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
end

function VisionSensor:ClearLineOfSight()
	if self.debugInstances.losRaycast then
		self.debugInstances.losRaycast:Destroy()
		self.debugInstances.losRaycast = nil
	end
end

return VisionSensor
