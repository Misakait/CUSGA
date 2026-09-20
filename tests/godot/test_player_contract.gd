@tool
extends McpTestSuite

## Player 根节点（entities/player.gd）生产迁移契约套件。
##
## 套件锁定四件事：玩家根脚本改为 GDScript 且公开面逐字等价旧 C#、player.tscn 完成脚本切换、
## C# 消费方降级为 Node + 稳定属性/方法协议、旧 C# 垫片保留完整实现作为兼容输入。
## 运行时“组件能否真的解析、饥饿扣血、死亡广播与库存写入是否连通”由运行中的游戏经
## game_eval 验证；编辑器侧只锁定形状与边界，避免依赖非 @tool 脚本的编辑器实例化。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批 GDScript 生产脚本、uid 旁车与旧 C# 垫片。
const PLAYER_GD: String = "res://entities/player.gd"
const PLAYER_GD_UID_PATH: String = "res://entities/player.gd.uid"
const PLAYER_CS: String = "res://entities/Player.cs"
const PLAYER_SCENE: String = "res://scenes/player_scenes/player.tscn"
const PRODUCTION_GAMEPLAY_PORT_GD: String = "res://core/application/gameplay_port.gd"
## C# 可选助手：C# 退役后安全收起跨语言对照，避免解析期错误与「空源文假通过」。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 旧 C# 与 GDScript 必须逐字一致的节点路径字面量。
const NODE_PATH_LITERALS: Array[String] = [
	"Components/HealthComponent",
	"Components/SatietyComponent",
	"Components/EnergyComponent",
	"Components/EquipmentComponent",
	"Components/AttributeComponent",
	"Components/TagComponent",
	"%StatusComponent",
	"Components/InventoryComponent",
	"Components/BattleDeckComponent",
	"/root/GlobalEventBus",
]

## 本批必须把 Player 降级为 Node 的 C# 消费方。
const DOWNGRADED_CONSUMERS: Array[String] = [
	"res://core/application/GameplayPort.cs",
	"res://core/gameflow/TerrainInteractionExecutor.cs",
	"res://core/gameflow/WorldInteractionCoordinator.cs",
	"res://core/gameflow/world_interaction_coordinator.gd",
	"res://resources/interaction/GatheringInteraction.cs",
	"res://resources/interaction/ReusableGatheringInteraction.cs",
	"res://core/ui/InventoryUI.cs",
	"res://core/debug/DebugLoadoutSeeder.cs",
	"res://resources/interaction/TerrainInteractionBuildContext.cs",
	"res://resources/talents/TalentEffect.cs",
	"res://resources/talents/AttributeTalentEffect.cs",
	"res://resources/talents/TagTalentEffect.cs",
]

## 每个 C# 消费方必须保留的跨语言边界片段。
const CONSUMER_BOUNDARY_SNIPPETS: Dictionary = {
	"res://core/application/GameplayPort.cs": [
		"private Node _player = null!;",
		"GetNode<Node>(PlayerPath)",
		"public Node Player => _player;",
		"_player.Call(\"TryAddItemToInventory\", stack).AsBool();",
		"ArgumentNullException.ThrowIfNull(stack);",
	],
	"res://core/gameflow/TerrainInteractionExecutor.cs": [
		"Node player = GetPlayer(gameplayPort);",
		"private static Node GetPlayer(Node gameplayPort)",
		"GetPlayerEquipment(gameplayPort)",
		"player.Get(\"Equipment\").AsGodotObject() as Node",
	],
	"res://core/gameflow/WorldInteractionCoordinator.cs": [
		"private Node GetGameplayPlayer()",
		"GetGameplayEquipment()",
		"player.Get(\"Equipment\").AsGodotObject() as Node",
	],
	"res://core/gameflow/world_interaction_coordinator.gd": [
		"func _get_gameplay_player() -> Node:",
		"func _get_gameplay_equipment() -> Node:",
		"var value: Variant = player.get(\"Equipment\")",
	],
	"res://resources/interaction/GatheringInteraction.cs": [
		"context.Player.Get(\"Equipment\").AsGodotObject() as Node",
		"Equipment.Call(\"GetGatheringYieldBonus\", GatheringTag)",
	],
	"res://resources/interaction/ReusableGatheringInteraction.cs": [
		"context.Player == null",
		"context.Player.Get(\"Equipment\").AsGodotObject() as Node",
	],
	"res://core/ui/InventoryUI.cs": [
		"_gameplayPort.Player.Get(\"Attributes\").AsGodotObject() as Node",
		"_gameplayPort.Player.Get(\"Equipment\").AsGodotObject() as EquipmentComponent",
	],
	"res://core/debug/DebugLoadoutSeeder.cs": [
		"GetNodeOrNull<Node>(PlayerPath)",
	],
	"res://resources/interaction/TerrainInteractionBuildContext.cs": [
		"public required Node Player { get; init; }",
	],
	"res://resources/talents/TalentEffect.cs": [
		"public abstract void Apply(Node targetPlayer);",
	],
	"res://resources/talents/AttributeTalentEffect.cs": [
		"public override void Apply(Node targetPlayer)",
		"targetPlayer.GetNodeOrNull<AttributeComponent>(\"AttributeComponent\")",
	],
	"res://resources/talents/TagTalentEffect.cs": [
		"public override void Apply(Node targetPlayer)",
		"targetPlayer.Get(\"TagComponent\").AsGodotObject() as Node",
		"tagComponent.Call(\"AddTag\", TagToGrant);",
	],
}

## 生产脚本必须保留的公开属性与私有字段。
const PRODUCTION_FIELDS: Array[String] = [
	"var Energy: Node = null",
	"var Attributes: Node = null",
	"var BattleDeck: Node = null",
	"var Equipment: Node = null",
	"var Status: Node = null",
	"var TagComponent: Node = null",
	"var _health: Node = null",
	"var _satiety: Node = null",
	"var _inventory: Node = null",
]

## 生产脚本必须保留的公开方法面。
const PRODUCTION_METHODS: Array[String] = [
	"func _ready() -> void:",
	"func _absorb_talent(new_talent: Resource) -> void:",
	"func OnSatietyDepleted() -> void:",
	"func OnPlayerDied() -> void:",
	"func _exit_tree() -> void:",
	"func TryAddItemToInventory(stack: RefCounted) -> bool:",
	"func _read_item_stack(stack: RefCounted) -> Dictionary:",
]

## 三条必须逐字保留的日志文本。
const LOG_TEXTS: Array[String] = [
	"主角感受到神秘力量涌入：",
	"主角：我太饿了！开始掉血！",
	"主角死亡，游戏结束！",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 玩家根节点契约套件名。
func suite_name() -> String:
	return "player_contract"


## 验证生产脚本存在、基类型正确、带 uid 旁车且不声明 class_name。
##
## @return 无返回值。
func test_production_script_shape() -> void:
	assert_true(FileAccess.file_exists(PLAYER_GD), "生产脚本必须存在。")
	assert_true(FileAccess.file_exists(PLAYER_GD_UID_PATH), "生产脚本必须带 uid 旁车。")

	var text: String = FileAccess.get_file_as_string(PLAYER_GD)
	assert_true(text.begins_with("extends Node"), "玩家根脚本必须直接继承 Node。")
	assert_false(_declares_class_name(text), "生产脚本不得声明 class_name，避免与兼容垫片重名。")
	assert_false(text.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	assert_true(text.contains("func _ready() -> void:"), "必须保留进入场景树时解析组件的时机。")
	assert_true(text.contains("func _exit_tree() -> void:"), "必须保留退出场景树时断开信号的时机。")

	var uid_text: String = FileAccess.get_file_as_string(PLAYER_GD_UID_PATH).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "uid 旁车必须声明 uid。")
	# 回归：路径常量必须是 NodePath。get_node() 只接受 String/StringNodePath，传 StringName 会在运行时
	# 触发 “Cannot pass a value of type StringName as NodePath” 的 Parser Error（本批已踩过）。
	assert_false(text.contains("_PATH: StringName = "), "节点路径常量不得声明为 StringName。")
	assert_true(text.contains("const HEALTH_COMPONENT_PATH: NodePath = ^\"Components/HealthComponent\""), "组件路径必须用 NodePath 字面量。")
	assert_true(text.contains("const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^\"%StatusComponent\""), "唯一名路径必须用 NodePath 字面量。")


## 验证公开属性、方法面与旧 C# 逐字对齐。
##
## @return 无返回值。
func test_public_surface_matches_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(PLAYER_GD)
	var cs_text: String = FileAccess.get_file_as_string(PLAYER_CS)
	## C# 物理退役后垫片已删除；只有垫片仍在时才做「逐字对照」。
	var has_legacy_shim: bool = CS_OPTIONAL.present(PLAYER_CS)

	for literal: String in PRODUCTION_FIELDS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留字段：%s" % literal)

	for literal: String in PRODUCTION_METHODS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留方法：%s" % literal)

	for literal: String in NODE_PATH_LITERALS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留节点路径：%s" % literal)
		if has_legacy_shim:
			assert_true(cs_text.contains(literal), "旧 C# 垫片必须保留同一节点路径：%s" % literal)

	if has_legacy_shim:
		assert_true(cs_text.contains("public partial class Player : Node"), "旧 C# 垫片必须仍继承 Node。")
		assert_true(cs_text.contains("public bool TryAddItemToInventory(RefCounted stack)"), "旧 C# 拾取入口必须保留。")
		assert_true(cs_text.contains("public Node Equipment { get; private set; }"), "旧 C# 装备属性必须仍是 Node 边界。")


## 验证信号名、伤害数值与三条日志文本与旧 C# 一致。
##
## @return 无返回值。
func test_signals_damage_and_logs_match_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(PLAYER_GD)
	var cs_text: String = FileAccess.get_file_as_string(PLAYER_CS)
	## C# 物理退役后垫片已删除；只有垫片仍在时才做「逐字对照」。
	var has_legacy_shim: bool = CS_OPTIONAL.present(PLAYER_CS)

	assert_true(gd_text.contains("const DEPLETED_SIGNAL: StringName = &\"Depleted\""), "归零信号名必须仍是 Depleted。")
	assert_true(gd_text.contains("const GLOBAL_EVENT_BUS_PATH: NodePath = ^\"/root/GlobalEventBus\""), "全局事件总线路径必须保持且为 NodePath。")
	assert_true(gd_text.contains("const ON_PLAYER_ACQUIRED_TALENT: StringName = &\"on_player_acquired_talent\""), "天赋事件名必须保持。")
	assert_true(gd_text.contains("const PLAYER_DIED_SIGNAL: StringName = &\"player_died\""), "死亡事件名必须保持。")
	assert_true(gd_text.contains("const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^\"%StatusComponent\""), "状态组件必须仍用唯一名路径且为 NodePath。")
	assert_true(gd_text.contains("const SATIETY_DEPLETED_DAMAGE: int = 5"), "饥饿伤害必须仍是 5。")
	assert_true(gd_text.contains("const ELEMENT_NONE: int = 0"), "ElementType.None 必须仍是 0。")

	if has_legacy_shim:
		assert_true(cs_text.contains("_health.Call(\"TakeDamage\", 5, (int)ElementType.None);"), "旧 C# 伤害数值与元素必须仍是 5 / None。")
	assert_true(gd_text.contains("_health.call(\"TakeDamage\", SATIETY_DEPLETED_DAMAGE, ELEMENT_NONE)"), "GDScript 必须用同一常量走同一方法协议。")
	if has_legacy_shim:
		assert_true(cs_text.contains("_globalEventBus.EmitSignal(\"player_died\");"), "旧 C# 死亡广播必须保留。")
	assert_true(gd_text.contains("_global_event_bus.emit_signal(PLAYER_DIED_SIGNAL)"), "GDScript 死亡广播必须走同一信号常量。")
	if has_legacy_shim:
		assert_true(cs_text.contains("GDSignals.OnPlayerAcquiredTalent"), "旧 C# 天赋事件必须仍走 GDSignals 常量。")
	assert_true(gd_text.contains("_global_event_bus.connect(ON_PLAYER_ACQUIRED_TALENT, _absorb_talent)"), "GDScript 必须订阅同一天赋事件。")
	assert_true(gd_text.contains("_satiety.connect(DEPLETED_SIGNAL, _satiety_depleted_callable)"), "饱食归零必须连到缓存 Callable。")
	assert_true(gd_text.contains("_health.connect(DEPLETED_SIGNAL, _health_depleted_callable)"), "生命归零必须连到缓存 Callable。")
	assert_true(gd_text.contains("_satiety.disconnect(DEPLETED_SIGNAL, _satiety_depleted_callable)"), "退出场景树必须精确断开饱食回调。")
	assert_true(gd_text.contains("_global_event_bus.disconnect(ON_PLAYER_ACQUIRED_TALENT, _absorb_talent)"), "退出场景树必须断开天赋回调。")

	for literal: String in LOG_TEXTS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留日志文本：%s" % literal)
		if has_legacy_shim:
			assert_true(cs_text.contains(literal), "旧 C# 垫片必须保留日志文本：%s" % literal)


## 验证跨语言物品堆叠读取协议与旧 C# ItemStackProtocol 等价。
##
## @return 无返回值。
func test_item_stack_protocol_matches_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(PLAYER_GD)
	var cs_text: String = FileAccess.get_file_as_string(PLAYER_CS)

	## C# 物理退役后垫片已删除；只有垫片仍在时才做「逐字对照」。
	if CS_OPTIONAL.present(PLAYER_CS):
		assert_true(cs_text.contains("ItemStackProtocol.TryRead(stack, out Resource item, out int amount)"), "旧 C# 必须仍走 ItemStackProtocol。")
		assert_true(cs_text.contains("_inventory.Call(\"AddItem\", item, amount).AsInt32() == 0"), "旧 C# 必须按未放入数量判定成功。")
	assert_true(gd_text.contains("_inventory.call(\"AddItem\", fields[\"item\"], fields[\"amount\"])"), "GDScript 必须调用同一 AddItem 协议。")
	for protocol: String in ["SetItem", "Clear", "Item", "Amount", "IsEmpty"]:
		assert_true(gd_text.contains(protocol), "跨语言堆叠协议必须保留字段/方法：%s" % protocol)


## 验证玩家场景已切换到 GDScript 根脚本且节点结构未变。
##
## @return 无返回值。
func test_scene_switches_to_gdscript_root() -> void:
	var scene: String = FileAccess.get_file_as_string(PLAYER_SCENE)
	var uid_text: String = FileAccess.get_file_as_string(PLAYER_GD_UID_PATH).strip_edges()

	assert_true(scene.contains("path=\"res://entities/player.gd\""), "玩家场景必须引用 GDScript 生产脚本。")
	assert_true(scene.contains(uid_text), "玩家场景必须使用生产脚本的新 uid。")
	assert_false(scene.contains("Player.cs"), "玩家场景不得再引用旧 C# 根脚本。")
	assert_true(
		scene.contains("[ext_resource type=\"Script\" uid=\"%s\" path=\"res://entities/player.gd\" id=\"1_d8qmr\"]" % uid_text),
		"必须复用原 ext_resource id，根节点块无需改动。"
	)
	assert_true(scene.contains("[node name=\"Player\" type=\"Node\""), "玩家根节点类型必须仍是 Node。")
	assert_true(scene.contains("script = ExtResource(\"1_d8qmr\")"), "根节点必须仍绑定原 ext_resource id。")
	for literal: String in [
		"[node name=\"Components\" type=\"Node\"",
		"[node name=\"StatusComponent\"",
		"[node name=\"HealthComponent\"",
		"[node name=\"InventoryComponent\"",
		"[node name=\"BattleDeckComponent\"",
		"unique_name_in_owner = true",
	]:
		assert_true(scene.contains(literal), "玩家场景节点结构不得改动：%s" % literal)


## 验证 C# 消费方全部改用 Node 与稳定属性/方法协议。
##
## @return 无返回值。
func test_csharp_consumers_downgraded_to_node_protocol() -> void:
	for path: String in DOWNGRADED_CONSUMERS:
		## GDScript 消费方必须始终存在；C# 消费方在 C# 退役后按条件收起。
		assert_true(
			not CS_OPTIONAL.present(path) or FileAccess.file_exists(path),
			"消费方文件必须存在：%s" % path
		)

	for path: String in CONSUMER_BOUNDARY_SNIPPETS.keys():
		## C# 源文对照：C# 退役后 read() 返回空串，整条 C# 边界片段对照按条件收起。
		var text: String = CS_OPTIONAL.read(path)
		if text.is_empty():
			continue
		for snippet: String in CONSUMER_BOUNDARY_SNIPPETS[path]:
			assert_true(text.contains(snippet), "%s 必须保留跨语言边界片段：%s" % [path, snippet])

	var port_gd: String = FileAccess.get_file_as_string(PRODUCTION_GAMEPLAY_PORT_GD)
	assert_true(port_gd.contains("var Player: Node = null"), "生产 GDScript 门面必须同样只持有 Node。")
	assert_true(port_gd.contains("Player.call(\"TryAddItemToInventory\", stack)"), "生产 GDScript 门面必须走同一方法协议。")


## 验证全项目自有 C# 代码不再把 Player 当作强类型使用。
##
## @return 无返回值。
func test_no_strong_typed_player_left_in_production_cs() -> void:
	var pattern := RegEx.new()
	var compiled: int = pattern.compile("<Player>|as Player\\b|\\bPlayer [A-Za-z_]+ =")
	assert_eq(compiled, OK, "强类型扫描正则必须能够编译。")

	var files: Array[String] = _collect_production_cs_files("res://")
	## C# 全量退役后项目自有 C# 文件应为 0，这正是完成态；此时本用例没有扫描对象，记跳过。
	if files.is_empty():
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	assert_gt(files.size(), 50, "必须扫描到项目自有 C# 文件。")

	var offenders: Array[String] = []
	for path: String in files:
		# 旧 C# 垫片自身就是 Player 类型定义，属允许保留的兼容输入。
		if path == PLAYER_CS:
			continue
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)

	assert_eq(offenders.size(), 0, "生产 C# 不得再把 Player 当作强类型使用：%s" % str(offenders))


## 验证旧 C# 垫片仍保留完整实现，未被掏空成空壳。
##
## @return 无返回值。
func test_legacy_csharp_shim_retained() -> void:
	## 本用例整体只对照旧 C# 垫片源文；C# 退役后记跳过。
	if not CS_OPTIONAL.present(PLAYER_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var text: String = FileAccess.get_file_as_string(PLAYER_CS)

	for snippet: String in [
		"public override void _Ready()",
		"public override void _ExitTree()",
		"private void AbsorbTalent(Resource newTalent)",
		"private void OnSatietyDepleted()",
		"private void OnPlayerDied()",
		# 属性组件批次已把玩家垫片同步降级为 Node + InitializeWithData 方法协议，
		# 这里锁定新边界，避免回退到会让 GDScript 属性组件解析失败的强类型调用。
		"GetNode<Node>(\"Components/AttributeComponent\")",
		"GetNode<Node>(\"%StatusComponent\")",
		"GetNode<Node>(\"/root/GlobalEventBus\")",
		"effect.Call(\"Apply\", this);",
	]:
		assert_true(text.contains(snippet), "旧 C# 垫片必须保留实现片段：%s" % snippet)


## 验证天赋效果子类已把玩家参数放宽为 Node，且未顺手改动旧节点路径。
##
## @return 无返回值。
func test_talent_effects_accept_node_player() -> void:
	## 本用例整体只对照 C# 天赋效果源文；C# 退役后记跳过，而不是退化成 0 断言失败。
	if not CS_OPTIONAL.present("res://resources/talents/AttributeTalentEffect.cs"):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var attribute_text: String = CS_OPTIONAL.read("res://resources/talents/AttributeTalentEffect.cs")
	assert_true(
		attribute_text.contains("targetPlayer.GetNodeOrNull<AttributeComponent>(\"AttributeComponent\")"),
		"天赋效果必须保留旧代码相对玩家根取 AttributeComponent 的路径，避免行为漂移。"
	)
	assert_false(
		attribute_text.contains("GetNodeOrNull<AttributeComponent>(\"Components/AttributeComponent\")"),
		"天赋效果不得顺手改写成组件子节点路径。"
	)


## 判断脚本全文是否声明了 class_name。
##
## @param text GDScript 全文。
## @return 声明了 class_name 时返回 true。
func _declares_class_name(text: String) -> bool:
	for raw_line: String in text.split("\n"):
		if raw_line.strip_edges().begins_with("class_name"):
			return true

	return false


## 递归收集项目自有 C# 文件，跳过编辑器缓存、测试与第三方插件目录。
##
## @param directory 起始目录的 res:// 路径。
## @return 项目自有 C# 文件路径数组。
func _collect_production_cs_files(directory: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return files

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			# 以点开头的条目同时覆盖 .godot 缓存与 . 与 .. 两个伪目录。
			if not entry.begins_with(".") and entry != "tests" and entry != "addons":
				files.append_array(_collect_production_cs_files("%s/%s" % [directory, entry]))
		elif entry.ends_with(".cs"):
			files.append("%s/%s" % [directory, entry])
		entry = dir.get_next()

	dir.list_dir_end()
	return files
