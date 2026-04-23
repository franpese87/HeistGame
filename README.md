# Heist Game

A Roblox-based game project featuring a sophisticated, modular NPC AI system for creating intelligent guard behaviors. This project serves as a robust template for developing stealth and action games where NPC awareness and reaction are key.

## Features

The core of this project is a server-side NPC AI system with the following features:

-   **State Machine:** NPCs operate on a state machine, transitioning between states like `Patrolling`, `Observing`, `Chasing`, `Attacking`, and `Returning`.
-   **Navigation System:** Utilizes a node-based navigation graph for pathfinding.
    -   **A* Pathfinding:** Implements the A* algorithm to find the shortest path between nodes.
    -   **3D Spatial Hashing:** Optimizes nearest-node lookups for better performance.
    -   **Dynamic Graph Generation:** Creates the navigation graph automatically from `BasePart`s placed in the workspace.
-   **Advanced Detection:**
    -   **Vision Cone:** NPCs have a configurable vision cone for line-of-sight detection.
    -   **Occlusion Checks:** Raycasting is used to check for physical obstructions.
    -   **Coyote Time & Detection Buffer:** A "coyote time" buffer prevents immediate target loss, and a detection accumulator ensures a target must be visible for a minimum time before being confirmed.
-   **Configurable Behavior:**
    -   NPC behavior is highly configurable through Lua files (`NPCBaseConfig.lua`, `NPCSpawnList.lua`).
    -   Easily define patrol routes, detection ranges, speeds, and more.
-   **Animation Control:** A dedicated `NPCAnimator` module manages animations based on the NPC's state (idle, walk, run).
-   **Debugging Tools:** Comprehensive visual debugging tools to display the navigation graph, spatial hash cells, connections, and NPC state indicators directly within Roblox Studio.

## Project Structure

The project follows a clear, organized structure, separating client, server, and shared logic.

```
HeistGame/
├───.gitignore
├───aftman.toml
├───default.project.json
├───HeistGame.rbxl
├───package.json
├───README.md
├───selene.toml
├───.claude/
├───.git/
├───node_modules/
├───src/
│   ├───client/
│   │   └───init.client.luau
│   ├───server/
│   │   ├───init.server.luau
│   │   ├───Config/
│   │   │   ├───DebugConfig.lua
│   │   │   ├───NPCBaseConfig.lua
│   │   │   └───NPCSpawnList.lua
│   │   └───NPCAISystem/
│   │       ├───DebugUtilities.lua
│   │       ├───init.lua
│   │       ├───NavigationGraph.lua
│   │       ├───NPCAIController.lua
│   │       ├───NPCAnimator.lua
│   │       ├───NPCManager.lua
│   │       └───Setup.lua
│   └───shared/
│       └───Hello.luau
```

## Configuration

The NPC AI system can be easily configured by modifying the files in `src/server/Config/`:

-   **`NPCBaseConfig.lua`**: Change the default behavior for all NPCs, such as detection range, movement speed, and attack damage.
-   **`NPCSpawnList.lua`**: Define the specific NPCs to spawn in the game, including their names and patrol routes.
-   **`DebugConfig.lua`**: Enable or disable visual debugging features and console logging to inspect the AI's behavior in real-time.

## Getting Started

This project is managed with [Rojo](https://github.com/rojo-rbx/rojo).

1.  **Build the Place**:
    To build the Roblox place file from the source code, run:
    ```bash
    rojo build -o "HeistGame.rbxl"
    ```

2.  **Run the Rojo Server**:
    Open the generated `HeistGame.rbxl` file in Roblox Studio. Then, to sync your code changes live, start the Rojo server:
    ```bash
    rojo serve
    ```

For more information on using Rojo, refer to the [Rojo documentation](https://rojo.space/docs).
