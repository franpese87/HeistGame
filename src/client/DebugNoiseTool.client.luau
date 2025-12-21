local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Esperar a que se cargue el personaje
player.CharacterAdded:Connect(function()
	local backpack = player:WaitForChild("Backpack")
	if backpack:FindFirstChild("NoiseMaker") then return end

	-- Crear la Tool
	local tool = Instance.new("Tool")
	tool.Name = "NoiseMaker"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Parent = backpack

	-- Lógica de la Tool
	local mouse = player:GetMouse()
	local eventFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventFolder then return end -- Si no se creó el evento en el server, abortar
	
	local event = eventFolder:WaitForChild("DebugNoiseEvent", 10)

	tool.Activated:Connect(function()
		if mouse.Target and event then
			local pos = mouse.Hit.Position
			event:FireServer(pos)
			
			-- Feedback visual local (punto rojo donde clickeaste)
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.Size = Vector3.new(0.5, 0.5, 0.5)
			p.Position = pos
			p.Color = Color3.fromRGB(255, 0, 0)
			p.Material = Enum.Material.Neon
			p.Transparency = 0.2
			p.Parent = workspace
			game:GetService("Debris"):AddItem(p, 0.5)
		end
	end)
end)