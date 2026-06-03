# Directory Structure

CUSGA is a Godot 4.6 C# project, not a web backend. Treat `backend` specs as the C# gameplay/runtime layer.

## Top-Level Ownership

- `core/application/` owns runtime ports and application-level managers, such as `GameplayPort` and `EncounterManager`.
- `core/gameflow/` owns world-to-combat flow and interaction orchestration, such as `WorldInteractionCoordinator` and `TerrainInteractionExecutor`.
- `core/combat/` owns combat formulas, skill execution, card effects, status hooks, and combat enums.
- `core/crafting/`, `core/map/`, and `core/inventory/` own focused gameplay rules that are reused by components and UI.
- `entities/` owns scene-backed entity nodes. `Player.cs` and `Monster.cs` cache child components from stable `Components/...` paths.
- `entities/components/` owns reusable Godot `Node` components such as inventory, equipment, attributes, status, health, energy, tags, and damage receiving.
- `resources/` owns Godot `Resource` data classes. These classes are usually `[GlobalClass]` and configured through `.tres` files.
- `core/ui/` owns C# `Control` UI classes that bind to gameplay components.
- `tests/CUSGA.Tests/` owns the current C# console-style test runner.

## Placement Rules

Put pure or mostly pure rules in `core/<system>/` when they can be tested without a scene tree. `CraftingService` is the current example: it depends on `ICraftingInventory` instead of directly coupling to `InventoryComponent`.

Put scene lifecycle and signal wiring in `Node`/`Control` classes. Examples include `GameplayPort`, `WorldInteractionCoordinator`, `InventoryUI`, and entity components.

Put editable game data in `resources/**` as Godot `Resource` classes, then reference those resources from scenes or `.tres` assets. Do not encode new content tables into manager classes when an existing resource type can own the data.

Put test-only stubs and helper classes inside the relevant test file unless there is already a reusable production abstraction. `tests/CUSGA.Tests/Program.cs` keeps `TestCraftingInventory`, resource stub factories, and `Assert` local to the runner.

## Naming Patterns

- Entity runtime state classes end with `Component` when they are Godot child nodes under `Components/`.
- Editable data classes usually end with `Data`, `Rule`, `Settings`, `Profile`, `Entry`, or `Recipe`.
- Terrain interaction steps end with `Op` and inherit `TerrainOp`.
- UI classes end with `UI` or describe a concrete UI control, such as `SlotUI` and `EquipmentSlotUI`.
- C# namespaces mirror folders under `CUSGA`, for example `CUSGA.core.gameflow` and `CUSGA.resources.interaction`.

## Avoid

- Do not add web/server folders such as `controllers`, `routes`, `repositories`, or `migrations`; no such layer exists.
- Do not put GDScript files under C# `core/**` unless the current directory already contains GDScript autoloads.
- Do not bypass the `Components/...` child-node convention for new entity components without changing the scene and tests together.
