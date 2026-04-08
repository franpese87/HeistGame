--[[
	TaserTool (cliente) - Input, cooldown UI y animación de disparo del jugador

	La Tool es creada y equipada por el servidor.
	Este script detecta la tool en el character y conecta el input.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Constantes
local COOLDOWN = 4          -- Debe coincidir con TaserConfig.cooldown (visual local)
local SHOOT_ANIM_ID = ""    -- Debe coincidir con TaserConfig.shootAnimationId
local EVENT_TIMEOUT = 10

-- Estado
local lastFireTime = 0

-- ==============================================================================
-- COOLDOWN UI
-- ==============================================================================

local function createCooldownUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TaserCooldownUI"
	screenGui.ResetOnSpawn = true

	local label = Instance.new("TextLabel")
	label.Name = "CooldownLabel"
	label.Size = UDim2.fromOffset(120, 30)
	label.Position = UDim2.new(0.5, -60, 0.9, 0)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(100, 180, 255)
	label.TextSize = 16
	label.Font = Enum.Font.SourceSansBold
	label.Text = "TASER READY"
	label.Visible = false
	label.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	screenGui.Parent = player.PlayerGui
	return label
end

-- ==============================================================================
-- ANIMACIÓN LOCAL
-- ==============================================================================

local function playShootAnimation(character)
	if SHOOT_ANIM_ID == "" then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = SHOOT_ANIM_ID
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play()
	track.Stopped:Once(function()
		track:Destroy()
		anim:Destroy()
	end)
end

-- ==============================================================================
-- INPUT SETUP
-- ==============================================================================

local function setupInput(tool, taserEvent, cooldownLabel)
	local cooldownConnection = nil

	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastFireTime < COOLDOWN then return end

		local character = player.Character
		if not character then return end

		lastFireTime = now
		taserEvent:FireServer()
		playShootAnimation(character)

		-- Mostrar cooldown UI
		cooldownLabel.Visible = true
		if cooldownConnection then
			cooldownConnection:Disconnect()
		end

		cooldownConnection = RunService.RenderStepped:Connect(function()
			local remaining = COOLDOWN - (os.clock() - lastFireTime)
			if remaining <= 0 then
				cooldownLabel.Text = "TASER READY"
				cooldownLabel.TextColor3 = Color3.fromRGB(100, 180, 255)
				cooldownLabel.Visible = false
				cooldownConnection:Disconnect()
				cooldownConnection = nil
			else
				cooldownLabel.Text = string.format("COOLDOWN %.1fs", remaining)
				cooldownLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
				cooldownLabel.Visible = true
			end
		end)
	end)
end

-- ==============================================================================
-- INICIALIZACIÓN
-- ==============================================================================

local function initialize(character)
	lastFireTime = 0

	-- Esperar RemoteEvent
	local eventFolder = ReplicatedStorage:WaitForChild("Events", EVENT_TIMEOUT)
	if not eventFolder then
		warn("[TaserTool] No se encontró la carpeta Events")
		return
	end
	local taserEvent = eventFolder:WaitForChild("TaserFire", EVENT_TIMEOUT)
	if not taserEvent then
		warn("[TaserTool] No se encontró TaserFire RemoteEvent")
		return
	end

	-- Esperar la tool creada por el servidor
	local tool = character:WaitForChild("Taser", EVENT_TIMEOUT)
	if not tool then
		warn("[TaserTool] Tool Taser no encontrada en el character")
		return
	end

	local cooldownLabel = createCooldownUI()
	setupInput(tool, taserEvent, cooldownLabel)
end

player.CharacterAdded:Connect(initialize)

if player.Character then
	task.defer(function()
		initialize(player.Character)
	end)
end
