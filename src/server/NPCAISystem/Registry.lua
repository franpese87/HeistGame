--[[
	Registry - Singleton para gestión centralizada de NPCs

	Proporciona:
	- Registro único de todos los NPCs activos
	- Consultas por ID, estado, posición, etc.
	- Loop de actualización centralizado
	- Acceso global mediante GetInstance()

	Uso:
		local registry = Registry.GetInstance()
		local allNPCs = registry:GetAllNPCs()
		local nearest = registry:FindNearestNPC(position, 50)
]]

local Registry = {}
Registry.__index = Registry

-- Singleton instance
local instance = nil

-- ==============================================================================
-- SINGLETON PATTERN
-- ==============================================================================

function Registry.GetInstance()
	if not instance then
		instance = setmetatable({}, Registry)
		instance:_Initialize()
	end
	return instance
end

-- Constructor privado
function Registry:_Initialize()
	self.npcs = {}          -- { [id] = { pawn = Pawn, controller = Controller } }
	self.npcCount = 0
	self.nextId = 1
	self.isRunning = false
	self.updateRate = 1/30  -- 30 FPS
end

-- ==============================================================================
-- REGISTRO Y DESREGISTRO
-- ==============================================================================

function Registry:RegisterNPC(pawn, controller)
	if not pawn or not controller then
		warn("Registry: Intento de registrar NPC con pawn o controller nil")
		return nil
	end

	local id = self.nextId
	self.nextId = self.nextId + 1

	self.npcs[id] = {
		id = id,
		pawn = pawn,
		controller = controller,
		registeredAt = tick()
	}

	-- Guardar referencia del ID en el controller para búsquedas inversas
	controller.registryId = id

	self.npcCount = self.npcCount + 1

	return id
end

function Registry:UnregisterNPC(id)
	local npcData = self.npcs[id]
	if not npcData then
		return false
	end

	self.npcs[id] = nil
	self.npcCount = self.npcCount - 1

	return true
end

function Registry:UnregisterByController(controller)
	if controller.registryId then
		return self:UnregisterNPC(controller.registryId)
	end

	-- Búsqueda lineal como fallback
	for id, data in pairs(self.npcs) do
		if data.controller == controller then
			return self:UnregisterNPC(id)
		end
	end

	return false
end

-- ==============================================================================
-- CONSULTAS BÁSICAS
-- ==============================================================================

function Registry:GetNPCById(id)
	return self.npcs[id]
end

function Registry:GetAllNPCs()
	local result = {}
	for _, npcData in pairs(self.npcs) do
		table.insert(result, npcData)
	end
	return result
end

function Registry:GetNPCCount()
	return self.npcCount
end

-- ==============================================================================
-- CONSULTAS AVANZADAS
-- ==============================================================================

-- Función genérica de filtrado con predicado
function Registry:Filter(predicate)
	local result = {}
	for _, npcData in pairs(self.npcs) do
		if predicate(npcData) then
			table.insert(result, npcData)
		end
	end
	return result
end

function Registry:GetNPCsByState(stateName)
	return self:Filter(function(npcData)
		return npcData.controller.currentState == stateName
	end)
end

function Registry:FindNearestNPC(position, maxDistance, excludeId)
	local nearest = nil
	local nearestDistance = maxDistance or math.huge

	for id, npcData in pairs(self.npcs) do
		if id ~= excludeId and npcData.controller.isActive then
			local npcPosition = npcData.pawn:GetPosition()
			local distance = (npcPosition - position).Magnitude

			if distance < nearestDistance then
				nearestDistance = distance
				nearest = npcData
			end
		end
	end

	return nearest, nearestDistance
end

function Registry:FindNPCsInRadius(position, radius)
	local result = {}

	for _, npcData in pairs(self.npcs) do
		if npcData.controller.isActive then
			local npcPosition = npcData.pawn:GetPosition()
			local distance = (npcPosition - position).Magnitude

			if distance <= radius then
				table.insert(result, {
					npcData = npcData,
					distance = distance
				})
			end
		end
	end

	-- Ordenar por distancia
	table.sort(result, function(a, b)
		return a.distance < b.distance
	end)

	return result
end

function Registry:GetActiveNPCs()
	return self:Filter(function(npcData)
		return npcData.controller.isActive
	end)
end

-- ==============================================================================
-- LOOP DE ACTUALIZACIÓN
-- ==============================================================================

function Registry:Start()
	if self.isRunning then
		return
	end

	self.isRunning = true

	task.spawn(function()
		while self.isRunning do
			local startTime = tick()

			for _, npcData in pairs(self.npcs) do
				if npcData.controller.isActive then
					local success, err = pcall(function()
						npcData.controller:Update(self.updateRate)
					end)

					if not success then
						warn("Registry: Error actualizando NPC " ..
							npcData.pawn:GetName() .. ": " .. tostring(err))
					end
				end
			end

			local elapsed = tick() - startTime
			local sleepTime = math.max(0, self.updateRate - elapsed)
			task.wait(sleepTime)
		end
	end)
end

function Registry:Stop()
	self.isRunning = false
end

function Registry:IsRunning()
	return self.isRunning
end

-- ==============================================================================
-- OPERACIONES EN MASA
-- ==============================================================================

function Registry:DestroyAll()
	for _, npcData in pairs(self.npcs) do
		if npcData.controller then
			npcData.controller:Destroy()
		end
		if npcData.pawn then
			npcData.pawn:Destroy()
		end
	end
	self.npcs = {}
	self.npcCount = 0
end

function Registry:AlertAllInRadius(position, radius, alertState)
	alertState = alertState or "Investigating"
	local npcsInRadius = self:FindNPCsInRadius(position, radius)

	local alertedCount = 0
	for _, entry in ipairs(npcsInRadius) do
		local controller = entry.npcData.controller
		-- Solo alertar si están en estado "tranquilo"
		if controller.currentState == "Patrolling" or
		   controller.currentState == "Observing" or
		   controller.currentState == "Returning" then
			controller.lastSeenPosition = position
			controller:ChangeState(alertState)
			alertedCount = alertedCount + 1
		end
	end

	return alertedCount
end

-- ==============================================================================
-- ITERADORES
-- ==============================================================================

function Registry:ForEach(callback)
	for id, npcData in pairs(self.npcs) do
		callback(id, npcData.pawn, npcData.controller)
	end
end

function Registry:ForEachActive(callback)
	for id, npcData in pairs(self.npcs) do
		if npcData.controller.isActive then
			callback(id, npcData.pawn, npcData.controller)
		end
	end
end

-- ==============================================================================
-- RESET (para testing o reinicio)
-- ==============================================================================

function Registry:Reset()
	self:Stop()
	self:DestroyAll()
	self.nextId = 1
end

return Registry
