--[[
	DebugToolsSetup - Inicializa el sistema de debug de ruido

	Crea el RemoteEvent para comunicación cliente-servidor.
	La Tool del cliente está en src/client/DebugNoiseTool.client.luau
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local NoiseService = require(script.Parent.Parent.Services.NoiseService)
local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)

-- Constantes
local DEBUG_NOISE_RANGE = 30
local DEBUG_SPHERE_SIZE = 2
local DEBUG_SPHERE_DURATION = 1

-- 1. Crear Estructura de Eventos
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local noiseEvent = eventsFolder:FindFirstChild("DebugNoiseEvent")
if not noiseEvent then
	noiseEvent = Instance.new("RemoteEvent")
	noiseEvent.Name = "DebugNoiseEvent"
	noiseEvent.Parent = eventsFolder
end

-- 2. Manejar el Evento del Servidor
noiseEvent.OnServerEvent:Connect(function(_player, position)
	print("[DebugTools] Generando ruido en:", position)

	-- Crear el ruido
	NoiseService.MakeNoise(position, DEBUG_NOISE_RANGE)

	-- Visualización extra (aunque NoiseService ya tiene la suya si debug=true)
	if DebugConfig.visuals and DebugConfig.visuals.showNoiseSpheres then
		local sphere = Instance.new("Part")
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CanQuery = false
		sphere.Transparency = 0.5
		sphere.Color = Color3.fromRGB(255, 0, 255) -- Magenta para debug manual
		sphere.Size = Vector3.new(DEBUG_SPHERE_SIZE, DEBUG_SPHERE_SIZE, DEBUG_SPHERE_SIZE)
		sphere.Position = position
		sphere.Shape = Enum.PartType.Ball
		sphere.Material = Enum.Material.Neon
		sphere.Parent = workspace
		Debris:AddItem(sphere, DEBUG_SPHERE_DURATION)
	end
end)

print("[DebugTools] Sistema de Debug de Ruido inicializado")
