# NPC Cover + Shooting System

**Fecha:** 2026-04-11
**Rama:** feature/taser_weapon

---

## Contexto

Los NPCs con `weaponType == "taser"` actualmente atacan en línea recta sin buscar cobertura. Este sistema añade un nuevo estado `COVER` que permite a los NPCs taser buscar un punto de cobertura, esconderse, asomarse para disparar y volver a cubrirse. Los NPCs melee no se ven afectados.

---

## Objetivos

- El NPC taser busca cobertura al confirmar un target en lugar de pasar directamente a ATTACKING.
- Ciclo de combate: esconderse (2s) → asomarse (0.5s) → disparar → expuesto (0.5s) → volver a cubrirse.
- Si el player sale del rango de ataque durante COVER o ATTACKING, el NPC abandona la cobertura y vuelve a CHASING.
- Si no hay CoverPoints disponibles, el NPC taser va directamente a ATTACKING (fallback).
- Los NPCs melee no entran nunca en COVER.

---

## CoverPoints

Los puntos de cobertura son `BasePart`s colocadas manualmente en una carpeta `workspace.CoverPoints`. No requieren configuración adicional. El NPC navega al centro del Part usando el sistema de navegación existente.

---

## Arquitectura

### Nuevo estado

Añadir `COVER = "Cover"` al enum `AIState` local en `Controller.lua:26`.

### Transiciones de estado (solo taser)

```
CHASING ──(target en rango de ataque, weaponType=="taser")──► COVER
                                                                  │
                                    ┌─────────────────────────────┘
                                    ▼
                                  COVER (escondido, 2s)
                                    │
                         coverTimer expirado + target en rango
                                    │
                                    ▼
                                ATTACKING (peek 0.5s → fire → exposed 0.5s)
                                    │
                    exposedTimer expirado + target en rango
                                    │
                                    └──────────────────────────► COVER

Salidas de emergencia:
  COVER ──(target fuera de rango)──► CHASING
  ATTACKING ──(target fuera de rango)──► CHASING  [lógica existente]
  COVER ──(target perdido)──► INVESTIGATING  [vía lógica existente]
```

Las transiciones melee no cambian: `CHASING → ATTACKING` como hasta ahora.

### CoverService (nuevo módulo)

Archivo: `src/server/NPCAISystem/CoverService.lua`

Función única:

```lua
-- Devuelve el mejor BasePart de workspace.CoverPoints para el NPC:
-- 1. Recoger todos los BaseParts de workspace.CoverPoints
-- 2. Filtrar por distancia ≤ coverSearchRadius desde npcPosition
-- 3. Ordenar por distancia, tomar los `count` más cercanos
-- 4. Para cada candidato: raycast desde candidate.Position hacia targetPosition
--      - FilterDescendantsInstances excluye el propio NPC y sus partes
--      - Si el raycast impacta algo antes de llegar al target → punto válido (cover bloquea LOS)
-- 5. Devolver el primer válido; si ninguno bloquea LOS, devolver el más cercano
-- 6. Devolver nil si workspace.CoverPoints no existe o no hay candidatos en rango
CoverService.FindBestCoverPoint(
    npcPosition: Vector3,
    targetPosition: Vector3,
    npcInstance: Model,
    maxRadius: number,
    count: number
) → BasePart?
```

### Retención de target durante COVER

Cuando el NPC está escondido, el VisionSensor no ve al player (LOS bloqueada por la cobertura). Para evitar que el sistema pierda el target por falsa falta de visión, se introduce `self.lastKnownTargetPosition: Vector3?`:
- Actualizada en `UpdateChasing` y `UpdateAttacking` (peek) cada frame que el target es visible.
- En `UpdateCover`, "target en rango" se evalúa como `(self.lastKnownTargetPosition - npcPos).Magnitude <= self.config.attackRange`.
- El NPC solo abandona COVER hacia CHASING si esa distancia supera `attackRange`. Si `self.lastKnownTargetPosition` es nil, ir a INVESTIGATING.

### Estado COVER en Controller

**ENTER COVER:**
1. `self.currentCoverPoint = CoverService.FindBestCoverPoint(...)`
2. Si `nil` → `self:ChangeState(AIState.ATTACKING)` (fallback, return)
3. Navegar a `self.currentCoverPoint.Position` usando el sistema existente
4. `self.coverStartTime = nil` (se asignará al llegar al punto)

**UPDATE COVER (`UpdateCover`):**
- Si aún navegando: comprobar llegada (`distancia al punto < ARRIVAL_THRESHOLD`)
  - Al llegar: `self.coverStartTime = tick()` (timer arranca al llegar, no antes)
- Si `self.coverStartTime` ya establecido:
  - `(lastKnownTargetPosition - npcPos).Magnitude > attackRange` → `CHASING`
  - `tick() - self.coverStartTime >= TaserConfig.coverDuration` → `ATTACKING`
- Si `lastKnownTargetPosition == nil` → `INVESTIGATING`

**EXIT COVER:**
- Parar navegación (`self.pawn:StopNavigation()` o equivalente)
- `self.currentCoverPoint = nil`
- `self.coverStartTime = nil`

### Estado ATTACKING — fases internas (solo taser)

Variables nuevas en Controller: `self.taserAttackPhase` y `self.taserPhaseStartTime`.

**ENTER ATTACKING (cuando viene de COVER, weaponType == "taser"):**
```lua
self.taserAttackPhase = "peek"
self.taserPhaseStartTime = tick()
```

**UpdateAttacking (taser path):**

| Fase | Duración | Comportamiento |
|------|----------|----------------|
| `"peek"` | 0.5s | Orientar NPC hacia target (`FaceTarget`), sin disparar |
| fire | instantáneo | Disparo único si cooldown libre (lógica existente); si cooldown aún activo, esperar hasta que expire |
| `"exposed"` | 0.5s | NPC quieto, puede recibir daño |

```lua
if self.taserAttackPhase == "peek" then
    self.pawn:FaceTarget(self.target)
    local canFire = (tick() - self.lastFireTime) >= TaserConfig.cooldown
    if tick() - self.taserPhaseStartTime >= TaserConfig.peekDelay and canFire then
        self:_FireTaserProjectile()
        self.taserAttackPhase = "exposed"
        self.taserPhaseStartTime = tick()
    end
elseif self.taserAttackPhase == "exposed" then
    if tick() - self.taserPhaseStartTime >= TaserConfig.exposedDuration then
        -- "en rango" = lastKnownTargetPosition distance ≤ attackRange
        if targetEnRango then
            self:ChangeState(AIState.COVER)
        else
            self:ChangeState(AIState.CHASING)
        end
    end
end
```

**ENTER ATTACKING (siempre, para cualquier origen, weaponType == "taser"):**
- Inicializar `taserAttackPhase = "peek"` y `self.taserPhaseStartTime = tick()`.

**Al expirar `exposed` (fallback — viene de CHASING porque no había cover):**
- Llamar `CoverService.FindBestCoverPoint(...)`:
  - Si encuentra punto → `ChangeState(AIState.COVER)`
  - Si nil → reiniciar `taserAttackPhase = "peek"` (ciclo peek/fire/exposed sin COVER)

---

## Configuración nueva en TaserConfig

```lua
-- Cobertura
coverDuration = 2,          -- segundos escondido en cobertura
peekDelay = 0.5,            -- segundos de asomo antes de poder disparar
exposedDuration = 0.5,      -- segundos expuesto tras disparar
coverSearchRadius = 40,     -- radio máximo para buscar CoverPoints (studs)
coverCandidateCount = 2,    -- cuántos candidatos evaluar (tomar los N más cercanos)
```

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/server/Config/TaserConfig.lua` | Añadir 5 valores de cobertura |
| `src/server/NPCAISystem/NPC/Controller.lua` | Añadir `COVER` al enum AIState; `UpdateCover`; modificar `UpdateChasing` (taser va a COVER); modificar `UpdateAttacking` (fases peek/exposed); `ChangeState` ENTER/EXIT COVER |
| `src/server/NPCAISystem/CoverService.lua` | Nuevo módulo |

---

## Verificación

1. **V1** — Guard_2 (taser) confirma target → navega a un CoverPoint cercano y se esconde.
2. **V2** — Tras 2s → asoma 0.5s sin disparar → dispara → queda expuesto 0.5s → vuelve a cubrirse. Ciclo se repite.
3. **V3** — Player se aleja durante COVER → Guard_2 abandona cobertura y pasa a CHASING.
4. **V4** — Player se aleja durante ATTACKING (fase peek o exposed) → Guard_2 pasa a CHASING.
5. **V5** — Sin `workspace.CoverPoints` o sin puntos en rango → Guard_2 va directamente a ATTACKING (ciclo peek/fire/exposed sin cover).
6. **V6** — Guard_1 (melee) — sin cambios visuales ni de comportamiento.
7. **V7** — Sin errores de consola en ningún caso.
