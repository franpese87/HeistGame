--[[
	ProceduralRotation - Rotación procedural de Motor6Ds

	Gestiona la rotación de cabeza (Neck) y torso (Waist/RootJoint) via C0.
	Rig-agnostic: recibe Motor6Ds por config, funciona con R6 y R15.
	Usado por el AI para orientar el cono de visión del NPC.

	IMPORTANTE: Este módulo modifica C0 de los Motor6Ds. Las AnimationTracks
	modifican Transform. Ambos se componen multiplicativamente:
	  Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
	Esto permite que micro-animaciones preconstruidas (inclinación, sacudida)
	coexistan con la rotación procedural sin conflicto.

	Usa Janitor para gestión automática de tweens.
]]

local TweenService = game:GetService("TweenService")

local ProceduralRotation = {}
ProceduralRotation.__index = ProceduralRotation

function ProceduralRotation.new(config)
	local self = setmetatable({}, ProceduralRotation)

	config = config or {}

	self.neck = config.neck
	self.rootJoint = config.rootJoint
	self.janitor = config.janitor

	-- Guardar CFrames originales para reset
	self.neckOriginalC0 = self.neck and self.neck.C0
	self.rootJointOriginalC0 = self.rootJoint and self.rootJoint.C0

	-- Debug: verificar que se encontraron los Motor6Ds
	local debugName = config.debugName or "?"
	if not self.neck then
		warn("[ProceduralRotation] " .. debugName .. ": Neck Motor6D no encontrado")
	end
	if not self.rootJoint then
		warn("[ProceduralRotation] " .. debugName .. ": RootJoint Motor6D no encontrado")
	end

	return self
end

-- Rota cabeza y torso con diferentes proporciones usando C0 (tween)
-- Los ratios deben sumar 1.0 para que el ángulo visual final sea correcto
function ProceduralRotation:RotateLayered(angle, ratios, tweenInfo)
	local headAngle = angle * (ratios.head or 0.7)
	local torsoAngle = angle * (ratios.torso or 0.3)

	-- Rotar cabeza (Neck.C0)
	if self.neck and self.neckOriginalC0 then
		local targetC0 = CFrame.Angles(0, math.rad(headAngle), 0) * self.neckOriginalC0
		local neckTween = TweenService:Create(self.neck, tweenInfo, {C0 = targetC0})
		if self.janitor then
			self.janitor:Add(neckTween, "Cancel", "neckTween")
		end
		neckTween:Play()
	end

	-- Rotar torso (RootJoint.C0)
	if self.rootJoint and self.rootJointOriginalC0 then
		local targetC0 = CFrame.Angles(0, math.rad(torsoAngle), 0) * self.rootJointOriginalC0
		local torsoTween = TweenService:Create(self.rootJoint, tweenInfo, {C0 = targetC0})
		if self.janitor then
			self.janitor:Add(torsoTween, "Cancel", "torsoTween")
		end
		torsoTween:Play()
	end
end

-- Restaura las rotaciones de cabeza y torso a sus valores originales (tween)
function ProceduralRotation:ResetRotation(tweenInfo)
	if self.neck and self.neckOriginalC0 then
		local tween = TweenService:Create(self.neck, tweenInfo, {C0 = self.neckOriginalC0})
		tween:Play()
	end
	if self.rootJoint and self.rootJointOriginalC0 then
		local tween = TweenService:Create(self.rootJoint, tweenInfo, {C0 = self.rootJointOriginalC0})
		tween:Play()
	end
end

-- Rotación instantánea de cabeza (sin tween, para head tracking responsive)
function ProceduralRotation:SetHeadRotation(angle)
	if self.neck and self.neckOriginalC0 then
		self.neck.C0 = CFrame.Angles(0, math.rad(angle), 0) * self.neckOriginalC0
	end
end

-- Resetea cabeza a posición original (instantáneo)
function ProceduralRotation:ResetHeadRotation()
	if self.neck and self.neckOriginalC0 then
		self.neck.C0 = self.neckOriginalC0
	end
end

-- Cancela tweens activos de rotación por capas
function ProceduralRotation:CancelTweens()
	if self.janitor then
		self.janitor:Remove("neckTween")
		self.janitor:Remove("torsoTween")
	end
end

function ProceduralRotation:GetOriginalNeckC0()
	return self.neckOriginalC0
end

function ProceduralRotation:GetOriginalRootJointC0()
	return self.rootJointOriginalC0
end

function ProceduralRotation:Destroy()
	self:CancelTweens()
	-- Restaurar C0 originales sin tween
	if self.neck and self.neckOriginalC0 then
		self.neck.C0 = self.neckOriginalC0
	end
	if self.rootJoint and self.rootJointOriginalC0 then
		self.rootJoint.C0 = self.rootJointOriginalC0
	end
	self.neck = nil
	self.rootJoint = nil
end

return ProceduralRotation
