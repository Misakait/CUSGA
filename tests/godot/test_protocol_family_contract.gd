@tool
extends McpTestSuite

## 协议 / 接口族迁移契约套件。
##
## 锁定 6 个旧 C# 跨语言协议类（CardEffectProtocol / CombatSkillDataProtocol /
## AttributeModifierDataProtocol / StatusEffectDataProtocol / MonsterDataProtocol /
## TerrainInstanceProtocol / ItemStackProtocol）与 4 个 C#-only 接口（IDamageable /
## ICraftingInventory / IShopInventory / IPlayerWallet）的迁移边界：
##
## - 协议类是「C# 侧读取 GDScript 生产对象」的垫片，其 GDScript 等价物就是被读取的 GDScript
##   生产脚本本身（多数协议类显式声明了该脚本路径常量），因此本批不新增生产脚本。
## - 接口是 C#-only 契约（GDScript 无法实现 C# 接口），其 GDScript 等价物是组件上的同名方法协议。
## - 两侧共享面是「脚本路径 / 字段名 / 方法名」，本套件把这些名字逐条钉死：改名会立刻红。
## 旧 C# 协议类与接口继续保留给未迁移的 C# 消费方，全量迁移完成前不得删除；
## C# 物理退役后，协议类侧的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 协议类逐条契约：[名称, C# 路径, [[C# 必须存在的片段], …], [[GDScript 生产脚本, [必须存在的片段]], …]]。
const PROTOCOL_ROWS: Array = [
	[
		"ItemStackProtocol",
		"res://core/inventory/ItemStackProtocol.cs",
		[
			"HasMethod(SetItemMethod)",
			"HasMethod(ClearMethod)",
			"private static readonly StringName ItemProperty = \"Item\";",
			"private static readonly StringName AmountProperty = \"Amount\";",
			"private static readonly StringName IsEmptyProperty = \"IsEmpty\";",
		],
		[
			[
				"res://resources/item/item_stack.gd",
				[
					"var Item: Resource",
					"var Amount: int",
					"func SetItem(item: Resource, amount: int) -> void",
					"func Clear() -> void",
					"var IsEmpty: bool",
				],
			],
		],
	],
	[
		"TerrainInstanceProtocol",
		"res://resources/interaction/TerrainInstanceProtocol.cs",
		[
			"public static bool TryReadBool(RefCounted terrain, string fieldName, out bool value)",
			"public static void SetBool(RefCounted terrain, string fieldName, bool value)",
			"public static bool TryReadInt(RefCounted terrain, string fieldName, out int value)",
			"public static void SetInt(RefCounted terrain, string fieldName, int value)",
			"public static bool TryReadBoardPosition(RefCounted terrain, out Vector2 value)",
			"public static bool TryReadLocalGridPos(RefCounted terrain, out Vector2I value)",
			"public static Resource ReadTerrainData(RefCounted terrain)",
		],
		[
			[
				"res://resources/interaction/terrain_instance.gd",
				[
					"var LocalGridPos: Vector2i",
					"var BoardPosition: Vector2",
					"var TerrainData: Resource",
					"var IsHarvested: bool",
					"var GrowthStage: int",
					"var RemainingGatheringCount: int",
					"var RefreshReadyTotalTime: int",
				],
			],
		],
	],
	[
		"StatusEffectDataProtocol",
		"res://core/combat/status/StatusEffectDataProtocol.cs",
		[
			"public const string GdScriptPath = \"res://core/combat/status/status_effect_data.gd\";",
			"public static bool IsGdStatusEffectData(GodotObject value)",
			"public static StackPolicy ReadStackPolicy(Resource data)",
			"public static DurationExpirePolicy ReadExpirePolicy(Resource data)",
			"public static DurationTickTiming ReadTickTiming(Resource data)",
			"public const string Id = \"Id\";",
			"public const string Policy = \"Policy\";",
			"public const string ExpirePolicy = \"ExpirePolicy\";",
			"public const string DurationTickTiming = \"DurationTickTiming\";",
		],
		[
			[
				"res://core/combat/status/status_effect_data.gd",
				[
					"@export var Id: StringName",
					"@export var DisplayName: String",
					"@export var Description: String",
					"@export var Icon: Texture2D",
					"@export var MaxStacks: int",
					"@export var Policy: int",
					"@export var ExpirePolicy: int",
					"@export var DurationTickTiming: int",
					"@export var DefaultHookPriority: int",
					"@export var InitOwnerTurnDuration: int",
					"@export var InitGlobalTurnDuration: int",
					"@export var InitRoundDuration: int",
				],
			],
		],
	],
	[
		"AttributeModifierDataProtocol",
		"res://core/combat/status/AttributeModifierDataProtocol.cs",
		[
			"internal readonly record struct AttributeModifierFields(",
			"public static AttributeModifierFields? TryRead(Variant modifier)",
			"public static Godot.Collections.Dictionary ToDictionary(AttributeModifier modifier)",
			"{ \"Type\", (int)modifier.Type },",
			"{ \"Mode\", (int)modifier.Mode },",
			"{ \"ValuePerStack\", modifier.ValuePerStack },",
			"{ \"Stacks\", modifier.Stacks },",
			"{ \"SourceId\", modifier.SourceId },",
		],
		[
			[
				"res://core/combat/status/attribute_modifier_data.gd",
				[
					"@export var Type: int",
					"@export var Mode: int",
					"@export var ValuePerStack: float",
				],
			],
			[
				"res://core/attributes/attribute_modifier.gd",
				[
					"func ToDictionary() -> Dictionary",
					"\"Type\": Type,",
					"\"Mode\": Mode,",
					"\"ValuePerStack\": ValuePerStack,",
					"\"Stacks\": Stacks,",
					"\"SourceId\": SourceId,",
				],
			],
		],
	],
	[
		"MonsterDataProtocol",
		"res://resources/monster/MonsterDataProtocol.cs",
		[
			"public const string ScriptPath = \"res://resources/monster/monster_data.gd\";",
			"public static bool IsMonsterData(GodotObject value)",
			"public static string ReadMonsterName(Resource data)",
			"public static int ReadElementalProperty(Resource data)",
			"public static int ReadFaction(Resource data)",
		],
		[
			[
				"res://resources/monster/monster_data.gd",
				[
					"@export var MonsterName: String",
					"@export var ElementalProperty: int",
					"@export var Faction: int",
					"@export var SkillSet: Resource",
					"@export var LootTable: Resource",
				],
			],
		],
	],
	[
		"CombatSkillDataProtocol",
		"res://core/combat/skills/CombatSkillDataProtocol.cs",
		[
			"public const string ScriptPath = \"res://core/combat/skills/combat_skill_data.gd\";",
			"public static bool IsCombatSkillData(GodotObject value)",
			"public static int ReadTargetingType(Resource skill)",
			"public static int ReadElement(Resource skill)",
			"public static StringName ReadCardId(Resource skill)",
			"public static bool Execute(Resource skill, SkillExecutionContext context)",
		],
		[
			[
				"res://core/combat/skills/combat_skill_data.gd",
				[
					"@export var Element: int",
					"@export var TargetingType: int",
					"func Execute(context: RefCounted) -> void",
				],
			],
			[
				"res://resources/item/base_card_data.gd",
				["@export var CardId: StringName", "@export var CardName: String"],
			],
		],
	],
	[
		"CardEffectProtocol",
		"res://core/combat/effects/CardEffectProtocol.cs",
		[
			"public const string CardEffectScriptPath = \"res://core/combat/effects/card_effect.gd\";",
			"public const string DamageEffectScriptPath = \"res://core/combat/effects/damage_effect.gd\";",
			"public static bool IsCardEffect(GodotObject value)",
			"public static bool IsDamageEffect(GodotObject value)",
			"public static Array<Resource> FilterEffects(Array source)",
			"public static bool HasDamageEffect(Array source)",
			"public static bool Execute(Resource effect, SkillExecutionContext context)",
		],
		[
			[
				"res://core/combat/effects/card_effect.gd",
				["func Execute(_context: RefCounted) -> void"],
			],
			[
				"res://core/combat/effects/damage_effect.gd",
				[
					"extends \"res://core/combat/effects/card_effect.gd\"",
					"func Execute(context: RefCounted) -> void",
				],
			],
		],
	],
]

## 接口逐条契约：[名称, C# 路径, [C# 成员声明], [[GDScript 实现脚本, [必须存在的片段]], …]]。
const INTERFACE_ROWS: Array = [
	[
		"IDamageable",
		"res://core/interfaces/IDamageable.cs",
		["int TakeDamage(int amount, ElementType elementType);"],
		[
			[
				"res://entities/components/health_component.gd",
				["func TakeDamage(amount: int, element_type: int) -> int"],
			],
		],
	],
	[
		"ICraftingInventory",
		"res://core/crafting/ICraftingInventory.cs",
		[
			"IReadOnlyList<ItemStack> Slots { get; }",
			"bool CanStore(ItemData item);",
			"int CountWhere(Func<ItemData, bool> predicate);",
			"int AddItem(ItemData item, int amount);",
			"bool TryRemoveItems(IReadOnlyDictionary<ItemData, int> itemsToRemove);",
		],
		[
			[
				"res://entities/components/inventory_component.gd",
				[
					"var Slots: Array",
					"func CanStore(item: Resource) -> bool",
					"func CountWhere(predicate: Callable) -> int",
					"func AddItem(item: Resource, amount: int) -> int",
					"func TryRemoveItems(items_to_remove: Dictionary) -> bool",
				],
			],
		],
	],
	[
		"IShopInventory",
		"res://core/shop/IShopInventory.cs",
		[
			"bool CanAddItem(ItemData item, int amount);",
			"int AddItem(ItemData item, int amount);",
			"bool TryRemoveItem(ItemData item, int amount);",
			"int ItemCnt(ItemData item);",
		],
		[
			[
				"res://entities/components/inventory_component.gd",
				[
					"func CanAddItem(item: Resource, amount: int) -> bool",
					"func TryRemoveItem(item: Resource, amount_to_remove: int) -> bool",
					"func ItemCnt(item: Resource) -> int",
				],
			],
		],
	],
	[
		"IPlayerWallet",
		"res://core/shop/IPlayerWallet.cs",
		["int Gold { get; }", "bool TrySpend(int amount);", "void Add(int amount);"],
		[
			[
				"res://core/autoloads/player_wallet.gd",
				[
					"var Gold: int",
					"func TrySpend(amount: int) -> bool",
					"func Add(amount: int) -> void",
				],
			],
		],
	],
]

## 生产 GDScript 扫描根目录（不含 res://tests）。
const PRODUCTION_ROOTS: Array = [
	"res://core",
	"res://entities",
	"res://resources",
	"res://scripts",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 协议 / 接口族契约套件名。
func suite_name() -> String:
	return "protocol_family_contract"


## 验证协议类与接口的文件形状：旧 C# 保留、GDScript 等价物存在。
##
## @return 无返回值。
func test_family_shape() -> void:
	for row: Array in PROTOCOL_ROWS:
		var cs_path: String = str(row[1])
		if CS_OPTIONAL.present(cs_path):
			assert_true(FileAccess.file_exists(cs_path), "旧 C# 协议类必须保留为兼容垫片：%s" % cs_path)
		for carrier_row: Array in row[3]:
			var gd_path: String = str(carrier_row[0])
			assert_true(FileAccess.file_exists(gd_path), "GDScript 等价物必须存在：%s" % gd_path)
	for row: Array in INTERFACE_ROWS:
		if CS_OPTIONAL.present(str(row[1])):
			assert_true(FileAccess.file_exists(str(row[1])), "旧 C# 接口必须保留为兼容垫片：%s" % row[1])
		for carrier_row: Array in row[3]:
			assert_true(FileAccess.file_exists(str(carrier_row[0])), "GDScript 实现脚本必须存在：%s" % carrier_row[0])


## 验证协议类读写的脚本路径 / 字段名 / 方法名与 GDScript 生产脚本逐条一致。
##
## @return 无返回值。
func test_protocol_boundaries() -> void:
	for row: Array in PROTOCOL_ROWS:
		var protocol_name: String = str(row[0])
		# C# 对照部分：垫片退役后整段退场，下面的 GDScript 断言仍照跑。
		var cs_text: String = CS_OPTIONAL.read(str(row[1]))
		if not cs_text.is_empty():
			for needle: String in row[2]:
				assert_true(
					cs_text.contains(needle),
					"旧 C# 协议必须保留既有读取面：%s → %s" % [protocol_name, needle]
				)
		for carrier_row: Array in row[3]:
			var gd_path: String = str(carrier_row[0])
			var gd_text: String = FileAccess.get_file_as_string(gd_path)
			for needle: String in carrier_row[1]:
				assert_true(
					gd_text.contains(needle),
					"GDScript 生产脚本必须保留同名字段 / 方法：%s → %s" % [gd_path, needle]
				)


## 验证 4 个 C#-only 接口的成员与 GDScript 组件方法协议逐条对应。
##
## @return 无返回值。
func test_interface_boundaries() -> void:
	for row: Array in INTERFACE_ROWS:
		var interface_name: String = str(row[0])
		# C# 对照部分：垫片退役后整段退场，下面的 GDScript 断言仍照跑。
		var cs_text: String = CS_OPTIONAL.read(str(row[1]))
		if not cs_text.is_empty():
			for needle: String in row[2]:
				assert_true(
					cs_text.contains(needle),
					"旧 C# 接口必须保留既有成员：%s → %s" % [interface_name, needle]
				)
		for carrier_row: Array in row[3]:
			var gd_path: String = str(carrier_row[0])
			var gd_text: String = FileAccess.get_file_as_string(gd_path)
			for needle: String in carrier_row[1]:
				assert_true(
					gd_text.contains(needle),
					"GDScript 组件必须保留同名方法协议：%s → %s" % [gd_path, needle]
				)


## 验证生产 GDScript 不依赖任何旧 C# 协议类 / 接口（裸标识符与 .cs 路径都算依赖）。
##
## @return 无返回值。
func test_no_production_gdscript_dependency() -> void:
	var names: Array = []
	var cs_paths: Array = []
	for row: Array in PROTOCOL_ROWS:
		names.append(str(row[0]))
		cs_paths.append(str(row[1]))
	for row: Array in INTERFACE_ROWS:
		names.append(str(row[0]))
		cs_paths.append(str(row[1]))

	for root: String in PRODUCTION_ROOTS:
		for name: String in names:
			var code_hits: Array = _grep_gd_code_references(root, name)
			assert_eq(
				code_hits,
				[],
				"生产 GDScript 不得引用旧 C# 协议 / 接口标识符：%s（%s）" % [name, root]
			)
		for cs_path: String in cs_paths:
			var path_hits: Array = _grep_gd_text_references(root, cs_path)
			assert_eq(
				path_hits,
				[],
				"生产 GDScript 不得加载旧 C# 协议 / 接口脚本：%s（%s）" % [cs_path, root]
			)


## 递归扫描目录下 .gd 的「代码部分」是否出现裸标识符（忽略注释与字符串字面量）。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配标识符。
## @return 命中文件的 res:// 路径数组。
func _grep_gd_code_references(directory: String, needle: String) -> Array:
	return _walk_gd(directory, needle, false)


## 递归扫描目录下 .gd 的全文（包含注释与字符串字面量）是否出现给定文本。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配文本。
## @return 命中文件的 res:// 路径数组。
func _grep_gd_text_references(directory: String, needle: String) -> Array:
	return _walk_gd(directory, needle, true)


## 递归遍历 .gd 文件并按指定模式匹配。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配文本。
## @param raw 为 true 时匹配全文（含注释与字符串）；为 false 时只匹配代码部分。
## @return 命中文件的 res:// 路径数组。
func _walk_gd(directory: String, needle: String, raw: bool) -> Array:
	var offenders: Array = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return offenders

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				offenders.append_array(_walk_gd("%s/%s" % [directory, entry], needle, raw))
		elif entry.ends_with(".gd"):
			var path := "%s/%s" % [directory, entry]
			var text: String = FileAccess.get_file_as_string(path)
			if raw:
				if text.contains(needle):
					offenders.append(path)
			else:
				for raw_line: String in text.split("\n"):
					if _strip_gd_comments_and_strings(raw_line).contains(needle):
						offenders.append(path)
						break
		entry = dir.get_next()

	dir.list_dir_end()
	return offenders


## 去掉一行 GDScript 的注释与字符串字面量，只保留代码部分。
##
## @param line GDScript 源码的一行。
## @return 去掉注释与字符串字面量后的代码文本。
func _strip_gd_comments_and_strings(line: String) -> String:
	var code: String = ""
	var in_string: bool = false
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if in_string:
			if character == "\\":
				index += 2
				continue
			if character == quote:
				in_string = false
			index += 1
			continue
		if character == "\"" or character == "'":
			in_string = true
			quote = character
			index += 1
			continue
		if character == "#":
			break
		code += character
		index += 1
	return code
