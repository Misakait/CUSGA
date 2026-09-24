extends Control

## 天赋选择界面的 GDScript 管理器。
##
## 职责边界：装配可选池、开关界面、记录并归还全局暂停、把卡片点击转发成全局天赋事件。
## TalentData 的内容、效果的实际应用与时间推进分别由 Resource、Player 与 TimeSystem 负责。
##
## 根节点刻意是 `Control` 而不是 `CanvasLayer`，与开局技能卡抽取界面
## （`run_start_skill_card_draft.gd` 挂在 `Control` 上）保持同一范式。两者都挂在
## `Main/UI/HUDLayer/HUDRoot` 之下，这样才满足两个前提：
##   1）共用同一个 `HUDLayer`，切开场战斗时随 `HUDLayer.hide()` 一起退场；
##   2）与共享浮窗 `TooltipPanel` 处在同一个 canvas 内，绘制顺序由兄弟次序决定，
##      把浮窗排在本界面之后即可让悬停详情盖在遮罩之上。

## 显式追加的天赋池。
##
## 生产场景刻意保持为空：可选天赋按目录实时枚举，新增 `.tres` 不需要改场景文件。
## 保留这个导出是为了让测试与特殊玩法能注入不落在目录里的资源。
@export var AllTalentsPool: Array[Resource] = []

## 天赋卡池目录；递归扫描其中的 `.tres`。
##
## 与开局技能卡抽取（`core/gameflow/run_start_skill_card_draft.gd`）采用同一范式：
## 池在 `_ready()` 时从目录枚举，因此「往目录里放一张卡」就是完整的接入动作。
@export var CardPoolDirectory: String = "res://resources/talents"

## 单张天赋卡的生产场景。
@export var CardScenePrefab: PackedScene

## 放置本轮天赋卡的容器。
@export var CardsContainer: HBoxContainer

## 共享悬停详情浮窗相对本节点的路径。
##
## 本界面与浮窗同为 `HUDRoot` 的直接子节点，所以默认是 `../TooltipPanel`，
## 与 `run_start_skill_card_draft.gd` 的 `TooltipPanelPath` 默认值相同。
@export var TooltipPanelPath: NodePath = NodePath("../TooltipPanel")

## 当前尚未被学会的天赋池。
##
## 「未被学会」是唯一的移除条件：本轮抽到但没选中的卡留在池里，下一轮仍可抽到；
## 只有被选中的那张会在 `OnTalentSelected` 中被移除。因此池的消耗速度由玩家的
## 实际选择决定，而不是由抽取次数决定。
var _available_talents: Array[Resource] = []

## 保持独立洗牌状态，避免改变项目其它随机序列。
var _random := RandomNumberGenerator.new()

## 当前 TimeSystem Autoload；只依赖稳定的天赋触发信号。
var _time_system: Node

## 共享悬停详情浮窗；缺失时只降级为警告，不阻断选择流程。
var _tooltip_panel: Node = null

## 本次打开界面之前，全局是否已经处于暂停状态。
##
## 天赋界面与暂停菜单共用同一个全局暂停开关（`pause_menu.gd` 有同样的记录），
## 关闭时只有「暂停由本次打开造成」才由本组件解除，否则会把别的系统
## （例如叠加在上层的暂停菜单）造成的暂停一并解除。
var _was_paused_before_open: bool = false


## 初始化可选池、解析浮窗并订阅天赋选择信号。
## 返回值：无。
func _ready() -> void:
	hide()
	_random.randomize()
	_available_talents = _build_talent_pool()
	_resolve_tooltip_panel()
	_time_system = get_node("/root/TimeSystem")
	_time_system.connect(&"TalentSelectionTriggered", _pop_up_talent_selection)


## 解除对长生命周期 Autoload 的信号订阅。
## 返回值：无。
func _exit_tree() -> void:
	if _time_system != null \
			and _time_system.has_signal(&"TalentSelectionTriggered") \
			and _time_system.is_connected(&"TalentSelectionTriggered", _pop_up_talent_selection):
		_time_system.disconnect(&"TalentSelectionTriggered", _pop_up_talent_selection)


## 接收卡片选择，广播同一个 TalentData Resource 并恢复游戏。
##
## 参数 selected_talent：卡片返回的 TalentData。
## 返回值：无。
func OnTalentSelected(selected_talent: Resource) -> void:
	print("玩家选择了天赋：" + str(selected_talent.get("TalentName")))
	# 只有被选中的那张离开池：未选中的卡本来就留在 _available_talents 里。
	_available_talents.erase(selected_talent)
	get_node("/root/GlobalEventBus").emit_signal(&"on_player_acquired_talent", selected_talent)
	hide()
	_set_tree_paused(_was_paused_before_open)


## 暂停游戏并展示本轮最多三张天赋卡。
## 返回值：无。
func _pop_up_talent_selection() -> void:
	if _available_talents.is_empty():
		# 不弹空界面：把所有天赋学完后，让玩家面对一个没有卡可选的界面
		# 比少一次选择更糟。这里留一条可诊断日志说明「为什么没弹」。
		print("天赋已全部学完，没有可用的天赋卡了！")
		return

	# 顺序不可颠倒：必须先在**未暂停**的状态下记录，否则记录到的永远是自己造成的暂停。
	_was_paused_before_open = _is_tree_paused()
	_set_tree_paused(true)
	show()
	_draw_three_talents()


## 原地洗牌可选池，并生成本轮最多三张卡片。
##
## 洗牌在池本身上进行是有意的：取前 N 张展示、且不把落选的卡移出数组，
## 就自然得到「未选中即回池」的语义，无需额外的回收步骤。
## 返回值：无。
func _draw_three_talents() -> void:
	if CardScenePrefab == null:
		push_error("TalentManager: 未配置 CardScenePrefab，天赋卡无法生成。")
		return

	if CardsContainer == null:
		push_error("TalentManager: 未配置 CardsContainer，天赋卡无处放置。")
		return

	for index in range(_available_talents.size() - 1, 0, -1):
		var swap_index := _random.randi_range(0, index)
		var temporary := _available_talents[index]
		_available_talents[index] = _available_talents[swap_index]
		_available_talents[swap_index] = temporary

	for child in CardsContainer.get_children():
		child.queue_free()

	var draw_count := mini(3, _available_talents.size())
	for index in range(draw_count):
		var data: Resource = _available_talents[index]
		var new_card := CardScenePrefab.instantiate() as Control
		CardsContainer.add_child(new_card)
		new_card.call("Initialize", data)
		# 由本界面统一注入共享浮窗：卡片是可复用场景，让它自己写死
		# 「距浮窗几层」会把卡片的可用位置限死，而界面根天然知道自己的层级。
		if new_card.has_method("SetTooltipPanel"):
			new_card.call("SetTooltipPanel", _tooltip_panel)
		new_card.connect(&"OnCardClicked", OnTalentSelected)


## 解析共享悬停详情浮窗。
##
## 缺失只降级为警告：浮窗是纯反馈节点，不该因为它缺位就让天赋选择无法进行。
## 返回值：无。
func _resolve_tooltip_panel() -> void:
	_tooltip_panel = get_node_or_null(TooltipPanelPath)
	if _tooltip_panel == null:
		push_warning(
			"TalentManager: 未找到悬停详情浮窗 %s，天赋卡悬停将不显示名称与描述。"
			% str(TooltipPanelPath)
		)


## 装配可选天赋池：目录枚举结果 + 显式追加项，按资源路径去重后排序。
##
## 排序只为让池顺序稳定（便于对照与测试），抽取本身仍然是随机的；去重则保证
## 同一份资源同时出现在目录与 `AllTalentsPool` 时不会在一轮里被展示两次。
## 返回值：按资源路径排序的天赋资源数组。
func _build_talent_pool() -> Array[Resource]:
	var pool: Array[Resource] = []
	var seen_keys: Dictionary = {}

	var candidates: Array[Resource] = _collect_talents(CardPoolDirectory)
	candidates.append_array(AllTalentsPool)

	for resource: Resource in candidates:
		if resource == null:
			continue
		# 去重键优先用资源路径（生产资源都可寻址）；无路径的动态资源退化为
		# 按实例判定，保证同一个实例不会被重复放入池中。
		var key: String = resource.resource_path
		if key.is_empty():
			key = str(resource.get_instance_id())
		if seen_keys.has(key):
			continue
		seen_keys[key] = true
		pool.append(resource)

	pool.sort_custom(
		func(left: Resource, right: Resource) -> bool:
			return left.resource_path < right.resource_path
	)

	return pool


## 递归收集目录中的天赋资源。
##
## 参数 dir_path：待扫描的 `res://` 目录。
## 返回值：目录中发现的天赋资源数组（未排序）；目录不可读时返回空数组。
func _collect_talents(dir_path: String) -> Array[Resource]:
	var found: Array[Resource] = []
	_collect_talents_recursive(dir_path, found)
	return found


## 递归扫描一个目录，把其中的天赋资源追加到目标数组。
##
## 扫描写法与 `core/gameflow/run_start_skill_card_draft.gd` 的
## `_collect_card_resources`、`core/autoloads/ItemsControl.gd` 的
## `load_items_recursively` 保持一致，使项目里「从 res:// 目录加载资源」只有一种写法。
## 参数 dir_path：待扫描的 `res://` 目录。
## 参数 target：接收天赋 Resource 的数组（原地追加）。
## 返回值：无。
func _collect_talents_recursive(dir_path: String, target: Array[Resource]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path: String = dir_path + "/" + file_name
			if dir.current_is_dir():
				_collect_talents_recursive(full_path, target)
			elif file_name.ends_with(".tres"):
				var resource: Resource = load(full_path) as Resource
				if _is_talent(resource):
					target.append(resource)
		file_name = dir.get_next()
	dir.list_dir_end()


## 判断一个资源是不是天赋卡。
##
## 判定标准是「同时暴露 `TalentName` 与 `Effects` 字段」，而不是按脚本路径或
## `class_name` 判断：`talent_data.gd` 刻意不声明 `class_name`（避免与退役中的
## C# 全局类型重名），按字段判定可让脚本换代时池装配不失效，
## 也与 `run_start_skill_card_draft.gd` 的 `_is_skill_card` 判定 `Skill` 字段同构。
## 参数 resource：待判定的资源。
## 返回值：true 表示该资源可被视为天赋卡。
func _is_talent(resource: Resource) -> bool:
	if resource == null:
		return false

	var has_name: bool = false
	var has_effects: bool = false
	for property_info: Variant in resource.get_property_list():
		if not (property_info is Dictionary):
			continue
		var property_name: StringName = StringName(property_info.get("name", ""))
		if property_name == &"TalentName":
			has_name = true
		elif property_name == &"Effects":
			has_effects = true

	return has_name and has_effects


## 读取当前场景树的暂停状态。
##
## 契约测试会用 `脚本.new()` 构造本界面（不入场景树），此时**不能**直接调用
## `get_tree()`：未入树的节点调用它会触发引擎级错误 `Parameter "data.tree" is null`，
## 把日志刷满噪音并掩盖真正的问题。因此先用 `is_inside_tree()` 收口。
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
