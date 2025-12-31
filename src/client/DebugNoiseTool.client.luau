--[[
	DebugNoiseTool - Herramienta de debug para generar ruido

	Crea una Tool "NoiseMaker" que permite hacer click en el mundo
	para generar ruidos que los NPCs pueden detectar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

-- Constantes
local FEEDBACK_SPHERE_SIZE = 0.5
local FEEDBACK_SPHERE_DURATION = 0.5
local EVENT_TIMEOUT = 10

-- Esperar a que se cargue el personaje
player.CharacterAdded:Connect(function()
	local backpack = player:WaitForChild("Backpack")
	if backpack:FindFirstChild("NoiseMaker") then return end

	-- Esperar al evento del servidor
	local eventFolder = ReplicatedStorage:WaitForChild("Events", EVENT_TIMEOUT)
	if not eventFolder then
		warn("[DebugNoiseTool] No se encontró la carpeta Events")
		return
	end

	local noiseEvent = eventFolder:WaitForChild("DebugNoiseEvent", EVENT_TIMEOUT)
	if not noiseEvent then
		warn("[DebugNoiseTool] No se encontró DebugNoiseEvent")
		return
	end

	-- Crear la Tool
	local tool = Instance.new("Tool")
	tool.Name = "NoiseMaker"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Parent = backpack

	-- Lógica de la Tool
	local mouse = player:GetMouse()

	tool.Activated:Connect(function()
		if not mouse.Target then return end

		local position = mouse.Hit.Position
		noiseEvent:FireServer(position)

		-- Feedback visual local (punto rojo donde clickeaste)
		local feedbackSphere = Instance.new("Part")
		feedbackSphere.Anchored = true
		feedbackSphere.CanCollide = false
		feedbackSphere.CanQuery = false
		feedbackSphere.Size = Vector3.new(FEEDBACK_SPHERE_SIZE, FEEDBACK_SPHERE_SIZE, FEEDBACK_SPHERE_SIZE)
		feedbackSphere.Position = position
		feedbackSphere.Color = Color3.fromRGB(255, 0, 0)
		feedbackSphere.Material = Enum.Material.Neon
		feedbackSphere.Transparency = 0.2
		feedbackSphere.Shape = Enum.PartType.Ball
		feedbackSphere.Parent = workspace
		Debris:AddItem(feedbackSphere, FEEDBACK_SPHERE_DURATION)
	end)
end)

-- También crear la tool si el personaje ya existe
if player.Character then
	task.defer(function()
		player.CharacterAdded:Fire()
	end)
end
