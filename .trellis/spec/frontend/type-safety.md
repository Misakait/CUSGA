# Type Safety And Cross-Language Boundaries

CUSGA crosses between C#, GDScript, Godot resources, and wrapper nodes. Keep those boundaries explicit.

## Generated Enum Bridge

`SkillTargetingType` is the current cross-language enum pattern:

- Source of truth: `core/combat/skills/SkillTargetingType.cs`.
- Generator: `addons/skill_targeting_type_codegen/skill_targeting_type_codegen.gd`.
- Output: `scripts/generated/SkillTargetingType.gd`.
- Test: `tests/godot/skill_targeting_type_codegen_tests.gd`.

GDScript battle/card code should preload `scripts/generated/SkillTargetingType.gd` and use `SkillTargetingType.Value.*`. Do not parse C# source at runtime inside battle flow.

When changing `SkillTargetingType.cs`, regenerate the GDScript file and run the codegen test.

## C# Resource Types

GDScript often reads C# resource properties dynamically, for example `card_data.Skill.TargetingType` or `monster.MonsterName`. Guard dynamic reads with null checks where the current code already does so.

For new C# data used by GDScript:

- Use `[GlobalClass]` if the type must be created/assigned in Godot.
- Use exported properties for editor-visible fields.
- Prefer `StringName`, enums, `Array`, and `Dictionary` types that Godot serializes cleanly.
- Add a generated bridge or explicit wrapper if GDScript needs stable enum names or integer values.

## Wrapper Node Unwrapping

Battle GDScript may deal with wrapper nodes such as `PlayerManager` while C# effects need the real entity with `Components/...` children. `battle_manager.gd` uses `_unwrap_combat_entity` and comments why this is required before building `SkillExecutionContext`.

When adding combat behavior in GDScript, pass real C# entity nodes into C# contexts and effects. Do not pass UI wrappers unless the C# API explicitly expects wrappers.

## Dynamic Boundary Guards

Use `has_method`, `has_signal`, `get_node_or_null`, `is_instance_valid`, and null checks at C#/GDScript boundaries. Existing examples:

- `passage_guard_controller.gd` checks methods and signals before requesting passage guard combat.
- `card_manager.gd` checks whether cards have `Skill` and `TargetingType`.
- `battle_manager.gd` checks component availability before reading speed.
- `DamageEffect` validates damage candidates and handles missing `DamageReceiverComponent` with a warning.

Do not turn these dynamic boundaries into unchecked calls unless tests prove the path is always present.
