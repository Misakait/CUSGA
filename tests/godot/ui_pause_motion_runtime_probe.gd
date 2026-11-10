extends RefCounted

## 使用真实大地图和暂停菜单验证动效期间的暂停交接，不替代生产暂停算法。
## 调用方须在游戏进程 await run_runtime_checks，并先关闭已有大地图与暂停菜单。

const MAP_SCENE: PackedScene = preload("res://scenes/map_scenes/map_view/LargeMap.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/ui_scenes/pause_menu.tscn")
const OPEN_METHODS: Array[StringName] = [&"show_map", &"open_pause_menu"]
const CLOSE_METHODS: Array[StringName] = [&"hide_map", &"close_pause_menu"]
const PANEL_NAMES: Array[String] = ["大地图", "暂停菜单"]
const MOTION_PATHS: Array[NodePath] = [^"MapJellyTransition", ^"PauseJellyTransition"]
const FIXTURE_NAME: String = "UIPauseMotionFixture"
const OPEN_WAIT_SECONDS: float = 0.7
const CLOSE_WAIT_SECONDS: float = 0.3
const CROSS_OPEN_DELAY_SECONDS: float = 0.05


## 在独立夹具中验证两个生产界面的暂停交接、关闭顺序和离树清理。
## 参数 tree：真实游戏 SceneTree；已有大地图和暂停菜单须处于关闭状态。
## 返回 checks、failures、passed 字典；调用方必须 await，结束后恢复进入时的暂停状态。
static func run_runtime_checks(tree: SceneTree) -> Dictionary:
	var result: Dictionary = {"checks": 0, "failures": [], "passed": false}
	if tree == null or Engine.is_editor_hint():
		_expect(result, false, "暂停动效回归必须在真实游戏进程执行。")
		return result
	var original_paused: bool = tree.paused
	var existing_owner: Node = _find_existing_pause_owner(tree)
	_expect(result, existing_owner == null, "先关闭已有大地图和暂停菜单，避免夹具把暂停责任交给外部界面。")
	if existing_owner != null:
		return result
	_expect(result, not tree.root.has_node(FIXTURE_NAME), "运行前不应残留同名暂停动效夹具。")
	if tree.root.has_node(FIXTURE_NAME):
		return result
	var settlement: Node = tree.root.get_node_or_null("SettlementManager")
	var ending: bool = settlement != null and bool(settlement.call("is_run_ending"))
	_expect(result, not ending, "结算进行时禁止打开暂停菜单，须在正常运行状态执行回归。")
	if ending:
		return result

	for leading: int in range(2):
		await _check_cross_open(tree, result, leading)
	# 同时交换打开与关闭顺序，避免只验证后开先关这一种栈式用法。
	for initially_paused: bool in [false, true]:
		for first_opened: int in range(2):
			for first_closed: int in range(2):
				await _check_close_order(tree, result, initially_paused, first_opened, first_closed)
	for removed_owner: int in range(2):
		await _check_owner_exit(tree, result, removed_owner)

	# 各用例先断言生产代码的结果，最后才还原调用者状态，避免清理掩盖失败。
	tree.paused = original_paused
	result["passed"] = (result["failures"] as Array).is_empty()
	return result


static func _check_cross_open(tree: SceneTree, result: Dictionary, leading: int) -> void:
	tree.paused = false
	var fixture: Dictionary = _new_fixture(tree)
	var panels: Array[Node] = fixture["panels"]
	var following: int = 1 - leading
	var label: String = "%s退场时打开%s" % [PANEL_NAMES[leading], PANEL_NAMES[following]]
	await _open_and_wait(tree, result, panels[leading], leading, label)
	panels[leading].call(CLOSE_METHODS[leading])
	await _wait_seconds(tree, CROSS_OPEN_DELAY_SECONDS)
	_expect(result, tree.paused, label + "：退场 0.05 秒时游戏仍暂停。")
	_expect(result, _panel_visible(panels[leading], leading), label + "：此时旧界面尚未隐藏。")
	_expect(result, _motion_busy(panels[leading], leading), label + "：交叉打开必须发生在实际退场期间。")
	await _open_and_wait(tree, result, panels[following], following, label)
	_expect(result, not _panel_visible(panels[leading], leading), label + "：旧界面应完成退场。")
	_expect(result, tree.paused, label + "：旧界面退场不能提前恢复游戏。")
	await _close_and_wait(tree, result, panels[following], following, label)
	_expect(result, not tree.paused, label + "：最后一个界面关闭后恢复游戏。")
	_free_fixture(tree, result, fixture, false, label)


static func _check_close_order(
	tree: SceneTree,
	result: Dictionary,
	initially_paused: bool,
	first_opened: int,
	first_closed: int,
) -> void:
	tree.paused = initially_paused
	var fixture: Dictionary = _new_fixture(tree)
	var panels: Array[Node] = fixture["panels"]
	var label: String = "原暂停=%s，先开%s，先关%s" % [
		str(initially_paused), PANEL_NAMES[first_opened], PANEL_NAMES[first_closed],
	]
	await _open_and_wait(tree, result, panels[first_opened], first_opened, label)
	await _open_and_wait(tree, result, panels[1 - first_opened], 1 - first_opened, label)
	await _close_and_wait(tree, result, panels[first_closed], first_closed, label)
	_expect(result, tree.paused, label + "：另一界面仍打开时必须保持暂停。")
	_expect(
		result, _panel_visible(panels[1 - first_closed], 1 - first_closed),
		label + "：关闭一个界面不得隐藏另一个。"
	)
	await _close_and_wait(tree, result, panels[1 - first_closed], 1 - first_closed, label)
	_expect(result, tree.paused == initially_paused, label + "：全部关闭后恢复打开前状态。")
	_free_fixture(tree, result, fixture, initially_paused, label)


static func _check_owner_exit(tree: SceneTree, result: Dictionary, removed_owner: int) -> void:
	tree.paused = false
	var fixture: Dictionary = _new_fixture(tree)
	var panels: Array[Node] = fixture["panels"]
	var remaining: int = 1 - removed_owner
	var label: String = "释放原始暂停拥有者%s" % PANEL_NAMES[removed_owner]
	await _open_and_wait(tree, result, panels[removed_owner], removed_owner, label)
	await _open_and_wait(tree, result, panels[remaining], remaining, label)
	# 直接释放触发真实 _exit_tree，验证离树兜底也能把恢复责任交给仍存在的界面。
	panels[removed_owner].free()
	_expect(result, tree.paused, label + "：另一界面存在时不能提前恢复游戏。")
	_expect(result, _panel_visible(panels[remaining], remaining), label + "：剩余界面继续可见。")
	await _close_and_wait(tree, result, panels[remaining], remaining, label)
	_expect(result, not tree.paused, label + "：剩余界面关闭后仍能恢复游戏。")
	_free_fixture(tree, result, fixture, false, label)


static func _new_fixture(tree: SceneTree) -> Dictionary:
	var host := Node.new()
	host.name = FIXTURE_NAME
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(host)
	var panels: Array[Node] = [MAP_SCENE.instantiate(), PAUSE_SCENE.instantiate()]
	for panel: Node in panels:
		host.add_child(panel)
	return {"host": host, "panels": panels}


static func _open_and_wait(
	tree: SceneTree, result: Dictionary, panel: Node, index: int, label: String
) -> void:
	panel.call(OPEN_METHODS[index])
	_expect(result, tree.paused, label + "：公开打开入口立即取得暂停。")
	await _wait_seconds(tree, OPEN_WAIT_SECONDS)
	_expect(result, _panel_visible(panel, index), label + "：入场后%s可见。" % PANEL_NAMES[index])
	_expect(result, not _motion_busy(panel, index), label + "：%s在暂停中完成入场。" % PANEL_NAMES[index])


static func _close_and_wait(
	tree: SceneTree, result: Dictionary, panel: Node, index: int, label: String
) -> void:
	panel.call(CLOSE_METHODS[index])
	await _wait_seconds(tree, CLOSE_WAIT_SECONDS)
	_expect(result, not _panel_visible(panel, index), label + "：退场后%s隐藏。" % PANEL_NAMES[index])
	_expect(result, not _motion_busy(panel, index), label + "：%s退场没有残留动画锁。" % PANEL_NAMES[index])


static func _panel_visible(panel: Node, index: int) -> bool:
	if index == 0:
		return (panel as CanvasLayer).visible
	return (panel.get_node("PauseOverlay") as Control).visible


static func _motion_busy(panel: Node, index: int) -> bool:
	var motion: Node = panel.get_node(MOTION_PATHS[index])
	return bool(motion.call("is_animating"))


static func _wait_seconds(tree: SceneTree, seconds: float) -> void:
	# 暂停和战斗时间倍率都不能阻塞等待，否则测试本身会死锁或改变覆盖的时间窗口。
	await tree.create_timer(seconds, true, false, true).timeout


static func _free_fixture(
	tree: SceneTree, result: Dictionary, fixture: Dictionary, paused_before: bool, label: String
) -> void:
	var host: Node = fixture["host"]
	if is_instance_valid(host):
		host.free()
	_expect(result, tree.paused == paused_before, label + "：释放夹具不得改变已恢复的暂停状态。")


static func _find_existing_pause_owner(tree: SceneTree) -> Node:
	for value: Variant in tree.get_nodes_in_group(&"ui_pause_owners"):
		if not is_instance_valid(value):
			continue
		var owner: Node = value as Node
		# 只读生产节点的占有标记；不能调用交接方法探测，否则会改写用户界面的恢复责任。
		if owner.has_method(&"show_map") and bool(owner.get("_owns_open_state")):
			return owner
		if owner.has_method(&"open_pause_menu") and bool(owner.get("_owns_pause_state")):
			return owner
	return null


static func _expect(result: Dictionary, condition: bool, message: String) -> void:
	result["checks"] = int(result["checks"]) + 1
	if not condition:
		(result["failures"] as Array).append(message)
