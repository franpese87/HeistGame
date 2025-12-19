local NPCAISystem = require(script.NPCAISystem)

print("🎮 Iniciando sistema de NPCs...")

-- ==============================================================================
-- CONFIGURACIÓN DE DEBUG VISUAL
-- ==============================================================================

local DEBUG_CONFIG = {
	-- Control de visualización
	keepNodesInWorkspace = false,        -- 🔄 true = mantener Parts, false = destruir
	visualizeOnStartup = true,           -- 🔄 true = visualizar al inicio
	
	-- Qué visualizar
	showNodes = true,
	showCells = true,
	showConnections = true,
	
	-- Estilo visual - Nodos
	nodeColor = Color3.fromRGB(0, 255, 0),
	nodeSize = 0.5,
	nodeTransparency = 0.3,
	
	-- Estilo visual - Celdas
	cellColor = Color3.fromRGB(100, 200, 255),
	cellTransparency = 0.85,
	cellWireframe = true,
	
	-- Estilo visual - Conexiones
	connectionColor = Color3.fromRGB(153, 202, 255),
	connectionWidth = 0.1,
}

-- ==============================================================================
-- CONFIGURACIÓN DEL GRAFO DE NAVEGACIÓN
-- ==============================================================================

local navGraph = NPCAISystem.Setup.CreateNavigationGraphFromFolder(
	workspace.NavigationNodes,
	{
		mode = "hybrid",
		maxDistance = 40,
		useRaycast = true,
		maxConnectionsPerNode = 6,
		ignoreList = {workspace.NavigationNodes},
		destroyParts = not DEBUG_CONFIG.keepNodesInWorkspace  -- Destruir si no está en modo debug
	}
)

-- ==============================================================================
-- DEBUG VISUAL (SOLO EN STUDIO)
-- ==============================================================================

if game:GetService("RunService"):IsStudio() then
	print("🐛 Activando debug...")
	
	-- Estadísticas del grafo
	-- NPCSystem.DebugUtilities.FullDebug(navGraph, DEBUG_CONFIG)
	
	-- Visualización si está habilitada
	if DEBUG_CONFIG.visualizeOnStartup then
		navGraph:DebugDrawAll(DEBUG_CONFIG)
	end
end

-- ==============================================================================
-- REPORTE FINAL
-- ==============================================================================

print("\n" .. string.rep("=", 60))
print("🎉 SISTEMA COMPLETAMENTE INICIALIZADO")

navGraph:DebugPrint()