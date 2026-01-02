# Node Generator Plugin

Plugin de Roblox Studio para generar nodos de navegación de forma visual.

## Compilación

Desde la raíz del proyecto:

```bash
rojo build plugin.project.json -o NodeGeneratorPlugin.rbxm
```

## Instalación

1. Copiar `NodeGeneratorPlugin.rbxm` a la carpeta de plugins de Roblox:

   **Windows:**
   ```
   %LOCALAPPDATA%\Roblox\Plugins
   ```

   **Mac:**
   ```
   ~/Documents/Roblox/Plugins
   ```

2. Reiniciar Roblox Studio

## Uso

### Preparación del workspace

1. Crear carpeta `NodeZones` en workspace
2. Dentro de `NodeZones`, crear Parts que delimiten las áreas de navegación
3. Cada Part debe tener el atributo `floor` (number) indicando el piso

```
workspace/
├── NodeZones/
│   ├── Floor0Zone (Part, floor=0)
│   ├── Floor1Zone (Part, floor=1)
│   └── StairsZone (Part, floor=0)
```

### Generar nodos

1. Click en el botón **"Node Generator"** en la toolbar de Studio
2. Ajustar el **spacing** (distancia entre nodos, default: 2 studs)
3. Click en **"Generate"**

Los nodos se crearán en `workspace/NavigationNodes/Floor_X/`

### Limpiar nodos

Click en **"Clear"** para eliminar todos los nodos generados.

## Configuración de zonas

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `floor` | number | **Requerido.** Número de piso (0, 1, 2...) |
| `spacing` | number | Opcional. Override del spacing para esta zona |

## Comportamiento

- Los nodos son cubos de **1x1x1 studs**
- Se posicionan en la **base** de cada zona
- El spacing se **ajusta automáticamente** para que los nodos encajen exactamente en los límites de la zona
- Cada piso tiene un **color diferente** para fácil identificación

## Colores por piso

| Piso | Color |
|------|-------|
| 0 | Verde |
| 1 | Azul |
| 2 | Naranja |
| 3 | Rosa |
| 4+ | Gris |

## Alternativa: Command Bar

El script `tools/NodeGenerator.lua` puede copiarse manualmente a `ServerScriptService` para usar desde la Command Bar:

```lua
local gen = require(game.ServerScriptService.NodeGenerator)
gen.Generate()     -- spacing 2 por defecto
gen.Generate(5)    -- spacing personalizado
gen.Clear()        -- eliminar nodos
```
