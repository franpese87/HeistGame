--[[
	Sandbox Client - Test de AnimationController sobre el player local

	Permite probar animaciones custom en el personaje del jugador.
	Keybinds:
	  Z = idle
	  X = walk
	  C = run
	  V = stop all

	Ejecutar con: rojo serve sandbox.project.json
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local AnimationController = Animation.Controller
local Registry = Animation.Registry

local player = Players.LocalPlayer
local animController = nil

local function setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")

	-- Limpiar controller anterior si existe
	if animController then
		animController:Destroy()
	end

	-- Detectar rig y usar animaciones apropiadas
	local animIds, animSpeeds = Registry.GetDefaultForRig(character)
	local rigType = Registry.GetRigType(character)
	print("[SandboxClient] Rig detectado: " .. rigType)

	animController = AnimationController.new(humanoid, animIds, {
		speeds = animSpeeds,
	})

	print("[SandboxClient] AnimationController listo. Keybinds: Z=idle, X=walk, C=run, V=stop")
end

-- Setup inicial y reconexión en respawn
if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

-- Keybinds para probar animaciones
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not animController then
		return
	end

	if input.KeyCode == Enum.KeyCode.Z then
		print("[SandboxClient] Playing: idle")
		animController:Play("idle")
	elseif input.KeyCode == Enum.KeyCode.X then
		print("[SandboxClient] Playing: walk")
		animController:Play("walk")
	elseif input.KeyCode == Enum.KeyCode.C then
		print("[SandboxClient] Playing: run")
		animController:Play("run")
	elseif input.KeyCode == Enum.KeyCode.V then
		print("[SandboxClient] Stop all")
		animController:Stop()
	end
end)
