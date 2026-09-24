@tool
extends McpTestSuite

## 天赋选择流程的运行时契约套件。
##
## 覆盖三条「接线断了会静默失效」的行为：池按目录枚举装配、属性天赋能从真实玩家结构上
## 解析出属性组件、天赋界面只归还自己造成的那次暂停。
##
## 断言偏向可观察行为而不是实现细节：池装配与效果应用直接调用真实脚本，
## 暂停与视觉一致性则以源码形状 + 数值快照锁定（这两者无法在未入树的夹具里跑出终态）。

const TALENT_MANAGER_SCRIPT: GDScript = preload("res://resources/talents/talent_manager.gd")
const ATTRIBUTE_TALENT_EFFECT_SCRIPT: GDScript = preload("res://resources/talents/attribute_talent_effect.gd")
const CARD_VISUALS: GDScript = preload("res://core/card_visual_config.gd")

## 天赋资源目录，与 TalentManager 的 CardPoolDirectory 默认值保持一致。
const TALENT_DIRECTORY: String = "res://resources/talents"

## 生产场景路径：界面结构与浮窗绘制层级都以真实场景文件为准。
const TALENT_SCREEN_SCENE_PATH: String = "res://scenes/talents/talent_screen.tscn"
const TALENT_CARD_SCENE_PATH: String = "res://scenes/talents/talent_card.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"

## 本次要求交付的测试天赋卡数量下限。
##
## 用「下限」而不是「恰好 10」：后续继续往目录里加天赋卡时，这个用例仍然成立，
## 而不会因为内容扩充而变红。
const MIN_TALENT_COUNT: int = 10


## 套件名，供 MCP 测试入口按名称过滤（`test_run(suite="talent_selection_contract")`）。
func suite_name() -> String:
	return "talent_selection_contract"


## 复刻玩家「用属性名暴露组件」的结构。
class FakeTalentHost extends Node:
	## 玩家脚本用属性名暴露的属性组件。
	var Attributes: Node = null


## 记录属性天赋写入的永久加成。
class FakeTalentAttributeComponent extends Node:
	## 属性类型整数值 -> 累计增量。
	var bonuses: Dictionary = {}

	## 记录一次永久加成。
	## 参数 attribute_type：属性类型整数值。
	## 参数 value：本次增量。
	## 参数 _source：变化来源，测试夹具不使用。
	## 返回值：固定 true，表示入队成功。
	func AddPermanentBonus(attribute_type: Variant, value: float, _source: Variant = null) -> bool:
		bonuses[int(attribute_type)] = float(bonuses.get(int(attribute_type), 0.0)) + value
		return true


## 验证天赋池按目录枚举装配，且显式池保持为空。
##
## 这是「新增一张天赋卡不需要改场景文件」的判据：池必须来自目录扫描。
func test_talent_pool_is_enumerated_from_directory() -> void:
	var manager: Node = TALENT_MANAGER_SCRIPT.new() as Node
	assert_true(manager != null, "TalentManager 脚本必须能够实例化。")
	if manager == null:
		return

	# 显式池默认必须为空：它只是给测试与特殊玩法注入资源的补充入口，
	# 生产内容一律走目录。
	var explicit_pool: Array = manager.get("AllTalentsPool")
	assert_eq(explicit_pool.size(), 0, "TalentManager 的显式天赋池默认值必须为空数组。")

	var pool: Array = manager.call("_build_talent_pool")
	assert_true(
		pool.size() >= MIN_TALENT_COUNT,
		"目录枚举必须至少装配出 %d 张天赋卡，实际 %d 张。" % [MIN_TALENT_COUNT, pool.size()]
	)

	# 入池的每一张都必须真的可被选择：没有效果的天赋卡选完不会产生任何变化。
	var incomplete: Array = []
	for resource: Variant in pool:
		if not (resource is Resource):
			incomplete.append("<非资源>")
			continue
		var effects: Variant = (resource as Resource).get("Effects")
		if typeof(effects) != TYPE_ARRAY or (effects as Array).is_empty():
			incomplete.append(str((resource as Resource).get("TalentName")))
	assert_true(incomplete.is_empty(), "每张入池天赋都必须至少带 1 条效果，缺失：%s" % str(incomplete))

	manager.free()


## 验证交付的天赋资源逐个字段完整，且效果都实现了 Apply 协议。
func test_talent_resources_are_complete() -> void:
	var dir: DirAccess = DirAccess.open(TALENT_DIRECTORY)
	assert_true(dir != null, "天赋资源目录必须存在：%s" % TALENT_DIRECTORY)
	if dir == null:
		return

	var paths: Array[String] = []
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			paths.append(TALENT_DIRECTORY + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	assert_true(
		paths.size() >= MIN_TALENT_COUNT,
		"天赋目录必须至少包含 %d 个 .tres，实际 %d 个。" % [MIN_TALENT_COUNT, paths.size()]
	)

	for path: String in paths:
		var data: Resource = load(path) as Resource
		assert_true(data != null, "天赋资源必须能够加载：%s" % path)
		if data == null:
			continue

		assert_false(
			str(data.get("TalentName")).strip_edges().is_empty(),
			"天赋名称不得为空：%s" % path
		)
		assert_false(
			str(data.get("Description")).strip_edges().is_empty(),
			"天赋描述不得为空：%s" % path
		)
		assert_true(data.get("TalentTexture") != null, "天赋图片不得为空：%s" % path)

		var effects: Array = data.get("Effects")
		assert_true(effects.size() >= 1, "天赋必须至少带 1 条效果：%s" % path)
		for effect: Variant in effects:
			assert_true(
				effect is Resource and (effect as Resource).has_method("Apply"),
				"天赋效果必须实现 Apply 协议：%s" % path
			)


## 验证属性天赋能通过「Attributes 属性」解析到组件并真实应用加成。
##
## 这正是本次修的缺陷：旧实现只查玩家根下的 `AttributeComponent`，
## 而 player.tscn 的实际布局是 `Components/AttributeComponent`，
## 于是属性天赋从不生效、也不留任何日志。
func test_attribute_talent_effect_resolves_exposed_component() -> void:
	var host := FakeTalentHost.new()
	var component := FakeTalentAttributeComponent.new()
	host.add_child(component)
	host.Attributes = component

	var effect := ATTRIBUTE_TALENT_EFFECT_SCRIPT.new() as Resource
	effect.set("TargetAttribute", 2)
	effect.set("BonusValue", 7.0)
	effect.call("Apply", host)

	assert_true(
		component.bonuses.has(2),
		"属性天赋必须能通过 Attributes 属性解析到属性组件并应用加成。"
	)
	assert_true(
		is_equal_approx(float(component.bonuses.get(2, 0.0)), 7.0),
		"属性天赋必须把配置的数值原样写入属性组件。"
	)

	host.free()


## 验证缺少 Attributes 属性时回退到组件子节点路径。
##
## 兜底分支覆盖「宿主不是 player.gd 而是别的实现」的情况；没有它，
## 换一个不带该属性的宿主就会重演一次静默失效。
func test_attribute_talent_effect_falls_back_to_component_path() -> void:
	var host := Node.new()
	var holder := Node.new()
	holder.name = "Components"
	var component := FakeTalentAttributeComponent.new()
	component.name = "AttributeComponent"
	host.add_child(holder)
	holder.add_child(component)

	var effect := ATTRIBUTE_TALENT_EFFECT_SCRIPT.new() as Resource
	effect.set("TargetAttribute", 5)
	effect.set("BonusValue", 20.0)
	effect.call("Apply", host)

	assert_true(
		component.bonuses.has(5),
		"缺少 Attributes 属性时必须回退到 Components/AttributeComponent 路径。"
	)
	assert_true(
		is_equal_approx(float(component.bonuses.get(5, 0.0)), 20.0),
		"兜底路径也必须把配置的数值原样写入属性组件。"
	)

	host.free()


## 验证天赋卡面从共享配置读视觉数值，且共享数值本身没有被顺手改掉。
##
## 数值快照的意义：这一层是「另一个界面复用战斗手感」的唯一防线，
## 只断言引用共享配置还不够——共享配置自己被改坏同样会让手感漂移。
func test_talent_card_uses_shared_visual_config() -> void:
	var source: String = FileAccess.get_file_as_string("res://resources/talents/talent_card.gd")
	assert_true(
		source.contains("res://core/card_visual_config.gd"),
		"天赋卡必须从共享的 card_visual_config.gd 读取视觉数值，而不是自己再写一份。"
	)
	assert_true(
		source.contains("CARD_VISUALS.CARD_HOVER_SCALE"),
		"天赋卡悬停缩放必须取自共享配置。"
	)
	assert_true(
		source.contains("CARD_VISUALS.SCALE_TWEEN_DURATION"),
		"天赋卡缩放时长必须取自共享配置。"
	)
	assert_true(
		source.contains("CARD_VISUALS.CARD_Z_INDEX_HOVER"),
		"天赋卡悬停层级必须取自共享配置。"
	)

	assert_true(
		is_equal_approx(CARD_VISUALS.CARD_HOVER_SCALE.x, 1.05),
		"共享悬停缩放必须保持 1.05，与战斗手牌一致。"
	)
	assert_true(
		is_equal_approx(CARD_VISUALS.SCALE_TWEEN_DURATION, 0.08),
		"共享缩放时长必须保持 0.08 秒。"
	)
	assert_eq(CARD_VISUALS.CARD_Z_INDEX_HOVER, 2, "共享悬停层级必须保持 2。")
	assert_eq(CARD_VISUALS.CARD_Z_INDEX_NORMAL, 1, "共享常态层级必须保持 1。")


## 验证天赋界面只归还自己造成的那次暂停。
##
## 天赋界面与暂停菜单共用同一个全局暂停开关（`pause_menu.gd` 有同样的约定）。
## 无条件置 false 会在「暂停菜单叠在天赋界面之上」时把菜单的暂停一起解除。
func test_talent_manager_returns_only_its_own_pause() -> void:
	var source: String = FileAccess.get_file_as_string("res://resources/talents/talent_manager.gd")
	assert_true(
		source.contains("_was_paused_before_open"),
		"天赋界面必须记录打开之前的暂停状态。"
	)
	assert_true(
		source.contains("_set_tree_paused(_was_paused_before_open)"),
		"关闭天赋界面必须归还打开前记录的那次暂停。"
	)
	assert_false(
		source.contains("get_tree().paused = false"),
		"天赋界面不得无条件解除全局暂停，否则会关掉别的系统造成的暂停。"
	)


## 验证共享浮窗排在天赋界面之后，否则悬停详情会被遮罩盖住。
##
## 两者现在同处 `HUDLayer` 的 canvas 内（天赋界面已在本次修复中由 CanvasLayer 改为
## Control），绘制顺序因此由 `HUDRoot` 里的兄弟次序决定。这个顺序写错不会报任何错，
## 只会让浮窗"看得见地"消失，所以必须在这里钉死。
func test_tooltip_panel_draws_above_talent_screen() -> void:
	var main_text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	var talent_pos: int = main_text.find("name=\"TalentScreen\"")
	var tooltip_pos: int = main_text.find("name=\"TooltipPanel\"")
	assert_true(talent_pos >= 0, "Main.tscn 必须挂载 TalentScreen。")
	assert_true(tooltip_pos >= 0, "Main.tscn 必须挂载 TooltipPanel。")
	assert_true(
		tooltip_pos > talent_pos,
		"TooltipPanel 必须声明在 TalentScreen 之后：同层节点后声明者绘制在上，"
		+ "浮窗排在前面会被天赋界面的半透明遮罩盖住。"
	)


## 验证天赋界面根节点是 Control，与开局技能卡抽取界面同范式。
##
## 这条同时守着两个前提：与父级 `HUDLayer` 同生死（战斗切换时一起退场），
## 以及与共享浮窗同处一个 canvas（绘制顺序才可比）。
func test_talent_screen_root_is_control() -> void:
	var packed_scene := load(TALENT_SCREEN_SCENE_PATH) as PackedScene
	assert_true(packed_scene != null, "天赋选择生产场景必须能够加载。")
	if packed_scene == null:
		return
	var screen := packed_scene.instantiate() as Control
	assert_true(screen != null, "天赋界面根节点必须是 Control，而不是独立 CanvasLayer。")
	if screen == null:
		return
	assert_eq(
		screen.process_mode,
		Node.PROCESS_MODE_ALWAYS,
		"天赋界面必须保持暂停时仍处理输入，否则打开后无法点击选卡。"
	)
	screen.free()


## 验证天赋卡描述区会随卡片拉伸并自动换行。
##
## 描述一度被钉死在 113x40 的固定矩形里，长描述静默裁掉一半——既不报错也不留日志。
## 现在改用锚定宽度 + 自动换行，卡片尺寸变化时也不会再溢出。
func test_talent_card_description_stretches_and_wraps() -> void:
	var packed_scene := load(TALENT_CARD_SCENE_PATH) as PackedScene
	assert_true(packed_scene != null, "天赋卡生产场景必须能够加载。")
	if packed_scene == null:
		return
	var card := packed_scene.instantiate() as Control
	var description := card.get_node_or_null("DescText") as RichTextLabel
	assert_true(description != null, "天赋卡必须保留 DescText RichTextLabel。")
	if description == null:
		card.free()
		return
	assert_true(
		description.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"描述必须开启自动换行，否则长描述会被静默截断。"
	)
	assert_true(
		description.anchor_right == 1.0 and description.anchor_bottom == 1.0,
		"描述区必须锚定到卡片右下，随卡片尺寸拉伸，而不是写死像素矩形。"
	)
	card.free()
