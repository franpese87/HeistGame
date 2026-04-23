--[[
	NPCAISystem - Sistema de IA para NPCs

	Arquitectura Pawn-Controller:
	- Pawn: Representación física del NPC (movimiento, animaciones, visual)
	- Controller: Cerebro del NPC (FSM, sensores, decisiones)
	- Registry: Singleton para acceso centralizado a todos los NPCs

	Estructura de carpetas:
	- NPC/: Clases instanciadas por cada NPC (Pawn, Controller)
	- Components/: Componentes reutilizables (VisionSensor, HearingSensor, Combat)
	- Debug/: Herramientas de visualización y debug

	Uso básico:
		local NPCAISystem = require(path.to.NPCAISystem)

		-- Crear grafo de navegación
		local graph = NPCAISystem.Factory.CreateNavigationGraphFromFolder(workspace.NavigationNodes, options)

		-- Spawn NPCs (se registran automáticamente en el Registry)
		local spawnedNPCs = NPCAISystem.Factory.SpawnAllNPCs(template, graph, spawnList, config)

		-- Iniciar loop de actualización
		NPCAISystem.GetRegistry():Start()

	Acceso desde clases externas:
		local registry = NPCAISystem.GetRegistry()
		local allNPCs = registry:GetAllNPCs()
		local nearest = registry:FindNearestNPC(position, 50)
		local chasingNPCs = registry:GetNPCsByState("Chasing")
]]

local NPCAISystem = {}

-- Servicios externos (src/server/Services/)
NPCAISystem.NavigationGraph = require(script.Parent.Services.NavigationGraph)
NPCAISystem.Factory = require(script.Factory)
NPCAISystem.Registry = require(script.Registry)

-- Patrón Pawn-Controller (NPC/)
NPCAISystem.Pawn = require(script.NPC.Pawn)
NPCAISystem.Controller = require(script.NPC.Controller)

-- Debug (Debug/)
NPCAISystem.Visualizer = require(script.Debug.Visualizer)

-- Acceso directo al singleton (conveniencia)
function NPCAISystem.GetRegistry()
	return NPCAISystem.Registry.GetInstance()
end

return NPCAISystem
