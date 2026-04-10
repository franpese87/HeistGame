# NPC Tool Hold Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproducir la animación de apuntado (tool hold R6) en loop mientras el NPC taser está en estado ATTACKING.

**Architecture:** Se añade el track `toolhold` al bloque condicional `weaponType == "taser"` de `_InitializeAnimations` en `Pawn.lua`. `Controller.ChangeState` llama `PlayAnimation("toolhold")` al entrar en ATTACKING y `PlayAnimation("idle")` al salir. La animación `shoot` (cuando tenga ID) se superpone correctamente gracias a la lógica existente de `PlayAnimationOnce`.

**Tech Stack:** Luau, Roblox AnimationTrack API (`Looped`, `Priority.Action`), Rojo live-sync

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/server/NPCAISystem/NPC/Pawn.lua` | Añadir track `toolhold` en el bloque taser de `_InitializeAnimations` (~línea 145) |
| `src/server/NPCAISystem/NPC/Controller.lua` | 2 líneas en `ChangeState`: ENTER y EXIT ATTACKING |

---

## Task 1: Track `toolhold` en Pawn._InitializeAnimations

**Files:**
- Modify: `src/server/NPCAISystem/NPC/Pawn.lua:144-160`

El bloque condicional taser (línea ~144) actualmente carga solo el track `shoot`. Hay que añadir `toolhold` dentro del mismo bloque `if self.weaponType == "taser"`, sin condición de ID (este track siempre se carga).

- [ ] **Step 1: Añadir el track `toolhold` al bloque taser en `_InitializeAnimations`**

Localizar el bloque (línea ~144):

```lua
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
```

Reemplazarlo por:

```lua
	-- Tracks de arma (solo NPCs taser)
	if self.weaponType == "taser" then
		-- Animación de apuntado (tool hold R6 estándar - siempre cargada)
		local toolholdAnim = Instance.new("Animation")
		toolholdAnim.Name = "toolhold"
		toolholdAnim.AnimationId = "rbxassetid://507768375"
		self.animations["toolhold"] = toolholdAnim

		local toolholdTrack = self.animator:LoadAnimation(toolholdAnim)
		toolholdTrack.Looped = true
		toolholdTrack.Priority = Enum.AnimationPriority.Action
		self.animationTracks["toolhold"] = toolholdTrack
		self.janitor:Add(toolholdTrack, "Destroy")

		-- Animación de disparo (solo si hay ID configurado)
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
```

---

## Task 2: Wiring en Controller.ChangeState

**Files:**
- Modify: `src/server/NPCAISystem/NPC/Controller.lua:1229-1261`

- [ ] **Step 2: Reproducir `toolhold` al entrar en ATTACKING**

Localizar el bloque ENTER ATTACKING (~línea 1258):

```lua
	elseif newState == AIState.ATTACKING then
		-- Desactivar AutoRotate para control manual de rotación
		self.pawn:SetAutoRotate(false)
		self.pawn:EquipWeaponVisual()
```

Reemplazarlo por:

```lua
	elseif newState == AIState.ATTACKING then
		-- Desactivar AutoRotate para control manual de rotación
		self.pawn:SetAutoRotate(false)
		self.pawn:EquipWeaponVisual()
		self.pawn:PlayAnimation("toolhold")
```

- [ ] **Step 3: Volver a `idle` al salir de ATTACKING**

Localizar el bloque EXIT ATTACKING (~línea 1229):

```lua
	elseif self.currentState == AIState.ATTACKING then
		-- Re-activar AutoRotate al salir de combate
		self.pawn:SetAutoRotate(true)
		self.pawn:UnequipWeaponVisual()
```

Reemplazarlo por:

```lua
	elseif self.currentState == AIState.ATTACKING then
		-- Re-activar AutoRotate al salir de combate
		self.pawn:SetAutoRotate(true)
		self.pawn:UnequipWeaponVisual()
		self.pawn:PlayAnimation("idle")
```

---

## Task 3: Verificación manual en Studio (ANTES de commitear)

> **No commitear hasta que todos estos checks pasen sin errores en la consola.**

- [ ] **Step 4: Arrancar Rojo y abrir Studio**

```bash
rojo serve
```

- [ ] **Step 5: V1 — Animación de apuntado al atacar**

Acercarse a Guard_2 hasta que entre en ATTACKING.
Esperado: brazo derecho sube con la pose de apuntado (tool hold).

- [ ] **Step 6: V2 — Animación vuelve a idle al salir**

Alejarse hasta que Guard_2 pierda el target.
Esperado: brazo vuelve a posición idle.

- [ ] **Step 7: V3 — Guard_1 (melee) sin cambios**

Verificar que Guard_1 entra y sale de ATTACKING sin reproducir ninguna animación de apuntado.
Esperado: comportamiento idéntico al anterior.

- [ ] **Step 8: V4 — Sin errores de consola**

Esperado: cero errores o warnings durante todos los pasos anteriores.

- [ ] **Step 9: Commit (solo tras pasar los checks)**

```bash
git add src/server/NPCAISystem/NPC/Pawn.lua src/server/NPCAISystem/NPC/Controller.lua
git commit -m "feat(npc): play toolhold animation during ATTACKING state"
```

---

## Self-Review contra el spec

| Requisito del spec | Tarea |
|---|---|
| Track `toolhold` cargado en `_InitializeAnimations` solo para `weaponType == "taser"` | Task 1 |
| `toolhold`: `Looped = true`, `Priority.Action` | Task 1 |
| Registrado en janitor | Task 1 |
| ENTER ATTACKING → `PlayAnimation("toolhold")` | Task 2, Step 2 |
| EXIT ATTACKING → `PlayAnimation("idle")` | Task 2, Step 3 |
| Compatibilidad con `shoot` via `PlayAnimationOnce` | Ya implementado — sin cambios necesarios |
| NPCs melee sin cambios | Task 1 (bloque condicional `weaponType == "taser"`) |
| Verificación V1–V4 | Task 3 |
