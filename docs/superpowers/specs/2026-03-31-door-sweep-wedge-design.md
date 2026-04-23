# Door Sweep Wedge - Design Spec

## Overview

Replace the instantaneous door stun check (`_CheckDoorStun`) with a continuous swept-area detection system during the door opening animation. The swept area is a cylindrical wedge (circular sector) centered on the door's hinge that grows in arc as the door rotates. Any NPC or player caught inside the wedge receives a stun/knockback.

## Architecture

### Detection: Mathematical (per-frame in Heartbeat)

The detection runs inside the existing `animateDoor` Heartbeat connection — no new loop is created.

Each frame during the opening animation:

1. **Gather candidates**: Use `Registry:FindNPCsInRadius()` for NPCs + `Players:GetPlayers()` for player characters, filtered by distance to hinge position <= door radius.
2. **Sector check**: For each candidate, determine if their XZ position falls within the circular sector defined by:
   - **Center**: hinge pivot position (XZ)
   - **Radius**: door width (`DoorPart.Size.X` — distance from hinge to free edge)
   - **Start angle**: door's closed direction (0 degrees of rotation)
   - **Current angle**: the `angleValue.Value` at this frame
   - The check uses dot product for angular range and cross product sign for directionality.
3. **Stun on first contact**: Each entity is stunned at most once per door open. A set (`alreadyHit`) tracks entities already hit during this animation. Excludes `openerInstance`.

### Debug Visual: Two cylinder lines (VisionSensor pattern)

Two thin `Part` instances (Shape = Cylinder) rendered from the hinge outward:

- **Fixed boundary**: Points in the door's closed direction. Stays static during the animation.
- **Moving boundary**: Points in the door's current rotation direction. Updates every frame.
- **Appearance**: Semi-transparent yellow (`Color3.fromRGB(255, 200, 0)`), Transparency 0.3, Size thickness 0.15 studs.
- **Lifetime**: Created when the opening animation starts, destroyed when it completes.
- **Controlled by**: `DebugConfig` — a new flag `showDoorSweep` (default: false). Only create visual parts when enabled.

### Integration in DoorService

**What changes:**
- `_CheckDoorStun()` is removed (instantaneous check replaced by continuous detection).
- `animateDoor()` receives additional parameters: `sweepData` (hinge position, radius, start angle, sign, openerInstance, alreadyHit set, debug parts).
- Inside the existing `Heartbeat:Connect` callback in `animateDoor`, after updating `doorPart.CFrame`, the sweep detection + debug visual update runs.
- On `tween.Completed`, debug parts are destroyed and sweep data is cleared.

**What does NOT change:**
- `Controller.lua` — the `STUNNED` state, `ApplyStun()`, `EnterStunned()`, `UpdateStunned()`, `ExitStunned()`, stun indicator, knockback logic all remain as-is. The wedge system only changes *when and how* impact is detected, not what happens after.
- `NPCBaseConfig.lua` — `stunDuration` and `stunKnockbackForce` remain unchanged.
- `DoorService.Open()` still determines the opening direction/angle. The sweep data is derived from the same values.

### Sweep geometry details

```
        Hinge (pivot)
          *-----------  Fixed boundary (closed direction)
         /|
        / |
       /  |  <- Swept area (circular sector)
      /   |
     / a  |
    *-----'  Moving boundary (current angle)

    a = current angleValue (grows from 0 to openAngle during animation)
    radius = DoorPart.Size.X (door width from hinge to free edge)
```

The sign of the angle (positive or negative `openAngle`) determines which side the sector expands toward. The sector check must handle both directions.

### Knockback direction

When an entity is hit, the knockback direction is computed as the vector from the hinge to the entity's position (projected to XZ plane, normalized). This naturally pushes entities outward from the hinge — the direction the door is sweeping them.

### Detection math (sector containment)

For a point P, hinge H, closed direction D0, and current angle A:

```
toPoint = (P - H) * Vector3.new(1, 0, 1)
distance = toPoint.Magnitude

if distance > radius then OUTSIDE end

pointAngle = atan2(cross(D0, toPoint.Unit), dot(D0, toPoint.Unit))

-- For positive openAngle: 0 <= pointAngle <= A
-- For negative openAngle: A <= pointAngle <= 0
if sign(openAngle) > 0 then
    inside = pointAngle >= 0 and pointAngle <= currentAngle
else
    inside = pointAngle <= 0 and pointAngle >= currentAngle
end
```

## Files to modify

| File | Changes |
|------|---------|
| `src/server/Services/DoorService.lua` | Remove `_CheckDoorStun`, add sweep detection in `animateDoor` Heartbeat, add debug visual creation/update/cleanup |
| `src/server/Config/DebugConfig.lua` | Add `showDoorSweep = false` flag |

## Out of scope

- Push/knockback logic changes (handled by existing `Controller:ApplyStun`)
- Door closing sweep (only opening triggers the wedge)
- Sound effects or particle effects on hit
