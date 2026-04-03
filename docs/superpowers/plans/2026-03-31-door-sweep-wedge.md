# Door Sweep Wedge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the instantaneous door stun check with a continuous swept-wedge detection system that detects NPCs and players inside the door's arc during the opening animation.

**Architecture:** The sweep detection runs inside the existing `animateDoor` Heartbeat callback in DoorService. Each frame, a mathematical sector-containment check determines if entities are inside the growing wedge. Debug visuals use two cylinder-line Parts (same pattern as VisionSensor cone boundaries). Controller.lua STUNNED state remains unchanged.

**Tech Stack:** Luau, Roblox Services (TweenService, RunService, Players, CollectionService)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `src/server/Services/DoorService.lua` | Modify | Remove `_CheckDoorStun`, add sweep helpers, integrate sweep into `animateDoor` and `DoorService.Open` |
| `src/server/Config/DebugConfig.lua` | Modify | Add `showDoorSweep` flag |

---

### Task 1: Add `showDoorSweep` flag to DebugConfig

**Files:**
- Modify: `src/server/Config/DebugConfig.lua:19-29`

- [ ] **Step 1: Add the flag**

In `src/server/Config/DebugConfig.lua`, add `showDoorSweep` inside the `visuals` table, after the existing entries:

```lua
	visuals = {
		-- Sistema de vision (VisionSensor)
		-- Pipeline: Distancia -> Cono -> Line of Sight
		showVisionDebug = true,

		-- Otros sistemas
		showNoiseSpheres = true,
		showNPCPaths = true,
		showLastSeenPosition = true,
		showStateIndicator = true,

		-- Puertas
		showDoorSweep = false,
	},
```

- [ ] **Step 2: Commit**

```bash
git add src/server/Config/DebugConfig.lua
git commit -m "feat(debug): add showDoorSweep flag to DebugConfig"
```

---

### Task 2: Add sweep debug visual helpers to DoorService

**Files:**
- Modify: `src/server/Services/DoorService.lua:1-40` (top of file — add requires, helpers)

- [ ] **Step 1: Add `Players` service require and `DebugConfig` require**

At the top of `DoorService.lua`, after the existing `require` lines (line 27), add:

```lua
local Players = game:GetService("Players")
local DebugConfig = require(script.Parent.Parent.Config.DebugConfig)
```

- [ ] **Step 2: Add debug helper functions**

After the `DOOR_STUN_RANGE` constant (line 38), add the debug visual helpers. These follow the exact same pattern as `VisionSensor.lua` lines 10-52:

```lua
-- ==============================================================================
-- DEBUG VISUAL HELPERS (patrón VisionSensor)
-- ==============================================================================

local function getDebugFolder()
	local folder = workspace:FindFirstChild("_DoorSweepDebug")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_DoorSweepDebug"
		folder.Parent = workspace
	end
	return folder
end

local function createDebugLine(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 200, 0)
	part.Transparency = 0.3
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = getDebugFolder()
	return part
end

local function rotateVectorXZ(vec, angle)
	local cos = math.cos(angle)
	local sin = math.sin(angle)
	return Vector3.new(
		vec.X * cos - vec.Z * sin,
		0,
		vec.X * sin + vec.Z * cos
	).Unit
end

local function positionDebugLine(line, origin, direction, length)
	local endPoint = origin + direction * length
	local midpoint = (origin + endPoint) / 2
	local xAxis = direction
	local yAxis = Vector3.new(0, 1, 0)
	local zAxis = xAxis:Cross(yAxis).Unit
	line.Size = Vector3.new(length, 0.15, 0.15)
	line.CFrame = CFrame.fromMatrix(midpoint, xAxis, yAxis, zAxis)
end
```

- [ ] **Step 3: Commit**

```bash
git add src/server/Services/DoorService.lua
git commit -m "feat(door): add sweep debug visual helper functions"
```

---

### Task 3: Add sector containment check function

**Files:**
- Modify: `src/server/Services/DoorService.lua` (after debug helpers, before `animateDoor`)

- [ ] **Step 1: Add the `isInsideSector` function**

This function implements the spec's detection math. Add it after the debug helpers block, before the `-- ANIMACIÓN` section:

```lua
-- ==============================================================================
-- DETECCIÓN DE SECTOR CIRCULAR (cuña de barrido)
-- ==============================================================================

-- Verifica si un punto XZ está dentro del sector circular definido por:
--   hingePos: posición de la bisagra (Vector3, se proyecta a XZ)
--   closedDir: dirección de la puerta cerrada en XZ (Vector3 unitario)
--   currentAngleRad: ángulo actual de apertura en radianes (con signo)
--   radius: radio del sector (ancho de la puerta)
local function isInsideSector(point, hingePos, closedDir, currentAngleRad, radius)
	local toPoint = (point - hingePos) * Vector3.new(1, 0, 1)
	local distance = toPoint.Magnitude

	if distance > radius or distance < 0.5 then
		return false
	end

	local pointDir = toPoint.Unit
	-- Ángulo del punto respecto a la dirección cerrada, con signo
	local dot = closedDir:Dot(pointDir)
	local cross = closedDir.X * pointDir.Z - closedDir.Z * pointDir.X
	local pointAngle = math.atan2(cross, dot)

	if currentAngleRad >= 0 then
		return pointAngle >= 0 and pointAngle <= currentAngleRad
	else
		return pointAngle <= 0 and pointAngle >= currentAngleRad
	end
end
```

The `distance < 0.5` guard prevents false positives for entities standing exactly on the hinge pivot.

- [ ] **Step 2: Commit**

```bash
git add src/server/Services/DoorService.lua
git commit -m "feat(door): add isInsideSector function for sweep detection"
```

---

### Task 4: Add `_RunSweepDetection` function

**Files:**
- Modify: `src/server/Services/DoorService.lua` (after `isInsideSector`, before `animateDoor`)

- [ ] **Step 1: Add the sweep detection function**

This function is called every frame from the Heartbeat callback during door opening. It checks all NPCs and players against the sector:

```lua
-- Ejecuta la detección de barrido para un frame de animación.
-- sweepData contiene: hingePos, closedDir, radius, openAngleRad, alreadyHit, openerInstance
local function runSweepDetection(sweepData, currentAngleRad)
	local hingePos = sweepData.hingePos
	local closedDir = sweepData.closedDir
	local radius = sweepData.radius
	local alreadyHit = sweepData.alreadyHit
	local openerInstance = sweepData.openerInstance

	-- NPCs
	if registry then
		local npcsInRange = registry:FindNPCsInRadius(hingePos, radius)
		for _, entry in ipairs(npcsInRange) do
			local controller = entry.npcData.controller
			local npcInstance = controller.pawn:GetInstance()
			if npcInstance ~= openerInstance and not alreadyHit[npcInstance] then
				if controller.isActive and controller.currentState ~= "Stunned" then
					local npcPos = controller.pawn:GetPosition()
					if isInsideSector(npcPos, hingePos, closedDir, currentAngleRad, radius) then
						alreadyHit[npcInstance] = true
						local knockbackDir = ((npcPos - hingePos) * Vector3.new(1, 0, 1)).Unit
						controller:ApplyStun(knockbackDir)
					end
				end
			end
		end
	end

	-- Players
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character or character == openerInstance then continue end
		if alreadyHit[character] then continue end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		local playerPos = rootPart.Position
		if isInsideSector(playerPos, hingePos, closedDir, currentAngleRad, radius) then
			alreadyHit[character] = true
			-- TODO: Player knockback se implementará en una fase posterior.
			-- Por ahora solo se registra el hit para debug.
		end
	end
end
```

Note: Player knockback/stun is registered but the actual effect is deferred — the spec says "de momento servirá como debug visual y posteriormente haremos que todo personaje que esté dentro de ese area sea empujado". The `alreadyHit` tracking ensures we know *who* was hit.

- [ ] **Step 2: Commit**

```bash
git add src/server/Services/DoorService.lua
git commit -m "feat(door): add runSweepDetection for continuous wedge detection"
```

---

### Task 5: Integrate sweep into `animateDoor` and `DoorService.Open`

**Files:**
- Modify: `src/server/Services/DoorService.lua:157-270` (`animateDoor` function and `DoorService.Open`)

This is the core integration. We modify `animateDoor` to accept sweep data and run detection + debug visuals each frame, and update `DoorService.Open` to build and pass sweep data instead of calling `_CheckDoorStun`.

- [ ] **Step 1: Modify `animateDoor` to accept and process sweep data**

Replace the current `animateDoor` function (lines 157-190) with:

```lua
local function animateDoor(data, targetAngle, easingDirection, sweepData, onComplete)
	-- Desconectar animación anterior si existe
	if data.connection then
		data.connection:Disconnect()
		data.connection = nil
	end

	-- Debug visual: crear líneas de borde del sector
	local debugFixedLine = nil
	local debugMovingLine = nil
	if sweepData and DebugConfig.visuals.showDoorSweep then
		debugFixedLine = createDebugLine("SweepFixed_" .. data.model.Name)
		debugMovingLine = createDebugLine("SweepMoving_" .. data.model.Name)

		-- Posicionar línea fija (dirección de puerta cerrada, no cambia)
		positionDebugLine(debugFixedLine, sweepData.hingePos, sweepData.closedDir, sweepData.radius)
	end

	-- Tween del ángulo (NumberValue)
	local tweenInfo = TweenInfo.new(data.openTime, Enum.EasingStyle.Quad, easingDirection)
	local tween = TweenService:Create(data.angleValue, tweenInfo, {Value = targetAngle})

	-- Actualizar CFrame cada frame basado en el ángulo actual
	data.connection = RunService.Heartbeat:Connect(function()
		data.doorPart.CFrame = calculateDoorCFrame(
			data.closedCFrame,
			data.hingeOffset,
			data.angleValue.Value
		)

		-- Sweep detection + debug visual (solo durante apertura)
		if sweepData then
			local currentAngleRad = math.rad(data.angleValue.Value)
			runSweepDetection(sweepData, currentAngleRad)

			-- Actualizar línea móvil del debug
			if debugMovingLine then
				local movingDir = rotateVectorXZ(sweepData.closedDir, currentAngleRad)
				positionDebugLine(debugMovingLine, sweepData.hingePos, movingDir, sweepData.radius)
			end
		end
	end)

	tween:Play()

	tween.Completed:Connect(function()
		if data.connection then
			data.connection:Disconnect()
			data.connection = nil
		end
		-- Asegurar CFrame final exacto
		data.doorPart.CFrame = calculateDoorCFrame(data.closedCFrame, data.hingeOffset, targetAngle)

		-- Limpiar debug visual del sweep
		if debugFixedLine then
			debugFixedLine:Destroy()
		end
		if debugMovingLine then
			debugMovingLine:Destroy()
		end

		if onComplete then
			onComplete()
		end
	end)
end
```

- [ ] **Step 2: Update `DoorService.Open` to build sweep data**

Replace the stun check call and the `animateDoor` call in `DoorService.Open` (lines 227-270). The full updated function:

```lua
function DoorService.Open(doorModel, openerPosition, openerInstance)
	local data = doors[doorModel]
	if not data or data.isOpen or data.isAnimating then return end

	data.isAnimating = true
	data.isOpen = true
	doorModel:SetAttribute("isOpen", true)

	-- Determinar dirección de apertura según el lado del que abre
	local angle = data.openAngle
	if openerPosition then
		local doorPos = data.closedCFrame.Position
		local doorLook = data.closedCFrame.LookVector
		local toOpener = (openerPosition - doorPos)
		local dot = doorLook:Dot(toOpener)
		if dot > 0 then
			angle = -angle
		end
	end

	-- Construir sweep data para detección continua durante la animación
	local hingePivot = data.closedCFrame * data.hingeOffset
	local hingePos = Vector3.new(hingePivot.Position.X, hingePivot.Position.Y, hingePivot.Position.Z)
	-- Dirección de la puerta cerrada: del hinge hacia el borde libre (eje X local)
	local closedDir = (data.closedCFrame.Position - hingePos) * Vector3.new(1, 0, 1)
	if closedDir.Magnitude < 0.1 then
		closedDir = data.closedCFrame.RightVector * (data.hingeOffset.Position.X < 0 and 1 or -1)
	end
	closedDir = (closedDir * Vector3.new(1, 0, 1)).Unit

	local sweepData = {
		hingePos = hingePos,
		closedDir = closedDir,
		radius = data.doorPart.Size.X,
		openAngleRad = math.rad(angle),
		openerInstance = openerInstance,
		alreadyHit = {},
	}

	-- Actualizar ProximityPrompt
	local prompt = data.doorPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Close"
	end

	animateDoor(data, angle, Enum.EasingDirection.Out, sweepData, function()
		data.isAnimating = false
		data.doorPart.CanCollide = false
		GeometryVersion.Increment()

		if data.autoClose then
			task.delay(data.autoCloseDelay, function()
				if data.isOpen and not data.isAnimating then
					DoorService.Close(doorModel)
				end
			end)
		end
	end)
end
```

- [ ] **Step 3: Update `DoorService.Close` to pass `nil` sweep data**

In `DoorService.Close`, update the `animateDoor` call (line 290) to include the new `nil` sweep parameter:

```lua
	animateDoor(data, 0, Enum.EasingDirection.In, nil, function()
		data.isAnimating = false
		GeometryVersion.Increment()
	end)
```

- [ ] **Step 4: Remove `_CheckDoorStun` and `DOOR_STUN_RANGE`**

Delete the `_CheckDoorStun` function (lines 196-221) and the `DOOR_STUN_RANGE` constant (line 38). These are fully replaced by the sweep system.

- [ ] **Step 5: Commit**

```bash
git add src/server/Services/DoorService.lua
git commit -m "feat(door): integrate continuous sweep wedge detection into animateDoor"
```

---

### Task 6: Verify and test in Studio

- [ ] **Step 1: Build and open in Studio**

```bash
rojo build -o "HeistGame.rbxl"
```

Open Roblox Studio with the built file. Enable debug by setting `showDoorSweep = true` in `DebugConfig.lua` before building.

- [ ] **Step 2: Manual test checklist**

1. Open a door near an NPC — NPC should get stunned when the door arc reaches it (not instantly)
2. Open a door with no NPCs nearby — no errors, no stun
3. Open a door from each side — wedge direction should match door direction
4. With `showDoorSweep = true`: two yellow lines should appear during opening, fixed + moving, then disappear when animation completes
5. With `showDoorSweep = false`: no debug lines appear
6. NPC opening a door should not stun itself
7. Open a door while an NPC is behind it (outside the sweep arc) — NPC should NOT be stunned

- [ ] **Step 3: Set `showDoorSweep` back to `false` and commit final state**

```bash
git add -A
git commit -m "feat(door): complete door sweep wedge system with debug visuals"
```
