# Resource Data Guidelines

Game content is represented with Godot `Resource` classes and `.tres` assets. This is the project's data layer; there is no database or ORM layer.

## Resource Class Shape

Use `[GlobalClass] public partial class ... : Resource` or a resource-derived base when the data must be editable in Godot.

Current examples:

- `ItemData` and `BaseCardData` for card/item display fields.
- `EquipmentData` for valid slots, set type, attribute ranges, and granted tags.
- `MonsterData` for initial stats, element, loot table, behavior scene, faction, and skill set.
- `CraftingRecipe` for inputs, output item, and output amount.
- `TerrainInteraction` subclasses for editable interaction behaviors.
- `StatusEffectData` subclasses for buff/status configuration.

Use `Godot.Collections.Array` and `Godot.Collections.Dictionary` for exported collections that must serialize through Godot resources.

## Defaults

Give exported fields safe defaults when the current code expects them:

- Empty arrays or dictionaries should default to `[]`.
- Stackable item data defaults to `MaxStackSize = 99`; equipment overrides to one item per stack.
- Combat skills default to `ElementType.None`, `SkillTargetingType.SingleEnemy`, and empty effects.
- Status effects default to one stack, reset-duration policy, and start-tick duration timing.

If a field is required by runtime logic, add validation at the use site and test it. Do not rely only on editor discipline.

## Display Fallbacks

Follow the existing fallback chain for card-like data:

- `BaseCardData` exposes `DisplayName`, `DisplayDescription`, and `DisplayIcon`.
- `SkillCardData` prefers its own card fields, then falls back to the linked `CombatSkillData`.
- GDScript `skill_card.gd` displays the combat skill element from `SkillCardData.Skill` so UI and combat data stay aligned.

New UI display fields should reuse these display properties instead of rereading raw resource fields in several places.

## Tags And Identifiers

Use `StringName` for stable gameplay identifiers such as `CardId`, item tags, status IDs, and gathering tags. Use exact tags for explicit behavior gates.

`EquipmentComponent` currently still supports identifier-fragment fallback for legacy equipment slots, but `MagicItem` requires `TagConsts.MagicItem`. Prefer explicit tags and valid slot data for new equipment resources.

## Generated Data Boundaries

`scripts/generated/SkillTargetingType.gd` is generated from `core/combat/skills/SkillTargetingType.cs` by `addons/skill_targeting_type_codegen`. Do not edit generated files by hand. If the C# enum changes, regenerate and run the codegen Godot test.
