--[[
	AnimationController - Gestión de AnimationTracks

	Carga, reproduce y gestiona AnimationTracks sobre cualquier Humanoid.
	Realm-agnostic: funciona tanto en server (NPCs) como en client (player).

	Las AnimationTracks son puramente cosméticas: no afectan translación,
	rotación procedural ni lógica del AI. Controlan la pose visual del
	personaje (brazos, piernas, postura).

	Usa Janitor para cleanup automático de tracks.
]]

local AnimationController = {}
AnimationController.__index = AnimationController

function AnimationController.new(humanoid, animationIds, options)
	local self = setmetatable({}, AnimationController)

	options = options or {}

	self.humanoid = humanoid
	self.speeds = options.speeds or {}
	self.defaultPriority = options.defaultPriority or Enum.AnimationPriority.Core
	self.looped = options.looped ~= false -- default true

	-- Usar janitor externo si se proporciona, o crear uno propio
	self.ownsJanitor = options.janitor == nil
	self.janitor = options.janitor

	-- Encontrar o crear Animator
	self.animator = humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = humanoid
	end

	-- Cargar todos los tracks
	self.animationTracks = {}

	for animName, animId in pairs(animationIds) do
		local animation = Instance.new("Animation")
		animation.Name = animName
		animation.AnimationId = animId

		local track = self.animator:LoadAnimation(animation)
		track.Looped = self.looped
		track.Priority = self.defaultPriority
		self.animationTracks[animName] = track

		if self.janitor then
			self.janitor:Add(track, "Destroy")
		end
	end

	self.currentAnimation = nil
	self.currentTrack = nil

	return self
end

function AnimationController:Play(animName, fadeTime)
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
	track:AdjustSpeed(self.speeds[animName] or 1.0)

	self.currentAnimation = animName
	self.currentTrack = track
end

function AnimationController:Stop(fadeTime)
	for _, track in pairs(self.animationTracks) do
		track:Stop(fadeTime or 0.1)
	end
	self.currentAnimation = nil
	self.currentTrack = nil
end

function AnimationController:SetSpeed(speed)
	if self.currentTrack then
		self.currentTrack:AdjustSpeed(speed)
	end
end

function AnimationController:GetCurrentAnimation()
	return self.currentAnimation
end

function AnimationController:GetTrack(animName)
	return self.animationTracks[animName]
end

function AnimationController:Destroy()
	-- Si no hay janitor externo, limpiar tracks manualmente
	if not self.janitor then
		for _, track in pairs(self.animationTracks) do
			track:Stop(0)
			track:Destroy()
		end
	end

	self.animationTracks = {}
	self.currentTrack = nil
	self.currentAnimation = nil
end

return AnimationController
