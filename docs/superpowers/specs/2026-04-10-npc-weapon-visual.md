# NPC Weapon Visual (Taser en mano al atacar)

**Fecha:** 2026-04-10
**Rama:** feature/taser_weapon

---

## Contexto

Guard_2 ya dispara el proyectil taser con su IA, pero no lleva ningún modelo visible en la mano. Este spec añade el modelo visual del arma: aparece al entrar en ATTACKING y desaparece al salir.

---

## Objetivos

- El NPC con `weaponType = "taser"` muestra el modelo del Taser en la mano derecha al entrar en estado ATTACKING.
- El modelo desaparece al salir de ATTACKING (cualquier estado siguiente).
- El modelo usado es el mismo que lleva el jugador (clon del Taser en `game.StarterPack`).
- Si el Taser no existe en StarterPack, el sistema falla silenciosamente sin errores.

---

## Arquitectura

### Pawn.lua — dos métodos nuevos

**`Pawn:EquipWeaponVisual()`**
- Solo actúa si `self.weaponType == "taser"`.
- Busca `game.StarterPack:FindFirstChild("Taser")`. Si no existe, sale silenciosamente.
- Clona el tool, establece `CanBeDropped = false`.
- Llama `self.humanoid:EquipTool(clone)` — Roblox crea el weld `RightGrip` automáticamente.
- Guarda la referencia en `self.equippedWeaponTool`.

**`Pawn:UnequipWeaponVisual()`**
- Si `self.equippedWeaponTool` existe, lo destruye.
- Pone `self.equippedWeaponTool = nil`.

**`Pawn:Destroy()`** — añadir llamada a `self:UnequipWeaponVisual()` antes del janitor cleanup, para evitar referencias colgantes.

### Controller.lua — ChangeState

En el bloque **EXIT ATTACKING** (línea ~1223):
```lua
elseif self.currentState == AIState.ATTACKING then
    self.pawn:SetAutoRotate(true)
    self.pawn:UnequipWeaponVisual()   -- ← nuevo
```

En el bloque **ENTER ATTACKING** (línea ~1251):
```lua
elseif newState == AIState.ATTACKING then
    self.pawn:SetAutoRotate(false)
    self.pawn:EquipWeaponVisual()     -- ← nuevo
```

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/server/NPCAISystem/NPC/Pawn.lua` | Añadir `EquipWeaponVisual`, `UnequipWeaponVisual`; actualizar `Destroy` |
| `src/server/NPCAISystem/NPC/Controller.lua` | 2 líneas en `ChangeState` |

---

## Verificación

1. Guard_2 entra en ATTACKING → modelo Taser aparece en mano derecha.
2. Guard_2 pierde el target y vuelve a CHASING/PATROLLING → modelo desaparece.
3. Guard_2 es stunneado mientras ataca → modelo desaparece al entrar en STUNNED.
4. Guard_2 muere → sin errores de consola (Destroy hace cleanup).
5. Sin Taser en StarterPack → sin errores, sin modelo (fallback silencioso).
