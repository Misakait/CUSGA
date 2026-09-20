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

When adding an optional exported `StringName` to a resource that already has saved `.tres` instances, treat the runtime value as nullable even if the field initializer uses `StringName.Empty`. Older resources can deserialize the new field as null until they are saved again. Use null-safe checks such as `tag is not null && !tag.IsEmpty` before calling `IsEmpty`, and add a regression test when the field controls runtime behavior.

## Display Fallbacks

Follow the existing fallback chain for card-like data:

- `BaseCardData` exposes `DisplayName`, `DisplayDescription`, and `DisplayIcon`.
- `SkillCardData` prefers its own card fields, then falls back to the linked `CombatSkillData`. During the mixed-language phase, GDScript must read the retained C# skill's exported `CardName`, `Description`, and `CardIcon`; inherited non-exported `Display*` computed properties are not a stable `Variant.get()` protocol.
- GDScript `skill_card.gd` displays the combat skill element from `SkillCardData.Skill` so UI and combat data stay aligned.

New UI display fields should reuse these display properties instead of rereading raw resource fields in several places.

## Tags And Identifiers

Use `StringName` for stable gameplay identifiers such as `CardId`, item tags, status IDs, and gathering tags. Use exact tags for explicit behavior gates.

`EquipmentComponent` currently still supports identifier-fragment fallback for legacy equipment slots, but `MagicItem` requires `TagConsts.MagicItem`. Prefer explicit tags and valid slot data for new equipment resources.

## Generated Data Boundaries

`scripts/generated/SkillTargetingType.gd` is generated from `core/combat/skills/SkillTargetingType.cs` by `addons/skill_targeting_type_codegen`. Do not edit generated files by hand. If the C# enum changes, regenerate and run the codegen Godot test.

## Migrated Loot Entries

`resources/loot/loot_drop.gd` is the serialized data form for one loot entry. Keep the
field names `Item`, `DropChance`, `MinAmount`, and `MaxAmount` stable so existing
monster and terrain assets retain their values. Production monster and terrain assets
use `resources/loot/loot_table.gd`, which consumes entries through a generic `Resource`
boundary and owns random rolls only; do not move inventory side effects into the data
Resource.

The production GDScript LootTable creates `resources/item/item_stack.gd` and stores the
original item as a generic `Resource`. The board and pickup pipeline accepts both this
stack and retained C# `ItemStack` through the stable `Item`, `Amount`, `IsEmpty`,
`SetItem`, and `Clear` protocol. `MonsterData.LootTable` remains a generic `Resource`
so old C# and production GDScript tables can coexist. Keep `LootTable.cs`,
`ItemStack.cs`, and their UIDs as compatibility inputs until all legacy interactions,
debug factories, and item resources have migrated.

## Migrated Room Terrain Pool Entries

`core/map/room_terrain_pool_entry.gd` is the serialized form for one terrain-pool
candidate. Keep `TerrainData` and `Weight` names stable, with `Weight = 1.0` as
the neutral default. The profile and layout generator currently accept generic
`Resource` entries so old C# `RoomTerrainPoolEntry` instances remain usable in
tests while `.tres` and `.tscn` assets move to GDScript. Keep weighted sampling
and invalid-entry filtering in `RoomTerrainLayoutGenerator`; the Resource should
only hold editable configuration.

## Migrated Room Terrain Profiles

`core/map/room_terrain_profile.gd` is the serialized form for room terrain
layout settings. Keep the field names `TerrainPool`, `MinCount`, `MaxCount`,
`GridColumns`, `GridRows`, `PlacementMin`, `PlacementMax`, and
`EncounterVarianceRange` stable so existing terrain `.tres` and map `.tscn`
values remain intact. `TerrainPool` is an `Array[Resource]` during migration;
its entries use `core/map/room_terrain_pool_entry.gd` while legacy C# profiles
remain valid through the compatibility overload.

The profile must not perform random selection or scene mutation. Keep layout
clamping, weighted sampling, invalid-entry filtering, and multiplier sampling
in `RoomTerrainLayoutGenerator`; use generic Resource reads at that boundary so
GDScript and C# assets can coexist until all callers have migrated.

## Migrated Debug Loadout Resources And Seeder

### 1. Scope / Trigger

- Trigger: `default_inventory_loadout.tres` and Main's startup Seeder move to GDScript while production inventory, equipment, item data, and ItemStack remain C#.
- Scope: the three DebugLoadout data Resources, `debug_loadout_seeder.gd`, the default `.tres`, and the Main node reference.
- Out of scope: ItemData/EquipmentData/ItemStack migration, inventory rules, equipment effects, and StartingStats calculations.

### 2. Signatures

```gdscript
@export var InventoryItems: Array[Resource]
@export var BattleDeckItems: Array[Resource]
@export var InventoryEquipment: Array[Resource]
@export var EquippedEquipment: Array[Resource]
func CreateStack() -> RefCounted
func ApplyLoadout() -> void
```

### 3. Contracts

- Preserve the PascalCase serialized names and all existing array order, amounts, slots, attribute ranges, icons, and gathering fields.
- Fixed item entries must return the retained C# `ItemStack` and pass the original C# `ItemData` Resource without cloning; identity is required by stacking, recipes, and item comparisons.
- Generated equipment entries instantiate the retained C# `EquipmentData` or `ToolData`, then wrap it in the retained C# `ItemStack`. Any non-empty gathering tag, positive yield growth, or positive time reduction selects `ToolData`.
- The Seeder reads player components as `Node` and uses `Capacity`, `GetStackAt`, `TrySetStackAt`, `TryClearStackAt`, `Equip`, `Unequip`, `InitialData`, and `InitializeWithData` as the migration protocol.
- Legacy C# DebugLoadout classes remain compatibility shims until the item chain and all C# tests have migrated.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Item is null or amount is non-positive | `CreateStack` returns null and the Seeder skips it |
| Loadout or Player is missing | Warn and do not mark `ApplyOnce` complete |
| Inventory is missing | Warn and stop before partial filling |
| BattleDeck, Equipment, or AttributeComponent is missing | Skip only that optional branch |
| Existing `InitialData` is non-null | Do not overwrite player starting stats |
| Inventory has no empty slot | Warn with item and inventory names |
| Editor `@tool` test loads a C# `.tres` as base `Resource` | Instantiate the C# data script directly for typed-call tests; verify real `.tres` behavior in a running Main scene |

### 5. Good / Base / Bad Cases

- Good: the default resource keeps all 10 inventory items, 4 deck cards, 6 inventory equipment entries, and 2 equipped entries; Main produces the same C# runtime objects through the GDScript Seeder.
- Base: an empty array or null entry produces no side effect, and `ApplyOnce=true` suppresses a second application.
- Bad: cloning a legacy `.tres` into a new ItemData instance makes identity-based recipes and stacking diverge; returning a GDScript ItemStack to the current C# InventoryComponent causes a typed parameter mismatch.

### 6. Tests Required

- Resource contract: assert production script paths, entry counts, representative quantities, slots, tags, and reductions.
- Factory contract: assert fixed entries return C# ItemStack with original ItemData identity; generated entries return the correct C# EquipmentData/ToolData with slots and attributes.
- Seeder contract: assert clear counts, fill order, starting-stat initialization, all 16 equipment slots, and ApplyOnce.
- Runtime contract: run `scenes/Main.tscn` through GodotAI and assert the real inventory/deck contents, retained item identity, generated equipment types, and applied attribute effects.

### 7. Wrong vs Correct

```gdscript
# Wrong: current C# InventoryComponent cannot receive the parallel GDScript stack,
# and copying ItemData breaks identity-based game rules.
var stack = preload("res://resources/item/item_stack.gd").new()
stack.SetItem(Item.duplicate(), Amount)
```

```gdscript
# Correct: keep the compatibility type and the original item Resource until the item chain migrates.
var stack = preload("res://core/inventory/ItemStack.cs").new()
stack.call("SetItem", Item, Amount)
```

## Migrated Item And Resource Card Data

- 普通物品生产资产使用 `resources/item/item_data.gd`，资源卡生产资产使用 `resources/item/card/resource_card_data.gd`；资源卡脚本只继承 ItemData，不拥有额外玩法逻辑。
- 迁移普通物品或资源卡时必须保留 `CardId`、`CardName`、`Description`、`CardIcon`、`MaxStackSize`、`BuyPrice`、`SellPrice` 与 `ItemTags` 的原值。资源卡未显式覆盖时，默认值仍为最大堆叠 99、买价 0、卖价 0 和空标签数组。
- `.tres` 切换到 GDScript 时必须同时清理旧 `script_class` 与 `metadata/_custom_type_script`，避免磁盘资源继续声明已经不再使用的 C# 自定义类型。测试加载资源时使用替换缓存模式，不能用编辑器旧 Resource 缓存中的元数据判断磁盘迁移是否完成。
- 消费者应通过通用 Resource/ItemData 字段协议读取普通物品和资源卡。`ItemData.cs` 与 `ResourceCardData.cs` 在跨语言调用和全部旧资产完成迁移前继续作为兼容输入，不得提前删除。
- `SkillCardData` 仍连接 `CombatSkillData` 与战斗执行，不能按普通资源卡批量切换；必须先把卡组、GameplayPort、战斗入口和 C# 强类型调用降到可验证的动态兼容边界。

## Skill Card Dynamic Migration Boundary

### 1. Scope / Trigger

- 当 SkillCardData 的 Resource 脚本或生产资产从 C# 切换到 GDScript 时，玩家卡组、遭遇端口和战斗场景之间必须先使用通用 Resource 协议。
- 该边界只迁移卡牌包装层；`CombatSkillData`、`SkillExecutionContext`、目标解析和 CardEffect 结算继续由现有战斗实现拥有。

### 2. Signatures

```gdscript
@export var Skill: Resource
@export var cost: int = 10
@export var CardTags: Array[String] = []
func ApplyEffect(context: RefCounted) -> void
func GetPlayerSkillCards() -> Array[Resource]
@export var starting_deck_data: Array[Resource]
```

```csharp
public Array<Resource> GetPlayerSkillCards();
public Task EnterCombatAsync(Array<Resource> battleDeck, Array<MonsterData> monsters);
```

### 3. Contracts

- GDScript SkillCardData 继承 `item_data.gd`，实际堆叠上限固定为 1；`MaxStackSize` 原始默认值仍为 99，不用修改序列化字段模拟 C# 虚属性。
- `DisplayName`、`DisplayDescription` 与 `DisplayIcon` 优先使用卡牌自身字段，再分别回退到 Skill 的导出字段 `CardName`、`Description`、`CardIcon`；不得用 GDScript 动态读取 C# `BaseCardData` 的非导出计算属性 `Display*`。`DisplayTag` 过滤空白标签后按换行连接；`Element` 读取 Skill 的导出字段，缺失时为 0。
- 卡组入口只接受具有 `ApplyEffect` 方法的 Resource，并在 GameplayPort、WorldInteractionCoordinator、WorldCombatScenePresenter、BattleManager、DeckManager 和 SkillCard 之间保持原 Resource 身份与顺序。
- `ApplyEffect` 只记录卡牌日志并调用 `Skill.Execute(context)`；不得复制目标选择、状态 Hook、伤害或效果遍历。
- 旧 `SkillCardData.cs` 和仍强类型依赖它的 BattleDeckComponent.cs、InventoryUI.cs 作为旧链兼容输入保留，直到对应 C# 生产路径不再需要。

### 4. Validation & Error Matrix

| 输入 | 行为 |
| --- | --- |
| C# SkillCardData | 作为 Resource 进入卡组并保持身份 |
| GDScript SkillCardData | 通过 `ApplyEffect` 协议进入同一卡组和战斗入口 |
| Skill 为保留的 C# CombatSkillData | 显示回退只读取 `CardName` / `Description` / `CardIcon` 导出字段；非导出 `Display*` 返回空不得覆盖有效序列化值 |
| 普通 Resource / 非 Resource | 在 GameplayPort/C# 协调器边界过滤，不进入战斗 |
| Skill 为空 | `ApplyEffect` 报配置错误并停止，不伪造结算 |
| Skill 缺少 `Execute` | 报稳定协议错误并停止 |
| context 为空 | 报执行上下文错误并停止 |

### 5. Good / Base / Bad Cases

- Good：同一数组包含旧 C# 与新 GDScript 技能卡，遭遇转发、抽牌、展示和弃牌均保持顺序及 Resource 身份，最终仍调用 C# CombatSkillData。
- Base：空卡组进入战斗时仍由 DeckManager 按原基础卡池规则补足，不改变费用和洗牌规则。
- Bad：在任一入口把数组重新收紧为 `Array[SkillCardData]` 或用 `is SkillCardData` 过滤；GDScript 资产会在进入战斗前被静默丢弃。

### 6. Tests Required

- Resource 契约：默认费用 10、空标签、实际堆叠 1、显示字段/图标回退、标签过滤、Element 与 ApplyEffect 委托；必须实例化真实 C# `CombatSkillData`，写入三个导出显示字段并断言 GDScript 回退值与 Resource 身份。
- 端口契约：同一动态数组混入 C# 卡、GDScript 卡和无效对象，断言只过滤无效对象并保持两种合法卡的顺序与身份。
- 源码边界：断言 C# Presenter/协调器和 GDScript BattleManager/DeckManager/SkillCard 均使用 Resource 数组或 Resource 字段。
- 运行时：用 GodotAI 直接运行 battle.tscn 与 Main.tscn，确认旧生产卡仍能抽取/展示/结算，且无新增脚本、类型或信号错误。

### 7. Wrong vs Correct

```gdscript
# 错误：具体全局类型会丢弃已经迁移为 GDScript 的技能卡。
func GetPlayerSkillCards() -> Array[SkillCardData]:
	return raw_cards.filter(func(card): return card is SkillCardData)
```

```gdscript
# 正确：稳定方法协议同时承接两种语言的 Resource，并保留对象身份。
func GetPlayerSkillCards() -> Array[Resource]:
	var cards: Array[Resource] = []
	for card: Variant in raw_cards:
		if card is Resource and card.has_method("ApplyEffect"):
			cards.append(card as Resource)
	return cards
```

```gdscript
# 错误：C# 非导出计算属性不保证能通过动态 Variant 协议读取。
var fallback_name := Skill.get("DisplayName")

# 正确：读取 C# Resource 已导出且参与序列化的稳定字段。
var fallback_name := Skill.get("CardName")
```
