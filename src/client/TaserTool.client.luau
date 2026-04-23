--[[
	TaserTool - Arma taser para el jugador

	Detecta el Tool "Taser" en Backpack/Character (StarterPack lo distribuye)
	y cablea Activated → TaserFire:FireServer().
	Muestra cooldown visual en pantalla.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TaserConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TaserConfig"))

local player = Players.LocalPlayer

local COOLDOWN = TaserConfig.cooldown or 4
local EVENT_TIMEOUT = 10

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
-- TOOL WIRING
-- ==============================================================================

local wiredTools = setmetatable({}, {__mode = "k"})

local FIRE_SOUND_NAME = "TaserFireSound"

-- Mutea todos los Sounds descendientes del Tool para que el cooldown
-- sea la fuente única de feedback de audio. El asset Roblox Taser trae
-- Sounds en Activated que disparan aunque el cooldown nuestro bloquee.
-- Excluye nuestro propio fireSound por nombre.
local function muteToolSounds(tool)
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("Sound") and d.Name ~= FIRE_SOUND_NAME then
			d.Volume = 0
		end
	end
	tool.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") and d.Name ~= FIRE_SOUND_NAME then
			d.Volume = 0
		end
	end)
end

local function wireTool(tool, taserEvent, cooldownLabel)
	if wiredTools[tool] then return end
	wiredTools[tool] = true

	muteToolSounds(tool)

	-- Handle es el Part que porta el sonido posicional 3D del asset.
	-- Parenteamos nuestro fireSound ahí para emitir desde la mano del player.
	local handle = tool:FindFirstChild("Handle")
	local fireSound = Instance.new("Sound")
	fireSound.Name = FIRE_SOUND_NAME
	fireSound.SoundId = "rbxassetid://82273261"  -- Taser zap SFX
	fireSound.Volume = 1
	fireSound.Parent = handle or tool

	local cooldownConnection = nil

	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastFireTime < COOLDOWN then return end

		local character = player.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		lastFireTime = now
		taserEvent:FireServer()
		fireSound:Play()

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
-- SETUP
-- ==============================================================================

local function resolveEvent()
	local eventFolder = ReplicatedStorage:WaitForChild("Events", EVENT_TIMEOUT)
	if not eventFolder then
		warn("[TaserTool] No se encontró la carpeta Events")
		return nil
	end
	local taserEvent = eventFolder:WaitForChild("TaserFire", EVENT_TIMEOUT)
	if not taserEvent then
		warn("[TaserTool] No se encontró TaserFire RemoteEvent")
		return nil
	end
	return taserEvent
end

local cooldownLabel = createCooldownUI()
local taserEvent = resolveEvent()
if not taserEvent then return end

local function watchContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child.Name == "Taser" then
			wireTool(child, taserEvent, cooldownLabel)
		end
	end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Taser" then
			wireTool(child, taserEvent, cooldownLabel)
		end
	end)
end

local function onCharacter(character)
	lastFireTime = 0
	local backpack = player:WaitForChild("Backpack", EVENT_TIMEOUT)
	if backpack then watchContainer(backpack) end
	watchContainer(character)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.defer(onCharacter, player.Character)
end
