extends Control

## 开局技能卡抽取界面与流程。
##
## 职责：在开局初始化完成之后抽出 5 张技能卡展示给玩家，收集玩家选择的 2 张，
## 并把它们写入玩家背包；其余 3 张作废。
##
## 设计要点（完整论证见 .trellis/tasks/09-23-run-start-skill-card-draft/design.md）：
##
## 1）**时机不依赖节点顺序**。本界面挂在 `Main.tscn` 的 `UI/HUDLayer/HUDRoot` 之下，
##    必然晚于排在 `UI` 之前的 `RunStartInitializer`；而后者在 `_ready()` 里**同步**广播
##    `RunStartInitialized`。因此只订阅信号永远收不到那一次广播。本脚本固定按
##    「订阅 → 补偿检查 HasInitialized()」的顺序处理，让节点顺序不参与正确性。
##
## 2）**卡池从目录实时枚举**。工程里没有「全部技能卡」的池资源，因此递归扫描
##    `CardPoolDirectory` 并缓存；判定标准是「资源暴露 `Skill` 字段」——与
##    `entities/components/battle_deck_component.gd` 的技能卡判定协议一致，
##    刻意不按脚本路径判断语言。测试资产（`test_card_*`）不进池。
##
## 3）**获取落点是背包**。玩家选择经 `InventoryComponent.AddItem` 写入背包，
##    而不是出战卡组；战斗牌池只读出战卡组，因此抽到的卡不会自动出现在战斗中
##    （这是与用户确认过的决策，详见任务的 prd.md 决策 D1）。
##
## 4）**可测**。所有依赖都通过「导出路径 + 稳定方法协议」访问，脚本里不出现
##    任何 autoload 标识符；测试可以只调用 `StartDraft()` 与选择/确认路径来验证行为。

## 抽卡环节完成信号。
##
## 参数 selected_cards：玩家最终选中的技能卡 Resource 数组（保持选择顺序）。
signal SkillCardDraftCompleted(selected_cards: Array)

## 每次抽取展示的张数。
const DRAW_COUNT: int = 5

## 玩家必须选中的张数。
const PICK_COUNT: int = 2

## 测试资产的文件名前缀；命中即不进抽卡池。
const TEST_ASSET_PREFIX: String = "test_card_"

## 单个卡槽占位的最小尺寸；卡面（Node2D）无法参与容器布局，因此由占位承担尺寸。
const CARD_SLOT_SIZE: Vector2 = Vector2(200.0, 160.0)

## 卡牌视觉数值的共享来源，与战斗手牌（`card_manager.gd`）共用同一份定义。
##
## 悬停缩放、缩放时长、选中抬升距离与层级都从它读取，避免同一套手感在两个界面里
## 各自演化。见 `core/card_visual_config.gd`。
const CARD_VISUALS := preload("res://core/card_visual_config.gd")

## 开局初始化节点相对本节点的路径。
##
## 默认值按实际层级推导：本节点挂在 `Main/UI/HUDLayer/HUDRoot` 之下，
## 因此到 `Main` 需要向上**四**层（HUDRoot → HUDLayer → UI → Main）。
## 路径写错不会静默：解析失败会 `push_error`，并会在运行期的开局验证里暴露。
@export var InitializerPath: NodePath = NodePath("../../../../RunStartInitializer")

## 玩家节点相对本节点的路径，用于定位背包组件；层级理由同上。
@export var PlayerPath: NodePath = NodePath("../../../../Player")

## 玩家背包组件相对玩家节点的路径，与 `player.tscn` 的 `Components` 布局一致。
@export var InventoryComponentPath: NodePath = NodePath("Components/InventoryComponent")

## 技能卡池目录；递归扫描其中的 `.tres`。
@export var CardPoolDirectory: String = "res://resources/skill_cards"

## 单张卡面的生产场景（复用战斗卡面 `SkillCard.tscn`）。
@export var CardScenePrefab: PackedScene

## 放置本轮卡面的容器，相对本节点的路径。
##
## 这里沿用 `run_start_initializer.gd` 的既有范式——导出**路径**而不是导出节点引用：
## 路径可被测试改写，脚本在界面缺失时也能给出可诊断的错误，而不是直接空指针崩溃。
@export var CardsContainerPath: NodePath = NodePath("Content/CardsContainer")

## 确认按钮相对本节点的路径；仅在恰好选中 `PICK_COUNT` 张时可用。
@export var ConfirmButtonPath: NodePath = NodePath("Content/ConfirmButton")

## 选择进度提示标签相对本节点的路径。
@export var HintLabelPath: NodePath = NodePath("Content/HintLabel")

## 全局提示浮窗相对本节点的路径。
##
## 默认值指向 `HUDRoot` 下的共享浮窗，与 `inventory_ui.gd`、`warehouse_ui.gd`
## 的 `TooltipPanelPath` 是同一范式。悬停卡面时用它显示卡名与描述。
@export var TooltipPanelPath: NodePath = NodePath("../TooltipPanel")

## 是否输出抽取细节日志。
@export var VerboseLog: bool = false

## 缓存的技能卡池；首次访问时枚举一次。
var _card_pool: Array[Resource] = []

## 本轮抽出的卡（顺序即展示顺序）。
var _drawn_cards: Array[Resource] = []

## 玩家当前选中的卡（顺序即点选顺序）。
var _selected_cards: Array[Resource] = []

## 与 `_drawn_cards` 一一对应的卡槽占位控件。
var _slot_views: Array[Control] = []

## 与 `_slot_views` 一一对应的卡面节点。
##
## 悬停缩放与选中位移都作用在卡面上而不是占位控件上：这样缩放天然以卡面原点
## （也就是卡槽中心）为轴，不必再维护 `pivot_offset`，也与战斗侧 `highlight_card()`
## 缩放 `SkillCard` 本体保持一致。
var _card_views: Array[Node2D] = []

## 与 `_slot_views` 一一对应的卡面基准位置（即卡槽中心）。
##
## 选中位移以它为基准重新计算，而不是在当前 `position` 上累加：反复悬停、点击、
## 取消都不会让卡面越飘越远。这与战斗侧 `_animate_click_mode_card_selection`
## 以 `hand_position` 为基准是同一个考虑。
var _card_view_base_positions: Array[Vector2] = []

## 界面节点引用；在 `_ready()` 里按导出路径解析一次并缓存。
var _cards_container: HBoxContainer = null
var _confirm_button: Button = null
var _hint_label: Label = null

## 全局提示浮窗；缺失时为 null（浮窗不是开局抽卡的必需依赖，缺了只降级不阻断）。
var _tooltip_panel: Node = null

## 独立洗牌状态，避免改变项目其它随机序列。
var _random := RandomNumberGenerator.new()

## 本次开局是否已经执行过抽卡；保证「每局恰好一次」。
var _has_drafted: bool = false

## 打开界面之前的暂停状态，用于只归还自己造成的那次暂停。
var _was_paused_before_open: bool = false


## 节点就绪时执行界面初始化。
## 返回值：无。
func _ready() -> void:
	Setup()


## 初始化界面：隐藏、准备随机、解析界面节点、订阅开局时机并做一次补偿检查。
##
## 单独抽成公开入口是为可测性服务的：编辑器里的契约测试不能用场景实例化来构造本节点
## （非 `@tool` 脚本经 `PackedScene.instantiate()` 会得到占位实例，其方法不可调用），
## 只能用 `脚本.new()` 构造。这个入口让测试能驱动与生产 `_ready()` **完全相同**的路径。
## 返回值：无。
func Setup() -> void:
	hide()
	_random.randomize()
	_resolve_view_nodes()
	_connect_initializer()


## 解除对开局初始化节点的信号订阅。
## 返回值：无。
func _exit_tree() -> void:
	var initializer: Node = get_node_or_null(InitializerPath)
	if initializer == null:
		return
	if initializer.is_connected(&"RunStartInitialized", _on_run_start_initialized):
		initializer.disconnect(&"RunStartInitialized", _on_run_start_initialized)


## 解析界面节点引用。
##
## 缺失时逐个报错但不中断流程：抽卡逻辑本身仍可运行（只是看不见或无法确认），
## 让「界面接线错了」在编辑器日志里被明确指出，而不是表现为静默无反应。
## 返回值：无。
func _resolve_view_nodes() -> void:
	_cards_container = get_node_or_null(CardsContainerPath) as HBoxContainer
	if _cards_container == null:
		push_error(
			"RunStartSkillCardDraft: 未找到卡面容器 %s，抽卡界面无法展示卡牌。"
			% str(CardsContainerPath)
		)

	_confirm_button = get_node_or_null(ConfirmButtonPath) as Button
	if _confirm_button == null:
		push_error("RunStartSkillCardDraft: 未找到确认按钮 %s。" % str(ConfirmButtonPath))
	else:
		_confirm_button.pressed.connect(_on_confirm_pressed)

	_hint_label = get_node_or_null(HintLabelPath) as Label
	if _hint_label == null:
		push_error("RunStartSkillCardDraft: 未找到提示标签 %s。" % str(HintLabelPath))

	# 悬停提示浮窗缺失只降级为警告：抽卡流程本身不依赖它，不该因为一个纯反馈节点
	# 缺位就让开局报错。这里也不校验方法，调用点统一用 `has_method` 守卫。
	_tooltip_panel = get_node_or_null(TooltipPanelPath)
	if _tooltip_panel == null:
		push_warning(
			"RunStartSkillCardDraft: 未找到提示浮窗 %s，卡面悬停将不显示卡名与描述。"
			% str(TooltipPanelPath)
		)


## 订阅开局初始化信号，并在初始化已经发生时立刻补一次抽卡。
##
## 补偿检查不是可选防御：本节点的 `_ready()` 必然晚于初始化节点的同步广播，
## 因此这一条恰恰是生产路径上的主要触发方式（见类文档第 1 点）。
## 返回值：无。
func _connect_initializer() -> void:
	var initializer: Node = get_node_or_null(InitializerPath)
	if initializer == null:
		push_error(
			"RunStartSkillCardDraft: 未找到开局初始化节点 %s，开局抽卡无法触发。"
			% str(InitializerPath)
		)
		return

	if not initializer.has_signal(&"RunStartInitialized"):
		push_error(
			"RunStartSkillCardDraft: %s 未提供 RunStartInitialized 信号，开局抽卡无法触发。"
			% str(InitializerPath)
		)
		return

	if not initializer.is_connected(&"RunStartInitialized", _on_run_start_initialized):
		initializer.connect(&"RunStartInitialized", _on_run_start_initialized)

	if initializer.has_method("HasInitialized") and bool(initializer.call("HasInitialized")):
		_on_run_start_initialized()


## 开局初始化完成后的入口。
## 返回值：无。
func _on_run_start_initialized() -> void:
	if not StartDraft() and VerboseLog:
		print("[RunStartSkillCardDraft] 本次开局未执行抽卡（已抽过或技能卡池不足）。")


## 执行一次开局抽卡：抽卡 → 展示 → 暂停并显示界面。
##
## 返回值：true 表示本次调用真的发起了抽卡；false 表示已抽过或卡池不足（两种情况都不弹界面）。
func StartDraft() -> bool:
	# 幂等：订阅路径与补偿路径都可能到达这里，必须保证每局只抽一次。
	if _has_drafted:
		return false

	var pool: Array[Resource] = GetCardPool()
	if pool.size() < PICK_COUNT:
		# 池不足时不动界面：让玩家面对一个永远无法完成的界面，比少一次开局抽卡更糟。
		push_error(
			"RunStartSkillCardDraft: 技能卡池不足 %d 张（当前 %d 张），本次开局跳过抽卡。"
			% [PICK_COUNT, pool.size()]
		)
		return false

	_has_drafted = true
	_drawn_cards = _draw_cards(pool)
	_selected_cards.clear()
	_show_cards()
	_refresh_selection_view()
	_was_paused_before_open = _is_tree_paused()
	_set_tree_paused(true)
	show()

	if VerboseLog:
		print("[RunStartSkillCardDraft] 开局抽卡：展示 %d 张，等待玩家选择 %d 张。" % [
			_drawn_cards.size(), PICK_COUNT
		])

	return true


## 返回技能卡池；首次调用时枚举目录并缓存。
##
## 缓存是有意的：本界面只在开局出现一次，但枚举涉及 60+ 个资源的加载，
## 重复枚举只会白白拖慢开局。资产在运行期不会增减，因此缓存无失效问题。
## 返回值：按资源路径排序的生产技能卡数组（不含测试资产）。
func GetCardPool() -> Array[Resource]:
	if _card_pool.is_empty():
		_card_pool = _load_card_pool()
	return _card_pool


## 返回本轮抽出的卡（副本，调用方修改不影响内部状态）。
## 返回值：本轮抽出的技能卡数组。
func GetDrawnCards() -> Array[Resource]:
	return _drawn_cards.duplicate()


## 返回玩家当前选中的卡（副本，调用方修改不影响内部状态）。
## 返回值：玩家选中的技能卡数组。
func GetSelectedCards() -> Array[Resource]:
	return _selected_cards.duplicate()


## 玩家是否已经完成本轮抽卡。
## 返回值：true 表示本轮已经发起过抽卡。
func HasDrafted() -> bool:
	return _has_drafted


## 枚举技能卡池：递归扫描目录并筛掉测试资产，最后按资源路径排序以获得稳定顺序。
## 返回值：生产技能卡数组；目录为空或不可读时返回空数组并报错。
func _load_card_pool() -> Array[Resource]:
	var pool: Array[Resource] = []
	_collect_card_resources(CardPoolDirectory, pool)

	if pool.is_empty():
		push_error(
			"RunStartSkillCardDraft: 未在 %s 找到任何技能卡资源，开局抽卡池为空。"
			% CardPoolDirectory
		)
		return pool

	# 排序只为让池顺序稳定（便于对照与测试），抽取本身仍然是随机的。
	pool.sort_custom(
		func(left: Resource, right: Resource) -> bool:
			return left.resource_path < right.resource_path
	)

	if VerboseLog:
		print("[RunStartSkillCardDraft] 技能卡池就绪：%d 张。" % pool.size())

	return pool


## 递归收集目录中的技能卡资源。
##
## 扫描写法与 `core/autoloads/ItemsControl.gd` 的 `load_items_recursively` 保持一致，
## 使项目里「从 res:// 目录加载资源」只有一种写法。
## 参数 dir_path：待扫描的 res:// 目录。
## 参数 target：接收技能卡 Resource 的数组（原地追加）。
## 返回值：无。
func _collect_card_resources(dir_path: String, target: Array[Resource]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path: String = dir_path + "/" + file_name
			if dir.current_is_dir():
				_collect_card_resources(full_path, target)
			elif file_name.ends_with(".tres") and not file_name.begins_with(TEST_ASSET_PREFIX):
				var resource: Resource = load(full_path) as Resource
				if _is_skill_card(resource):
					target.append(resource)
		file_name = dir.get_next()
	dir.list_dir_end()


## 判断一个资源是不是技能卡。
##
## 判定标准是「暴露 `Skill` 字段」，与 `entities/components/battle_deck_component.gd`
## 的 `_can_store_item` 完全一致：生产物品已全部使用 GDScript，而按脚本路径判断
## 会把语言绑定留在生产代码里。
## 参数 resource：待判定的资源。
## 返回值：true 表示该资源可被视为技能卡。
func _is_skill_card(resource: Resource) -> bool:
	if resource == null:
		return false

	for property_info: Variant in resource.get_property_list():
		if property_info is Dictionary \
				and StringName(property_info.get("name", "")) == &"Skill":
			return true

	return false


## 从池中洗牌后取出展示用的卡。
##
## 采用与 `resources/talents/talent_manager.gd` 相同的 Fisher-Yates 原地洗牌；
## 洗牌在池的**副本**上进行，因此不会改变 `GetCardPool()` 返回的稳定顺序，
## 也不会让同一张卡在一轮里出现两次。
## 参数 pool：技能卡池。
## 返回值：长度为 min(DRAW_COUNT, 池大小) 且互不重复的技能卡数组。
func _draw_cards(pool: Array[Resource]) -> Array[Resource]:
	var shuffled: Array[Resource] = pool.duplicate()

	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index: int = _random.randi_range(0, index)
		var temporary: Resource = shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = temporary

	var draw_count: int = mini(DRAW_COUNT, shuffled.size())
	return shuffled.slice(0, draw_count)


## 为抽出的每张卡生成「占位控件 + 卡面」并挂进容器。
##
## 卡面（`SkillCard`）的根节点是 `Node2D`，无法参与 `HBoxContainer` 布局，
## 因此由 `Button` 占位承担布局与点击，卡面只负责渲染并居中放置。
## 返回值：无。
func _show_cards() -> void:
	if _cards_container == null:
		return

	for child in _cards_container.get_children():
		child.queue_free()
	_slot_views.clear()
	_card_views.clear()
	_card_view_base_positions.clear()

	for index in _drawn_cards.size():
		var card: Resource = _drawn_cards[index]
		var slot := Button.new()
		slot.flat = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = CARD_SLOT_SIZE
		# 卡面自己就显示卡名，不再用系统 tooltip 重复一遍；
		# 悬停提示改由共享的 TooltipPanel 承担，与战斗侧一致。
		_cards_container.add_child(slot)

		# 悬停表现由占位控件驱动：卡面被占位覆盖，卡面自己的 Area2D 收不到鼠标事件。
		# 视觉效果与战斗侧 `highlight_card()` 逐项一致，只是触发来源不同。
		slot.mouse_entered.connect(_on_card_slot_mouse_entered.bind(index))
		slot.mouse_exited.connect(_on_card_slot_mouse_exited.bind(index))
		slot.pressed.connect(_on_card_slot_pressed.bind(card))

		_attach_card_view(slot, card)
		_slot_views.append(slot)


## 把卡面实例挂到占位控件中心。
##
## 参数 slot：承担布局与点击的占位控件。
## 参数 card：该卡槽要展示的技能卡。
## 返回值：无。
func _attach_card_view(slot: Control, card: Resource) -> void:
	# 无论成功与否都要登记一张卡面：`_card_views` 用下标与卡槽对应，
	# 一次构造失败若跳过登记，后面所有卡槽的动效都会错位到邻居身上。
	if CardScenePrefab == null:
		push_error("RunStartSkillCardDraft: 未配置 CardScenePrefab，卡面无法显示。")
		_register_card_view(null, CARD_SLOT_SIZE * 0.5)
		return

	var card_view: Node2D = CardScenePrefab.instantiate() as Node2D
	if card_view == null:
		push_error(
			"RunStartSkillCardDraft: CardScenePrefab 的根节点不是 Node2D，无法作为卡面使用。"
		)
		_register_card_view(null, CARD_SLOT_SIZE * 0.5)
		return

	slot.add_child(card_view)
	# 卡面的标签是按「相对根节点原点」的偏移排布的，因此把原点放到占位中心即可。
	# 这个位置同时是卡面的基准位置：悬停缩放以它为轴心，选中位移以它为起点。
	var base_position: Vector2 = CARD_SLOT_SIZE * 0.5
	card_view.position = base_position
	# 显式对齐常驻层级，不依赖卡面场景自己的 z_index 默认值：卡面是可替换的导出项，
	# 把「初始层级应该是几」这条状态契约留在调用方，换卡面场景时行为才不会漂。
	card_view.z_index = CARD_VISUALS.CARD_Z_INDEX_NORMAL
	_register_card_view(card_view, base_position)

	if not card_view.has_method("init_card_data"):
		push_error("RunStartSkillCardDraft: 卡面缺少 init_card_data 协议，无法绑定数据。")
		return

	card_view.call("init_card_data", card)

	# 卡面场景自带一个 LockColor 锁定遮罩，且它在场景里的默认可见性是「显示」。
	# 战斗侧靠 CardManager 按 control_lock 状态显式调用 lock()/unlock() 对齐状态，
	# 而抽卡界面没有战斗锁定语义，必须在这里显式解除——否则每张卡都会被一块
	# 210×150 的半透明黑盖住，叠加全屏遮罩后整屏近乎全黑。
	if card_view.has_method("unlock"):
		card_view.call("unlock")


## 登记一张卡面及其基准位置，保持与卡槽下标一一对应。
##
## 参数 card_view：卡面节点；构造失败时传 null，但下标仍要占位。
## 参数 base_position：卡面未抬升时的位置（即占位中心）。
## 返回值：无。
func _register_card_view(card_view: Node2D, base_position: Vector2) -> void:
	_card_views.append(card_view)
	_card_view_base_positions.append(base_position)


## 鼠标移入某个卡槽：按战斗侧的悬停表现放大卡面并置顶，同时显示提示浮窗。
##
## 参数 index：卡槽下标（与 `_drawn_cards` 同序）。
## 返回值：无。
func _on_card_slot_mouse_entered(index: int) -> void:
	_apply_card_hover(index, true)


## 鼠标移出某个卡槽：卡面缩放回常态并恢复层级，同时隐藏提示浮窗。
##
## 参数 index：卡槽下标（与 `_drawn_cards` 同序）。
## 返回值：无。
func _on_card_slot_mouse_exited(index: int) -> void:
	_apply_card_hover(index, false)


## 应用一次悬停表现。
##
## 数值与缓动全部取自 `CARD_VISUALS`，与战斗侧 `highlight_card()` 逐项一致：
## Tween 缩放、`z_index` 立刻切换、**不改变颜色**。
##
## 悬停与选中是两种独立表现：悬停改缩放与层级，选中改位置（见
## `_set_card_view_lifted`）。因此移开鼠标的已选卡会缩回常态，但仍保持抬升，
## 玩家依然认得出自己选了哪张——这正是战斗侧把抬升距离与悬停缩放分开的理由。
##
## 参数 index：卡槽下标。
## 参数 hovered：true 表示悬停，false 表示移出。
## 返回值：无。
func _apply_card_hover(index: int, hovered: bool) -> void:
	var card_view: Node2D = _get_card_view(index)
	if card_view == null:
		return

	var target_scale: Vector2 = CARD_VISUALS.CARD_HOVER_SCALE \
			if hovered else CARD_VISUALS.CARD_NORMAL_SCALE
	# 层级立刻切换（战斗侧同样是立刻赋值），缩放走补间。
	card_view.z_index = CARD_VISUALS.CARD_Z_INDEX_HOVER \
			if hovered else CARD_VISUALS.CARD_Z_INDEX_NORMAL
	_tween_scale(card_view, target_scale)

	if hovered:
		_show_card_tooltip(index)
	else:
		_hide_card_tooltip()


## 把卡面缩放到目标值：在场景树中走补间，否则直接落到终值。
##
## `Node.create_tween()` 在节点尚未入场景树时会报错并返回 null；而编辑器契约测试
## 刻意让夹具不入树（理由见套件文件头）。因此这里显式分叉：生产路径得到补间动画，
## 测试路径直接得到终态，两边都能被断言，也不会产生引擎级错误噪音。
##
## 参数 card_view：目标卡面。
## 参数 target_scale：目标缩放。
## 返回值：无。
func _tween_scale(card_view: Node2D, target_scale: Vector2) -> void:
	if not is_inside_tree():
		card_view.scale = target_scale
		return

	var tween: Tween = create_tween()
	tween.tween_property(card_view, "scale", target_scale, CARD_VISUALS.SCALE_TWEEN_DURATION)


## 处理一次卡面点击：切换该卡的选中状态。
##
## 已选满时点击未选中的卡会被忽略（不改动选中集合），这是一种正常的交互结果，
## 因此只更新提示文案，不产生警告。
## 参数 card：被点击的卡。
## 返回值：无。
func _on_card_slot_pressed(card: Resource) -> void:
	if _selected_cards.has(card):
		_selected_cards.erase(card)
	elif _selected_cards.size() < PICK_COUNT:
		_selected_cards.append(card)

	_refresh_selection_view()


## 按当前选中集合刷新卡面位置、进度提示与确认按钮可用性。
## 返回值：无。
func _refresh_selection_view() -> void:
	for index in _slot_views.size():
		var card: Resource = _drawn_cards[index] if index < _drawn_cards.size() else null
		var is_selected: bool = card != null and _selected_cards.has(card)
		_set_card_view_lifted(index, is_selected)

	if _hint_label != null:
		_hint_label.text = "已选 %d/%d" % [_selected_cards.size(), PICK_COUNT]

	if _confirm_button != null:
		_confirm_button.disabled = _selected_cards.size() != PICK_COUNT


## 把某张卡面抬升到选中位置或放回基准位置。
##
## 位置始终由「基准位置 + 偏移」算出，而不是在当前 `position` 上累加：反复悬停、
## 点击、取消都不会让卡面越飘越远。缓动与时长照搬战斗侧
## `_animate_click_mode_card_selection`（`TRANS_QUAD` + `EASE_OUT`）。
##
## 参数 index：卡槽下标。
## 参数 lifted：true 表示上移 `CLICK_SELECTED_LIFT_DISTANCE`，false 表示回位。
## 返回值：无。
func _set_card_view_lifted(index: int, lifted: bool) -> void:
	var card_view: Node2D = _get_card_view(index)
	if card_view == null or index >= _card_view_base_positions.size():
		return

	var target_position: Vector2 = _card_view_base_positions[index]
	if lifted:
		target_position += Vector2(0.0, -CARD_VISUALS.CLICK_SELECTED_LIFT_DISTANCE)

	_tween_lift(card_view, target_position)


## 把卡面移动到目标位置：在场景树中走补间，否则直接落到终值（理由同 `_tween_scale`）。
##
## 缓动与时长为照搬战斗侧 `_animate_click_mode_card_selection` 的
## `TRANS_QUAD` + `EASE_OUT`。
##
## 参数 card_view：目标卡面。
## 参数 target_position：目标位置。
## 返回值：无。
func _tween_lift(card_view: Node2D, target_position: Vector2) -> void:
	if not is_inside_tree():
		card_view.position = target_position
		return

	var tween: Tween = create_tween()
	tween.tween_property(
		card_view, "position", target_position, CARD_VISUALS.CLICK_SELECTED_LIFT_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 取下标的卡面；下标越界或该卡面构造失败时返回 null。
##
## 参数 index：卡槽下标。
## 返回值：对应的卡面节点；不可用时为 null。
func _get_card_view(index: int) -> Node2D:
	if index < 0 or index >= _card_views.size():
		return null
	return _card_views[index]


## 显示某张卡的悬停提示。
##
## 文案取 `DisplayName` / `DisplayDescription`，与卡面自身显示的文字同源，
## 避免浮窗文字与卡面文字不一致。浮窗缺失只降级不报错：它不是开局抽卡的必需依赖。
##
## 参数 index：卡槽下标。
## 返回值：无。
func _show_card_tooltip(index: int) -> void:
	if _tooltip_panel == null or index < 0 or index >= _drawn_cards.size():
		return

	if not _tooltip_panel.has_method("show_tooltip"):
		return

	var card: Resource = _drawn_cards[index]
	_tooltip_panel.call("show_tooltip", _card_display_name(card), _card_description(card))


## 隐藏悬停提示。
## 返回值：无。
func _hide_card_tooltip() -> void:
	if _tooltip_panel != null and _tooltip_panel.has_method("hide_tooltip"):
		_tooltip_panel.call("hide_tooltip")


## 确认按钮回调：选满时发放选择的卡并收起界面。
## 返回值：无。
func _on_confirm_pressed() -> void:
	if _selected_cards.size() != PICK_COUNT:
		return

	var granted: int = _grant_selected_cards()
	if VerboseLog:
		print("[RunStartSkillCardDraft] 抽卡完成：选中 %d 张，成功写入背包 %d 张。" % [
			_selected_cards.size(), granted
		])

	SkillCardDraftCompleted.emit(_selected_cards.duplicate())
	_close_draft()


## 把选中的卡逐张写入玩家背包。
##
## 参数：无（读取 `_selected_cards`）。
## 返回值：成功写入背包的张数；放不下的张数不计入并留下警告。
func _grant_selected_cards() -> int:
	var inventory: Node = _resolve_inventory()
	if inventory == null:
		return 0

	var granted: int = 0
	for card: Resource in _selected_cards:
		var leftover: int = int(inventory.call("AddItem", card, 1))
		if leftover > 0:
			# 不重抽、不回池：背包放不下是可诊断问题，而不是可以静默吞掉的异常。
			push_warning(
				"RunStartSkillCardDraft: 背包放不下 %s，本次抽卡少获得 1 张。"
				% _card_display_name(card)
			)
		else:
			granted += 1

	return granted


## 收起界面并归还本次造成的那次暂停。
## 返回值：无。
func _close_draft() -> void:
	hide()
	_set_tree_paused(_was_paused_before_open)


## 解析玩家背包组件。
##
## 返回值：找到时返回背包组件；缺失时返回 null 并报错（此时玩家的选择不会入包）。
func _resolve_inventory() -> Node:
	var player: Node = get_node_or_null(PlayerPath)
	if player == null:
		push_error(
			"RunStartSkillCardDraft: 未找到玩家节点 %s，抽卡结果无法写入背包。" % str(PlayerPath)
		)
		return null

	var inventory: Node = player.get_node_or_null(InventoryComponentPath)
	if inventory == null:
		push_error(
			"RunStartSkillCardDraft: 玩家缺少背包组件 %s，抽卡结果无法写入背包。"
			% str(InventoryComponentPath)
		)
		return null

	return inventory


## 读取一张卡用于界面与日志的显示名。
##
## 参数 card：技能卡 Resource。
## 返回值：优先 DisplayName；为空时回退 CardName。
func _card_display_name(card: Resource) -> String:
	var display_name: Variant = card.get("DisplayName")
	if display_name != null and not str(display_name).strip_edges().is_empty():
		return str(display_name)

	return str(card.get("CardName"))


## 读取一张卡的描述文本，用于悬停提示。
##
## 取值优先级与 `_card_display_name` 保持一致：优先 `DisplayDescription`（卡面自己
## 显示的那份文本），为空时回退 `Description`（战斗侧 tooltip 使用的原始字段）。
## 这样浮窗里的文字与卡面文字必然同源，不会出现两处说法不一致。
##
## `get()` 对不存在的属性返回 null 而不是报错，因此卡数据结构变化时这里只会退化为
## 空字符串，不会中断抽卡流程。
##
## 参数 card：技能卡 Resource。
## 返回值：描述文本；两个字段都为空时返回空字符串。
func _card_description(card: Resource) -> String:
	var display_description: Variant = card.get("DisplayDescription")
	if display_description != null and not str(display_description).strip_edges().is_empty():
		return str(display_description)

	return str(card.get("Description"))


## 读取当前场景树的暂停状态。
##
## 契约测试用 `脚本.new()` 构造本界面（不入场景树），此时**不能**直接调用 `get_tree()`：
## 未入树的节点调用它会触发引擎级错误 `Parameter "data.tree" is null`——虽然返回值同样是
## null，但会把日志刷满噪音、掩盖真正的问题。因此先用 `is_inside_tree()` 收口。
## 返回值：true 表示当前处于暂停状态；不在场景树中时返回 false。
func _is_tree_paused() -> bool:
	if not is_inside_tree():
		return false

	var tree: SceneTree = get_tree()
	return tree != null and tree.paused


## 设置场景树暂停状态。
##
## 参数 paused：目标暂停状态。
## 返回值：无；节点不在场景树中时不做任何事（理由同 `_is_tree_paused`）。
func _set_tree_paused(paused: bool) -> void:
	if not is_inside_tree():
		return

	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = paused
