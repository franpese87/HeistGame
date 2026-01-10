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
The AI uses 6 states with defined transitions:
- `PATROLLING` → `OBSERVING` → `PATROLLING` (patrol loop)
- `PATROLLING/OBSERVING` → `CHASING` → `ATTACKING` (combat)
- `CHASING` → `INVESTIGATING` → `RETURNING` → `PATROLLING` (target lost)

### Component-Based Sensors
- **VisionSensor**: Raycasting with vision cone, detection accumulator, coyote time
- **HearingSensor**: Listens to NoiseService events, configurable range
- **CombatSystem**: Attack range validation, cooldowns, damage application

### Navigation System (2.5D)
- A* pathfinding algorithm
- Spatial hashing (2D grid per floor) for O(1) nearest-node lookup
- Multi-floor support via Floor_0, Floor_1, etc. folders
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
2. `NPCSpawnList.lua` - Per-NPC overrides

Key configurable values:
- `detectionRange`, `attackRange`, `loseTargetTime`
- `patrolSpeed`, `chaseSpeed`
- `observationConeAngle`, `observationAngles`
- Patrol routes via node names

## Conventions

- File naming: `*.lua` for modules, `*.client.luau` / `*.server.luau` for scripts
- Navigation nodes organized in `NavigationNodes/Floor_X` folders
- NPCs tagged via CollectionService for detection
- Debug visualization controlled via `DebugConfig.lua`

## Update Loop

NPCManager runs at 30 fps:
1. `UpdateSenses()` - Run vision and hearing sensors
2. State-specific update - Execute current state behavior
3. Handle state transitions based on sensor results

## Important Notes

- All game logic runs server-side (FilteringEnabled)
- NoiseService uses Signal pattern for efficient global noise detection
- Spatial hash cell sizes: 16x14 studs (configurable)
- **Maximum 8 connections per navigation node** (updated from 6 for complete grid connectivity)
- All components use Janitor for automatic memory cleanup
- **NodeGenerator plugin creates persistent Beams** in `NavigationNodes/_ConnectionBeams`
  - Beams are reused by debug system when both `showNodes` and `showConnections` are enabled
  - Auto-cleaned when either setting is disabled

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