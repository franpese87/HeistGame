local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local DebugUtilities = require(script.Parent.Parent.DebugUtilities)

local VisionSensor = {}
VisionSensor.__index = VisionSensor

function VisionSensor.new(npc, config)
	local self = setmetatable({}, VisionSensor)

	self.npc = npc
	self.rootPart = npc:FindFirstChild("HumanoidRootPart")
	
	-- Configuración
	config = config or {}
	self.detectionRange = config.detectionRange or 50
	self.visionHeight = config.visionHeight or 2
	self.observationConeAngle = config.observationConeAngle or 90
	self.minDetectionTime = config.minDetectionTime or 0.3
	self.loseTargetTime = config.loseTargetTime or 3
	self.coneVisualDuration = config.coneVisualDuration or 0.1

	-- Raycast params
	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.FilterDescendantsInstances = {self.npc}

	-- Estado interno de detección
	self.detectionTimeAccumulator = nil -- Tiempo acumulado viendo al target actual
	self.lostDetectionTime = nil        -- Momento en que perdimos de vista al target (para el timeout de olvido)
	self.lastSeenTime = 0               -- Última vez que validamos visualmente (para coyote time)
	self.currentTarget = nil            -- El target CONFIRMADO actual
	self.lastSeenPosition = nil         -- Última posición conocida del target

	-- Debug
	self.debugEnabled = false
	self.debugConfig = { showRaycast = false }

	return self
end

function VisionSensor:SetDebug(enabled, config)
	self.debugEnabled = enabled
	self.debugConfig = config or self.debugConfig
end

-- ==============================================================================
-- CORE SCAN FUNCTION (MEJORADO)
-- ==============================================================================

function VisionSensor:Scan()
	local nearestTarget = nil
	local nearestDistance = self.detectionRange
	local currentTime = tick()

	-- 1. Recopilar posibles objetivos (Jugadores + NPCs)
	local potentialTargets = {}

	-- Añadir jugadores
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then 
			table.insert(potentialTargets, player.Character) 
		end
	end

	-- Añadir otros NPCs (Etiquetados con 'Entity' via CollectionService)
	for _, entity in ipairs(CollectionService:GetTagged("Entity")) do
		if entity ~= self.npc then -- No detectarse a sí mismo
			table.insert(potentialTargets, entity)
		end
	end

	-- 2. Filtrar y encontrar el más cercano
	for _, targetChar in ipairs(potentialTargets) do
		-- Usamos la función auxiliar IsValidTarget para limpiar lógica
		if self:IsValidTarget(targetChar) then
			local targetRoot = targetChar.HumanoidRootPart -- IsValidTarget garantiza que existe
			local distance = (self.rootPart.Position - targetRoot.Position).Magnitude

			if distance < nearestDistance then
				if self:HasLineOfSight(targetRoot) then
					nearestDistance = distance
					nearestTarget = targetChar
					-- NOTA: No actualizamos lastSeenTime aquí para evitar escrituras innecesarias
				end
			end
		end
	end

	-- 3. Actualizar estado UNA sola vez con el mejor candidato
	if nearestTarget then
		self.lastSeenTime = currentTime
		self.lastSeenPosition = nearestTarget.HumanoidRootPart.Position
	end

	return self:ProcessDetectionLogic(nearestTarget, currentTime)
end

-- Helper: Valida si un personaje es un objetivo válido (Vivo, Enemigo, etc.)
function VisionSensor:IsValidTarget(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	-- A. Validación Física
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return false
	end

	-- B. Validación de Facciones (Team Check)
	-- Intenta obtener atributo 'Team' del NPC o del Player
	local myTeam = self.npc:GetAttribute("Team")
	local targetTeam = character:GetAttribute("Team")

	-- Si es jugador, sobreescribimos con su Team real de Roblox
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		-- Si el jugador está en un Team, usamos el nombre, sino 'Player' (o nil/Neutral)
		targetTeam = player.Team and player.Team.Name or "Player"
	end
	
	-- Lógica de Equipos:
	-- Si ambos tienen equipo y son el mismo, son amigos -> Ignorar.
	-- Si myTeam es nil, atacamos a cualquiera (comportamiento hostil por defecto).
	if myTeam and targetTeam and myTeam == targetTeam then
		return false
	end

	return true
end

-- ==============================================================================
-- LINE OF SIGHT PHYSICS
-- ==============================================================================

function VisionSensor:HasLineOfSight(targetPart)
	local origin = self.rootPart.Position + Vector3.new(0, self.visionHeight, 0)
	local targetPos = targetPart.Position
	local directionVector = (targetPos - origin)
	local distance = directionVector.Magnitude

	-- 1. CHEQUEO DE DISTANCIA
	if distance > self.detectionRange then 
		return false 
	end

	-- 2. CÁLCULO DE ÁNGULO (Cono de visión)
	local lookVectorFlat = (self.rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local directionFlat = (directionVector * Vector3.new(1, 0, 1)).Unit

	local dotProduct = lookVectorFlat:Dot(directionFlat)
	local halfAngleRad = math.rad(self.observationConeAngle / 2)
	local threshold = math.cos(halfAngleRad)

	if dotProduct < threshold then
		return false 
	end

	-- 3. RAYCAST DE OCLUSIÓN
	return self:CheckOcclusion(origin, directionVector, targetPart)
end

function VisionSensor:CheckOcclusion(origin, direction, targetPart)
	local result = workspace:Raycast(origin, direction, self.raycastParams)
	local canSee = false

	if result and result.Instance:IsDescendantOf(targetPart.Parent) then
		canSee = true
	end

	-- DEBUG VISUAL
	if self.debugEnabled and self.debugConfig.showRaycast then
		local debugColor = canSee and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
		DebugUtilities.VisualizeRaycast(origin, direction, result, {
			hitColor = debugColor,
			missColor = debugColor,
			duration = 0.1,
			width = 0.1
		})
	end

	return canSee
end

-- ==============================================================================
-- DETECTION LOGIC (BUFFER / MEMORY)
-- ==============================================================================

function VisionSensor:ProcessDetectionLogic(visibleTarget, currentTime)
	local COYOTE_TIME = 0.5
	local deltaTime = 0.03 -- Aproximación si no se pasa delta, suficiente para lógica de buffer
	
	local timeSinceLastSight = currentTime - self.lastSeenTime
	local inCoyoteTime = timeSinceLastSight < COYOTE_TIME
	local isPhysicallyVisible = visibleTarget ~= nil

	-- EVENTOS DE RETORNO
	local events = {
		TargetConfirmed = false,  -- Se acaba de confirmar un target nuevo
		TargetLost = false,       -- Se ha olvidado definitivamente al target
		TargetSpotting = false    -- Se está viendo al target (útil para UI de alerta)
	}

	-- CASO 1: TE VEO (Física o Mentalmente por buffer)
	if isPhysicallyVisible then
		self.detectionTimeAccumulator = (self.detectionTimeAccumulator or 0) + deltaTime
		self.lostDetectionTime = nil -- Reset de olvido

		-- Confirmación de target
		if self.detectionTimeAccumulator >= self.minDetectionTime then
			if self.currentTarget ~= visibleTarget then
				self.currentTarget = visibleTarget
				events.TargetConfirmed = true
			end
			events.TargetSpotting = true
		end

	elseif inCoyoteTime and self.detectionTimeAccumulator and self.detectionTimeAccumulator > 0 then
		-- CASO 2: COYOTE TIME (No hacemos nada, mantenemos el estado)
		events.TargetSpotting = true
		
	else
		-- CASO 3: NO TE VEO
		if self.detectionTimeAccumulator and self.detectionTimeAccumulator > 0 then
			self.detectionTimeAccumulator = self.detectionTimeAccumulator - (deltaTime * 2)
			if self.detectionTimeAccumulator <= 0 then
				self.detectionTimeAccumulator = nil
			end
		end

		-- Lógica de olvidar (Memoria a largo plazo)
		if self.currentTarget then
			if not self.lostDetectionTime then
				self.lostDetectionTime = currentTime
			end

			local timeLost = currentTime - self.lostDetectionTime
			if timeLost >= self.loseTargetTime then
				events.TargetLost = true
				self.currentTarget = nil
				self.lostDetectionTime = nil
				self.detectionTimeAccumulator = nil
			end
		end
	end

	return self.currentTarget, self.lastSeenPosition, events
end

return VisionSensor