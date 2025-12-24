local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Janitor = require(ReplicatedStorage.Packages.janitor)

local NPCAnimator = {}
NPCAnimator.__index = NPCAnimator

-- ==============================================================================
-- CONFIGURACIÓN DE ANIMACIONES (R6 Default)
-- ==============================================================================

local ANIMATION_IDS = {
	idle = "rbxassetid://180435571",  -- Animación idle default R6
	walk = "rbxassetid://180426354",  -- Animación walk default R6
	run = "rbxassetid://180426354",   -- Animación run default R6 (mismo que walk pero más rápido)
}

-- Velocidades de reproducción para diferenciar walk de run
local ANIMATION_SPEEDS = {
	idle = 1.0,
	walk = 1.0,
	run = 1.5,  -- Más rápido para simular correr
}

-- ==============================================================================
-- CONSTRUCTOR
-- ==============================================================================

function NPCAnimator.new(humanoid)
	local self = setmetatable({}, NPCAnimator)

	self.janitor = Janitor.new()
	self.humanoid = humanoid
	self.animator = humanoid:FindFirstChildOfClass("Animator")

	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = humanoid
	end

	-- Cargar todas las animaciones
	self.animations = {}
	self.animationTracks = {}

	for animName, animId in pairs(ANIMATION_IDS) do
		local animation = Instance.new("Animation")
		animation.Name = animName
		animation.AnimationId = animId

		self.animations[animName] = animation

		-- Cargar el track
		local track = self.animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Core

		self.animationTracks[animName] = track
		self.janitor:Add(track, "Destroy")
	end

	-- Estado actual
	self.currentAnimation = nil
	self.currentTrack = nil

	-- Iniciar con idle
	self:PlayAnimation("idle")

	return self
end

-- ==============================================================================
-- REPRODUCIR ANIMACIÓN
-- ==============================================================================

function NPCAnimator:PlayAnimation(animName, fadeTime)
	-- Si ya está reproduciendo esta animación, no hacer nada
	if self.currentAnimation == animName then
		return
	end

	-- Validar que existe la animación
	if not self.animationTracks[animName] then
		return
	end

	fadeTime = fadeTime or 0.1

	-- Detener animación anterior
	if self.currentTrack then
		self.currentTrack:Stop(fadeTime)
	end

	-- Reproducir nueva animación
	local track = self.animationTracks[animName]
	track:Play(fadeTime)

	-- Ajustar velocidad de reproducción
	track:AdjustSpeed(ANIMATION_SPEEDS[animName] or 1.0)

	-- Actualizar estado
	self.currentAnimation = animName
	self.currentTrack = track

	-- Debug
	-- print("🎬 Reproduciendo: " .. animName)
end

-- ==============================================================================
-- DETENER TODAS LAS ANIMACIONES
-- ==============================================================================

function NPCAnimator:StopAll()
	for _, track in pairs(self.animationTracks) do
		track:Stop(0.1)
	end

	self.currentAnimation = nil
	self.currentTrack = nil
end

-- ==============================================================================
-- AJUSTAR VELOCIDAD DE ANIMACIÓN ACTUAL
-- ==============================================================================

function NPCAnimator:SetSpeed(speed)
	if self.currentTrack then
		self.currentTrack:AdjustSpeed(speed)
	end
end

-- ==============================================================================
-- OBTENER ESTADO ACTUAL
-- ==============================================================================

function NPCAnimator:GetCurrentAnimation()
	return self.currentAnimation
end

function NPCAnimator:IsPlaying(animName)
	return self.currentAnimation == animName and 
		self.currentTrack and 
		self.currentTrack.IsPlaying
end

-- ==============================================================================
-- CLEANUP
-- ==============================================================================

function NPCAnimator:Destroy()
	self:StopAll()
	self.janitor:Destroy()

	self.animationTracks = {}
	self.animations = {}
	self.currentTrack = nil
	self.currentAnimation = nil
end

-- ==============================================================================
-- UTILIDADES ESTÁTICAS
-- ==============================================================================

-- Cambiar IDs de animaciones globalmente (útil para personalización)
function NPCAnimator.SetAnimationID(animName, animId)
	if ANIMATION_IDS[animName] then
		ANIMATION_IDS[animName] = animId
	end
end

-- Obtener IDs de animaciones actuales
function NPCAnimator.GetAnimationIDs()
	local ids = table.clone(ANIMATION_IDS)
	return ids
end

return NPCAnimator