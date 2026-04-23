local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NPCAISystem = require(script.NPCAISystem)
local DoorService = require(script.Services.DoorService)
local ProjectileService = require(script.Services.ProjectileService)
local TaserConfig = require(ReplicatedStorage.Shared.TaserConfig)
local DebugConfig = require(script.Config.DebugConfig)
local NPCBaseConfig = require(script.Config.NPCBaseConfig)
local isStudio = RunService:IsStudio()

print("🎮 Iniciando sistema de NPCs...")

-- ==============================================================================
-- 0. INICIALIZAR SERVICIOS
-- ==============================================================================

DoorService.Init()
ProjectileService.Init()

-- Limpieza del asset Roblox Taser en StarterPack.
-- El asset trae un LocalScript (Stickmasterluke) con cooldown propio de 3s
-- y toggling de Tool.Enabled que interfiere con nuestra lógica cliente.
-- Se destruye aquí para que el Tool distribuido al Backpack venga limpio.
local StarterPack = game:GetService("StarterPack")
local taserTemplate = StarterPack:FindFirstChild("Taser")
if taserTemplate then
	for _, d in ipairs(taserTemplate:GetDescendants()) do
		if d:IsA("LocalScript") or d:IsA("Script") then
			d:Destroy()
		end
	end
end

-- ==============================================================================
-- 0.5 REMOTE EVENTS
-- ==============================================================================

local Players = game:GetService("Players")

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local taserEvent = Instance.new("RemoteEvent")
taserEvent.Name = "TaserFire"
taserEvent.Parent = eventsFolder

-- Cooldown tracking por player (server-side autoritativo)
local lastFireTimes = {}

taserEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()

	-- Validar cooldown server-side
	if lastFireTimes[player] and now - lastFireTimes[player] < TaserConfig.cooldown then
		return
	end

	-- Validar que el character existe
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Usar posición y dirección del SERVER (anti-spoofing)
	local direction = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	-- Offset forward: evita que el proyectil spawnee dentro del hitbox
	-- del player en movimiento (velocidad player + lag puede solapar con el ray).
	local origin = rootPart.Position + direction * 2

	lastFireTimes[player] = now
	ProjectileService.Fire(origin, direction, TaserConfig, character)
end)

-- Limpiar tracking cuando el player sale
Players.PlayerRemoving:Connect(function(player)
	lastFireTimes[player] = nil
end)

-- ==============================================================================
-- 1. CREAR GRAFO DE NAVEGACIÓN
-- ==============================================================================

-- Mantener las Parts de nodos si estamos en Studio y showNodes está activo
local keepNodesForDebug = isStudio and DebugConfig.visualizeOnStartup and DebugConfig.showNodes

local navGraph = NPCAISystem.Factory.CreateNavigationGraphFromFolder(
	workspace.NavigationNodes,
	{
		mode = "hybrid",
		maxDistance = 40,
		useRaycast = true,
		maxConnectionsPerNode = 6,
		ignoreList = { workspace.NavigationNodes },
		logging = DebugConfig.logging,
		keepSourceParts = keepNodesForDebug,
	}
)

-- ==============================================================================
-- 2. DESCUBRIR E INICIALIZAR NPCs DEL NIVEL
-- ==============================================================================

-- Inyectar logging config en NPCBaseConfig
local npcConfigWithLogging = table.clone(NPCBaseConfig)
npcConfigWithLogging.logging = DebugConfig.logging

-- Descubrir NPCs con tag "NPC" en el nivel e inicializarlos
local spawnedNPCs = NPCAISystem.Factory.InitializeWorldNPCs(
	navGraph,
	npcConfigWithLogging
)

-- Obtener registry e iniciar loop de actualización
local registry = NPCAISystem.GetRegistry()
registry:Start()

-- ==============================================================================
-- 3. REPORTE Y DEBUG (SOLO STUDIO)
-- ==============================================================================

NPCAISystem.Visualizer.PrintSystemReport(
	registry,
	navGraph,
	spawnedNPCs,
	NPCBaseConfig
)

if isStudio and DebugConfig.visualizeOnStartup then
	NPCAISystem.Visualizer.DrawAll(navGraph, DebugConfig)
end
