--[[
	TaserTool - Arma taser para el jugador

	Crea un Tool "Taser" en el Backpack del jugador.
	Al activar: envía RemoteEvent al servidor para disparar.
	Muestra cooldown visual en pantalla.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Constantes
local COOLDOWN = 4  -- Debe coincidir con TaserConfig.cooldown (visual local)
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
-- TOOL SETUP
-- ==============================================================================

local function setupTaser()
	local backpack = player:WaitForChild("Backpack")
	if backpack:FindFirstChild("Taser") then return end

	-- Esperar al evento del servidor
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

	-- Crear Tool
	local tool = Instance.new("Tool")
	tool.Name = "Taser"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Parent = backpack

	-- Crear UI de cooldown
	local cooldownLabel = createCooldownUI()
	local cooldownConnection = nil

	-- Activación
	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastFireTime < COOLDOWN then return end

		local character = player.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		lastFireTime = now
		taserEvent:FireServer()

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
				if cooldownConnection then
					cooldownConnection:Disconnect()
					cooldownConnection = nil
				end
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

player.CharacterAdded:Connect(function()
	lastFireTime = 0  -- Reset cooldown al respawnear
	setupTaser()
end)

if player.Character then
	task.defer(setupTaser)
end
