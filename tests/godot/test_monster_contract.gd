@tool
extends McpTestSuite

## Monster 根节点（entities/monster.gd）生产迁移契约套件。
##
## 套件锁定四件事：怪物根脚本改为 GDScript 且公开面逐字等价旧 C#、monster.tscn 完成脚本切换、
## C# 消费方降级为字段协议（不再按 C# Monster 强类型判断）、旧 C# 垫片保留完整实现作为兼容输入。
## 运行时“组件能否真的解析、死亡广播与技能过滤是否连通”由运行中的游戏经 game_eval 验证；
## 编辑器侧只锁定形状与边界，避免依赖非 @tool 脚本的编辑器实例化。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批 GDScript 生产脚本、uid 旁车与旧 C# 垫片。
const MONSTER_GD: String = "res://entities/monster.gd"
const MONSTER_GD_UID_PATH: String = "res://entities/monster.gd.uid"
const MONSTER_CS: String = "res://entities/Monster.cs"
const MONSTER_SCENE: String = "res://scenes/monster_scenes/monster.tscn"
## 本批需要降级的 C# 消费方与其 GDScript 生产对照。
const DAMAGE_RECEIVER_CS: String = "res://entities/components/DamageReceiverComponent.cs"
const DAMAGE_RECEIVER_GD: String = "res://entities/components/damage_receiver_component.gd"
const MONSTER_DATA_PROTOCOL_CS: String = "res://resources/monster/MonsterDataProtocol.cs"
## 战斗技能能力协议字面量：判定不依赖脚本路径，由生产脚本声明的方法集合驱动。
const COMBAT_SKILL_REQUIRED_METHODS_LITERAL: String = "const COMBAT_SKILL_REQUIRED_METHODS: Array[StringName] = [&\"Execute\", &\"RequiresTarget\"]"

## 旧 C# 与 GDScript 必须逐字一致的节点路径字面量。
const NODE_PATH_LITERALS: Array[String] = [
	"Components/AttributeComponent",
	"Components/FactionComponent",
	"Components/HealthComponent",
	"%StatusComponent",
	"Components/LootComponent",
	"Components/SkillComponent",
	"HealthBar",
	"CardName",
	"Element",
	"TargetSelectionOutline",
	"Area2D",
	"Sprite2D",
]

## 生产脚本必须保留的公开属性与私有字段。
const PRODUCTION_FIELDS: Array[String] = [
	"@export var BaseData: Resource = null",
	"var Health: Node = null",
	"var Attributes: Node = null",
	"var Faction: Node = null",
	"var Status: Node = null",
	"var SkillComponent: Node = null",
	"var Loot: Node = null",
	"var _health_bar: ProgressBar = null",
	"var _area_2d: Area2D = null",
]

## 生产脚本必须保留的公开方法面。
const PRODUCTION_METHODS: Array[String] = [
	"func _ready() -> void:",
	"func _exit_tree() -> void:",
	"func Initialize(data: Resource) -> void:",
	"func TryClaimDeathPresentation() -> bool:",
	"func FinalizeCombatDeathPresentation() -> void:",
	"func FinalizeUnclaimedDeath() -> void:",
	"func ApplyTargetSelectionVisual(",
	"func StartTargetSelectionPulse(",
	"func StopTargetSelectionPulse() -> void:",
	"func ResetTargetSelectionVisual(normal_sprite_scale: Vector2, duration: float) -> void:",
	"func TweenVisualScale(target_sprite_scale: Vector2, duration: float) -> void:",
	"func ResetVisualScale(duration: float) -> void:",
	"func GetCombatSkills() -> Array[Resource]:",
	"func GetRandomCombatSkill() -> Resource:",
]

## 参与卡面缩放的六个节点路径；血条必须被排除。
const VISUAL_NODE_PATHS: Array[String] = [
	"Sprite2D",
	"CardName",
	"Element",
	"MonsterAttribute",
	"StatusEffectBar",
	"TargetSelectionOutline",
]

## 三条必须逐字保留的界面/诊断文本。
const LOG_TEXTS: Array[String] = [
	"未知怪物",
	"敌人",
	"HealthBar node is missing on Monster!",
]

## 怪物场景不得再出现的旧 C# 根脚本路径。
const LEGACY_ROOT_SCRIPT_REFERENCE: String = "res://entities/Monster.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 怪物根节点契约套件名。
func suite_name() -> String:
	return "monster_contract"


## 验证生产脚本存在、基类型正确、带 uid 旁车且不声明 class_name。
##
## @return 无返回值。
func test_production_script_shape() -> void:
	assert_true(FileAccess.file_exists(MONSTER_GD), "生产脚本必须存在。")
	assert_true(FileAccess.file_exists(MONSTER_GD_UID_PATH), "生产脚本必须带 uid 旁车。")

	var text: String = FileAccess.get_file_as_string(MONSTER_GD)
	assert_true(text.begins_with("extends Node2D"), "怪物根脚本必须直接继承 Node2D。")
	assert_false(_declares_class_name(text), "生产脚本不得声明 class_name，避免与兼容垫片重名。")
	assert_false(text.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	assert_true(text.contains("func _ready() -> void:"), "必须保留进入场景树时解析组件的时机。")
	assert_true(text.contains("func _exit_tree() -> void:"), "必须保留退出场景树时断开信号的时机。")

	var uid_text: String = FileAccess.get_file_as_string(MONSTER_GD_UID_PATH).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "uid 旁车必须声明 uid。")
	# 回归：路径常量必须是 NodePath。get_node() 只接受 String/NodePath，传 StringName 会在运行时
	# 触发 “Cannot pass a value of type StringName as NodePath” 的 Parser Error。
	assert_false(text.contains("_PATH: StringName = "), "节点路径常量不得声明为 StringName。")
	assert_true(text.contains("const HEALTH_COMPONENT_PATH: NodePath = ^\"Components/HealthComponent\""), "组件路径必须用 NodePath 字面量。")
	assert_true(text.contains("const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^\"%StatusComponent\""), "唯一名路径必须用 NodePath 字面量。")
	assert_true(text.contains("const SPRITE_PATH: NodePath = ^\"Sprite2D\""), "卡面基准路径必须用 NodePath 字面量。")
	# 回归：本项目把 inference_on_variant 当错误；脚本构造必须显式转型。
	assert_true(text.contains("STARTING_STATS_SCRIPT.new() as Resource"), "兜底初始属性必须显式转型，避免 Variant 推断。")
	assert_false(text.contains(":= STARTING_STATS_SCRIPT.new()"), "不得用 := 直接推断 GDScript.new() 的 Variant 结果。")


## 验证公开属性、方法面与旧 C# 逐字对齐。
##
## @return 无返回值。
func test_public_surface_matches_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)
	var cs_text: String = CS_OPTIONAL.read(MONSTER_CS)

	for literal: String in PRODUCTION_FIELDS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留字段：%s" % literal)

	for literal: String in PRODUCTION_METHODS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留方法：%s" % literal)

	for literal: String in NODE_PATH_LITERALS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留节点路径：%s" % literal)
		if not cs_text.is_empty():
			assert_true(cs_text.contains(literal), "旧 C# 垫片必须保留同一节点路径：%s" % literal)

	# C# 对照部分：垫片退役后整段退场，上面的 GDScript 断言仍照跑。
	if cs_text.is_empty():
		return
	assert_true(cs_text.contains("public partial class Monster : Node2D"), "旧 C# 垫片必须仍继承 Node2D。")
	assert_true(cs_text.contains("public Resource BaseData { get; set; }"), "旧 C# 垫片必须保留跨语言 BaseData。")
	assert_true(cs_text.contains("public Node Health { get; private set; }"), "旧 C# 垫片必须保留 Node 生命组件边界。")
	assert_true(cs_text.contains("public bool TryClaimDeathPresentation()"), "旧 C# 垫片必须保留死亡认领入口。")


## 验证信号名、界面文本与诊断文本与旧 C# 一致。
##
## @return 无返回值。
func test_signals_and_texts_match_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)
	var cs_text: String = CS_OPTIONAL.read(MONSTER_CS)

	assert_true(gd_text.contains("signal DeathPresentationRequested"), "必须保留同名死亡表现信号。")
	assert_true(gd_text.contains("const DEPLETED_SIGNAL: StringName = &\"Depleted\""), "生命归零信号名必须仍是 Depleted。")
	assert_true(gd_text.contains("const VALUE_CHANGED_SIGNAL: StringName = &\"ValueChanged\""), "生命值变化信号名必须仍是 ValueChanged。")
	assert_true(gd_text.contains("const DEATH_PRESENTATION_REQUESTED: StringName = &\"DeathPresentationRequested\""), "信号名常量必须与信号声明一致。")
	assert_true(gd_text.contains("const TOOLTIP_PANEL_GROUP: StringName = &\"tooltip_panel\""), "提示面板分组名必须保持。")
	assert_true(gd_text.contains("Health.connect(DEPLETED_SIGNAL, _health_depleted_callable)"), "生命归零必须连到缓存 Callable。")
	assert_true(gd_text.contains("Health.connect(VALUE_CHANGED_SIGNAL, _health_value_changed_callable)"), "生命变化必须连到缓存 Callable。")
	assert_true(gd_text.contains("Health.disconnect(DEPLETED_SIGNAL, _health_depleted_callable)"), "退出场景树必须精确断开归零回调。")
	assert_true(gd_text.contains("Health.disconnect(VALUE_CHANGED_SIGNAL, _health_value_changed_callable)"), "退出场景树必须精确断开数值回调。")

	for literal: String in LOG_TEXTS:
		assert_true(gd_text.contains(literal), "生产脚本必须保留界面/诊断文本：%s" % literal)
	if not cs_text.is_empty():
		assert_true(cs_text.contains("未知怪物"), "旧 C# 垫片必须保留同一兜底名称。")
		assert_true(cs_text.contains("HealthBar node is missing on Monster!"), "旧 C# 垫片必须保留同一血条缺失诊断。")


## 验证五行展示名映射与旧 C# ElementType 逐字一致。
##
## @return 无返回值。
func test_element_display_names_match_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)

	for literal: String in [
		"const ELEMENT_NONE: int = 0",
		"const ELEMENT_WOOD: int = 1",
		"const ELEMENT_METAL: int = 2",
		"const ELEMENT_WATER: int = 3",
		"const ELEMENT_EARTH: int = 4",
		"const ELEMENT_FIRE: int = 5",
	]:
		assert_true(gd_text.contains(literal), "五行枚举取值必须与 ElementType 一致：%s" % literal)

	var mappings := {
		"ELEMENT_WOOD:": "木",
		"ELEMENT_METAL:": "金",
		"ELEMENT_WATER:": "水",
		"ELEMENT_EARTH:": "土",
		"ELEMENT_FIRE:": "火",
	}
	for branch: String in mappings.keys():
		assert_true(
			gd_text.contains("%s\n\t\t\treturn \"%s\"" % [branch, mappings[branch]]),
			"%s 必须映射为 %s。" % [branch, mappings[branch]]
		)
	assert_true(gd_text.contains("_:\n\t\t\treturn \"无\""), "其余取值必须回退到“无”。")
	assert_true(gd_text.contains("func _get_element_display_name(element: int) -> String:"), "必须保留五行展示名入口。")


## 验证卡面缩放缓存路径与旧 C# 一致，且故意排除血条。
##
## @return 无返回值。
func test_visual_scale_targets_match_legacy() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)
	var cs_text: String = CS_OPTIONAL.read(MONSTER_CS)

	for path: String in VISUAL_NODE_PATHS:
		assert_true(gd_text.contains("\t\"%s\"," % path), "卡面缩放路径必须保留：%s" % path)
	if not cs_text.is_empty():
		assert_true(cs_text.contains("\"Sprite2D\", \"CardName\", \"Element\", \"MonsterAttribute\", \"StatusEffectBar\", \"TargetSelectionOutline\""), "旧 C# 垫片必须保留同一组缩放路径。")
	assert_false(
		gd_text.contains("\t\"HealthBar\",\n"),
		"血条不得进入卡面缩放缓存，否则高亮时血条会跟着放大。"
	)
	assert_true(gd_text.contains("func _cache_visual_scale_targets() -> void:"), "必须保留缓存入口。")
	assert_true(gd_text.contains("if node is Node2D:"), "Node2D 卡面必须缓存缩放与位置。")
	assert_true(gd_text.contains("elif node is Control:"), "Control 卡面必须缓存缩放与位置。")
	assert_true(gd_text.contains("_visual_modulate_base_map[node] = (node as CanvasItem).modulate"), "CanvasItem 必须缓存调制颜色。")


## 验证死亡流程顺序、去重与认领语义与旧 C# 一致。
##
## @return 无返回值。
func test_death_flow_contract() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)

	assert_true(gd_text.contains("var _is_combat_defeated: bool = false"), "必须保留逻辑死亡去重标记。")
	assert_true(gd_text.contains("var _is_death_presentation_claimed: bool = false"), "必须保留视觉收尾认领标记。")

	var guard_index: int = gd_text.find("func _handle_death() -> void:")
	var drop_index: int = gd_text.find("Loot.call(\"TriggerDrop\", global_position, 0)")
	var pick_index: int = gd_text.find("_area_2d.input_pickable = false")
	var monitor_index: int = gd_text.find("_area_2d.monitoring = false")
	var emit_index: int = gd_text.find("emit_signal(DEATH_PRESENTATION_REQUESTED)")
	var deferred_index: int = gd_text.find("call_deferred(\"FinalizeUnclaimedDeath\")")
	assert_gt(guard_index, -1, "必须保留逻辑死亡入口。")
	assert_gt(drop_index, guard_index, "掉落必须在死亡入口之后触发。")
	assert_gt(pick_index, drop_index, "关闭鼠标拾取必须在掉落之后。")
	assert_gt(monitor_index, pick_index, "关闭区域监测必须在关闭拾取之后。")
	assert_gt(emit_index, monitor_index, "死亡表现信号必须在关闭拾取之后发出。")
	assert_gt(deferred_index, emit_index, "未认领兜底回收必须在信号之后延迟调用。")
	assert_true(gd_text.contains("\tif _is_combat_defeated:\n\t\treturn"), "重复死亡必须直接返回。")
	assert_true(gd_text.contains("if not _is_combat_defeated or _is_death_presentation_claimed:"), "认领必须同时检查逻辑死亡与重复认领。")
	assert_true(gd_text.contains("if not is_queued_for_deletion():\n\t\tqueue_free()"), "收尾必须避免重复入队释放。")
	assert_true(gd_text.contains("if not _is_death_presentation_claimed:\n\t\tFinalizeCombatDeathPresentation()"), "无导演认领时必须延续旧即时销毁语义。")


## 验证技能读取沿用脚本路径过滤协议，兼容旧 C# 与 GDScript 技能。
##
## @return 无返回值。
func test_skill_protocol_contract() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)
	var cs_text: String = CS_OPTIONAL.read(MONSTER_CS)

	assert_true(gd_text.contains(COMBAT_SKILL_REQUIRED_METHODS_LITERAL), "生产脚本必须声明战斗技能能力协议。")
	assert_true(gd_text.contains("SkillComponent.has_method(\"GetCombatSkills\")"), "技能读取必须走方法协议。")
	assert_true(gd_text.contains("SkillComponent.has_method(\"GetRandomCombatSkill\")"), "随机技能必须走方法协议。")
	assert_true(gd_text.contains("typeof(raw_skills) != TYPE_ARRAY"), "非数组返回必须回退空数组。")
	assert_true(gd_text.contains("resource.has_method(method_name)"), "必须按能力协议识别新旧战斗技能。")
	assert_true(not gd_text.contains("resource_path"), "生产脚本不得再按脚本路径识别技能。")
	# 旧 C# 垫片保持原有协议调用，避免两侧过滤规则漂移。
	if not cs_text.is_empty():
		assert_true(cs_text.contains("CombatSkillDataProtocol.FilterSkills"), "旧 C# 垫片必须仍走 CombatSkillDataProtocol。")
		assert_true(cs_text.contains("CombatSkillDataProtocol.IsCombatSkillData"), "旧 C# 垫片随机技能必须仍走同一协议。")


## 验证怪物场景已切换到 GDScript 根脚本且节点结构未变。
##
## @return 无返回值。
func test_scene_switches_to_gdscript_root() -> void:
	var scene: String = FileAccess.get_file_as_string(MONSTER_SCENE)
	var uid_text: String = FileAccess.get_file_as_string(MONSTER_GD_UID_PATH).strip_edges()

	assert_true(scene.contains("path=\"res://entities/monster.gd\""), "怪物场景必须引用 GDScript 生产脚本。")
	assert_true(scene.contains(uid_text), "怪物场景必须使用生产脚本的新 uid。")
	assert_false(scene.contains(LEGACY_ROOT_SCRIPT_REFERENCE), "怪物场景不得再引用旧 C# 根脚本。")
	assert_true(
		scene.contains("[ext_resource type=\"Script\" uid=\"%s\" path=\"res://entities/monster.gd\" id=\"1_1wyrm\"]" % uid_text),
		"必须复用原 ext_resource id，根节点块无需改动。"
	)
	assert_true(scene.contains("script = ExtResource(\"1_1wyrm\")"), "根节点必须仍绑定原 ext_resource id。")

	for literal: String in [
		"[node name=\"Monster\" type=\"Node2D\"",
		"[node name=\"Sprite2D\" type=\"Sprite2D\"",
		"[node name=\"TargetSelectionOutline\" type=\"Line2D\"",
		"[node name=\"Area2D\" type=\"Area2D\"",
		"[node name=\"HealthBar\" type=\"ProgressBar\"",
		"[node name=\"CardName\" type=\"Label\"",
		"[node name=\"Element\" type=\"Label\"",
		"[node name=\"MonsterAttribute\" type=\"VBoxContainer\"",
		"[node name=\"StatusEffectBar\" type=\"HBoxContainer\"",
		"[node name=\"Components\" type=\"Node\"",
		"unique_name_in_owner = true",
	]:
		assert_true(scene.contains(literal), "怪物场景节点结构不得改动：%s" % literal)

	# 怪物数据子资源必须继续指向生产 GDScript 怪物数据，序列化字段与取值不得变化。
	for literal: String in [
		"script = ExtResource(\"5_kt6in\")",
		"MonsterName = \"kirin\"",
		"ElementalProperty = 1",
		"BaseData = SubResource(\"Resource_43qb6\")",
	]:
		assert_true(scene.contains(literal), "怪物数据序列化必须保持不变：%s" % literal)


## 验证 C# 消费方改用字段协议，不再按 C# Monster 强类型判断防守方。
##
## @return 无返回值。
func test_csharp_consumer_downgraded_to_field_protocol() -> void:
	var receiver_cs: String = CS_OPTIONAL.read(DAMAGE_RECEIVER_CS)
	var receiver_gd: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_GD)

	# C# 对照部分：垫片退役后整段退场，下面的 GDScript 断言仍照跑。
	if not receiver_cs.is_empty():
		assert_false(receiver_cs.contains("is Monster monster"), "属性克制不得再依赖 C# Monster 强类型判断。")
		assert_true(
			receiver_cs.contains("defender.Get(\"BaseData\").AsGodotObject() as Resource"),
			"属性克制必须按字段协议读取怪物数据。"
		)
		assert_true(
			receiver_cs.contains("MonsterDataProtocol.ReadElementalProperty"),
			"属性克制必须经跨语言协议读取五行属性。"
		)
		assert_true(receiver_cs.contains("if (defender != null)"), "防守方为空时必须安全跳过属性克制。")

	# 生产 GDScript 同一条路径已经是字段协议，两侧必须保持一致。
	assert_true(receiver_gd.contains("defender.get(\"BaseData\")"), "GDScript 生产组件必须同样按字段协议读取。")
	assert_true(receiver_gd.contains("_read_int(base_data, \"ElementalProperty\")"), "GDScript 生产组件必须读取同一字段。")

	var protocol: String = CS_OPTIONAL.read(MONSTER_DATA_PROTOCOL_CS)
	if not protocol.is_empty():
		assert_true(protocol.contains("public const string ScriptPath = \"res://resources/monster/monster_data.gd\""), "怪物数据协议必须继续指向生产 GDScript。")


## 验证全项目自有 C# 代码不再把 Monster 当作强类型使用。
##
## @return 无返回值。
func test_no_strong_typed_monster_left_in_production_cs() -> void:
	var pattern := RegEx.new()
	var compiled: int = pattern.compile("\\bis Monster\\b|\\bas Monster\\b|<Monster>")
	assert_eq(compiled, OK, "强类型扫描正则必须能够编译。")

	var files: Array[String] = _collect_production_cs_files("res://")
	# C# 物理退役后没有可扫描的生产 C# 文件：本用例的对照面随之消失。
	if files.is_empty():
		return
	assert_gt(files.size(), 50, "必须扫描到项目自有 C# 文件。")

	var offenders: Array[String] = []
	for path: String in files:
		# 旧 C# 垫片自身就是 Monster 类型定义，属允许保留的兼容输入。
		if path == MONSTER_CS:
			continue
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)

	assert_eq(offenders.size(), 0, "生产 C# 不得再把 Monster 当作强类型使用：%s" % str(offenders))


## 验证旧 C# 垫片仍保留完整实现，未被掏空成空壳。
##
## @return 无返回值。
func test_legacy_csharp_shim_retained() -> void:
	if not CS_OPTIONAL.present(MONSTER_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var text: String = FileAccess.get_file_as_string(MONSTER_CS)

	for snippet: String in [
		"public override void _Ready()",
		"public override void _ExitTree()",
		"private void HandleDeath()",
		"private Node FindTooltipPanel()",
		"private void OnHealthChanged(int currentValue, int maxValue)",
		"private void CacheVisualScaleTargets()",
		"private bool TryGetBaseSpriteScale(out Vector2 baseSpriteScale)",
		"private void AppendVisualScaleProperties(Tween tween, Vector2 targetSpriteScale, double duration)",
		# 属性组件批次已把怪物垫片降级为 Node + InitializeWithData 方法协议，
		# 这里锁定新边界，避免回退到会让 GDScript 属性组件解析失败的强类型调用。
		"GetNode<Node>(\"Components/AttributeComponent\")",
		"GetNode<Node>(\"%StatusComponent\")",
		"MonsterDataProtocol.ReadResourceField(data, \"InitialAttributes\")",
		# 旧美术/行为树代码保持注释状态，不得被顺手删掉或启用。
		"// if (data.ModelScene != null)",
	]:
		assert_true(text.contains(snippet), "旧 C# 垫片必须保留实现片段：%s" % snippet)


## 验证生产 GDScript 与旧 C# 垫片都不再强类型前置判定怪物数据脚本。
##
## @return 无返回值。
func test_monster_data_type_checks_are_cross_language() -> void:
	var gd_text: String = FileAccess.get_file_as_string(MONSTER_GD)
	var cs_text: String = CS_OPTIONAL.read(MONSTER_CS)

	assert_false(gd_text.contains("MonsterData)"), "GDScript 不得声明旧 C# 怪物数据类型判断。")
	assert_true(gd_text.contains("func _read_resource_field(data: Resource, field_name: String) -> Resource:"), "必须保留跨语言资源字段读取。")
	assert_true(gd_text.contains("func _read_monster_name(data: Resource) -> String:"), "必须保留跨语言名称读取。")
	assert_true(gd_text.contains("func _read_elemental_property(data: Resource) -> int:"), "必须保留跨语言五行读取。")
	assert_true(gd_text.contains("func _read_faction(data: Resource) -> int:"), "必须保留跨语言阵营读取。")
	assert_true(gd_text.contains("data.get(\"MonsterName\")"), "名称必须按字段名读取。")
	assert_true(gd_text.contains("data.get(\"Faction\")"), "阵营必须按字段名读取。")
	if not cs_text.is_empty():
		assert_true(cs_text.contains("MonsterDataProtocol.ReadFaction"), "旧 C# 垫片必须仍经协议读阵营。")


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
