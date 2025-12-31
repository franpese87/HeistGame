--[[
	Pawn - Representación física del NPC (Patrón Pawn-Controller)

	Encapsula toda la lógica relacionada con el "cuerpo" del NPC:
	- Referencias físicas (Instance, Humanoid, RootPart)
	- Movimiento y rotación
	- Animaciones (integrado)
	- Indicadores visuales de estado

	El Controller (cerebro) usa el Pawn para interactuar con el mundo físico.

	Usa Janitor para gestión automática de recursos (tweens, GUI, tracks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Janitor = require(ReplicatedStorage.Packages.janitor)

local Pawn = {}
Pawn.__index = Pawn

-- ==============================================================================
-- CONFIGURACIÓN DE ANIMACIONES (R6 Default)
-- ==============================================================================

local ANIMATION_IDS = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	run = "rbxassetid://180426354",
}

local ANIMATION_SPEEDS = {
	idle = 1.0,
	walk = 1.0,
	run = 1.5,
}

-- ==============================================================================
-- CONFIGURACIÓN DE ESTADOS VISUALES
-- ==============================================================================

local STATE_VISUALS = {
	["Patrolling"] = {emoji = "🚶", text = "PATROLLING", color = Color3.fromRGB(0, 255, 0)},
	["Observing"] = {emoji = "👁️", text = "OBSERVING", color = Color3.fromRGB(100, 150, 255)},
	["Chasing"] = {emoji = "🏃", text = "CHASING", color = Color3.fromRGB(255, 0, 0)},
	["Attacking"] = {emoji = "⚔️", text = "ATTACKING", color = Color3.fromRGB(255, 100, 0)},
	["Investigating"] = {emoji = "❓", text = "INVESTIGATING", color = Color3.fromRGB(255, 165, 0)},
	["Returning"] = {emoji = "🔄", text = "RETURNING", color = Color3.fromRGB(255, 255, 0)}
}

-- ==============================================================================
-- CONSTRUCTOR
-- ==============================================================================

function Pawn.new(npcInstance, config)
	local self = setmetatable({}, Pawn)

	-- Janitor para cleanup automático
	self.janitor = Janitor.new()

	-- Referencias físicas
	self.instance = npcInstance
	self.humanoid = npcInstance:FindFirstChildOfClass("Humanoid")
	self.rootPart = npcInstance:FindFirstChild("HumanoidRootPart")

	if not self.humanoid or not self.rootPart then
		warn("[Pawn] " .. npcInstance.Name .. " no tiene Humanoid o HumanoidRootPart")
		return nil
	end

	-- Configuración de velocidades
	config = config or {}
	self.patrolSpeed = config.patrolSpeed or 16
	self.chaseSpeed = config.chaseSpeed or 24

	-- Inicializar sistema de animaciones
	self:_InitializeAnimations()

	-- Sistema de indicadores de estado
	self.showStateIndicator = config.showStateIndicator or false
	self.stateIndicatorOffset = config.stateIndicatorOffset or 4
	self.stateIndicator = nil

	if self.showStateIndicator then
		self:_CreateStateIndicator()
	end

	return self
end

-- ==============================================================================
-- ANIMACIONES (Integrado)
-- ==============================================================================

function Pawn:_InitializeAnimations()
	self.animator = self.humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = self.humanoid
	end

	self.animations = {}
	self.animationTracks = {}

	for animName, animId in pairs(ANIMATION_IDS) do
		local animation = Instance.new("Animation")
		animation.Name = animName
		animation.AnimationId = animId
		self.animations[animName] = animation

		local track = self.animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Core
		self.animationTracks[animName] = track

		-- Registrar track en janitor para cleanup automático
		self.janitor:Add(track, "Destroy")
	end

	self.currentAnimation = nil
	self.currentTrack = nil

	-- Iniciar con idle
	self:PlayAnimation("idle")
end

function Pawn:PlayAnimation(animName, fadeTime)
	if self.currentAnimation == animName then
		return
	end

	if not self.animationTracks[animName] then
		return
	end

	fadeTime = fadeTime or 0.1

	if self.currentTrack then
		self.currentTrack:Stop(fadeTime)
	end

	local track = self.animationTracks[animName]
	track:Play(fadeTime)
	track:AdjustSpeed(ANIMATION_SPEEDS[animName] or 1.0)

	self.currentAnimation = animName
	self.currentTrack = track
end

function Pawn:StopAnimations()
	for _, track in pairs(self.animationTracks) do
		track:Stop(0.1)
	end
	self.currentAnimation = nil
	self.currentTrack = nil
end

function Pawn:SetAnimationSpeed(speed)
	if self.currentTrack then
		self.currentTrack:AdjustSpeed(speed)
	end
end

-- ==============================================================================
-- POSICIÓN Y CFRAME
-- ==============================================================================

function Pawn:GetPosition()
	return self.rootPart.Position
end

function Pawn:GetCFrame()
	return self.rootPart.CFrame
end

function Pawn:SetCFrame(cframe)
	self.rootPart.CFrame = cframe
end

function Pawn:LerpCFrame(targetCFrame, alpha)
	self.rootPart.CFrame = self.rootPart.CFrame:Lerp(targetCFrame, alpha)
end

function Pawn:TeleportTo(position)
	self.instance:PivotTo(CFrame.new(position))
end

-- ==============================================================================
-- MOVIMIENTO
-- ==============================================================================

function Pawn:MoveTo(position)
	self.humanoid:MoveTo(position)
end

function Pawn:StopMovement()
	self.humanoid:MoveTo(self.rootPart.Position)
end

function Pawn:SetWalkSpeed(speed)
	self.humanoid.WalkSpeed = speed
end

function Pawn:SetPatrolSpeed()
	self.humanoid.WalkSpeed = self.patrolSpeed
end

function Pawn:SetChaseSpeed()
	self.humanoid.WalkSpeed = self.chaseSpeed
end

function Pawn:GetPatrolSpeed()
	return self.patrolSpeed
end

function Pawn:GetChaseSpeed()
	return self.chaseSpeed
end

-- ==============================================================================
-- ROTACIÓN
-- ==============================================================================

function Pawn:LookAt(targetPosition)
	local direction = (targetPosition - self.rootPart.Position) * Vector3.new(1, 0, 1)
	if direction.Magnitude > 0 then
		self.rootPart.CFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + direction)
	end
end

function Pawn:SetAutoRotate(enabled)
	self.humanoid.AutoRotate = enabled
end

function Pawn:GetLookVector()
	return self.rootPart.CFrame.LookVector
end

function Pawn:RotateWithTween(targetCFrame, tweenInfo)
	-- Janitor cancela automáticamente el tween anterior al reemplazarlo
	self.janitor:Remove("rotationTween")

	local tween = TweenService:Create(self.rootPart, tweenInfo, {CFrame = targetCFrame})
	self.janitor:Add(tween, "Cancel", "rotationTween")
	tween:Play()

	return tween
end

function Pawn:CancelRotationTween()
	self.janitor:Remove("rotationTween")
end

-- ==============================================================================
-- INDICADOR DE ESTADO
-- ==============================================================================

function Pawn:_CreateStateIndicator()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StateIndicator"
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffset = Vector3.new(0, self.stateIndicatorOffset, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = self.rootPart

	-- Registrar en janitor para cleanup automático
	self.janitor:Add(billboard, "Destroy")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🚶 PATROLLING"
	label.TextSize = 18
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.fromRGB(0, 255, 0)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard

	self.stateIndicator = {billboard = billboard, label = label}
end

function Pawn:UpdateStateIndicator(stateName)
	if not self.showStateIndicator or not self.stateIndicator then return end
	local visual = STATE_VISUALS[stateName]
	if visual then
		self.stateIndicator.label.Text = visual.emoji .. " " .. visual.text
		self.stateIndicator.label.TextColor3 = visual.color
	end
end

-- ==============================================================================
-- ESTADO Y UTILIDADES
-- ==============================================================================

function Pawn:IsAlive()
	return self.humanoid and self.humanoid.Health > 0
end

function Pawn:GetHealth()
	return self.humanoid and self.humanoid.Health or 0
end

function Pawn:GetMaxHealth()
	return self.humanoid and self.humanoid.MaxHealth or 100
end

function Pawn:GetName()
	return self.instance.Name
end

function Pawn:GetInstance()
	return self.instance
end

function Pawn:GetHumanoid()
	return self.humanoid
end

function Pawn:GetRootPart()
	return self.rootPart
end

-- ==============================================================================
-- CLEANUP
-- ==============================================================================

function Pawn:Destroy()
	-- Janitor limpia automáticamente: tweens, tracks, billboard
	self.janitor:Destroy()

	-- Limpiar referencias
	self.animationTracks = {}
	self.animations = {}
	self.currentTrack = nil
	self.currentAnimation = nil
	self.stateIndicator = nil
end

return Pawn
