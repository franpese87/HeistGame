--[[
	Controller - Cerebro del NPC (Patron Pawn-Controller)

	Motor de FSM (Maquina de Estados Finitos) que:
	- Coordina sensores (Vision, Audicion)
	- Despacha logica al estado activo (States/)
	- Delega navegacion al PathFollower (Components/)

	Usa el Pawn para interactuar con el mundo fisico.

	Cada estado es un modulo independiente con Enter(ctrl)/Update(ctrl)/Exit(ctrl).
]]

local VisionSensor = require(script.Parent.Parent.Components.VisionSensor)
local Combat = require(script.Parent.Parent.Components.Combat)
local HearingSensor = require(script.Parent.Parent.Components.HearingSensor)
local PathFollower = require(script.Parent.Parent.Components.PathFollower)
local DebugConfig = require(script.Parent.Parent.Parent.Config.DebugConfig)

-- State modules
local StateModules = {
	Patrolling = require(script.Parent.States.PatrollingState),
	Observing = require(script.Parent.States.ObservingState),
	Alerted = require(script.Parent.States.AlertedState),
	Chasing = require(script.Parent.States.ChasingState),
	Attacking = require(script.Parent.States.AttackingState),
	Investigating = require(script.Parent.States.InvestigatingState),
	Returning = require(script.Parent.States.ReturningState),
	Stunned = require(script.Parent.States.StunnedState),
}

-- Estados que requieren sensores a maxima frecuencia (cada frame)
local HIGH_PRIORITY_STATES = {
	Chasing = true,
	Attacking = true,
	Alerted = true,
}

local Controller = {}
Controller.__index = Controller

-- ==============================================================================
-- CONSTRUCTOR
-- ==============================================================================

function Controller.new(pawn, navigationGraph, config)
	local self = setmetatable({}, Controller)

	self.pawn = pawn
	self.graph = navigationGraph
	config = config or {}

	-- RaycastParams reutilizable (observacion, validacion de angulos)
	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.FilterDescendantsInstances = {pawn:GetInstance()}

	-- Componente de navegacion
	self.pathFollower = PathFollower.new(pawn, navigationGraph, config)

	-- Observacion
	self.observationAngles = config.observationAngles or {-45, 0, 45, 0}
	self.observationTimePerAngle = config.observationTimePerAngle or 1.0
	self.observationValidationDistance = config.observationValidationDistance or 5
	self.rotationTweenInfo = TweenInfo.new(self.observationTimePerAngle * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	self.observationHeadRatio = config.observationHeadRatio or 0.7
	self.observationTorsoRatio = config.observationTorsoRatio or 0.3

	-- Rotacion en combate
	self.attackRotationSpeed = config.attackRotationSpeed or 0.15

	-- Reaccion (ALERTED)
	self.reactionTime = config.reactionTime or 0.8
	self.alertedTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self.alertedHeadRatio = config.alertedHeadRatio or 0.8
	self.alertedTorsoRatio = config.alertedTorsoRatio or 0.2

	-- Head tracking (CHASING)
	self.enableHeadTrackingDuringChase = config.enableHeadTrackingDuringChase
	if self.enableHeadTrackingDuringChase == nil then
		self.enableHeadTrackingDuringChase = true
	end
	self.headTrackingMaxAngle = config.headTrackingMaxAngle or 90

	-- Investigacion (duracion = tiempo total de observacion en un nodo de patrulla)
	self.investigationDuration = #self.observationAngles * self.observationTimePerAngle

	-- Stun
	self.stunDuration = config.stunDuration or 3

	-- FSM configuracion (sandbox/testing)
	self.allowedStates = config.allowedStates
	self.disableSenses = config.disableSenses or false

	-- Componentes (Sensores y Combate)
	local npcInstance = pawn:GetInstance()
	self.visionSensor = VisionSensor.new(npcInstance, config)
	self.combatSystem = Combat.new(npcInstance, config)
	self.hearingSensor = HearingSensor.new(npcInstance, config)

	if DebugConfig.visuals and DebugConfig.visuals.showVisionDebug then
		self.visionSensor:SetDebug(true)
	end

	-- Estado FSM: initialState configurable con validacion
	local requestedInitial = config.initialState
	local validInitial = false
	if requestedInitial and StateModules[requestedInitial] then
		self.currentState = requestedInitial
		validInitial = true
	end
	if not validInitial then
		if requestedInitial and requestedInitial ~= "Patrolling" then
			warn("[Controller] " .. pawn:GetName() .. ": initialState '"
				.. tostring(requestedInitial) .. "' invalido, usando Patrolling")
		end
		self.currentState = "Patrolling"
	end
	self.isActive = true
	self.stateStartTime = os.clock()

	-- Target tracking
	self.target = nil
	self.lastSeenPosition = nil
	self.lastVisionEvents = nil
	self.senseFrameCounter = 0

	-- Patrullaje
	self.patrolNodes = config.patrolNodes or {}
	self.currentPatrolIndex = 1

	-- Cache de orientaciones (invalidado por GeometryVersion)
	self.observationCache = {}

	-- Estado temporal compartido (usado por estados)
	self.originalCFrame = nil
	self.currentObservationIndex = 1
	self.observationStartTime = 0
	self.alertedStartTime = 0

	-- Debug logging
	local loggingConfig = config.logging or DebugConfig.logging or {}
	self.logFlags = {
		stateChanges = loggingConfig.stateChanges or false,
		detection = loggingConfig.detection or false,
	}

	-- Iniciar patrullaje
	if #self.patrolNodes > 0 then
		self:MoveToNextPatrolNode()
	end

	return self
end

-- ==============================================================================
-- DEBUG LOGGING
-- ==============================================================================

function Controller:Log(category, message)
	if self.logFlags[category] then
		print("[" .. self.pawn:GetName() .. "][" .. category .. "] " .. message)
	end
end

-- ==============================================================================
-- MAIN UPDATE LOOP
-- ==============================================================================

function Controller:Update(_deltaTime)
	if not self.isActive or not self.pawn:IsAlive() then
		self.isActive = false
		return
	end

	-- Stunned: no procesar sensores (inconsciente), solo Update del estado
	if self.currentState == "Stunned" then
		local stateModule = StateModules[self.currentState]
		if stateModule then
			stateModule.Update(self)
		end
		return
	end

	-- Sensores (desactivables para sandbox/testing)
	if not self.disableSenses then
		self.senseFrameCounter = self.senseFrameCounter + 1
		if HIGH_PRIORITY_STATES[self.currentState] or self.senseFrameCounter % 2 == 0 then
			self:UpdateSenses()
		end
	end

	-- Despachar al estado activo
	local stateModule = StateModules[self.currentState]
	if stateModule then
		stateModule.Update(self)
	end
end

-- ==============================================================================
-- SENSORY SYSTEM
-- ==============================================================================

function Controller:UpdateSenses()
	-- 1. VISION
	local currentTarget, lastPos, events = self.visionSensor:Scan()
	self.lastVisionEvents = events

	if currentTarget then
		self.target = currentTarget
	end

	if lastPos then
		self.lastSeenPosition = lastPos
	end

	-- Deteccion instantanea -> ALERTED (solo desde estados no-combate)
	if events.TargetSpotted then
		self:Log("detection", "TARGET DETECTADO: " .. currentTarget.Name)

		if self.currentState ~= "Chasing"
		   and self.currentState ~= "Attacking"
		   and self.currentState ~= "Alerted" then
			self:ChangeState("Alerted")
		end
	end

	if events.TargetLost then
		self:Log("detection", "TARGET PERDIDO (Olvido total)")
		self.target = nil

		if self.currentState == "Chasing" or self.currentState == "Attacking" then
			self:ChangeState("Investigating")
		end
	end

	-- 2. OIDO
	local heardNoisePos = self.hearingSensor:CheckForNoise()
	if heardNoisePos then
		if self.currentState == "Patrolling" or self.currentState == "Observing" or self.currentState == "Returning" then
			self:Log("detection", "Ruido oido en " .. tostring(heardNoisePos))
			self.lastSeenPosition = heardNoisePos
			self:ChangeState("Investigating")
		end
	end
end

-- ==============================================================================
-- STATE MANAGEMENT
-- ==============================================================================

function Controller:ChangeState(newState)
	if self.currentState == newState then return end

	-- Verificar si el estado esta permitido (sandbox/testing)
	if self.allowedStates and not self.allowedStates[newState] then
		return
	end

	-- EXIT estado actual
	local oldStateModule = StateModules[self.currentState]
	if oldStateModule and oldStateModule.Exit then
		oldStateModule.Exit(self)
	end

	local oldState = self.currentState
	self.currentState = newState
	self.stateStartTime = os.clock()
	self:Log("stateChanges", oldState .. " -> " .. newState)

	self.pawn:UpdateStateIndicator(newState)

	-- ENTER nuevo estado
	local newStateModule = StateModules[newState]
	if newStateModule and newStateModule.Enter then
		newStateModule.Enter(self, oldState)
	end
end

function Controller:GetState()
	return self.currentState
end

-- ==============================================================================
-- PATROL HELPERS (usados por estados)
-- ==============================================================================

function Controller:MoveToNextPatrolNode()
	if #self.patrolNodes == 0 then return end
	self.currentPatrolIndex = self.currentPatrolIndex + 1
	if self.currentPatrolIndex > #self.patrolNodes then
		self.currentPatrolIndex = 1
	end
	self.pathFollower:ClearPath()
end

function Controller:GetNearestPatrolNode()
	local nearestNode = nil
	local shortestDistance = math.huge
	for _, node in ipairs(self.patrolNodes) do
		local distance = (self.pawn:GetPosition() - node.Position).Magnitude
		if distance < shortestDistance then
			shortestDistance = distance
			nearestNode = node
		end
	end
	return nearestNode
end

-- ==============================================================================
-- EXTERNAL API
-- ==============================================================================

function Controller:ApplyStun()
	self:ChangeState("Stunned")
end

-- ==============================================================================
-- DEBUG
-- ==============================================================================

function Controller:EnableDebug(config)
	self.debugEnabled = true
	self.debugConfig = config

	-- Propagar al PathFollower
	self.pathFollower:SetDebug(true, config)
end

-- ==============================================================================
-- CLEANUP
-- ==============================================================================

function Controller:Destroy()
	self.isActive = false

	if self.hearingSensor then
		self.hearingSensor:Destroy()
	end

	if self.pawn then
		self.pawn:Destroy()
	end
end

return Controller
