local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Janitor = require(ReplicatedStorage.Packages.janitor)
local NoiseService = require(script.Parent.Parent.NPCAISystem.NoiseService)
local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)

local janitor = Janitor.new()

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
janitor:Add(noiseEvent.OnServerEvent:Connect(function(player, position)
	-- Solo permitir si el jugador es admin o estamos en Studio
	-- Por simplicidad, permitimos a todos por ahora en desarrollo
	print("[DebugTools] Generando ruido en: ", position)

	-- Crear el ruido (Rango 30 studs por defecto)
	NoiseService.MakeNoise(position, 30)

	-- Visualización extra (aunque NoiseService ya tiene la suya si debug=true)
	if DebugConfig.visuals and DebugConfig.visuals.showNoiseSpheres then
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 0.5
		p.Color = Color3.fromRGB(255, 0, 255) -- Magenta para debug manual
		p.Size = Vector3.new(2, 2, 2)
		p.Position = position
		p.Shape = Enum.PartType.Ball
		p.Parent = workspace
		game:GetService("Debris"):AddItem(p, 1)
	end
end))

-- 3. Crear la Tool "NoiseMaker" y dársela a los jugadores
local function giveDebugTool(player)
	local backpack = player:WaitForChild("Backpack")
	if backpack:FindFirstChild("NoiseMaker") then return end

	local tool = Instance.new("Tool")
	tool.Name = "NoiseMaker"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	
	-- LocalScript de la herramienta
	local localScript = Instance.new("LocalScript")
	localScript.Name = "NoiseClickerClient"
	localScript.Parent = tool
	
	-- Inyectar código del cliente
	-- (Nota: En un entorno normal esto sería un archivo separado, pero para este setup auto-contenido lo hacemos así)
	local clientCode = [[
		local tool = script.Parent
		local player = game.Players.LocalPlayer
		local mouse = player:GetMouse()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local event = ReplicatedStorage:WaitForChild("Events"):WaitForChild("DebugNoiseEvent")
		
		tool.Equipped:Connect(function()
			mouse.Icon = "rbxasset://textures/ArrowCursor.png" -- Cursor normal
		end)
		
		tool.Activated:Connect(function()
			if mouse.Target then
				local pos = mouse.Hit.Position
				event:FireServer(pos)
				
				-- Feedback visual local inmediato
				local p = Instance.new("Part")
				p.Anchored = true
				p.CanCollide = false
				p.Size = Vector3.new(1,1,1)
				p.Position = pos
				p.Color = Color3.new(1,0,0)
				p.Material = Enum.Material.Neon
				p.Parent = workspace
				game:GetService("Debris"):AddItem(p, 0.5)
			end
		end)
	]]
	
	-- Usamos loadstring o simplemente vinculamos el source si es un plugin, 
	-- pero como estamos runtime, necesitamos crear un ModuleScript o vincularlo.
	-- EN ROBLOX STUDIO: La propiedad .Source solo es escribible por plugins.
	-- WORKAROUND: Creamos el LocalScript físicamente en el sistema de archivos.
	-- Como no puedo "inyectar" código Lua en un Instance creado runtime sin usar loadstring (que puede estar desactivado),
	-- la mejor opción es que este archivo .server.lua SOLO cree el RemoteEvent,
	-- y yo cree un archivo separado para la Tool en la carpeta StarterPack del proyecto.
end

-- En lugar de crear la Tool dinámicamente (que es complicado por .Source),
-- simplemente imprimimos que el sistema está listo.
print("✅ Sistema de Debug de Ruido Inicializado. (Evento creado)")
