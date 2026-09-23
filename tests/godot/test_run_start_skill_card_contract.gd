@tool
extends McpTestSuite

## 开局技能卡抽取的契约套件。
##
## 覆盖三层契约：
## 1）**卡池**：来自生产目录、排除测试资产、判定标准与出战卡组一致、缓存且顺序稳定；
## 2）**抽取与选择**：恰好 5 张且互不重复、必须选满 2 张才能确认、第 3 张被拒、
##    已选中可取消、选中的 2 张真实写入背包、未选中的不写入、同局只抽一次；
## 3）**时机**：订阅路径与「初始化已完成」的补偿路径都能触发抽卡。
##
## 夹具刻意复刻生产层级 `Main/UI/HUDLayer/HUDRoot/<界面>`，因此脚本里那两个
## `../../../../` 的默认导出路径也会被这套测试一并验证——路径写错会在这里直接失败。
##
## 两条**环境限制**（因此改由源码形状断言 + 运行期 `game_eval` 覆盖，而不是在这里装作测过）：
## - 编辑器里非 `@tool` 脚本经 `PackedScene.instantiate()` 会得到「占位实例」，方法不可调用。
##   所以界面用 `脚本.new()` 构造并显式调用 `Setup()`，卡面用本文件内的 `@tool` 桩视图替代
##   真实战斗卡面；战斗卡面自身的实例化行为由 `game_eval` 在真实游戏里验证。
## - 夹具不入场景树（避免 `_ready` 隐式触发、也避免抽卡把测试运行器暂停），
##   因此「抽卡期间暂停 / 确认后归还暂停」由源码形状断言锁定。

const DRAFT_SCRIPT: GDScript = preload("res://core/gameflow/run_start_skill_card_draft.gd")
const DRAFT_GD: String = "res://core/gameflow/run_start_skill_card_draft.gd"
const DRAFT_SCENE_PATH: String = "res://scenes/ui_scenes/skill_card_draft_screen.tscn"
const SKILL_CARD_GD: String = "res://scripts/card_scripts/skill_card.gd"
const INVENTORY_SCRIPT: GDScript = preload("res://entities/components/inventory_component.gd")
## 卡牌视觉数值的共享来源；悬停 / 选中的预期值都从它取，避免测试再抄一份字面量。
const CARD_VISUALS: GDScript = preload("res://core/card_visual_config.gd")
## 共享来源脚本与战斗卡牌脚本，用于锁定「数值只有一份来源」这条契约。
const CARD_VISUAL_CONFIG_GD: String = "res://core/card_visual_config.gd"
const CARD_MANAGER_GD: String = "res://scripts/card_scripts/card_manager.gd"
## 提示浮窗场景，用于锁定「暂停下浮窗仍可用」这条契约。
const TOOLTIP_PANEL_SCENE_PATH: String = "res://scenes/ui_scenes/TooltipPanel.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
## 屏幕过渡场景（场景切换黑幕），用于锁定「过渡动画必须无视暂停」这条契约。
const TRANSITIONS_SCENE_PATH: String = "res://scenes/ui_scenes/ScreenTransitions.tscn"

## 抽卡界面的确认按钮、卡面容器与提示标签路径（与界面场景结构一致）。
const CONFIRM_BUTTON_PATH: String = "Content/ConfirmButton"
const CARDS_CONTAINER_PATH: String = "Content/CardsContainer"


## 开局初始化桩：只回答「是否已初始化」，用于分别驱动订阅路径与补偿路径。
class InitializerStub extends Node:
	signal RunStartInitialized

	## 是否已经完成初始化。
	var Initialized: bool = false

	## 返回初始化状态。
	## 返回值：true 表示已初始化。
	func HasInitialized() -> bool:
		return Initialized


## 卡面桩视图：替代真实战斗卡面，记录收到的卡数据。
##
## 真实的 `SkillCard` 是非 `@tool` 脚本，在编辑器测试里无法被实例化出真实行为，
## 因此这里只验证「抽卡界面是否把正确的卡交给卡面视图」这条契约。
class StubCardView extends Node2D:
	## 收到的卡数据（按绑定顺序）。
	var ReceivedCards: Array[Resource] = []

	## unlock() 被调用的次数。
	var UnlockCount: int = 0

	## 模拟生产卡面的初始化协议。
	## 参数 card_data：本卡槽要展示的技能卡。
	## 返回值：无。
	func init_card_data(card_data: Resource) -> void:
		ReceivedCards.append(card_data)

	## 模拟生产卡面的解除锁定协议（隐藏 LockColor 遮罩）。
	## 返回值：无。
	func unlock() -> void:
		UnlockCount += 1
		var lock_color: CanvasItem = get_node_or_null("LockColor") as CanvasItem
		if lock_color != null:
			lock_color.visible = false


## 提示浮窗桩：记录抽卡界面请求过的标题与描述。
##
## 真实 `TooltipPanel` 会延迟显示、跟随鼠标并做渐现，这些都与本套件要验证的
## 「界面是否在正确的时机请求了正确的文案」无关，因此这里只记录调用参数。
class StubTooltipPanel extends Node:
	## 收到的标题（按调用顺序）。
	var Titles: Array[String] = []

	## 收到的描述（按调用顺序）。
	var Descriptions: Array[String] = []

	## hide_tooltip() 被调用的次数。
	var HideCount: int = 0

	## 模拟生产浮窗的显示协议。
	## 参数 title_text：卡名。
	## 参数 desc_text：卡牌描述。
	## 返回值：无。
	func show_tooltip(title_text: String, desc_text: String) -> void:
		Titles.append(title_text)
		Descriptions.append(desc_text)

	## 模拟生产浮窗的隐藏协议。
	## 返回值：无。
	func hide_tooltip() -> void:
		HideCount += 1


# ----- 夹具 -----

## 搭建与生产一致的开局装配。
##
## 层级复刻 `Main/UI/HUDLayer/HUDRoot/<抽卡界面>`，并在 `Main` 下同时挂初始化桩与玩家，
## 使界面脚本的默认导出路径（`../../../../RunStartInitializer`、`../../../../Player`）
## 能被真实解析。夹具不入场景树，因此 `_ready()` 不会自动触发，由测试显式调用 `Setup()`。
## 参数 initializer_initialized：初始化桩是否报告「已完成」。
## 返回值：{"screen", "inventory", "initializer", "main"}。
func _build_fixture(initializer_initialized: bool = false) -> Dictionary:
	var main: Node = track(Node.new()) as Node
	main.name = "Main"

	var ui: Control = Control.new()
	ui.name = "UI"
	main.add_child(ui)

	var hud_layer: CanvasLayer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	ui.add_child(hud_layer)

	var hud_root: Control = Control.new()
	hud_root.name = "HUDRoot"
	hud_layer.add_child(hud_root)

	var initializer: InitializerStub = InitializerStub.new()
	initializer.name = "RunStartInitializer"
	initializer.Initialized = initializer_initialized
	main.add_child(initializer)

	var player: Node = Node.new()
	player.name = "Player"
	main.add_child(player)

	var components: Node = Node.new()
	components.name = "Components"
	player.add_child(components)

	var inventory: Node = INVENTORY_SCRIPT.new() as Node
	inventory.name = "InventoryComponent"
	components.add_child(inventory)

	# 悬停提示浮窗与抽卡界面同级挂在 HUDRoot 下，与生产 Main.tscn 的结构一致；
	# 界面脚本的默认 TooltipPanelPath（"../TooltipPanel"）因此能被真实解析。
	var tooltip_panel: StubTooltipPanel = StubTooltipPanel.new()
	tooltip_panel.name = "TooltipPanel"
	hud_root.add_child(tooltip_panel)

	var screen: Control = DRAFT_SCRIPT.new() as Control
	screen.name = "SkillCardDraftScreen"
	_build_screen_children(screen)
	screen.set("CardScenePrefab", _build_stub_card_scene())
	hud_root.add_child(screen)

	# 与生产 `_ready()` 等价的初始化入口。
	screen.call("Setup")

	return {
		"screen": screen,
		"inventory": inventory,
		"initializer": initializer,
		"main": main,
		"tooltip_panel": tooltip_panel,
	}


## 按界面场景的结构手工搭建子节点。
##
## 参数 screen：抽卡界面根节点。
## 返回值：无。
func _build_screen_children(screen: Control) -> void:
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	screen.add_child(content)

	var cards: HBoxContainer = HBoxContainer.new()
	cards.name = "CardsContainer"
	content.add_child(cards)

	var hint: Label = Label.new()
	hint.name = "HintLabel"
	content.add_child(hint)

	var confirm: Button = Button.new()
	confirm.name = "ConfirmButton"
	content.add_child(confirm)


## 构造一个卡面桩场景，使抽卡界面走真实的「实例化卡面并绑定数据」路径。
## 返回值：根节点为 StubCardView 的 PackedScene。
func _build_stub_card_scene() -> PackedScene:
	var scene: PackedScene = PackedScene.new()
	var view: StubCardView = StubCardView.new()
	view.name = "StubSkillCardView"
	# 复刻 SkillCard.tscn 的关键结构：一块**默认可见**的锁定遮罩。
	# 生产卡面正是靠 unlock() 把它关掉，漏掉这一步会让每张卡都盖着黑块。
	var lock_color: ColorRect = ColorRect.new()
	lock_color.name = "LockColor"
	lock_color.size = Vector2(210.0, 150.0)
	lock_color.position = Vector2(-105.0, -75.0)
	view.add_child(lock_color)
	lock_color.owner = view
	scene.pack(view)
	view.free()
	return scene


## 取出界面里的确认按钮。
## 参数 screen：抽卡界面实例。
## 返回值：确认按钮；缺失时返回 null。
func _confirm_button(screen: Node) -> Button:
	return screen.get_node_or_null(CONFIRM_BUTTON_PATH) as Button


## 取出第 index 个卡槽占位。
## 参数 screen：抽卡界面实例。
## 参数 index：卡槽序号。
## 返回值：卡槽按钮；越界或缺失时返回 null。
func _card_slot(screen: Node, index: int) -> Button:
	var container: Node = screen.get_node_or_null(CARDS_CONTAINER_PATH)
	if container == null or index >= container.get_child_count():
		return null
	return container.get_child(index) as Button


## 取出第 index 个卡槽上挂载的卡面桩视图。
## 参数 screen：抽卡界面实例。
## 参数 index：卡槽序号。
## 返回值：卡面桩视图；缺失时返回 null。
func _card_view(screen: Node, index: int) -> StubCardView:
	var slot: Button = _card_slot(screen, index)
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0) as StubCardView


## 模拟点击第 index 张卡。
## 参数 screen：抽卡界面实例。
## 参数 index：卡槽序号。
## 返回值：无。
func _click_card(screen: Node, index: int) -> void:
	var slot: Button = _card_slot(screen, index)
	assert_true(slot != null, "卡槽 %d 必须存在。" % index)
	if slot != null:
		slot.pressed.emit()


## 统计选中集合里的卡数量。
## 参数 screen：抽卡界面实例。
## 返回值：选中张数。
func _selected_count(screen: Node) -> int:
	var selected: Array = screen.call("GetSelectedCards")
	return selected.size()


## 判断资源是否暴露 Skill 字段（独立实现，避免用被测代码自证）。
## 参数 card：待判定资源。
## 返回值：true 表示带 Skill 字段。
func _has_skill_field(card: Resource) -> bool:
	for property_info: Variant in card.get_property_list():
		if property_info is Dictionary \
				and StringName(property_info.get("name", "")) == &"Skill":
			return true
	return false


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：开局抽卡契约套件名。
func suite_name() -> String:
	return "run_start_skill_card_contract"


# ----- 卡池 -----

## 验证卡池来自生产目录、排除测试资产，且判定标准与出战卡组一致。
## 返回值：无。
func test_card_pool_excludes_test_assets() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	var pool: Array = screen.call("GetCardPool")

	assert_gt(pool.size(), 4, "技能卡池必须足够支撑一次 5 张抽取。")

	var test_asset_count: int = 0
	var missing_skill_count: int = 0
	var null_skill_count: int = 0
	for value: Variant in pool:
		var card: Resource = value as Resource
		if card == null:
			continue
		if card.resource_path.contains("test_card_"):
			test_asset_count += 1
		if not _has_skill_field(card):
			missing_skill_count += 1
		elif card.get("Skill") == null:
			null_skill_count += 1

	assert_eq(test_asset_count, 0, "测试资产（test_card_*）不得进入抽卡池。")
	assert_eq(missing_skill_count, 0, "卡池元素必须暴露 Skill 字段，与出战卡组判定协议一致。")
	assert_eq(null_skill_count, 0, "卡池元素必须带有真实的战斗技能数据。")


## 验证卡池被缓存，且顺序按资源路径稳定排列。
## 返回值：无。
func test_card_pool_is_cached_and_sorted() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	var first: Array = screen.call("GetCardPool")
	var second: Array = screen.call("GetCardPool")

	assert_true(is_same(first, second), "卡池必须被缓存：重复枚举会白白拖慢开局。")

	var inversions: int = 0
	var previous_path: String = ""
	for value: Variant in first:
		var card: Resource = value as Resource
		if card == null:
			continue
		if card.resource_path < previous_path:
			inversions += 1
		previous_path = card.resource_path

	assert_eq(inversions, 0, "卡池必须按资源路径排序，才能得到稳定顺序。")


# ----- 抽取与展示 -----

## 验证抽取结果：恰好 5 张、互不重复、全部来自卡池；重复多轮以覆盖随机性。
## 返回值：无。
func test_draw_returns_five_distinct_cards() -> void:
	for round_index in 4:
		var fixture: Dictionary = _build_fixture()
		var screen: Node = fixture["screen"]
		assert_true(bool(screen.call("StartDraft")), "开局抽卡必须成功发起。")

		var drawn: Array = screen.call("GetDrawnCards")
		assert_eq(drawn.size(), 5, "每局必须恰好抽出 5 张（第 %d 轮）。" % round_index)

		var unique_paths: Dictionary = {}
		for value: Variant in drawn:
			var card: Resource = value as Resource
			unique_paths[card.resource_path if card != null else ""] = true
		assert_eq(unique_paths.size(), 5, "5 张必须互不重复（第 %d 轮）。" % round_index)

		var pool: Array = screen.call("GetCardPool")
		var outside_count: int = 0
		for value: Variant in drawn:
			if not pool.has(value):
				outside_count += 1
		assert_eq(outside_count, 0, "抽出的卡必须来自技能卡池（第 %d 轮）。" % round_index)


## 验证抽出的每张卡都被交给了对应卡槽上的卡面视图。
## 返回值：无。
func test_drawn_cards_are_bound_to_card_views() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	screen.call("StartDraft")

	var drawn: Array = screen.call("GetDrawnCards")
	var container: Node = screen.get_node_or_null(CARDS_CONTAINER_PATH)
	assert_true(container != null, "抽卡界面必须提供卡面容器。")
	if container == null:
		return

	assert_eq(container.get_child_count(), 5, "卡面容器里必须恰好有 5 个卡槽。")

	var unbound_count: int = 0
	var locked_count: int = 0
	for index in drawn.size():
		var view: StubCardView = _card_view(screen, index)
		if view == null or view.ReceivedCards.size() != 1 or view.ReceivedCards[0] != drawn[index]:
			unbound_count += 1
			continue
		var lock_color: CanvasItem = view.get_node_or_null("LockColor") as CanvasItem
		if view.UnlockCount != 1 or lock_color == null or lock_color.visible:
			locked_count += 1
	assert_eq(unbound_count, 0, "每个卡槽的卡面必须收到它自己那张卡。")
	assert_eq(
		locked_count,
		0,
		"每张卡面都必须被解除一次锁定遮罩；漏掉会让整屏近乎全黑（LockColor 在场景里默认可见）。"
	)


# ----- 选择 -----

## 验证确认按钮的可用性由「恰好 2 张」决定。
## 返回值：无。
func test_confirm_requires_exactly_two_selections() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	var confirm: Button = _confirm_button(screen)
	assert_true(confirm != null, "抽卡界面必须提供确认按钮。")
	if confirm == null:
		return

	screen.call("StartDraft")
	assert_true(confirm.disabled, "一张未选时确认必须不可用。")

	_click_card(screen, 0)
	assert_eq(_selected_count(screen), 1, "点击第一张卡必须选中它。")
	assert_true(confirm.disabled, "只选 1 张时确认必须仍不可用。")

	_click_card(screen, 1)
	assert_eq(_selected_count(screen), 2, "点击第二张卡必须选中它。")
	assert_false(confirm.disabled, "恰好选满 2 张时确认必须可用。")


## 验证选满后再点未选中的卡会被忽略，且已选中的卡可以取消。
## 返回值：无。
func test_third_selection_is_rejected() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	screen.call("StartDraft")

	_click_card(screen, 0)
	_click_card(screen, 1)
	_click_card(screen, 2)

	var drawn: Array = screen.call("GetDrawnCards")
	var selected: Array = screen.call("GetSelectedCards")
	assert_eq(selected.size(), 2, "选中数量必须被限制为 2 张。")
	assert_false(selected.has(drawn[2]), "第三张不得进入选中集合。")

	# 再次点击已选中的卡是取消选择，不是被拒——两条路径都必须正确。
	_click_card(screen, 0)
	assert_eq(_selected_count(screen), 1, "再次点击已选中的卡必须取消该选择。")


# ----- 获取 -----

## 验证确认后选中的 2 张进入玩家背包、未选中的 3 张不进入，且界面收起。
## 返回值：无。
func test_confirm_grants_selected_cards_into_inventory() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	var inventory: Node = fixture["inventory"]
	screen.call("StartDraft")

	_click_card(screen, 0)
	_click_card(screen, 2)

	var drawn: Array = screen.call("GetDrawnCards")
	var first: Resource = drawn[0]
	var second: Resource = drawn[2]

	var confirm: Button = _confirm_button(screen)
	assert_true(confirm != null, "抽卡界面必须提供确认按钮。")
	if confirm == null:
		return
	confirm.pressed.emit()

	assert_eq(int(inventory.call("ItemCnt", first)), 1, "选中的第一张必须进入玩家背包。")
	assert_eq(int(inventory.call("ItemCnt", second)), 1, "选中的第二张必须进入玩家背包。")

	var leaked_count: int = 0
	for index in drawn.size():
		if index == 0 or index == 2:
			continue
		if int(inventory.call("ItemCnt", drawn[index])) > 0:
			leaked_count += 1
	assert_eq(leaked_count, 0, "未选中的卡不得进入玩家背包。")

	assert_false(screen.visible, "确认后抽卡界面必须收起。")


## 验证同一局只抽一次，重复触发不改变已抽出的卡。
## 返回值：无。
func test_start_draft_is_idempotent() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Node = fixture["screen"]
	assert_true(bool(screen.call("StartDraft")), "第一次抽卡必须成功。")
	var first_draw: Array = screen.call("GetDrawnCards")

	assert_false(bool(screen.call("StartDraft")), "同一局不得发起第二次抽卡。")
	var second_draw: Array = screen.call("GetDrawnCards")
	assert_eq(second_draw.size(), first_draw.size(), "重复触发不得改变已抽出的卡数。")
	assert_true(second_draw == first_draw, "重复触发必须保留同一批卡（内容与顺序都不变）。")


# ----- 时机 -----

## 验证订阅路径：收到初始化信号后才开始抽卡。
## 返回值：无。
func test_draft_starts_on_initialized_signal() -> void:
	var fixture: Dictionary = _build_fixture(false)
	var screen: Node = fixture["screen"]
	assert_false(bool(screen.call("HasDrafted")), "初始化之前不得抽卡。")

	var initializer: Node = fixture["initializer"]
	initializer.emit_signal(&"RunStartInitialized")

	assert_true(bool(screen.call("HasDrafted")), "收到初始化信号后必须开始抽卡。")
	assert_true(screen.visible, "抽卡期间界面必须可见。")


## 验证补偿路径：界面晚于初始化节点就绪时，仍然会在初始化阶段补上抽卡。
##
## 这是本任务最容易写错的一处——抽卡界面挂在 `UI` 之下，必然晚于初始化节点的同步广播，
## 只靠订阅永远收不到信号。因此该用例锁定的正是「补偿检查」这条生产主路径。
## 返回值：无。
func test_draft_compensates_when_already_initialized() -> void:
	var fixture: Dictionary = _build_fixture(true)
	var screen: Node = fixture["screen"]
	assert_true(bool(screen.call("HasDrafted")), "初始化已完成时必须在初始化阶段补偿触发抽卡。")
	assert_true(screen.visible, "补偿触发的抽卡同样必须显示界面。")
	assert_eq(
		(screen.call("GetDrawnCards") as Array).size(),
		5,
		"补偿触发的抽卡同样必须抽出 5 张。"
	)


# ----- 生产接线 -----

## 验证 Main 场景接线、界面场景结构、抽取数值常量，以及暂停归属与卡面守卫的源码形状。
## 返回值：无。
func test_production_wiring_shape() -> void:
	var main_text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	assert_contains(main_text, 'name="SkillCardDraftScreen"', "Main 场景必须挂载开局抽卡界面。")
	assert_contains(main_text, "skill_card_draft_screen.tscn", "抽卡界面必须引用生产场景文件。")

	var screen_text: String = FileAccess.get_file_as_string(DRAFT_SCENE_PATH)
	assert_contains(screen_text, DRAFT_GD, "抽卡界面必须挂载生产脚本。")
	assert_contains(screen_text, "SkillCard.tscn", "抽卡界面必须复用战斗卡面场景。")
	assert_contains(screen_text, 'name="CardsContainer"', "抽卡界面必须提供卡面容器。")
	assert_contains(screen_text, 'name="ConfirmButton"', "抽卡界面必须提供确认按钮。")
	assert_contains(screen_text, "visible = false", "抽卡界面默认必须隐藏，由开局时机决定何时显示。")

	var script_text: String = FileAccess.get_file_as_string(DRAFT_GD)
	assert_contains(script_text, "const DRAW_COUNT: int = 5", "抽取张数必须为 5。")
	assert_contains(script_text, "const PICK_COUNT: int = 2", "选取张数必须为 2。")
	assert_contains(
		script_text,
		'NodePath("../../../../RunStartInitializer")',
		"默认初始化路径必须与生产层级一致（HUDRoot 到 Main 为四层）。"
	)
	assert_contains(script_text, "HasInitialized", "抽卡必须依赖初始化节点的完成状态查询，而不能只靠信号。")

	# 暂停归属：只归还自己造成的那次暂停，避免把其它界面的暂停状态一并解除。
	assert_contains(
		script_text,
		"_was_paused_before_open = _is_tree_paused()",
		"打开界面之前必须记录全局暂停状态。"
	)
	assert_contains(
		script_text,
		"_set_tree_paused(_was_paused_before_open)",
		"收起界面必须只归还本次造成的暂停。"
	)

	# 卡面守卫：战斗路径照旧连接，非战斗路径不报错（编辑器测试无法实例化真实卡面，
	# 因此这里锁定源码形状；真实实例化行为由运行期 game_eval 覆盖）。
	var skill_card_text: String = FileAccess.get_file_as_string(SKILL_CARD_GD)
	assert_contains(
		skill_card_text,
		'has_method("connect_card_signals")',
		"卡面必须用存在性守卫解除对 CardManager 父节点的硬依赖。"
	)
	assert_contains(
		skill_card_text,
		'call("connect_card_signals", self)',
		"守卫为真时仍必须照旧连接，战斗手牌行为不得改变。"
	)


## 暂停期可用性契约。
##
## 两条都曾经真实地把整屏变黑 / 让界面点不动：
## 1) 抽卡界面自己必须 PROCESS_MODE_ALWAYS，否则暂停期间卡面按钮点不动（战斗暂停菜单与天赋界面同样如此）；
## 2) 屏幕过渡动画（场景切换黑幕）必须无视暂停——淡入 Tween/动画一旦被暂停冻住，
##    黑幕会永久停在 alpha=1，把包括抽卡界面在内的整个画面盖成全黑。
## 返回值：无。
func test_pause_safe_ui_and_screen_transition() -> void:
	var screen_text: String = FileAccess.get_file_as_string(DRAFT_SCENE_PATH)
	assert_contains(
		screen_text,
		"process_mode = 3",
		"抽卡界面必须使用 PROCESS_MODE_ALWAYS，否则暂停期间卡面按钮点不动。"
	)

	var transitions_text: String = FileAccess.get_file_as_string(TRANSITIONS_SCENE_PATH)
	assert_contains(
		transitions_text,
		"process_mode = 3",
		"屏幕过渡必须无视暂停：淡入动画被冻住会让黑幕永久停在 alpha=1，整屏全黑。"
	)

	var script_text: String = FileAccess.get_file_as_string(DRAFT_GD)
	assert_contains(
		script_text,
		'has_method("unlock")',
		"挂载卡面后必须解除默认可见的锁定遮罩，否则每张卡都被黑块盖住。"
	)

	var skill_card_text: String = FileAccess.get_file_as_string(SKILL_CARD_GD)
	assert_contains(
		skill_card_text,
		"$LockColor.visible = false",
		"卡面的解锁协议必须隐藏 LockColor，抽卡界面正是依赖它清除遮罩。"
	)


# ----- 悬停与选中动效（照搬战斗卡牌视觉）-----
#
# 夹具刻意不入场景树，而 `Node.create_tween()` 要求节点在树内，因此这些用例断言的是
# **终态**（界面在未入树时直接落终值，见 `_tween_scale` / `_tween_lift`）。
# 补间动画的过程由运行期 `game_eval` 覆盖。

## 模拟鼠标移入第 index 个卡槽。
##
## 生产里悬停由占位 Button 自己的 `mouse_entered` 驱动（卡面被占位覆盖，卡面自身的
## `Area2D` 收不到事件），所以这里发同一个信号，走与生产完全相同的响应路径。
##
## 参数 screen：抽卡界面实例。
## 参数 index：卡槽序号。
## 返回值：无。
func _hover_card(screen: Node, index: int) -> void:
	var slot: Button = _card_slot(screen, index)
	assert_true(slot != null, "卡槽 %d 必须存在。" % index)
	if slot != null:
		slot.mouse_entered.emit()


## 模拟鼠标移出第 index 个卡槽。
## 参数 screen：抽卡界面实例。
## 参数 index：卡槽序号。
## 返回值：无。
func _unhover_card(screen: Node, index: int) -> void:
	var slot: Button = _card_slot(screen, index)
	assert_true(slot != null, "卡槽 %d 必须存在。" % index)
	if slot != null:
		slot.mouse_exited.emit()


## 悬停必须把卡面放大到战斗的悬停值并置顶，移出必须回到战斗的常态值与层级。
## 返回值：无。
func test_hover_applies_battle_scale_and_layer() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Control = fixture["screen"]
	screen.call("StartDraft")

	var view: StubCardView = _card_view(screen, 0)
	assert_true(view != null, "卡槽 0 必须挂载卡面。")
	assert_true(
		view.scale == CARD_VISUALS.CARD_NORMAL_SCALE,
		"初始卡面必须是战斗的常态缩放，实际 %s。" % str(view.scale)
	)
	assert_true(
		view.z_index == CARD_VISUALS.CARD_Z_INDEX_NORMAL,
		"初始卡面必须是战斗的常态层级，实际 %d。" % view.z_index
	)

	_hover_card(screen, 0)
	assert_true(
		view.scale == CARD_VISUALS.CARD_HOVER_SCALE,
		"悬停必须放大到战斗的悬停缩放，实际 %s。" % str(view.scale)
	)
	assert_true(
		view.z_index == CARD_VISUALS.CARD_Z_INDEX_HOVER,
		"悬停必须置顶到战斗的悬停层级，实际 %d。" % view.z_index
	)

	_unhover_card(screen, 0)
	assert_true(
		view.scale == CARD_VISUALS.CARD_NORMAL_SCALE,
		"移出必须回到战斗的常态缩放，实际 %s。" % str(view.scale)
	)
	assert_true(
		view.z_index == CARD_VISUALS.CARD_Z_INDEX_NORMAL,
		"移出必须回到战斗的常态层级，实际 %d。" % view.z_index
	)


## 悬停与选中都不得改变卡面颜色（战斗侧只用缩放与层级表达状态）。
## 返回值：无。
func test_hover_and_selection_never_tint_card_view() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Control = fixture["screen"]
	screen.call("StartDraft")

	var view: StubCardView = _card_view(screen, 1)
	assert_true(view != null, "卡槽 1 必须挂载卡面。")

	_hover_card(screen, 1)
	assert_true(view.modulate == Color.WHITE, "悬停不得给卡面染色，实际 %s。" % str(view.modulate))

	_click_card(screen, 1)
	assert_true(view.modulate == Color.WHITE, "选中不得给卡面染色，实际 %s。" % str(view.modulate))

	_unhover_card(screen, 1)
	assert_true(view.modulate == Color.WHITE, "移出后卡面也不得被染色。")


## 选中必须把卡面抬升战斗的抬升距离，取消必须回到基准位置。
##
## 位置按「基准位置 + 偏移」计算而不是在当前值上累加，所以反复切换不会越飘越远。
## 返回值：无。
func test_selection_lifts_card_view_by_battle_distance() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Control = fixture["screen"]
	screen.call("StartDraft")

	var view: StubCardView = _card_view(screen, 2)
	assert_true(view != null, "卡槽 2 必须挂载卡面。")
	var base_position: Vector2 = view.position

	_click_card(screen, 2)
	var expected_lifted: Vector2 = base_position \
			+ Vector2(0.0, -CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE)
	assert_true(
		view.position == expected_lifted,
		"选中必须按战斗的距离上移卡面：期望 %s，实际 %s。" % [str(expected_lifted), str(view.position)]
	)

	_click_card(screen, 2)
	assert_true(
		view.position == base_position,
		"取消选中必须把卡面放回基准位置，实际 %s。" % str(view.position)
	)


## 反复选中 / 取消不得累积位移。
## 返回值：无。
func test_repeated_toggling_does_not_accumulate_offset() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Control = fixture["screen"]
	screen.call("StartDraft")

	var view: StubCardView = _card_view(screen, 3)
	assert_true(view != null, "卡槽 3 必须挂载卡面。")
	var base_position: Vector2 = view.position

	for _round in 3:
		_click_card(screen, 3)
		_click_card(screen, 3)

	assert_true(
		view.position == base_position,
		"三轮反复切换后卡面必须仍在基准位置，实际 %s。" % str(view.position)
	)


## 悬停必须让共享浮窗显示该卡的卡名与描述，移出必须隐藏。
## 返回值：无。
func test_hover_shows_card_name_and_description_in_tooltip() -> void:
	var fixture: Dictionary = _build_fixture()
	var screen: Control = fixture["screen"]
	var panel: StubTooltipPanel = fixture["tooltip_panel"]
	screen.call("StartDraft")

	var drawn: Array = screen.call("GetDrawnCards")
	_hover_card(screen, 2)

	# 卡数据的显示名自带回退语义：优先 DisplayName，缺失时用 CardName。
	# 生产技能卡目前没有 DisplayName 字段，因此实际取到的是 CardName——这里复刻同一条
	# 回退规则，避免断言把"字段恰好叫什么"写死成对实现的重复描述。
	var expected_title: Variant = drawn[2].get("DisplayName")
	if expected_title == null or str(expected_title).strip_edges().is_empty():
		expected_title = drawn[2].get("CardName")

	assert_true(panel.Titles.size() == 1, "悬停一次必须请求一次浮窗显示。")
	assert_true(
		panel.Titles[0] == str(expected_title),
		"浮窗标题必须是该卡的显示名：期望 %s，实际 %s。" % [str(expected_title), panel.Titles[0]]
	)
	assert_true(panel.Descriptions.size() == 1, "浮窗请求必须同时带上描述。")
	assert_true(
		not panel.Descriptions[0].is_empty(),
		"浮窗描述不应为空（卡数据自带 DisplayDescription）。"
	)

	_unhover_card(screen, 2)
	assert_true(panel.HideCount == 1, "移出必须隐藏浮窗。")


## 视觉数值必须只有一份来源：战斗卡牌脚本引用共享配置，而不是各写一份字面量。
## 返回值：无。
func test_card_visual_values_come_from_one_shared_source() -> void:
	var manager_text: String = FileAccess.get_file_as_string(CARD_MANAGER_GD)

	for export_name: String in [
		"card_normal_scale",
		"card_hover_scale",
		"scale_tween_duration",
		"click_selected_card_lift_distance",
		"click_selected_card_lift_duration",
	]:
		assert_contains(
			manager_text,
			"@export var %s" % export_name,
			"战斗卡牌的导出 %s 必须保留：既有测试会写它，场景也需要可覆盖入口。" % export_name
		)

	assert_contains(
		manager_text,
		'preload("res://core/card_visual_config.gd")',
		"战斗卡牌脚本必须引用共享的视觉配置。"
	)
	assert_contains(
		manager_text,
		"= CARD_VISUALS.CARD_HOVER_SCALE",
		"战斗卡牌的悬停缩放必须取自共享配置，而不是本地字面量。"
	)
	assert_contains(
		manager_text,
		"= CARD_VISUALS.SCALE_TWEEN_DURATION",
		"战斗卡牌的缩放时长必须取自共享配置。"
	)
	assert_contains(
		manager_text,
		"= CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE",
		"战斗卡牌的选中抬升距离必须取自共享配置。"
	)

	var draft_text: String = FileAccess.get_file_as_string(DRAFT_GD)
	assert_contains(
		draft_text,
		'preload("res://core/card_visual_config.gd")',
		"抽卡界面必须引用同一份共享视觉配置。"
	)
	assert_contains(
		draft_text,
		"CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE",
		"抽卡界面的选中抬升必须取自共享配置。"
	)


## 共享配置里的数值必须等于战斗原有的手感取值（重构不得顺手改掉表现）。
## 返回值：无。
func test_shared_config_keeps_battle_feel_values() -> void:
	assert_true(
		CARD_VISUALS.CARD_NORMAL_SCALE == Vector2(1.0, 1.0), "常态缩放必须保持战斗原值。"
	)
	assert_true(
		CARD_VISUALS.CARD_HOVER_SCALE == Vector2(1.05, 1.05), "悬停缩放必须保持战斗原值。"
	)
	assert_true(CARD_VISUALS.SCALE_TWEEN_DURATION == 0.08, "缩放时长必须保持战斗原值。")
	assert_true(CARD_VISUALS.CARD_Z_INDEX_NORMAL == 1, "常态层级必须保持战斗原值。")
	assert_true(CARD_VISUALS.CARD_Z_INDEX_HOVER == 2, "悬停层级必须保持战斗原值。")
	assert_true(
		CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE == 36.0, "选中抬升距离必须保持战斗原值。"
	)
	assert_true(
		CARD_VISUALS.CLICK_SELECTED_LIFT_DURATION == 0.12, "选中抬升时长必须保持战斗原值。"
	)


## 提示浮窗必须在暂停下仍能工作，否则悬停提示永远不显示（抽卡界面正是暂停态）。
## 返回值：无。
func test_tooltip_panel_is_pause_safe() -> void:
	var panel_text: String = FileAccess.get_file_as_string(TOOLTIP_PANEL_SCENE_PATH)
	assert_contains(
		panel_text,
		"process_mode = 3",
		"提示浮窗必须无视暂停：延迟显示与跟随鼠标都在 _process，渐现依赖 Tween。"
	)
