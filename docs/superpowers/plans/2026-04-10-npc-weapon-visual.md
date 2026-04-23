# NPC Weapon Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar el modelo del Taser en la mano derecha del NPC al entrar en estado ATTACKING, y ocultarlo al salir.

**Architecture:** `Pawn` expone dos métodos (`EquipWeaponVisual` / `UnequipWeaponVisual`) que clonan/destruyen el Tool de `StarterPack`. `Controller.ChangeState` los llama al entrar y salir de ATTACKING. No se commitea hasta que el usuario haya verificado en Studio.

**Tech Stack:** Luau, Roblox API (`Humanoid:EquipTool`, `StarterPack`), Rojo live-sync

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/server/NPCAISystem/NPC/Pawn.lua` | Añadir `self.equippedWeaponTool = nil` en constructor; añadir `EquipWeaponVisual` y `UnequipWeaponVisual`; actualizar `Destroy` |
| `src/server/NPCAISystem/NPC/Controller.lua` | 2 líneas en `ChangeState` (EXIT y ENTER ATTACKING) |

---

## Task 1: Métodos de visual de arma en Pawn

**Files:**
- Modify: `src/server/NPCAISystem/NPC/Pawn.lua`

- [ ] **Step 1: Inicializar `equippedWeaponTool` en el constructor**

En `Pawn.new()`, después de la línea `self.weaponType = config.weaponType or "melee"` (línea ~97), añadir:

```lua
self.equippedWeaponTool = nil
```

El bloque completo queda:
```lua
self.patrolSpeed = config.patrolSpeed or 16
self.chaseSpeed = config.chaseSpeed or 24
self.weaponType = config.weaponType or "melee"
self.equippedWeaponTool = nil
```

- [ ] **Step 2: Añadir `EquipWeaponVisual` y `UnequipWeaponVisual`**

Añadir los dos métodos justo antes de la sección `-- POSICIÓN Y CFRAME` (después de `Pawn:PlayAnimationOnce`, alrededor de línea 215). Insertar una nueva sección:

```lua
-- ==============================================================================
-- VISUAL DE ARMA
-- ==============================================================================

function Pawn:EquipWeaponVisual()
	if self.weaponType ~= "taser" then return end
	local taserTemplate = game:GetService("StarterPack"):FindFirstChild("Taser")
	if not taserTemplate then return end

	local clone = taserTemplate:Clone()
	clone.CanBeDropped = false
	self.humanoid:EquipTool(clone)
	self.equippedWeaponTool = clone
end

function Pawn:UnequipWeaponVisual()
	if self.equippedWeaponTool then
		self.equippedWeaponTool:Destroy()
		self.equippedWeaponTool = nil
	end
end
```

- [ ] **Step 3: Llamar `UnequipWeaponVisual` en `Pawn:Destroy()`**

El método `Destroy` está al final del archivo (línea ~455). Añadir la llamada antes de `self.janitor:Destroy()`:

```lua
function Pawn:Destroy()
	self:UnequipWeaponVisual()  -- ← nuevo: limpiar arma antes del janitor

	-- Janitor limpia automáticamente: tweens, tracks, billboard
	self.janitor:Destroy()

	-- Limpiar referencias
	self.animationTracks = {}
	self.animations = {}
	self.currentTrack = nil
	self.currentAnimation = nil
	self.stateIndicator = nil
end
```

---

## Task 2: Wiring en Controller.ChangeState

**Files:**
- Modify: `src/server/NPCAISystem/NPC/Controller.lua`

El método `ChangeState` está en la línea ~1206. Tiene dos bloques relevantes: EXIT (cuando se sale de un estado) y ENTER (cuando se entra en uno).

- [ ] **Step 4: Llamar `UnequipWeaponVisual` al salir de ATTACKING**

Localizar el bloque EXIT ATTACKING (~línea 1223):

```lua
	elseif self.currentState == AIState.ATTACKING then
		-- Re-activar AutoRotate al salir de combate
		self.pawn:SetAutoRotate(true)
```

Reemplazarlo por:

```lua
	elseif self.currentState == AIState.ATTACKING then
		-- Re-activar AutoRotate al salir de combate
		self.pawn:SetAutoRotate(true)
		self.pawn:UnequipWeaponVisual()
```

- [ ] **Step 5: Llamar `EquipWeaponVisual` al entrar en ATTACKING**

Localizar el bloque ENTER ATTACKING (~línea 1251):

```lua
	elseif newState == AIState.ATTACKING then
		-- Desactivar AutoRotate para control manual de rotación
		self.pawn:SetAutoRotate(false)
```

Reemplazarlo por:

```lua
	elseif newState == AIState.ATTACKING then
		-- Desactivar AutoRotate para control manual de rotación
		self.pawn:SetAutoRotate(false)
		self.pawn:EquipWeaponVisual()
```

---

## Task 3: Verificación manual en Studio (ANTES de commitear)

> **No commitear hasta que todos estos checks pasen sin errores en la consola.**

- [ ] **Step 6: Arrancar Rojo y abrir Studio**

```bash
rojo serve
```

Abrir el lugar en Roblox Studio y hacer Play.

- [ ] **Step 7: V1 — Taser aparece al atacar**

Mover el jugador a rango de Guard_2 hasta que entre en ATTACKING.
Esperado: el modelo del Taser aparece en la mano derecha del NPC.

- [ ] **Step 8: V2 — Taser desaparece al perder el target**

Alejarse del NPC hasta que pierda el target (CHASING → INVESTIGATING / RETURNING).
Esperado: el modelo del Taser desaparece.

- [ ] **Step 9: V3 — Taser desaparece al ser stunneado**

Disparar al NPC mientras está en ATTACKING para stunnearlo.
Esperado: al entrar en STUNNED, el Taser desaparece.

- [ ] **Step 10: V4 — Sin errores de consola**

Revisar el Output durante todos los pasos anteriores.
Esperado: cero errores o warnings relacionados con el taser visual.

- [ ] **Step 11: Commit (solo tras pasar los checks)**

```bash
git add src/server/NPCAISystem/NPC/Pawn.lua src/server/NPCAISystem/NPC/Controller.lua
git commit -m "feat(npc): show taser model in hand during ATTACKING state"
```

---

## Self-Review contra el spec

| Requisito del spec | Tarea |
|---|---|
| Aparece al entrar en ATTACKING | Task 2, Step 5 |
| Desaparece al salir de ATTACKING | Task 2, Step 4 |
| Mismo modelo que el jugador (StarterPack) | Task 1, Step 2 |
| Fallback silencioso si no hay Taser en StarterPack | Task 1, Step 2 (`if not taserTemplate then return end`) |
| Cleanup en Destroy | Task 1, Step 3 |
| Verificación V1–V4 | Task 3 |
