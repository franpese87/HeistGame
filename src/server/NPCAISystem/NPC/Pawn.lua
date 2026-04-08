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

local DebugConfig = require(script.Parent.Parent.Parent.Config.DebugConfig)
local AnimationRegistry = require(ReplicatedStorage.Shared.Animation.AnimationRegistry)
local Janitor = require(ReplicatedStorage.Packages.janitor)

local Pawn = {}
Pawn.__index = Pawn

-- ==============================================================================
-- CONFIGURACIÓN DE ESTADOS VISUALES
-- ==============================================================================

local STATE_VISUALS = {
	["Patrolling"] = {emoji = "🚶", text = "PATROLLING", color = Color3.fromRGB(0, 255, 0)},
	["Observing"] = {emoji = "👁️", text = "OBSERVING", color = Color3.fromRGB(100, 150, 255)},
	["Chasing"] = {emoji = "🏃", text = "CHASING", color = Color3.fromRGB(255, 0, 0)},
	["Attacking"] = {emoji = "⚔️", text = "ATTACKING", color = Color3.fromRGB(255, 100, 0)},
	["Investigating"] = {emoji = "❓", text = "INVESTIGATING", color = Color3.fromRGB(255, 165, 0)},
	["Returning"] = {emoji = "🔄", text = "RETURNING", color = Color3.fromRGB(255, 255, 0)},
	["Alerted"] = {emoji = "❗", text = "ALERTED", color = Color3.fromRGB(255, 255, 255)},
	["Stunned"] = {emoji = "💫", text = "STUNNED", color = Color3.fromRGB(180, 80, 255)},
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

	-- Referencias a Motor6Ds para rotación por capas (R15)
	local head = npcInstance:FindFirstChild("Head")
	self.neck = head and head:FindFirstChild("Neck")
	local upperTorso = npcInstance:FindFirstChild("UpperTorso")
	self.waist = upperTorso and upperTorso:FindFirstChild("Waist")

	-- Guardar CFrames originales para reset
	self.neckOriginalC0 = self.neck and self.neck.C0
	self.waistOriginalC0 = self.waist and self.waist.C0

	-- Debug: verificar que se encontraron los Motor6Ds
	if not self.neck then
		warn("[Pawn] " .. npcInstance.Name .. ": Neck Motor6D no encontrado (R15: Head.Neck)")
	end
	if not self.waist then
		warn("[Pawn] " .. npcInstance.Name .. ": Waist Motor6D no encontrado (R15: UpperTorso.Waist)")
	end

	-- Configuración de velocidades
	config = config or {}
	self.patrolSpeed = config.patrolSpeed or 16
	self.chaseSpeed = config.chaseSpeed or 24
	self.weaponType = config.weaponType or "melee"

	-- Inicializar sistema de animaciones
	self:_InitializeAnimations()

	-- Sistema de indicadores de estado (controlado por DebugConfig)
	self.showStateIndicator = DebugConfig.visuals.showStateIndicator or false
	self.stateIndicatorOffset = config.stateIndicatorOffset or 4
	self.stateIndicator = nil

	if self.showStateIndicator then
		self:_CreateStateIndicator()
	end

	return self
end

-- ==============================================================================
-- ANIMACIONES (R15 via AnimationRegistry)
-- ==============================================================================

function Pawn:_InitializeAnimations()
	self.animator = self.humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = self.humanoid
	end

	local animIds = AnimationRegistry.R15_DEFAULT
	self.animSpeeds = AnimationRegistry.R15_DEFAULT_SPEEDS

	self.animations = {}
	self.animationTracks = {}

	for animName, animId in pairs(animIds) do
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

	-- Track de disparo (solo NPCs taser, solo si hay ID configurado)
	if self.weaponType == "taser" then
		local TaserConfig = require(script.Parent.Parent.Parent.Config.TaserConfig)
		local shootId = TaserConfig.shootAnimationId
		if shootId and shootId ~= "" then
			local shootAnim = Instance.new("Animation")
			shootAnim.Name = "shoot"
			shootAnim.AnimationId = shootId
			self.animations["shoot"] = shootAnim

			local shootTrack = self.animator:LoadAnimation(shootAnim)
			shootTrack.Looped = false
			shootTrack.Priority = Enum.AnimationPriority.Action
			self.animationTracks["shoot"] = shootTrack
			self.janitor:Add(shootTrack, "Destroy")
		end
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
	track:AdjustSpeed(self.animSpeeds[animName] or 1.0)

	self.currentAnimation = animName
	self.currentTrack = track
end

-- Reproduce una animación non-looped y retoma la animación previa al terminar.
-- Si la animación es interrumpida externamente (cambio de estado), no retoma.
function Pawn:PlayAnimationOnce(animName, fadeTime)
	if not self.animationTracks[animName] then return end
	fadeTime = fadeTime or 0.1

	local track = self.animationTracks[animName]
	local previousAnimation = self.currentAnimation or "idle"

	if self.currentTrack then
		self.currentTrack:Stop(fadeTime)
	end

	self.currentAnimation = animName
	self.currentTrack = track
	track:Play(fadeTime)

	track.Stopped:Once(function()
		if self.currentAnimation == animName then
			self.currentAnimation = nil
			self.currentTrack = nil
			self:PlayAnimation(previousAnimation, fadeTime)
		end
	end)
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

	-- Calcular el camino de rotación más corto
	local currentCFrame = self.rootPart.CFrame
	local currentPos = currentCFrame.Position

	-- Extraer ángulos Y (rotación horizontal)
	local _, currentAngleY, _ = currentCFrame:ToOrientation()
	local _, targetAngleY, _ = targetCFrame:ToOrientation()

	-- Calcular diferencia angular y normalizarla a [-π, π]
	local angleDiff = targetAngleY - currentAngleY

	-- Normalizar para tomar el camino más corto
	if angleDiff > math.pi then
		angleDiff = angleDiff - 2 * math.pi
	elseif angleDiff < -math.pi then
		angleDiff = angleDiff + 2 * math.pi
	end

	-- Crear CFrame objetivo usando el camino más corto
	local shortestRotationCFrame = CFrame.new(currentPos) * CFrame.Angles(0, currentAngleY + angleDiff, 0)

	local tween = TweenService:Create(self.rootPart, tweenInfo, {CFrame = shortestRotationCFrame})
	self.janitor:Add(tween, "Cancel", "rotationTween")
	tween:Play()

	return tween
end

function Pawn:CancelRotationTween()
	self.janitor:Remove("rotationTween")
end

-- ==============================================================================
-- ROTACIÓN POR CAPAS (Observación realista - solo cabeza y torso)
-- ==============================================================================

-- Rota cabeza y torso con diferentes proporciones usando C0
-- Los ratios deben sumar 1.0 para que el ángulo visual final sea correcto
function Pawn:RotateLayered(angle, ratios, tweenInfo)
	local headAngle = angle * (ratios.head or 0.7)
	local torsoAngle = angle * (ratios.torso or 0.3)

	-- Rotar cabeza (Neck.C0) — R15: Head.Neck
	if self.neck and self.neckOriginalC0 then
		local targetC0 = CFrame.Angles(0, math.rad(headAngle), 0) * self.neckOriginalC0
		local neckTween = TweenService:Create(self.neck, tweenInfo, {C0 = targetC0})
		self.janitor:Add(neckTween, "Cancel", "neckTween")
		neckTween:Play()
	end

	-- Rotar torso (Waist.C0) — R15: UpperTorso.Waist
	if self.waist and self.waistOriginalC0 then
		local targetC0 = CFrame.Angles(0, math.rad(torsoAngle), 0) * self.waistOriginalC0
		local waistTween = TweenService:Create(self.waist, tweenInfo, {C0 = targetC0})
		self.janitor:Add(waistTween, "Cancel", "waistTween")
		waistTween:Play()
	end
end

-- Restaura las rotaciones de cabeza y torso a sus valores originales
function Pawn:ResetLayeredRotation(tweenInfo)
	if self.neck and self.neckOriginalC0 then
		local tween = TweenService:Create(self.neck, tweenInfo, {C0 = self.neckOriginalC0})
		tween:Play()
	end
	if self.waist and self.waistOriginalC0 then
		local tween = TweenService:Create(self.waist, tweenInfo, {C0 = self.waistOriginalC0})
		tween:Play()
	end
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
-- INDICADOR DE ALERTA ("!" animado sobre la cabeza)
-- ==============================================================================

function Pawn:ShowAlertIndicator()
	self:ClearAlertIndicator()

	local head = self.instance:FindFirstChild("Head")
	if not head then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AlertIndicator"
	billboard.Size = UDim2.fromScale(2, 2)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "ExclamationMark"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextColor3 = Color3.fromRGB(255, 50, 50)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextTransparency = 1
	label.Parent = billboard

	self.alertIndicator = billboard

	-- Animacion: sube + fadein
	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local positionTween = TweenService:Create(billboard, tweenInfo, {StudsOffset = Vector3.new(0, 2, 0)})
	local fadeinTween = TweenService:Create(label, tweenInfo, {TextTransparency = 0})
	positionTween:Play()
	fadeinTween:Play()
end

function Pawn:ClearAlertIndicator()
	if not self.alertIndicator then return end

	local label = self.alertIndicator:FindFirstChild("ExclamationMark")
	if label then
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local positionTween = TweenService:Create(self.alertIndicator, tweenInfo, {StudsOffset = Vector3.new(0, 2.5, 0)})
		local fadeoutTween = TweenService:Create(label, tweenInfo, {TextTransparency = 1})
		positionTween:Play()
		fadeoutTween:Play()

		local indicator = self.alertIndicator
		fadeoutTween.Completed:Connect(function()
			if indicator and indicator.Parent then
				indicator:Destroy()
			end
		end)
	else
		self.alertIndicator:Destroy()
	end

	self.alertIndicator = nil
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
