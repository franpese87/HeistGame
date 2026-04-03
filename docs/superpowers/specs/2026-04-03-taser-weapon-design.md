# Taser Weapon System - Design Spec

## Overview

Add an equippable taser weapon that fires a physical projectile to stun NPCs and players. Players spawn with it; NPCs can be configured to use it instead of melee. The projectile travels horizontally in a straight line from the shooter's position in their look direction (XZ plane), colliding with environment and characters. Balance is driven by cooldown (no ammo system).

## Architecture

### Approach: Shared ProjectileService + Lightweight Tool

A server-side `ProjectileService` centralizes all projectile logic (creation, movement, collision, stun application). Both the player's Tool (via RemoteEvent) and NPC Controllers call `ProjectileService.Fire()`. The client Tool only handles input and cooldown UI.

```
PLAYER:
  Client (TaserTool) → RemoteEvent "TaserFire" → Server handler
       input + cooldown UI                          validates cooldown
                                                    ProjectileService.Fire(origin, dir, config, owner)

NPC:
  Controller (ATTACKING, weaponType=="taser") → ProjectileService.Fire(origin, dir, config, owner)
```

All authoritative logic (cooldown enforcement, projectile creation, hit detection, stun application) runs server-side.

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `src/server/Config/TaserConfig.lua` | New | Balance values (cooldown, speed, range, stun duration) |
| `src/server/Services/ProjectileService.lua` | New | Projectile lifecycle: create, move, collide, cleanup |
| `src/client/TaserTool.client.luau` | New | Player input, equip Tool, cooldown UI |
| `src/server/init.server.luau` | Modify | Init ProjectileService, create RemoteEvent, connect handler |
| `src/server/NPCAISystem/NPC/Controller.lua` | Modify | Bifurcate ATTACKING state by weaponType |
| `src/server/Config/NPCBaseConfig.lua` | Modify | Add weaponType, taserEngageDistance defaults |
| `src/server/Config/NPCSpawnList.lua` | Modify | Override weaponType per NPC |

## TaserConfig

```lua
return {
    -- Projectile
    projectileSpeed = 60,       -- studs/s
    projectileRadius = 0.3,     -- Part radius (hitbox)
    maxRange = 80,              -- studs before auto-destroy

    -- Balance
    cooldown = 4,               -- seconds between shots
    stunDuration = 3,           -- seconds of stun on hit

    -- Visual
    projectileColor = Color3.fromRGB(100, 180, 255),  -- electric blue
    projectileYOffset = 0,      -- Y offset from shooter's RootPart (0 = fires from hip height)
}
```

**Rationale:**
- **Cooldown 4s** — With infinite ammo, missing must be punishing. 4s gives the target time to close distance or find cover.
- **Speed 60 studs/s** — Fast enough to be useful in corridors, slow enough to be reactable at range.
- **Range 80 studs** — Covers a long corridor but not infinite.
- **Stun 3s** — Same as door slam stun. Consistent across systems.

## ProjectileService

### API

```lua
ProjectileService.Init()
    -- Called from init.server.luau. Connects RunService.Heartbeat for projectile updates.

ProjectileService.Fire(origin, direction, config, ownerInstance)
    -- Creates a projectile Part, registers it in the active projectiles table.
    -- origin: Vector3 (shooter position, adjusted to projectileHeight)
    -- direction: Vector3 (XZ unit vector, Y=0)
    -- config: TaserConfig table (speed, radius, maxRange, stunDuration, color)
    -- ownerInstance: Character model of the shooter (excluded from collision)
```

### Projectile lifecycle

1. **Create:** Small Part (sphere, Neon material, `projectileColor`, Size = `projectileRadius * 2`). Anchored, CanCollide false, CanTouch false, CanQuery false. Positioned at `origin + Vector3.new(0, projectileYOffset, 0)` (by default fires from RootPart height, which is hip/chest level).

2. **Move (Heartbeat):** Each frame, for each active projectile:
   - Compute new position: `newPos = pos + direction * speed * dt`
   - Raycast from `pos` to `newPos` (short-range raycast covering the frame's travel distance) to detect collision with walls or characters
   - RaycastParams: `FilterType = Exclude`, `FilterDescendantsInstances = {ownerInstance}`
   - If raycast hits:
     - Check if hit Instance belongs to a Character (walk up parents to find Humanoid)
     - **Character hit:** Apply stun (see below), destroy projectile
     - **Environment hit:** Destroy projectile, no effect
   - If no hit: update Part position to `newPos`
   - If total distance traveled > `maxRange`: destroy projectile

3. **Destroy:** Remove Part, remove from active projectiles table.

### Stun application on hit

Given the hit Character model:

- **NPC:** `Registry:GetNPCByInstance(model)` — if found and active and not already Stunned: `controller:ApplyStun()`
- **Player:** Get Humanoid from character, call `StunService.Apply(humanoid, stunDuration)`

This reuses the exact same stun path as the door slam system.

## TaserTool (Client)

### Equipment
- On player spawn (`CharacterAdded`), create a `Tool` instance named "Taser" in the player's `Backpack`
- Default Roblox Tool appearance (no custom Handle mesh in this iteration)

### Input
- `Tool.Activated` fires when player clicks while tool is equipped
- Client checks local cooldown timer — if ready:
  - Fire RemoteEvent `"TaserFire"` with `{ position = rootPart.Position, direction = lookVectorXZ }`
  - Start local cooldown timer (for immediate UI feedback)
- Direction is `HumanoidRootPart.CFrame.LookVector` projected to XZ: `(lookVector * Vector3.new(1, 0, 1)).Unit`

### Cooldown UI
- Simple `ScreenGui` with a `TextLabel` or small bar
- Shows remaining cooldown time, updates each frame via `RenderStepped`
- Hidden when cooldown is ready

### Server validation
The server handler (in `init.server.luau`) maintains a `lastFireTime` table per player. When receiving the RemoteEvent:
1. Check `os.clock() - lastFireTime[player] >= cooldown` — reject if too soon
2. Validate that the player's character exists and has a HumanoidRootPart
3. Use the **server-side** character position and look direction (not the client-sent values) to prevent spoofing
4. Call `ProjectileService.Fire(serverPosition, serverDirection, TaserConfig, character)`

## NPC Taser Integration

### Configuration
- `NPCBaseConfig.lua` adds: `weaponType = "melee"` (default) and `taserEngageDistance = 20` (studs)
- `NPCSpawnList.lua` can override per NPC: `weaponType = "taser"`
- Controller reads `config.weaponType` in constructor, stores as `self.weaponType`

### ATTACKING state bifurcation

`UpdateAttacking` checks `self.weaponType`:

**weaponType == "taser":**
- The NPC does NOT approach to melee range
- Maintains position at approximately `taserEngageDistance` from target
- Each frame: face target (existing rotation logic), check if cooldown is ready
- If cooldown ready and has line of sight to target (raycast): fire via `ProjectileService.Fire(npcPosition, directionToTarget, TaserConfig, npcInstance)`
- Track `self.lastTaserFireTime` for cooldown enforcement
- If target moves out of LOS: transition to CHASING to reposition

**weaponType == "melee":**
- Existing melee logic, unchanged

### CHASING state adjustment
- NPCs with `weaponType == "taser"` transition to ATTACKING at `taserEngageDistance` instead of `attackRange`
- This requires checking `self.weaponType` in the distance threshold for the CHASING → ATTACKING transition

## Level design fit

The game uses long narrow corridors. This naturally favors the taser:
- Hard to dodge in tight corridors (high hit rate)
- Balanced by the 4s cooldown (miss = vulnerability window)
- Cover behind corners is the primary counter
- NPCs with taser create "danger zones" in long corridors that the player must navigate around or rush through

## Out of scope (future iterations)

- Custom taser model/mesh
- Impact VFX (particles, electricity effect, sound)
- NPC evasive behavior (retreating, strafing)
- Ammo system / pickups
- Player stun visual feedback (screen shake, vignette)
- Projectile prediction/leading for NPC accuracy
