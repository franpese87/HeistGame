--[[
	Sandbox Server - Test de AnimationController y ProceduralRotation en NPC dummy

	Crea un NPC R6 programáticamente y ejercita los módulos de animación.
	Ejecutar con: rojo serve sandbox.project.json
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local AnimationController = Animation.Controller
local ProceduralRotation = Animation.ProceduralRotation
local Registry = Animation.Registry

-- ==============================================================================
-- CREAR NPC DUMMY R6
-- ==============================================================================

local function createR6Dummy(position)
	local model = Instance.new("Model")
	model.Name = "AnimationDummy"

	-- HumanoidRootPart
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Transparency = 1
	rootPart.Anchored = false
	rootPart.CanCollide = false
	rootPart.CFrame = CFrame.new(position)
	rootPart.Parent = model

	-- Torso
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.BrickColor = BrickColor.new("Bright blue")
	torso.Anchored = false
	torso.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.BrickColor = BrickColor.new("Bright yellow")
	head.Anchored = false
	head.Parent = model

	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head

	-- Arms
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1, 2, 1)
	leftArm.BrickColor = BrickColor.new("Bright yellow")
	leftArm.Anchored = false
	leftArm.Parent = model

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1, 2, 1)
	rightArm.BrickColor = BrickColor.new("Bright yellow")
	rightArm.Anchored = false
	rightArm.Parent = model

	-- Legs
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1, 2, 1)
	leftLeg.BrickColor = BrickColor.new("Br. yellowish green")
	leftLeg.Anchored = false
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1, 2, 1)
	rightLeg.BrickColor = BrickColor.new("Br. yellowish green")
	rightLeg.Anchored = false
	rightLeg.Parent = model

	-- Motor6Ds
	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = rootPart
	rootJoint.Part1 = torso
	rootJoint.C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	rootJoint.C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	rootJoint.Parent = rootPart

	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = torso
	neck.Part1 = head
	neck.C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	neck.C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	neck.Parent = torso

	local leftShoulder = Instance.new("Motor6D")
	leftShoulder.Name = "Left Shoulder"
	leftShoulder.Part0 = torso
	leftShoulder.Part1 = leftArm
	leftShoulder.C0 = CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
	leftShoulder.C1 = CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
	leftShoulder.Parent = torso

	local rightShoulder = Instance.new("Motor6D")
	rightShoulder.Name = "Right Shoulder"
	rightShoulder.Part0 = torso
	rightShoulder.Part1 = rightArm
	rightShoulder.C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0)
	rightShoulder.C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0)
	rightShoulder.Parent = torso

	local leftHip = Instance.new("Motor6D")
	leftHip.Name = "Left Hip"
	leftHip.Part0 = torso
	leftHip.Part1 = leftLeg
	leftHip.C0 = CFrame.new(-1, -1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
	leftHip.C1 = CFrame.new(-0.5, 1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
	leftHip.Parent = torso

	local rightHip = Instance.new("Motor6D")
	rightHip.Name = "Right Hip"
	rightHip.Part0 = torso
	rightHip.Part1 = rightLeg
	rightHip.C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0)
	rightHip.C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0)
	rightHip.Parent = torso

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = rootPart
	model.Parent = workspace

	return model, humanoid
end

-- ==============================================================================
-- TEST SEQUENCE
-- ==============================================================================

print("=== Animation Sandbox: Iniciando tests ===")

local model, humanoid = createR6Dummy(Vector3.new(0, 5, 0))
print("[Sandbox] NPC dummy creado")

-- Test 1: AnimationController
print("\n--- Test 1: AnimationController ---")
local animController = AnimationController.new(humanoid, Registry.R6_DEFAULT, {
	speeds = Registry.R6_DEFAULT_SPEEDS,
})

task.wait(1)
print("[Test 1] Reproduciendo idle...")
animController:Play("idle")
task.wait(2)

print("[Test 1] Crossfade a walk...")
animController:Play("walk")
task.wait(2)

print("[Test 1] Crossfade a run (1.5x speed)...")
animController:Play("run")
task.wait(2)

print("[Test 1] Stop...")
animController:Stop()
task.wait(1)

print("[Test 1] AnimationController OK")

-- Test 2: ProceduralRotation
print("\n--- Test 2: ProceduralRotation ---")
local torso = model:FindFirstChild("Torso")
local procRotation = ProceduralRotation.new({
	neck = torso and torso:FindFirstChild("Neck"),
	rootJoint = model.HumanoidRootPart:FindFirstChild("RootJoint"),
	debugName = "AnimationDummy",
})

-- Reproducir idle para que se vea la rotación
animController:Play("idle")
task.wait(1)

local testTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

print("[Test 2] RotateLayered +45° (head 70%, torso 30%)...")
procRotation:RotateLayered(45, {head = 0.7, torso = 0.3}, testTweenInfo)
task.wait(1.5)

print("[Test 2] RotateLayered -45°...")
procRotation:RotateLayered(-45, {head = 0.7, torso = 0.3}, testTweenInfo)
task.wait(1.5)

print("[Test 2] ResetRotation...")
procRotation:ResetRotation(testTweenInfo)
task.wait(1)

print("[Test 2] SetHeadRotation sweep...")
for angle = -90, 90, 10 do
	procRotation:SetHeadRotation(angle)
	task.wait(0.1)
end
procRotation:ResetHeadRotation()
task.wait(0.5)

print("[Test 2] ProceduralRotation OK")

-- Test 3: Blending (AnimationTrack + ProceduralRotation simultáneo)
print("\n--- Test 3: Blending AnimationTrack + ProceduralRotation ---")
animController:Play("walk")
task.wait(0.5)

print("[Test 3] Walk + head rotation sweep...")
for angle = -60, 60, 5 do
	procRotation:SetHeadRotation(angle)
	task.wait(0.05)
end
procRotation:ResetHeadRotation()
task.wait(1)

print("[Test 3] Blending OK")

-- Cleanup
animController:Destroy()
procRotation:Destroy()

print("\n=== Animation Sandbox: Todos los tests completados ===")
