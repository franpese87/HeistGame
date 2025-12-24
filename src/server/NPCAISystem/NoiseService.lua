-- NoiseService: Un servicio centralizado para manejar ruidos y la reacción de la IA.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Signal = require(ReplicatedStorage.Packages.signal)

local NoiseService = {}

NoiseService.NoiseDetected = Signal.new()
NoiseService.debug = true -- Bandera para controlar la visualización de ruidos

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- GESTIÓN DE OYENTES (DEPRECATED - Migrado a Signal)
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

-- Estos métodos se mantienen por compatibilidad pero ya no se usan
-- Los listeners ahora se conectan directamente a NoiseService.NoiseDetected:Connect()

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- CREACIÓN DE RUIDO
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

function NoiseService.MakeNoise(position, range, _travelsThroughFloors)
	if NoiseService.debug then
		NoiseService.VisualizeNoise(position, range)
	end

	-- Emitir señal con los datos del ruido
	NoiseService.NoiseDetected:Fire(position, range)
end

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- DEPURACIÓN VISUAL
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

function NoiseService.VisualizeNoise(position, range)
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(range * 2, range * 2, range * 2)
	sphere.Position = position
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Color = Color3.new(0, 1, 1) -- Cian
	sphere.Material = Enum.Material.Neon
	sphere.Transparency = 0.8
	sphere.Parent = workspace
	
	Debris:AddItem(sphere, 1.5)
end

return NoiseService
