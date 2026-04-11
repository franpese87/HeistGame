# Taser Animation and Tool Design — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the taser visual feature: correct cylinder Handle shape and verify all spec requirements pass.

**Architecture:** Most of the spec is already implemented across prior commits. The single remaining code gap is the Handle shape — `createTaserHandleProcedural` creates a block Part; the spec requires a Cylinder. All animation, equip, and respawn logic is in place.

**Tech Stack:** Luau, Roblox API (`Enum.PartType.Cylinder`), Rojo live-sync

---

## Gap Analysis (what is already done)

| Spec requirement | Status |
|---|---|
| `TaserConfig.shootAnimationId = ""` | ✅ done |
| `TaserConfig.toolModelId = ""` | ✅ done |
| `Pawn:PlayAnimationOnce()` | ✅ done |
| Shoot track loaded in `_InitializeAnimations` when `weaponType == "taser"` | ✅ done |
| `Controller:UpdateAttackingTaser()` calls `PlayAnimationOnce("shoot")` | ✅ done |
| Guard_2 has `weaponType = "taser"` in NPCSpawnList | ✅ done |
| Server creates Tool → Backpack | ✅ done |
| Client equips from Backpack + connects `tool.Activated` | ✅ done |
| Client plays shoot animation (silent fallback when ID empty) | ✅ done |
| Respawn via `CharacterAdded` | ✅ done |
| **Handle is Cylinder shape** | ❌ **missing** |

---

## Task 1: Fix Handle to cylinder shape

**Files:**
- Modify: `src/server/init.server.luau:75-83`

The current `createTaserHandleProcedural` creates a plain block Part. The spec requires:
```
Shape:    Cylinder
Size:     (0.3, 0.8, 0.3)   -- X/Z = diameter, Y = length
Color:    Color3.fromRGB(30, 120, 220)
Material: SmoothPlastic
CanCollide: false
```

In Roblox, `Enum.PartType.Cylinder` orients the cylinder along the X axis, so
`Size = Vector3.new(length, diameter, diameter)` → `Vector3.new(0.8, 0.3, 0.3)`.

- [ ] **Step 1: Edit `createTaserHandleProcedural` in `init.server.luau`**

Replace lines 76-82 so the function reads:

```lua
local function createTaserHandleProcedural(tool)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(0.8, 0.3, 0.3)
	handle.Color = Color3.fromRGB(30, 120, 220)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Parent = tool
end
```

> Note on axis: Roblox Cylinder extends along X. `Size.X` = length (0.8 studs), `Size.Y/Z` = diameter (0.3 studs each). This matches the spec's visual intent of a slender handheld taser.

- [ ] **Step 2: Commit**

```bash
git add src/server/init.server.luau
git commit -m "fix(taser): use cylinder shape for tool handle with correct dimensions"
```

---

## Task 2: Manual verification in Roblox Studio

Run `rojo serve` and open the place in Studio. Play-test each spec item:

- [ ] **V1 — Tool in hand on spawn**
  - Press Play. The blue cylinder taser must be in the player's right hand immediately, without pressing any key.
  - Expected: Tool visible in hand, not needing selection.

- [ ] **V2 — Cylinder model visible**
  - Check third-person camera. The Handle must look like a short blue cylinder (not a block).

- [ ] **V3 — NPC shoot (no animation ID)**
  - Move player into Guard_2's range. Guard_2 must enter ATTACKING state and fire the projectile silently (no animation, no console errors).

- [ ] **V4 — Player shoot (no animation ID)**
  - Click to activate the taser. A projectile fires. No animation plays, no console errors.

- [ ] **V5 — Respawn**
  - Die (fall off the map or use Studio's reset). On respawn the taser must appear in hand automatically.

- [ ] **V6 — Zero console errors**
  - Output window must show no errors or warnings from the taser system throughout all steps above.

- [ ] **Step 3: Commit verification result**

If all checks pass:
```bash
git commit --allow-empty -m "chore(taser): all spec verification items pass"
```

---

## Self-Review against spec

| Spec section | Covered by |
|---|---|
| A. Tool visual (server-side): create Handle procedurally | Task 1 |
| A. Handle: Cylinder, Size (0.3, 0.8, 0.3), blue, SmoothPlastic | Task 1 |
| A. Respawn repeats equip | already done |
| B. `shootAnimationId` placeholder in TaserConfig | already done |
| B. `Pawn:PlayAnimationOnce` for NPC | already done |
| B. `UpdateAttackingTaser` calls `PlayAnimationOnce` | already done |
| B. Client animation via Animator on Activated | already done |
| B. Silent fallback when ID empty | already done |
| Verification checklist (all 7 items) | Task 2 |
