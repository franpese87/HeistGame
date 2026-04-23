--[[
	ProjectileService - Gestión centralizada de proyectiles

	Crea, mueve y gestiona la colisión de proyectiles tipo taser.
	Usado tanto por players (via RemoteEvent) como por NPCs (via Controller).
	Toda la lógica es server-side (autoritativa).
]]

local RunService = game:GetService("RunService")

local StunService = require(script.Parent.StunService)

local ProjectileService = {}

-- Proyectiles activos: { { part, direction, speed, maxRange, distanceTraveled, raycastParams, stunDuration, ownerInstance } }
local activeProjectiles = {}

-- Referencia al Registry (se asigna en Init)
local registry = nil

-- Busca el Model Character ancestro de una instancia golpeada
local function findCharacterFromHit(hitInstance)
	local current = hitInstance
	while current do
		if current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Aplica stun al character impactado (NPC o Player)
local function applyStunToCharacter(character, stunDuration, ownerInstance)
	if character == ownerInstance then return end

	-- NPC
	if registry then
		local npcData = registry:GetNPCByInstance(character)
		if npcData and npcData.controller.isActive and npcData.controller.currentState ~= "Stunned" then
			npcData.controller:ApplyStun()
			return
		end
	end

	-- Player
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		StunService.Apply(humanoid, stunDuration)
	end
end

function ProjectileService.Init()
	local Registry = require(script.Parent.Parent.NPCAISystem.Registry)
	registry = Registry.GetInstance()

	RunService.Heartbeat:Connect(function(dt)
		ProjectileService._Update(dt)
	end)
end

function ProjectileService.Fire(origin, direction, config, ownerInstance)
	-- Normalizar dirección a XZ
	local dir = (direction * Vector3.new(1, 0, 1))
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit

	-- Posición inicial con offset Y
	local spawnPos = origin + Vector3.new(0, config.projectileYOffset or 0, 0)

	-- Crear Part del proyectil
	local diameter = (config.projectileRadius or 0.3) * 2
	local color = config.projectileColor or Color3.fromRGB(100, 180, 255)
	local part = Instance.new("Part")
	part.Name = "TaserProjectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Position = spawnPos
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = workspace

	-- Trail para visibilidad durante movimiento del shooter
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA0"
	a0.Position = Vector3.new(0, 0, diameter * 0.5)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailA1"
	a1.Position = Vector3.new(0, 0, -diameter * 0.5)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.MinLength = 0
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 1
	trail.Parent = part

	-- RaycastParams: excluir al shooter
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {ownerInstance}

	table.insert(activeProjectiles, {
		part = part,
		direction = dir,
		speed = config.projectileSpeed or 60,
		maxRange = config.maxRange or 80,
		stunDuration = config.stunDuration or 3,
		distanceTraveled = 0,
		raycastParams = rayParams,
		ownerInstance = ownerInstance,
	})
end

function ProjectileService._Update(dt)
	local i = 1
	while i <= #activeProjectiles do
		local projectile = activeProjectiles[i]
		local part = projectile.part

		-- Si la Part fue destruida externamente, limpiar
		if not part.Parent then
			table.remove(activeProjectiles, i)
			continue
		end

		local currentPos = part.Position
		local moveDistance = projectile.speed * dt
		local moveVector = projectile.direction * moveDistance
		local newPos = currentPos + moveVector

		-- Raycast del tramo recorrido este frame (detecta colisión con paredes y personajes)
		local rayResult = workspace:Raycast(currentPos, moveVector, projectile.raycastParams)

		if rayResult then
			local character = findCharacterFromHit(rayResult.Instance)
			if character then
				applyStunToCharacter(character, projectile.stunDuration, projectile.ownerInstance)
			end
			part:Destroy()
			table.remove(activeProjectiles, i)
			continue
		end

		-- Sin colisión: mover
		projectile.distanceTraveled = projectile.distanceTraveled + moveDistance
		if projectile.distanceTraveled >= projectile.maxRange then
			part:Destroy()
			table.remove(activeProjectiles, i)
			continue
		end

		part.Position = newPos
		i = i + 1
	end
end

return ProjectileService
