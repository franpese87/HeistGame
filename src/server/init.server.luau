local NPCAISystem = require(script.NPCAISystem)
local DoorService = require(script.Services.DoorService)
local ProjectileService = require(script.Services.ProjectileService)
local TaserConfig = require(script.Config.TaserConfig)
local DebugConfig = require(script.Config.DebugConfig)
local NPCBaseConfig = require(script.Config.NPCBaseConfig)
local NPCSpawnList = require(script.Config.NPCSpawnList)

local RunService = game:GetService("RunService")
local isStudio = RunService:IsStudio()

print("🎮 Iniciando sistema de NPCs...")

-- ==============================================================================
-- 0. INICIALIZAR SERVICIOS
-- ==============================================================================

DoorService.Init()
ProjectileService.Init()

-- ==============================================================================
-- 0.5 REMOTE EVENTS
-- ==============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	local origin = rootPart.Position
	local direction = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit

	lastFireTimes[player] = now
	ProjectileService.Fire(origin, direction, TaserConfig, character)
end)

-- Limpiar tracking cuando el player sale
Players.PlayerRemoving:Connect(function(player)
	lastFireTimes[player] = nil
end)

-- ==============================================================================
-- 0.75 PLAYER SETUP - Tool de Taser
-- ==============================================================================

local function createTaserHandleProcedural(tool)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(0.8, 0.3, 0.3)
	handle.Color = Color3.fromRGB(30, 120, 220)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Parent = tool
end

local function createTaserTool()
	-- Intentar usar asset si está configurado
	local modelId = TaserConfig.toolModelId
	if modelId and modelId ~= "" then
		local success, result = pcall(function()
			return game:GetService("InsertService"):LoadAsset(tonumber(modelId:match("%d+")))
		end)
		if success and result then
			local toolAsset = result:FindFirstChildWhichIsA("Tool", true)
			if toolAsset then
				toolAsset.Name = "Taser"
				toolAsset.CanBeDropped = false
				toolAsset.Parent = nil
				result:Destroy()
				return toolAsset
			end
			-- Asset cargó pero no contiene un Tool — listar hijos para diagnosticar
			local children = {}
			for _, child in ipairs(result:GetChildren()) do
				table.insert(children, child.ClassName .. " '" .. child.Name .. "'")
			end
			warn("[TaserTool] Asset cargó pero no contiene Tool. Hijos: " .. table.concat(children, ", "))
			result:Destroy()
		else
			warn("[TaserTool] InsertService:LoadAsset falló: " .. tostring(result))
		end
		warn("[TaserTool] Usando modelo procedural")
	end

	-- Fallback: modelo procedural
	local tool = Instance.new("Tool")
	tool.Name = "Taser"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = ""
	createTaserHandleProcedural(tool)
	return tool
end

local function equipTaserToPlayer(player, character)
	character:WaitForChild("Humanoid", 5)
	local backpack = player:WaitForChild("Backpack", 5)
	if not backpack then return end

	local tool = createTaserTool()
	tool.Parent = backpack  -- El cliente equipa desde LocalScript para registrar input correctamente
end

local function setupPlayerTaser(player)
	player.CharacterAdded:Connect(function(character)
		equipTaserToPlayer(player, character)
	end)
	-- Character ya cargado (jugadores presentes al iniciar el script en Studio)
	if player.Character then
		task.spawn(equipTaserToPlayer, player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayerTaser)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerTaser(player)
end

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
local spawnedNPCs = NPCAISystem.Factory.SpawnAllNPCs(
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

NPCAISystem.Visualizer.PrintSystemReport(
	registry,
	navGraph,
	spawnedNPCs,
	NPCBaseConfig
)

if isStudio and DebugConfig.visualizeOnStartup then
	NPCAISystem.Visualizer.DrawAll(navGraph, DebugConfig)
end
