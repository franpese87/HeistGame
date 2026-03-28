local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Janitor = require(ReplicatedStorage.Packages.janitor)
local NoiseService = require(script.Parent.Parent.Parent.Services.NoiseService)

local HearingSensor = {}
HearingSensor.__index = HearingSensor

function HearingSensor.new(npc, config)
	local self = setmetatable({}, HearingSensor)

	self.janitor = Janitor.new()
	self.npc = npc
	self.rootPart = npc:FindFirstChild("HumanoidRootPart")

	-- Configuración
	config = config or {}
	self.hearingMultiplier = config.hearingMultiplier or 1.0
	self.memoryDuration = config.noiseMemoryDuration or 5.0

	-- Estado (Memoria a corto plazo)
	self.lastNoise = nil

	-- Conectar al Signal de NoiseService
	self.janitor:Add(NoiseService.NoiseDetected:Connect(function(position, range)
		self:OnGlobalNoise(position, range)
	end))

	return self
end

-- Callback cuando se detecta un ruido global
function HearingSensor:OnGlobalNoise(position, range)
	if not self.rootPart then return end

	local distance = (self.rootPart.Position - position).Magnitude
	local effectiveRange = range * self.hearingMultiplier

	if distance <= effectiveRange then
		self.lastNoise = {
			position = position,
			time = os.clock(),
			priority = 1
		}
	end
end

-- El controlador llama a esto para saber si hay algo nuevo
function HearingSensor:CheckForNoise()
	if not self.lastNoise then return nil end

	-- Verificar si el recuerdo es muy viejo
	if os.clock() - self.lastNoise.time > self.memoryDuration then
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
	self.janitor:Destroy()
	self.lastNoise = nil
end

return HearingSensor