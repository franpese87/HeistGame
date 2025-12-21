local NoiseService = require(script.Parent.Parent.NoiseService)

local HearingSensor = {}
HearingSensor.__index = HearingSensor

function HearingSensor.new(npc, config)
	local self = setmetatable({}, HearingSensor)

	self.npc = npc
	self.rootPart = npc:FindFirstChild("HumanoidRootPart")
	
	-- Configuración
	config = config or {}
	self.hearingMultiplier = config.hearingMultiplier or 1.0 -- >1 escucha más lejos, <1 es sordo
	self.memoryDuration = config.noiseMemoryDuration or 5.0   -- Cuánto tiempo recuerda un ruido

	-- Estado (Memoria a corto plazo)
	self.lastNoise = nil

	-- Registrarse en el servicio global
	-- NOTA: Modificaremos NoiseService ligeramente para que acepte este componente en lugar del controlador
	NoiseService.RegisterListener(self)

	return self
end

-- Este método será llamado por el NoiseService
function HearingSensor:OnGlobalNoise(position, range)
	if not self.rootPart then return end

	-- Calcular distancia real
	local distance = (self.rootPart.Position - position).Magnitude
	
	-- Aplicar multiplicador auditivo del NPC
	-- Si range=50 y multiplier=1.2, escucha hasta 60 studs
	local effectiveRange = range * self.hearingMultiplier

	if distance <= effectiveRange then
		-- Guardar el ruido en memoria
		self.lastNoise = {
			position = position,
			time = tick(),
			priority = 1 -- Preparado para futuro (disparos > pasos)
		}
	end
end

-- El controlador llama a esto para saber si hay algo nuevo
function HearingSensor:CheckForNoise()
	if not self.lastNoise then return nil end

	-- Verificar si el recuerdo es muy viejo
	if tick() - self.lastNoise.time > self.memoryDuration then
		self.lastNoise = nil
		return nil
	end

	-- Devolver la posición y resetear (consumir el evento)
	-- Opcional: Podríamos no resetearlo si queremos que persista, 
	-- pero usualmente se "reacciona" una vez.
	local noisePos = self.lastNoise.position
	self.lastNoise = nil -- Consumido
	
	return noisePos
end

function HearingSensor:Destroy()
	NoiseService.UnregisterListener(self)
	self.lastNoise = nil
end

return HearingSensor