--!strict
-- init.server.luau
-- Server entry point for HeistGame.
-- Boot order:
--   0. Servicios base (DoorService, NavigationGraph, NPCAISystem)
--   1. RemoteEvents en ReplicatedStorage/Events
--   2. Módulos de mecánicas (AlarmManager, MissionManager, SafeCrackingServer)
--   3. Routing de eventos
--   4. Arranque de misión y loops

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local isStudio = RunService:IsStudio()

-- ==============================================================================
-- 0. SISTEMAS NPC / NAVEGACIÓN / PUERTAS (feature/npc_ai_system + door_system)
-- ==============================================================================

local NPCAISystem   = require(script.NPCAISystem)
local DoorService   = require(script.Services.DoorService)
local NoiseService  = require(script.Services.NoiseService)
local DebugConfig   = require(script.Config.DebugConfig)
local NPCBaseConfig = require(script.Config.NPCBaseConfig)
local NPCSpawnList  = require(script.Config.NPCSpawnList)

print("🎮 Iniciando sistema de NPCs...")

DoorService.Init()

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

local npcTemplate = game.ServerStorage:FindFirstChild("NPCTemplate")
if not npcTemplate then
	error("❌ No se encontró NPCTemplate en ServerStorage")
end

local npcConfigWithLogging = table.clone(NPCBaseConfig)
npcConfigWithLogging.logging = DebugConfig.logging

local spawnedNPCs = NPCAISystem.Factory.SpawnAllNPCs(
	npcTemplate,
	navGraph,
	NPCSpawnList,
	npcConfigWithLogging
)

local registry = NPCAISystem.GetRegistry()
registry:Start()

NPCAISystem.Visualizer.PrintSystemReport(registry, navGraph, spawnedNPCs, NPCBaseConfig)

if isStudio and DebugConfig.visualizeOnStartup then
	NPCAISystem.Visualizer.DrawAll(navGraph, DebugConfig)
end

-- ==============================================================================
-- 1. REMOTEVENTS
-- ==============================================================================

local Events  = Instance.new("Folder")
Events.Name   = "Events"
Events.Parent = ReplicatedStorage

local function makeEvent(name: string): RemoteEvent
	local e    = Instance.new("RemoteEvent")
	e.Name     = name
	e.Parent   = Events
	return e
end

local events = {
	DetectionUpdated      = makeEvent("DetectionUpdated"),
	AlarmTriggered        = makeEvent("AlarmTriggered"),
	PhaseChanged          = makeEvent("PhaseChanged"),
	ObjectiveUpdated      = makeEvent("ObjectiveUpdated"),
	AllObjectivesComplete = makeEvent("AllObjectivesComplete"),
	EscapeTimerSync       = makeEvent("EscapeTimerSync"),
	MissionComplete       = makeEvent("MissionComplete"),
	RequestInteract       = makeEvent("RequestInteract"),
	InteractResult        = makeEvent("InteractResult"),
	RequestStartMiniGame  = makeEvent("RequestStartMiniGame"),
	MiniGameResult        = makeEvent("MiniGameResult"),
	UpdateStealthState    = makeEvent("UpdateStealthState"),
}

-- ==============================================================================
-- 2. MÓDULOS DE MECÁNICAS
-- ==============================================================================

local Server = script.Parent

local GameSession        = require(Server.GameSession)
local AlarmManager       = require(Server.AlarmManager)
local MissionManager     = require(Server.MissionManager)
local SafeCrackingServer = require(Server.SafeCrackingServer)

-- GameSession MUST init first: wires PlayerAdded/PlayerRemoving for all modules.
GameSession.init()

-- Puente NPC→AlarmManager: Controller.lua debe crear este BindableEvent y
-- dispararlo cuando transite a CHASING. Mientras tanto funciona sin él.
local npcBridge: BindableEvent? = script.Parent:FindFirstChild("NPCDetectedPlayer") :: BindableEvent?

AlarmManager.init(events.AlarmTriggered, events.PhaseChanged, npcBridge)

MissionManager.init({
	PhaseChanged          = events.PhaseChanged,
	ObjectiveUpdated      = events.ObjectiveUpdated,
	AllObjectivesComplete = events.AllObjectivesComplete,
	EscapeTimerSync       = events.EscapeTimerSync,
	MissionComplete       = events.MissionComplete,
})

SafeCrackingServer.init({
	InteractResult        = events.InteractResult,
	RequestStartMiniGame  = events.RequestStartMiniGame,
	MiniGameResult        = events.MiniGameResult,
}, MissionManager)

-- ==============================================================================
-- 3. ROUTING DE EVENTOS
-- ==============================================================================

events.RequestInteract.OnServerEvent:Connect(function(
	player: Player,
	objectType: string,
	objectId: string
)
	if objectType == "safe" then
		SafeCrackingServer.openSession(player, objectId, "safe")

	elseif objectType == "alarm_panel" or objectType == "camera" then
		SafeCrackingServer.openSession(player, objectId, "hack")

	elseif objectType == "loot" then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local lootModel = game.Workspace:FindFirstChild(objectId, true)
			if lootModel and lootModel:IsA("BasePart") then
				local dist = ((lootModel :: BasePart).Position - root.Position).Magnitude
				if dist <= 12 then
					MissionManager.reportLootCollected(player, objectId)
					events.InteractResult:FireClient(player, objectId, true, nil)
				else
					events.InteractResult:FireClient(player, objectId, false, "Too far")
				end
			end
		end

	elseif objectType == "exit" then
		MissionManager.onPlayerReachedExit(player)
	end
end)

events.UpdateStealthState.OnServerEvent:Connect(function(
	player: Player,
	isCrouching: boolean,
	_isDisguised: boolean,
	_inShadow: boolean
)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if root and humanoid then
		-- Scale noise range: crouching walk generates ~8 studs range, full sprint ~20
		local speedRatio = math.clamp(humanoid.WalkSpeed / 16, 0, 1)
		local noiseRange = isCrouching
			and (speedRatio * 8)
			or  (8 + speedRatio * 12)
		if noiseRange > 1 then
			NoiseService.MakeNoise(root.Position, noiseRange)
		end
	end
end)

-- ==============================================================================
-- 4. ARRANQUE DE MISIÓN Y LOOPS
-- ==============================================================================

task.delay(2, function()
	MissionManager.loadMission("bank_job")
	task.delay(1, function()
		MissionManager.startMission()
	end)
end)

RunService.Heartbeat:Connect(function(dt: number)
	MissionManager.tick(dt)
end)

print("[HeistGame] Server initialised.")
