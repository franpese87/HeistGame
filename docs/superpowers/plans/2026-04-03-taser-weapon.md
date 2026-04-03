# Taser Weapon System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an equippable taser weapon that fires a physical projectile to stun NPCs and players, usable by both players (Tool) and configurable NPCs.

**Architecture:** A server-side `ProjectileService` centralizes projectile lifecycle (create, move, collide, stun). Players fire via RemoteEvent from a client Tool; NPCs fire directly from Controller. All authoritative logic is server-side. Config values in `TaserConfig.lua` drive balance.

**Tech Stack:** Luau, Roblox Services (RunService, Players, ReplicatedStorage), existing StunService + Registry + Controller

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `src/server/Config/TaserConfig.lua` | Create | All taser balance values |
| `src/server/Services/ProjectileService.lua` | Create | Projectile lifecycle: create Part, move per frame, raycast collision, apply stun, cleanup |
| `src/client/TaserTool.client.luau` | Create | Player input (Tool.Activated), cooldown UI (ScreenGui), fire RemoteEvent |
| `src/server/init.server.luau` | Modify | Require ProjectileService, create RemoteEvent, connect server handler with validation |
| `src/server/NPCAISystem/NPC/Controller.lua` | Modify | Read weaponType from config, bifurcate ATTACKING + CHASING transitions for taser NPCs |
| `src/server/Config/NPCBaseConfig.lua` | Modify | Add `weaponType` and `taserEngageDistance` defaults |
| `src/server/Config/NPCSpawnList.lua` | Modify | Override `weaponType = "taser"` on specific NPCs |

---

### Task 1: Create TaserConfig

**Files:**
- Create: `src/server/Config/TaserConfig.lua`

- [ ] **Step 1: Create the config file**

```lua
-- Configuración del arma Taser
-- Valores de balance ajustables para proyectil, cooldown y stun

return {
	-- Proyectil
	projectileSpeed = 60,        -- studs/s
	projectileRadius = 0.3,      -- radio de la Part (hitbox)
	maxRange = 80,               -- studs antes de autodestruirse

	-- Balance
	cooldown = 4,                -- segundos entre disparos
	stunDuration = 3,            -- segundos de stun al impactar

	-- Visual
	projectileColor = Color3.fromRGB(100, 180, 255),  -- azul eléctrico
	projectileYOffset = 0,       -- offset Y desde RootPart del shooter (0 = altura de cadera)
}
```

- [ ] **Step 2: Commit**

```bash
git add src/server/Config/TaserConfig.lua
git commit -m "feat(taser): add TaserConfig with balance values"
```

---

### Task 2: Create ProjectileService

**Files:**
- Create: `src/server/Services/ProjectileService.lua`

- [ ] **Step 1: Create ProjectileService with Init and Fire**

```lua
--[[
	ProjectileService - Gestión centralizada de proyectiles

	Crea, mueve y gestiona la colisión de proyectiles tipo taser.
	Usado tanto por players (via RemoteEvent) como por NPCs (via Controller).
	Toda la lógica es server-side (autoritativa).
]]

local RunService = game:GetService("RunService")

local StunService = require(script.Parent.StunService)

local ProjectileService = {}

-- Proyectiles activos: { { part, direction, speed, maxRange, distanceTraveled, raycastParams, stunDuration, ownerInstance } }
local activeProjectiles = {}

-- Referencia al Registry (se asigna en Init)
local registry = nil

-- Busca el Model Character ancestro de una instancia golpeada
local function findCharacterFromHit(hitInstance)
	local current = hitInstance
	while current do
		if current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Aplica stun al character impactado (NPC o Player)
local function applyStunToCharacter(character, stunDuration, ownerInstance)
	if character == ownerInstance then return end

	-- NPC
	if registry then
		local npcData = registry:GetNPCByInstance(character)
		if npcData and npcData.controller.isActive and npcData.controller.currentState ~= "Stunned" then
			npcData.controller:ApplyStun()
			return
		end
	end

	-- Player
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		StunService.Apply(humanoid, stunDuration)
	end
end

function ProjectileService.Init()
	local Registry = require(script.Parent.Parent.NPCAISystem.Registry)
	registry = Registry.GetInstance()

	RunService.Heartbeat:Connect(function(dt)
		ProjectileService._Update(dt)
	end)
end

function ProjectileService.Fire(origin, direction, config, ownerInstance)
	-- Normalizar dirección a XZ
	local dir = (direction * Vector3.new(1, 0, 1))
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit

	-- Posición inicial con offset Y
	local spawnPos = origin + Vector3.new(0, config.projectileYOffset or 0, 0)

	-- Crear Part del proyectil
	local diameter = (config.projectileRadius or 0.3) * 2
	local part = Instance.new("Part")
	part.Name = "TaserProjectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Position = spawnPos
	part.Color = config.projectileColor or Color3.fromRGB(100, 180, 255)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = workspace

	-- RaycastParams: excluir al shooter
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {ownerInstance}

	table.insert(activeProjectiles, {
		part = part,
		direction = dir,
		speed = config.projectileSpeed or 60,
		maxRange = config.maxRange or 80,
		stunDuration = config.stunDuration or 3,
		distanceTraveled = 0,
		raycastParams = rayParams,
		ownerInstance = ownerInstance,
	})
end

function ProjectileService._Update(dt)
	local i = 1
	while i <= #activeProjectiles do
		local projectile = activeProjectiles[i]
		local part = projectile.part

		-- Si la Part fue destruida externamente, limpiar
		if not part.Parent then
			table.remove(activeProjectiles, i)
			continue
		end

		local currentPos = part.Position
		local moveDistance = projectile.speed * dt
		local moveVector = projectile.direction * moveDistance
		local newPos = currentPos + moveVector

		-- Raycast del tramo recorrido este frame (detecta colisión con paredes y personajes)
		local rayResult = workspace:Raycast(currentPos, moveVector, projectile.raycastParams)

		if rayResult then
			-- Algo fue golpeado
			local character = findCharacterFromHit(rayResult.Instance)
			if character then
				applyStunToCharacter(character, projectile.stunDuration, projectile.ownerInstance)
			end
			-- Destruir proyectil (tanto si golpeó personaje como pared)
			part:Destroy()
			table.remove(activeProjectiles, i)
			continue
		end

		-- Sin colisión: mover
		projectile.distanceTraveled = projectile.distanceTraveled + moveDistance
		if projectile.distanceTraveled >= projectile.maxRange then
			part:Destroy()
			table.remove(activeProjectiles, i)
			continue
		end

		part.Position = newPos
		i = i + 1
	end
end

return ProjectileService
```

- [ ] **Step 2: Commit**

```bash
git add src/server/Services/ProjectileService.lua
git commit -m "feat(taser): add ProjectileService with projectile lifecycle and stun"
```

---

### Task 3: Create TaserTool client script

**Files:**
- Create: `src/client/TaserTool.client.luau`

- [ ] **Step 1: Create the client tool script**

```lua
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
```

- [ ] **Step 2: Commit**

```bash
git add src/client/TaserTool.client.luau
git commit -m "feat(taser): add TaserTool client with input and cooldown UI"
```

---

### Task 4: Wire up server handler in init.server.luau

**Files:**
- Modify: `src/server/init.server.luau`

- [ ] **Step 1: Add ProjectileService require and TaserConfig require**

After the existing requires at the top of the file (line 5), add:

```lua
local ProjectileService = require(script.Services.ProjectileService)
local TaserConfig = require(script.Config.TaserConfig)
```

- [ ] **Step 2: Add ProjectileService init and RemoteEvent setup**

After `DoorService.Init()` (line 16), add:

```lua
ProjectileService.Init()

-- ==============================================================================
-- 0.5 REMOTE EVENTS
-- ==============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local taserEvent = Instance.new("RemoteEvent")
taserEvent.Name = "TaserFire"
taserEvent.Parent = eventsFolder

-- Cooldown tracking por player (server-side autoritativo)
local lastFireTimes = {}

taserEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()

	-- Validar cooldown server-side
	if lastFireTimes[player] and now - lastFireTimes[player] < TaserConfig.cooldown then
		return
	end

	-- Validar que el character existe
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Usar posición y dirección del SERVER (anti-spoofing)
	local origin = rootPart.Position
	local direction = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit

	lastFireTimes[player] = now
	ProjectileService.Fire(origin, direction, TaserConfig, character)
end)

-- Limpiar tracking cuando el player sale
Players.PlayerRemoving:Connect(function(player)
	lastFireTimes[player] = nil
end)
```

- [ ] **Step 3: Commit**

```bash
git add src/server/init.server.luau
git commit -m "feat(taser): wire ProjectileService and RemoteEvent handler in server init"
```

---

### Task 5: Add weapon config defaults to NPCBaseConfig

**Files:**
- Modify: `src/server/Config/NPCBaseConfig.lua:70-75`

- [ ] **Step 1: Add weaponType and taserEngageDistance**

Before the `stateIndicatorOffset` line (line 74), add the new weapon config:

```lua
	-- Tipo de arma
	weaponType = "melee",             -- "melee" o "taser" (configurable por NPC)
	taserEngageDistance = 20,          -- [DIFICULTAD] Distancia a la que el NPC taser empieza a disparar (studs)
```

- [ ] **Step 2: Commit**

```bash
git add src/server/Config/NPCBaseConfig.lua
git commit -m "feat(taser): add weaponType and taserEngageDistance to NPCBaseConfig"
```

---

### Task 6: Configure a taser NPC in NPCSpawnList

**Files:**
- Modify: `src/server/Config/NPCSpawnList.lua`

- [ ] **Step 1: Add weaponType override to one NPC**

Change Guard_2 to use taser (or add a new NPC entry). Replace the Guard_2 entry:

```lua
	{
		name = "Guard_2",
		patrolRoute = { "Node_0_405", "Node_0_415" },
		weaponType = "taser",
	},
```

- [ ] **Step 2: Commit**

```bash
git add src/server/Config/NPCSpawnList.lua
git commit -m "feat(taser): configure Guard_2 as taser NPC in spawn list"
```

---

### Task 7: Integrate taser firing into NPC Controller

**Files:**
- Modify: `src/server/NPCAISystem/NPC/Controller.lua`

This task modifies the Controller to:
1. Read `weaponType` and `taserEngageDistance` from config
2. Require `ProjectileService` and `TaserConfig`
3. Bifurcate `UpdateAttacking` by weapon type
4. Adjust CHASING → ATTACKING transition distance for taser NPCs

- [ ] **Step 1: Add requires**

After the existing `StunService` require (line 20), add:

```lua
local ProjectileService = require(script.Parent.Parent.Parent.Services.ProjectileService)
local TaserConfig = require(script.Parent.Parent.Parent.Config.TaserConfig)
```

- [ ] **Step 2: Read weapon config in constructor**

After the stun config line `self.stunDuration = config.stunDuration or 3` (line 102), add:

```lua
	-- Arma
	self.weaponType = config.weaponType or "melee"
	self.taserEngageDistance = config.taserEngageDistance or 20
	self.lastTaserFireTime = 0
```

- [ ] **Step 3: Modify CHASING → ATTACKING transition**

In `UpdateChasing` (line 753-757), replace the distance check:

```lua
	local engageDistance = self.weaponType == "taser" and self.taserEngageDistance or self.combatSystem.attackRange
	if distance <= engageDistance then
		self.currentPath = nil
		self:ChangeState(AIState.ATTACKING)
		return
	end
```

- [ ] **Step 4: Modify ATTACKING → CHASING fallback distance**

In `UpdateAttacking` (line 928-931), replace the distance check that sends the NPC back to CHASING:

```lua
	local disengageDistance = self.weaponType == "taser" and (self.taserEngageDistance + 5) or (self.combatSystem.attackRange + 1)
	if distance > disengageDistance then
		self:ChangeState(AIState.CHASING)
		return
	end
```

- [ ] **Step 5: Add taser attack logic in UpdateAttacking**

Replace the existing melee attack call at the end of `UpdateAttacking`. The current code (lines 934-941) is:

```lua
	-- Rotación suave con interpolación hacia el target
	local targetDirection = (targetRoot.Position - self.pawn:GetPosition()) * Vector3.new(1, 0, 1)
	if targetDirection.Magnitude > 0.1 then
		local targetCFrame = CFrame.lookAt(self.pawn:GetPosition(), self.pawn:GetPosition() + targetDirection)
		self.pawn:LerpCFrame(targetCFrame, self.attackRotationSpeed)
	end

	self.combatSystem:TryAttack(self.target)
```

Replace with:

```lua
	-- Rotación suave con interpolación hacia el target
	local targetDirection = (targetRoot.Position - self.pawn:GetPosition()) * Vector3.new(1, 0, 1)
	if targetDirection.Magnitude > 0.1 then
		local targetCFrame = CFrame.lookAt(self.pawn:GetPosition(), self.pawn:GetPosition() + targetDirection)
		self.pawn:LerpCFrame(targetCFrame, self.attackRotationSpeed)
	end

	if self.weaponType == "taser" then
		self:UpdateAttackingTaser(targetRoot)
	else
		self.combatSystem:TryAttack(self.target)
	end
```

- [ ] **Step 6: Add UpdateAttackingTaser method**

Add this new method right after the `UpdateAttacking` function (after line 942):

```lua
function Controller:UpdateAttackingTaser(targetRoot)
	local now = os.clock()
	if now - self.lastTaserFireTime < TaserConfig.cooldown then
		return
	end

	-- Verificar LOS antes de disparar
	local npcPos = self.pawn:GetPosition()
	local targetPos = targetRoot.Position
	local direction = (targetPos - npcPos) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then return end
	direction = direction.Unit

	-- Raycast de LOS (reutilizar raycastParams del controller, que ya excluye al NPC)
	local origin = npcPos + Vector3.new(0, TaserConfig.projectileYOffset or 0, 0)
	local toTarget = targetPos - origin
	local losResult = workspace:Raycast(origin, toTarget, self.raycastParams)

	-- Solo disparar si el raycast golpea al target (o no golpea nada = LOS libre)
	local hasLOS = not losResult or losResult.Instance:IsDescendantOf(targetRoot.Parent)
	if not hasLOS then
		-- Sin línea de visión: volver a perseguir para reposicionarse
		self:ChangeState(AIState.CHASING)
		return
	end

	-- Disparar
	self.lastTaserFireTime = now
	local npcInstance = self.pawn:GetInstance()
	ProjectileService.Fire(npcPos, direction, TaserConfig, npcInstance)
end
```

- [ ] **Step 7: Commit**

```bash
git add src/server/NPCAISystem/NPC/Controller.lua
git commit -m "feat(taser): integrate taser firing into NPC Controller ATTACKING state"
```

---

### Task 8: Build and manual test

- [ ] **Step 1: Build the project**

```bash
rojo build -o "HeistGame.rbxl"
```

- [ ] **Step 2: Manual test checklist**

1. Player spawns with Taser tool in backpack
2. Equip taser → click → projectile fires in look direction (blue sphere traveling through corridor)
3. Projectile hits NPC → NPC enters STUNNED state
4. Projectile hits wall → projectile disappears, no effect
5. Cooldown UI appears after firing, counts down 4s, then hides
6. Clicking during cooldown does nothing
7. Guard_2 (taser NPC) detects player → stops at ~20 studs → fires taser projectile
8. NPC taser projectile hits player → player is stunned (can't move for 3s)
9. NPC taser projectile hits wall → no effect
10. Guard_1 (melee NPC) still attacks normally at close range
11. NPC with taser transitions to CHASING if player breaks LOS

- [ ] **Step 3: Commit final state with build**

```bash
git add -A
git commit -m "feat(taser): complete taser weapon system with player tool and NPC integration"
```
