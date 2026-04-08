# Taser: Animación de Disparo y Tool Visual del Jugador

**Fecha:** 2026-04-08  
**Rama:** feature/taser_weapon

---

## Contexto

El sistema de taser funciona mecánicamente (proyectil, stun, cooldown) pero carece de feedback visual:

1. El jugador lleva el taser como Tool invisible en el Backpack — tiene que seleccionarla manualmente y no hay modelo 3D en la mano.
2. Ni el jugador ni el NPC Guard_2 reproducen ninguna animación al disparar — el tiro ocurre de forma silenciosa.

Este spec define cómo añadir ambas cosas de forma limpia y mantenible.

---

## Objetivos

- El jugador lleva el taser **siempre equipado** en la mano derecha al spawnear, sin intervención.
- Existe un **modelo 3D simple** visible como Handle de la Tool.
- Al disparar, **jugador y NPC reproducen una animación de disparo** (one-shot, non-looped).
- El ID de animación es un **placeholder en config** — enchufar el asset real cambia un solo valor.

---

## Arquitectura

### A) Tool visual del jugador (server-side)

La Tool se crea y equipa en el **servidor**, no en el cliente. Esto garantiza replicación correcta y que otros jugadores vean el arma.

**Flujo:**
1. `PlayerAdded → CharacterAdded` en `init.server.luau`
2. Servidor crea `Tool` con Handle (Part cilíndrica azul)
3. Llama `Humanoid:EquipTool(tool)` — aparece en mano derecha inmediatamente
4. Al respawnear, `CharacterAdded` repite el proceso

**El cliente** deja de crear la Tool. Solo detecta la tool por nombre en el character y conecta `tool.Activated` para input + cooldown UI + animación local.

**Handle (modelo procedural):**
```
Shape:    Cylinder
Size:     (0.3, 0.8, 0.3)
Color:    Color3.fromRGB(30, 120, 220)  -- azul eléctrico
Material: SmoothPlastic
CanCollide: false
```

### B) Animación de disparo

**Config (`TaserConfig.lua`):**
```lua
shootAnimationId = "",  -- placeholder; asignar rbxassetid://... cuando esté listo
```
Si el ID es vacío o nil, el sistema omite la animación silenciosamente — sin errores.

**En NPCs (`Pawn.lua`):**
- Nueva función `Pawn:PlayAnimationOnce(animName, fadeTime)`:
  - Carga el track con `Priority.Action`, `Looped = false`
  - Reproduce y al terminar (`track.Stopped`) retoma la animación previa
- El track `shoot` se inicializa en `_InitializeAnimations()` solo si `TaserConfig.shootAnimationId` no es vacío

**En Controller (`Controller.lua`):**
- `UpdateAttackingTaser()` llama `self.pawn:PlayAnimationOnce("shoot")` justo antes de `ProjectileService.Fire()`

**En el jugador (`TaserTool.client.luau`):**
- Al `tool.Activated`: reproduce la animación via `Humanoid.Animator` del character local
- Mismo fallback silencioso si no hay ID

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/server/Config/TaserConfig.lua` | Añadir `shootAnimationId = ""` |
| `src/server/NPCAISystem/NPC/Pawn.lua` | Añadir track `shoot` + `PlayAnimationOnce()` |
| `src/server/NPCAISystem/NPC/Controller.lua` | Llamar `PlayAnimationOnce("shoot")` al disparar |
| `src/server/init.server.luau` | Crear y equipar Tool server-side en CharacterAdded |
| `src/client/TaserTool.client.luau` | Simplificar: detectar tool existente + animación local |

---

## Verificación

1. **Tool en mano:** Al entrar/respawnear, el taser aparece en la mano derecha sin seleccionarlo.
2. **Modelo visible:** La Part cilíndrica azul es visible en tercera persona.
3. **No seleccionable manualmente:** La tool no aparece en la barra de herramientas de forma que interrumpa el flujo.
4. **Disparo NPC:** Guard_2 en estado ATTACKING reproduce la animación `shoot` (o ninguna si ID vacío, sin errores).
5. **Disparo jugador:** Al activar el taser, el jugador reproduce la animación (o ninguna si ID vacío).
6. **Respawn:** Al morir y respawnear, la tool vuelve a aparecer equipada.
7. **Sin errores de consola** en ninguno de los casos anteriores.
