# HeistGame - Claude Code Context

> **IMPORTANTE PARA CLAUDE**: Mantén este archivo actualizado cuando se realicen cambios significativos en la arquitectura, se añadan nuevos sistemas, o se modifique la estructura del proyecto.

## Development Principles

**CRITICAL - Read this first in every session:**

1. **Clean Architecture**
   - Maintain clear separation of responsibilities
   - Follow component-based patterns (State Machine, Sensors, Navigation, Combat as independent components)
   - Avoid circular dependencies
   - Don't mix logic from different systems

2. **Code Optimization**
   - Minimize costly operations in the 30fps update loop
   - Use efficient data structures (spatial hashing, caching, etc.)
   - Avoid unnecessary raycasts or redundant calculations
   - Be mindful of Roblox/Luau performance characteristics

3. **Clean Code**
   - No unnecessary abstractions or over-engineering
   - Delete dead code completely (no `-- removed` comments or `_unused` variables)
   - Single responsibility per function
   - Consistent naming with existing codebase
   - Only modify what's necessary for the task

4. **Changes Policy**
   - Only make requested changes
   - Don't refactor working code unless explicitly asked
   - Don't add unsolicited "improvements"
   - Document significant architectural decisions in this file

## Project Overview

HeistGame is a Roblox game project featuring an advanced NPC AI system with component-based architecture. The project uses **Rojo** for code synchronization and **Luau** (Roblox's typed Lua variant).

## Technology Stack

- **Language**: Luau/Lua
- **Build Tool**: Rojo 7.7.0-rc.1 (via Aftman)
- **Package Manager**: Wally
- **Linting**: Selene
- **Target Platform**: Roblox

### Dependencies (Wally)
- **janitor** (1.18.3) - Memory cleanup and lifecycle management
  - Integrated in: NPCAIController, NPCAnimator, HearingSensor, DebugToolsSetup
  - Manages: Tweens, animation tracks, event connections, GUI instances
- **signal** (2.0.0) - Efficient event system
  - Used in: NoiseService for global noise detection
  - Replaces previous listener registration pattern

## Build Commands

```bash
wally install                    # Install dependencies
rojo build -o "HeistGame.rbxl"  # Build place file
rojo serve                       # Live-sync with Studio
```

## Directory Structure

```
src/
├── client/                    # Client-side scripts (minimal)
│   ├── init.client.luau       # Client entry point
│   └── DebugNoiseTool.client.luau
├── server/                    # Server-side (all game logic)
│   ├── init.server.luau       # Server entry point
│   ├── Config/                # Configuration files
│   │   ├── NPCBaseConfig.lua  # Default NPC settings
│   │   ├── NPCSpawnList.lua   # NPC spawn definitions
│   │   └── DebugConfig.lua    # Debug visualization settings
│   ├── NPCAISystem/           # Core AI system
│   │   ├── NPCAIController.lua    # State machine logic
│   │   ├── NavigationGraph.lua    # A* pathfinding + spatial hashing
│   │   ├── NPCManager.lua         # NPC lifecycle management
│   │   ├── NPCAnimator.lua        # Animation system
│   │   ├── NoiseService.lua       # Global noise event system
│   │   ├── Setup.lua              # Initialization & spawning
│   │   ├── DebugUtilities.lua     # Debug visualization
│   │   └── Components/            # Modular components
│   │       ├── VisionSensor.lua   # Raycasting vision detection
│   │       ├── HearingSensor.lua  # Audio detection
│   │       └── CombatSystem.lua   # Attack/damage logic
│   └── Debug/
└── shared/                    # Shared utilities (minimal)
```

## Architecture Patterns

### Client/Server Separation
- **Server**: All NPC AI, state management, navigation, sensors, combat
- **Client**: Minimal - entry point and debug tools only

### NPC AI State Machine
The AI uses 8 states with defined transitions:
- `PATROLLING` → `OBSERVING` → `PATROLLING` (patrol loop)
- `PATROLLING/OBSERVING` → `ALERTED` → `CHASING` → `ATTACKING` (combat)
- `CHASING` → `INVESTIGATING` → `RETURNING` → `PATROLLING` (target lost)
- Any state → `STUNNED` → resumes previous state (door knockback, etc.)

**Per-NPC state configuration** (via Roblox Attributes on model):
- `initialState` (string): FSM starting state, default `"Patrolling"`
- `allowedStates` (string): comma-separated whitelist — transitions to unlisted states are silently blocked
- `disableSenses` (bool): bypasses vision/hearing update entirely (useful for sandbox testing)

### Component-Based Sensors
- **VisionSensor**: Raycasting with vision cone, detection accumulator, coyote time
- **HearingSensor**: Listens to NoiseService events, configurable range
- **CombatSystem**: Attack range validation, cooldowns, damage application

### Navigation System (2.5D)
- A* pathfinding algorithm
- **3D spatial hash** (`spatialGrid3D["x,y,z"]`) for O(1) nearest-node lookup
  - Cell key: `math.floor(pos / cellSize)` per axis — default 16×4×14 studs
  - `cellSizeY=4` separates stacked floors without fragmenting a single floor
  - Handles same-height zones (separate X/Z buckets) AND stacked floors (separate Y buckets)
  - `SearchGrid3D` searches 3×3×3 neighborhood (27 cells), uses full 3D distance
  - `floorYRanges` still computed from node data for `GetFloorFromPosition`
- Multi-floor support via `Floor_X_ZoneName` folders (one per zone per floor)
- Node connections validated via raycast

## Key Files to Understand

| File | Purpose |
|------|---------|
| `NPCAIController.lua` | Core AI state machine (~637 lines) |
| `NavigationGraph.lua` | Pathfinding & spatial optimization (~756 lines) |
| `NPCBaseConfig.lua` | Default NPC configuration values |
| `Setup.lua` | NPC spawning and initialization |
| `VisionSensor.lua` | Vision detection implementation |

## Configuration System

NPCs use layered configuration:
1. `NPCBaseConfig.lua` - Base defaults for all NPCs
2. Roblox Attributes on each NPC model - Per-NPC overrides (any key from NPCBaseConfig)

`NPCSpawnList.lua` is **deprecated** — kept for reference and programmatic spawning only.
NPCs are now placed directly in workspace with tag `"NPC"` and discovered via CollectionService.

Key configurable values (NPCBaseConfig defaults, overridable per-model via Attributes):
- `detectionRange`, `attackRange`, `loseTargetTime`
- `patrolSpeed`, `chaseSpeed`
- `observationConeAngle`, `observationAngles`
- `initialState`, `allowedStates`, `disableSenses` — FSM sandbox controls
- `enablePathSmoothing`, `agentRadius` — navigation quality
- `patrolRoute` (string Attribute): comma-separated node names, e.g. `"Node_0_1, Node_0_5"`
- `snapToFirstPatrolNode` (bool Attribute): teleport NPC to first patrol node on init

## Conventions

- File naming: `*.lua` for modules, `*.client.luau` / `*.server.luau` for scripts
- Navigation nodes organized in `NavigationNodes/Floor_X_ZoneName` folders (one per zone/room per floor)
  - Folder name format must start with `Floor_X` (integer) for the graph loader to detect floor number
  - Zone name is free-form (matches the zone part name in `NodeZones`)
- NPCs placed in workspace with CollectionService tag `"NPC"`, R15 rigs only
- NPC configuration via Roblox Attributes on the model (no Lua edits required)
- Debug visualization controlled via `DebugConfig.lua`

## Update Loop

NPCManager runs at 30 fps:
1. `UpdateSenses()` - Run vision and hearing sensors
2. State-specific update - Execute current state behavior
3. Handle state transitions based on sensor results

## Important Notes

- All game logic runs server-side (FilteringEnabled)
- NoiseService uses Signal pattern for efficient global noise detection
- **3D spatial hash cell sizes: 16×4×14 studs** (X×Y×Z, configurable via `cellSizeX/Y/Z`)
  - `cellSizeY=4` is the vertical resolution — must be < floor separation, > intra-floor Y variance
- **Maximum 8 connections per navigation node** (4 cardinal + 4 diagonal)
- All components use Janitor for automatic memory cleanup
- **NodeGenerator plugin creates persistent Beams** in `NavigationNodes/_ConnectionBeams`
  - Beams are reused by debug system when both `showNodes` and `showConnections` are enabled
  - Auto-cleaned when either setting is disabled
- **NPCs are R15 only** — Motor6Ds: `Head.Neck` (head rotation) + `UpperTorso.Waist` (torso rotation)
  - Animation IDs come from `AnimationRegistry.R15_DEFAULT` in `src/shared/Animation/`

## Recent Implementation Changes

### Memory Safety Improvements (2025-12-24)
- **Integrated Janitor** across all major components for automatic cleanup
  - NPCAIController: Manages animator, tweens, state indicators
  - NPCAnimator: Manages animation tracks
  - HearingSensor: Manages Signal connections
  - DebugToolsSetup: Manages RemoteEvent connections
- **Migrated NoiseService to Signal** for better performance
  - Replaced manual listener registration with Signal pattern
  - HearingSensor now connects directly to `NoiseService.NoiseDetected:Connect()`
  - More efficient than previous iteration-based approach
- **Fixed Rojo configuration**
  - Removed non-existent DevPackages reference from default.project.json
  - Packages folder now syncs correctly to ReplicatedStorage

### NodeGenerator Plugin Improvements (2026-01-10)
- **Added Editor Mode** with visual connection display using Beams
  - Toggle button in plugin UI to show/hide node connections
  - Beams stored in `NavigationNodes/_ConnectionBeams` folder
  - Auto-cleanup when using "Clear" button
- **Increased max connections from 6 to 8**
  - Ensures complete 8-directional connectivity in grid (4 cardinal + 4 diagonal)
  - Fixes irregular connection patterns in obstacle-free areas
- **Integration with debug system**
  - `Visualizer.DrawConnections()` now reuses plugin Beams if present
  - Beams automatically maintained when `showNodes=true` and `showConnections=true`
  - Beams removed when either debug option is disabled
- **Removed obsolete NodeGenerator.lua** (Command Bar version replaced by plugin)

### Path Smoothing Implementation (2026-01-10)
- **Line-of-Sight (LOS) post-processing** for smoother NPC navigation
  - Eliminates intermediate nodes when direct visibility exists
  - Uses "string-pulling" approach: finds farthest visible node and skips to it
- **Multi-raycast validation** for agent width
  - Center ray + left/right/up rays based on `agentRadius`
  - Prevents clipping through corners
- **Floor-aware smoothing**
  - Only smooths between nodes on the same floor
  - Preserves all waypoints on stairs for safety
- **Configuration in NPCBaseConfig**
  - `enablePathSmoothing`: Toggle feature (default: true)
  - `agentRadius`: Agent width for LOS checks (default: 1.0)
- **Files modified**
  - `NavigationGraph.lua`: Added `SmoothPath()` function
  - `Controller.lua`: Integrated smoothing after A* path calculation
  - `NPCBaseConfig.lua`: Added configuration options

### 3D Spatial Hash for Navigation Graph (2026-04-12)
- **Replaced 2D-per-floor hash with unified 3D hash** (`spatialGrid3D["x,y,z"]`)
  - Previous approach used separate 2D grids per floor — failed when multiple zones shared the same physical height
  - New approach: single grid keyed by `(X/cellSizeX, Y/cellSizeY, Z/cellSizeZ)` integer buckets
  - `SearchGrid3D` searches 27-cell 3×3×3 neighborhood, returns nearest node by 3D Euclidean distance
  - Correctly handles same-height zones (different X/Z buckets) AND stacked floors (different Y buckets)
  - `cellSizeY=4` default — configurable via `NavigationGraph.new({ cellSizeY = N })`
- **`floorYRanges`** still computed from node data for `GetFloorFromPosition` (external use)
- **Files modified**: `NavigationGraph.lua`, `Visualizer.lua` (`DrawCells`, `PrintSystemReport`)

### World-Placed NPCs + Configurable FSM + R15 (2026-04-12)
- **NPCs placed directly in workspace** — no more template cloning from ServerStorage
  - Discovery via CollectionService tag `"NPC"` (`Factory.InitializeWorldNPCs`)
  - Configuration read from Roblox Attributes on each model (`Factory._ReadNPCConfig`)
  - `NPCSpawnList.lua` deprecated (kept for programmatic spawning reference)
- **Configurable FSM per NPC** via Attributes:
  - `allowedStates`: comma-separated whitelist — `ChangeState()` silently blocks unlisted transitions
  - `initialState`: FSM starting state (validated, falls back to Patrolling with warn)
  - `disableSenses`: skips `UpdateSenses()` entirely when true
- **R15 migration**: Motor6Ds now `Head.Neck` + `UpperTorso.Waist` (was `Torso.Neck` + `HumanoidRootPart.RootJoint`)
  - Animation IDs from shared `AnimationRegistry.R15_DEFAULT`
- **Files modified**: `Factory.lua`, `Controller.lua`, `Pawn.lua`, `NPCBaseConfig.lua`, `init.server.luau`

### NodeGenerator Plugin — Zone-per-Folder (2026-04-12)
- **Each NodeZone gets its own subfolder** `Floor_X_ZoneName` in NavigationNodes
  - Previously all zones with the same `floor` Attribute shared a single `Floor_X` folder
  - New folder name format preserves floor number at the start for regex compatibility
- **Global node counter per floor** (`nodeCountByFloor`) passed across zones — guarantees unique node names even when two zones share the same floor number
- **Fixed `autoConnectNodes` accumulation bug**: `nodesByFloor[floor] = {}` → `nodesByFloor[floor] = nodesByFloor[floor] or {}` so multi-zone floors accumulate all nodes for connection
- **Files modified**: `NodeGeneratorPlugin.server.lua`

### VisionSensor Refactoring (2026-01-12)
- **Simplified target detection to Players only**
  - Removed NPC vs NPC detection (CollectionService "Entity" tag system)
  - Eliminated team/faction logic from `IsValidTarget()`
  - Game design: Players vs NPCs only (no inter-NPC combat)
  - Removed `Registry:GetNPCsByTeam()` unused function
- **Modular detection pipeline** (optimized for performance)
  - **Phase 1: Distance Check** - Magnitude calculation (most efficient)
  - **Phase 2: Vision Cone Check** - Dot product angle validation (moderate cost)
  - **Phase 3: Line of Sight Check** - Raycast occlusion (most expensive)
  - Early exit at each phase if check fails (avoids unnecessary computations)
- **Comprehensive debug visual system**
  - `showDetectionRadius`: Sphere showing detection range (Phase 1)
  - `showVisionCone`: WedgePart showing NPC's field of view (Phase 2)
  - `showLineOfSight`: Raycasts showing occlusion checks (Phase 3)
  - `showAllChecks`: Visualize failed checks (red/yellow for debugging)
  - `showDetectionInfo`: Real-time stats label (targets checked, phase results)
- **Persistent vs temporary visuals**
  - Detection sphere and vision cone update every frame
  - Raycasts and phase markers are temporary (0.05s duration)
  - Debug instances stored in `self.debugInstances` for cleanup
- **Configuration in DebugConfig**
  - All visual options configurable per-phase
  - Integrated with Controller debug setup
- **Files modified**
  - `VisionSensor.lua`: Complete rewrite with modular architecture
  - `DebugConfig.lua`: Updated with new visual options
  - `Controller.lua`: Updated debug initialization
  - `Registry.lua`: Removed team-based functions