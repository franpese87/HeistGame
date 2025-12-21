-- NoiseService: Un servicio centralizado para manejar ruidos y la reacción de la IA.

local Debris = game:GetService("Debris")

local NoiseService = {}

NoiseService.listeners = {}
NoiseService.debug = true -- Bandera para controlar la visualización de ruidos

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- GESTIÓN DE OYENTES
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

-- Registra un componente HearingSensor
function NoiseService.RegisterListener(listener)
	if not listener then return end
	table.insert(NoiseService.listeners, listener)
end

-- Elimina un oyente de la lista
function NoiseService.UnregisterListener(listenerToRemove)
	for i, listener in ipairs(NoiseService.listeners) do
		if listener == listenerToRemove then
			table.remove(NoiseService.listeners, i)
			break
		end
	end
end

-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --
-- CREACIÓN DE RUIDO
-- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| --

function NoiseService.MakeNoise(position, range, _travelsThroughFloors)
	if NoiseService.debug then
		NoiseService.VisualizeNoise(position, range)
	end
	
	-- Difundir el ruido a todos los sensores registrados.
	-- El sensor individual decidirá si lo escucha o no (basado en distancia y stats).
	for _, listener in ipairs(NoiseService.listeners) do
		if listener.OnGlobalNoise then
			listener:OnGlobalNoise(position, range)
		end
	end
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
