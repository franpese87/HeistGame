local NPCAISystem = require(script.NPCAISystem)
local DebugConfig = require(script.Config.DebugConfig)
local NPCBaseConfig = require(script.Config.NPCBaseConfig)
local NPCSpawnList = require(script.Config.NPCSpawnList)

local RunService = game:GetService("RunService")
local isStudio = RunService:IsStudio()

print("🎮 Iniciando sistema de NPCs...")

-- ==============================================================================
-- 1. CREAR GRAFO DE NAVEGACIÓN
-- ==============================================================================

local navGraph = NPCAISystem.Setup.CreateNavigationGraphFromFolder(
	workspace.NavigationNodes,
	{
		mode = "hybrid",
		maxDistance = 40,
		useRaycast = true,
		maxConnectionsPerNode = 6,
		ignoreList = { workspace.NavigationNodes },
		destroyParts = not DebugConfig.keepNodesInWorkspace,
		logging = DebugConfig.logging,
	}
)

-- ==============================================================================
-- 2. CREAR Y SPAWNEAR NPCs
-- ==============================================================================

local npcTemplate = game.ServerStorage:FindFirstChild("NPCTemplate")
if not npcTemplate then
	error("❌ No se encontró NPCTemplate en ServerStorage")
end

-- Inyectar logging config en NPCBaseConfig
local npcConfigWithLogging = table.clone(NPCBaseConfig)
npcConfigWithLogging.logging = DebugConfig.logging

-- SpawnAllNPCs ahora registra automáticamente en el Registry singleton
local spawnedNPCs = NPCAISystem.Setup.SpawnAllNPCs(
	npcTemplate,
	navGraph,
	NPCSpawnList,
	npcConfigWithLogging
)

-- Obtener registry e iniciar loop de actualización
local registry = NPCAISystem.GetRegistry()
registry:Start()

-- ==============================================================================
-- 3. REPORTE Y DEBUG (SOLO STUDIO)
-- ==============================================================================

NPCAISystem.DebugUtilities.PrintSystemReport(
	registry,
	navGraph,
	spawnedNPCs,
	NPCBaseConfig,
	DebugConfig
)

if isStudio and DebugConfig.visualizeOnStartup then
	NPCAISystem.DebugUtilities.DrawAll(navGraph, DebugConfig)
end
