--[[
	PathFollower - Componente de navegacion por grafo

	Encapsula toda la logica de seguimiento de caminos:
	- Calculo de rutas via A* (delegado al NavigationGraph)
	- Seguimiento de path nodo a nodo
	- Interaccion con puertas durante navegacion
	- Path smoothing
	- Persecucion con recalculo dinamico

	Uso:
		local pf = PathFollower.new(pawn, graph, config)
		pf:NavigateToPosition(targetPos, "patrol")
		-- en el update loop:
		pf:FollowCurrentPath()
]]

local DoorService = require(script.Parent.Parent.Parent.Services.DoorService)
local Visualizer = require(script.Parent.Parent.Debug.Visualizer)

local ARRIVAL_THRESHOLD = 3

local PathFollower = {}
PathFollower.__index = PathFollower

function PathFollower.new(pawn, graph, config)
	local self = setmetatable({}, PathFollower)

	self.pawn = pawn
	self.graph = graph

	config = config or {}
	self.enablePathSmoothing = config.enablePathSmoothing ~= false
	self.agentRadius = config.agentRadius or 1.0
	self.directApproachDistance = config.directApproachDistance or 8
	self.nodeTimeout = 4
	self.pathRecalcInterval = config.pathRecalcInterval or 1.5
	self.pathFailCooldown = config.pathFailCooldown or 0.3

	-- RaycastParams para deteccion de puertas
	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.raycastParams.FilterDescendantsInstances = {pawn:GetInstance()}

	-- Estado de navegacion
	self.currentPath = nil
	self.currentPathIndex = 1
	self.waitingForDoor = nil
	self.targetLastPosition = nil
	self.lastPathCalcTime = 0
	self.lastPathFailTime = 0
	self.timeStartedMovingToNode = 0

	-- Debug
	self.debugEnabled = false
	self.debugConfig = nil

	return self
end

-- ==============================================================================
-- API PUBLICA
-- ==============================================================================

function PathFollower:HasArrivedAt(position)
	return (self.pawn:GetPosition() - position).Magnitude < ARRIVAL_THRESHOLD
end

function PathFollower:HasPath()
	return self.currentPath ~= nil and #self.currentPath > 0
end

function PathFollower:ClearPath()
	self.currentPath = nil
	self.currentPathIndex = 1
	self.waitingForDoor = nil
end

function PathFollower:ClearChaseState()
	self:ClearPath()
	self.targetLastPosition = nil
end

-- Navega hacia una posicion usando el grafo. Maneja velocidad y animacion.
function PathFollower:NavigateToPosition(position, mode)
	if mode == "patrol" then
		self.pawn:SetPatrolSpeed()
	else
		self.pawn:SetChaseSpeed()
	end

	if self.currentPath and #self.currentPath > 0 then
		self.pawn:PlayAnimation(mode == "patrol" and "walk" or "run")
		self:FollowCurrentPath()
	else
		self:CalculatePathTo(position)
	end
end

-- Navega hacia un target en movimiento (persecucion).
-- Decide entre acercamiento directo (corta distancia) y grafo (larga distancia).
function PathFollower:NavigateToTarget(targetRoot)
	local npcPos = self.pawn:GetPosition()
	local targetPos = targetRoot.Position
	local distance = (npcPos - targetPos).Magnitude

	if distance <= self.directApproachDistance then
		self.currentPath = nil
		self.pawn:MoveTo(targetPos)
	else
		self:ChaseUsingGraph(targetRoot)
	end
end

-- ==============================================================================
-- PATHFINDING
-- ==============================================================================

function PathFollower:CalculatePathTo(targetPosition)
	local npcPos = self.pawn:GetPosition()

	local startNode = self.graph:GetNearestNodeTowardsTarget(npcPos, targetPosition)
	local endNode = self.graph:GetNearestNode(targetPosition)

	if not startNode or not endNode then
		self.currentPath = nil
		return
	end

	if startNode.name == endNode.name then
		self.currentPath = nil
		return
	end

	local path = self.graph:GetPathBetweenNodes(startNode, endNode)

	-- Fallback: si A* falla con el nodo inicial, probar candidatos alternativos.
	if not path then
		local startCandidates = self.graph:GetNearestNodeCandidates(npcPos, 5)
		for _, candidate in ipairs(startCandidates) do
			if candidate.name ~= startNode.name and candidate.name ~= endNode.name then
				local fallbackPath = self.graph:GetPathBetweenNodes(candidate, endNode)
				if fallbackPath then
					path = fallbackPath
					break
				end
			end
		end
	end

	if path and #path > 0 then
		if self.enablePathSmoothing then
			path = self.graph:SmoothPath(path, self.agentRadius)
		end

		self.currentPath = path
		self.timeStartedMovingToNode = os.clock()

		local firstNode = path[1]
		local distToFirst = (npcPos - firstNode.position).Magnitude
		if distToFirst < 2 and #path > 1 then
			self.currentPathIndex = 2
		else
			self.currentPathIndex = 1
		end

		if self.debugEnabled and self.debugConfig and self.debugConfig.showPath then
			Visualizer.DrawNPCPath(self.pawn:GetName(), path, self.currentPathIndex, {
				color = self.debugConfig.pathColor,
			})
		end
	else
		self.lastPathFailTime = os.clock()
		self.currentPath = nil
	end
end

-- ==============================================================================
-- PERSECUCION CON RECALCULO
-- ==============================================================================

function PathFollower:ChaseUsingGraph(targetRoot)
	local targetPosition = targetRoot.Position
	local currentTime = os.clock()

	if not self.currentPath or #self.currentPath == 0 then
		if currentTime - self.lastPathFailTime < self.pathFailCooldown then
			return
		end
		self:CalculatePathTo(targetPosition)
		self.targetLastPosition = targetPosition
		self.lastPathCalcTime = currentTime
		return
	end

	-- Recalcular si el target se movio significativamente
	local targetMoved = self.targetLastPosition and (targetPosition - self.targetLastPosition).Magnitude > 10
	local timerExpired = (currentTime - self.lastPathCalcTime) >= self.pathRecalcInterval
	local arrivedAtNode = self.currentPath[self.currentPathIndex] and self:HasArrivedAt(self.currentPath[self.currentPathIndex].position)

	if targetMoved and (arrivedAtNode or timerExpired) then
		self:CalculatePathTo(targetPosition)
		self.targetLastPosition = targetPosition
		self.lastPathCalcTime = currentTime
	end

	self:FollowCurrentPath()
end

-- ==============================================================================
-- SEGUIMIENTO DE PATH
-- ==============================================================================

function PathFollower:FollowCurrentPath()
	if not self.currentPath or self.currentPathIndex > #self.currentPath then
		self.currentPath = nil
		return
	end

	-- Esperando a que una puerta termine de abrirse
	if self.waitingForDoor then
		if DoorService.IsClosed(self.waitingForDoor) or DoorService.IsAnimating(self.waitingForDoor) then
			self.pawn:StopMovement()
			self.pawn:PlayAnimation("idle")
			return
		end
		self.waitingForDoor = nil
	end

	if os.clock() - self.timeStartedMovingToNode > self.nodeTimeout then
		self.currentPath = nil
		return
	end

	local targetNode = self.currentPath[self.currentPathIndex]

	-- Detectar puerta cerrada en el camino
	local doorInPath = self:CheckForDoorInPath(targetNode.position)
	if doorInPath and DoorService.IsClosed(doorInPath) then
		self.pawn:StopMovement()
		self.pawn:PlayAnimation("idle")
		self.waitingForDoor = doorInPath
		DoorService.Open(doorInPath, self.pawn:GetPosition(), self.pawn:GetInstance())
		return
	end

	self.pawn:MoveTo(targetNode.position)

	if self:HasArrivedAt(targetNode.position) then
		self.currentPathIndex = self.currentPathIndex + 1
		self.timeStartedMovingToNode = os.clock()
		if self.currentPathIndex > #self.currentPath then
			self.currentPath = nil
		end
	end
end

function PathFollower:CheckForDoorInPath(targetPosition)
	local origin = self.pawn:GetPosition()
	local direction = targetPosition - origin
	local distance = direction.Magnitude

	if distance < 0.5 then return nil end

	local result = workspace:Raycast(origin, direction, self.raycastParams)
	if not result then return nil end

	local hitDistance = (result.Position - origin).Magnitude
	if hitDistance > distance then return nil end

	return DoorService.GetDoorFromPart(result.Instance)
end

-- ==============================================================================
-- DEBUG
-- ==============================================================================

function PathFollower:SetDebug(enabled, config)
	self.debugEnabled = enabled
	self.debugConfig = config
end

return PathFollower
