# NPC Tool Hold Animation (Taser apuntado)

**Fecha:** 2026-04-10
**Rama:** feature/taser_weapon

---

## Contexto

El NPC taser ya equipa el modelo del arma en ATTACKING, pero no reproduce ninguna animación de apuntado. El jugador levanta el brazo automáticamente al equipar una Tool porque el script `Animate` de Roblox carga `rbxassetid://507768375` (tool hold R6 estándar). Los NPCs no tienen ese script, por lo que hay que hacerlo manualmente.

---

## Objetivos

- El NPC con `weaponType == "taser"` reproduce la animación de apuntado (`toolhold`) en loop mientras está en estado ATTACKING.
- Al salir de ATTACKING, la animación vuelve a `idle`.
- Si en el futuro se añade un `shootAnimationId` real, `PlayAnimationOnce("shoot")` se superpone al `toolhold` durante el disparo y retoma automáticamente.
- Sin cambios visibles para NPCs melee.

---

## Arquitectura

### Pawn.lua — `_InitializeAnimations`

Añadir el track `toolhold` al bloque condicional `weaponType == "taser"` existente (donde ya se carga el track `shoot`):

```lua
-- Animación de apuntado (tool hold R6 estándar)
local toolholdAnim = Instance.new("Animation")
toolholdAnim.Name = "toolhold"
toolholdAnim.AnimationId = "rbxassetid://507768375"
self.animations["toolhold"] = toolholdAnim

local toolholdTrack = self.animator:LoadAnimation(toolholdAnim)
toolholdTrack.Looped = true
toolholdTrack.Priority = Enum.AnimationPriority.Action
self.animationTracks["toolhold"] = toolholdTrack
self.janitor:Add(toolholdTrack, "Destroy")
```

### Controller.lua — `ChangeState`

**ENTER ATTACKING** (después de `EquipWeaponVisual`):
```lua
self.pawn:PlayAnimation("toolhold")
```

**EXIT ATTACKING** (después de `UnequipWeaponVisual`):
```lua
self.pawn:PlayAnimation("idle")
```

> Nota: `PlayAnimation` hace early-return si la animación ya está activa, por lo que llamarlo en ENTER es seguro aunque el NPC entre y salga rápidamente de ATTACKING.

---

## Compatibilidad con `shoot`

`PlayAnimationOnce("shoot")` usa `Priority.Action` y al terminar llama `PlayAnimation(previousAnimation)`. Como `previousAnimation` será `"toolhold"`, la secuencia es:
1. `toolhold` en loop (ATTACKING activo)
2. Disparo: `shoot` one-shot superpone `toolhold`
3. Al terminar `shoot`: retoma `toolhold`

Esto funciona sin cambios adicionales gracias a la lógica ya implementada en `PlayAnimationOnce`.

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/server/NPCAISystem/NPC/Pawn.lua` | Añadir track `toolhold` en `_InitializeAnimations` |
| `src/server/NPCAISystem/NPC/Controller.lua` | 2 líneas en `ChangeState` (ENTER y EXIT ATTACKING) |

---

## Verificación

1. Guard_2 entra en ATTACKING → brazo derecho sube (animación toolhold visible).
2. Guard_2 sale de ATTACKING → brazo vuelve a posición idle.
3. Guard_2 recibe disparo de taser mientras ataca → entra en STUNNED, brazo baja.
4. Guard_1 (melee) — sin cambios visuales.
5. Sin errores de consola en ningún caso.
