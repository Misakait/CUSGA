@tool
extends McpTestSuite

## 仓库界面金币实时刷新的契约套件。
##
## 锁定的是「余额一变，界面立刻跟着变」这条行为：仓库顶部的金币数字与两个升级按钮的
## 可用性都由余额决定，一旦缺少钱包订阅，界面就会停在下一次主动刷新之前——金币被改动后
## 数字与按钮状态都不动，直到玩家碰巧触发一次刷新（升级、整理、重新进出场景）。
##
## 刻意不使用场景树夹具：仓库控制器的跨场景依赖全部经 `_resolve_dependencies()` 解析、
## 控件引用经 `_resolve_nodes()` 建立，直接注入替身既能精确控制输入，又不必拉起整套生产
## 场景（那会连带建出 34 个格子视图，让本套件的关注点被淹没）。

## 生产仓库控制器脚本。
const WAREHOUSE_CONTROL_SCRIPT: GDScript = preload("res://scripts/warehouse/warehouse_control.gd")

## 生产仓库控制器源码路径，用于断言订阅挂在哪个生命周期函数上。
const WAREHOUSE_CONTROL_SOURCE_PATH: String = "res://scripts/warehouse/warehouse_control.gd"


## 钱包替身。
##
## 只实现界面真正用到的那两件事：读 `Gold`、广播 `GoldChanged`。界面若绕开信号去轮询余额，
## 或者伸手去拿钱包的其它接口，本套件会当场失败。
class FakeWallet extends Node:
	## 余额变化信号，签名与生产 PlayerWallet 保持一致。
	signal GoldChanged(new_gold: int)

	## 当前余额，供界面经 Object.get("Gold") 读取。
	var Gold: int = 0

	## 改写余额并广播，模拟一次真实的余额变化。
	## 参数 gold：新的余额。
	## 返回值：无。
	func SetGold(gold: int) -> void:
		Gold = gold
		GoldChanged.emit(Gold)


## 进度替身，只实现升级按钮真正会读的那四个查询。
##
## 价格刻意取 500 / 300 两个不同值：这样「余额 400」就能同时观察到「扩栏已可用、扩容仍
## 不可用」，从而证明刷新是按按钮各自判定的，而不是整体开关一次。
class FakeProgression extends Node:
	## 下一次仓库扩容的价格。
	var WarehouseNextCost: int = 500
	## 下一次带入栏扩容的价格。
	var CarryNextCost: int = 300

	## 仓库是否已满级。替身恒为未满级，否则按钮会走「已满级」分支而看不到价格判定。
	## 返回值：恒为 false。
	func IsWarehouseMaxLevel() -> bool:
		return false

	## 读取下一次仓库扩容价格。
	## 返回值：当前配置的价格。
	func GetWarehouseNextCost() -> int:
		return WarehouseNextCost

	## 带入栏是否已满级。理由同 IsWarehouseMaxLevel()。
	## 返回值：恒为 false。
	func IsCarryMaxLevel() -> bool:
		return false

	## 读取下一次带入栏扩容价格。
	## 返回值：当前配置的价格。
	func GetCarryNextCost() -> int:
		return CarryNextCost


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：仓库金币刷新契约套件名。
func suite_name() -> String:
	return "warehouse_gold_refresh_contract"


## 验证余额变化会立刻刷新金币数字。
## 返回值：无。
func test_gold_change_refreshes_the_gold_label_immediately() -> void:
	var wallet: Node = track(FakeWallet.new()) as Node
	var controller: Node = _make_controller(wallet, track(FakeProgression.new()) as Node)
	var gold_label := controller.get("_gold_label") as Label

	controller.call("_connect_wallet")

	wallet.call("SetGold", 100)
	assert_eq(gold_label.text, "金币：100", "余额变化必须立刻刷新金币数字，不能等下一次主动刷新。")

	wallet.call("SetGold", 1600)
	assert_eq(gold_label.text, "金币：1600", "余额持续变化必须持续实时刷新。")


## 验证余额变化会立刻刷新升级按钮的可用性。
##
## 按钮可用性同样由余额决定，只刷新数字会留下「钱够了但按钮还是灰的」这种半刷新状态。
## 返回值：无。
func test_gold_change_refreshes_upgrade_button_availability() -> void:
	var wallet: Node = track(FakeWallet.new()) as Node
	var controller: Node = _make_controller(wallet, track(FakeProgression.new()) as Node)
	var upgrade_warehouse := controller.get("_upgrade_warehouse_button") as Button
	var upgrade_carry := controller.get("_upgrade_carry_button") as Button

	controller.call("_connect_wallet")

	wallet.call("SetGold", 100)
	assert_true(upgrade_warehouse.disabled, "余额 100 不够 500，仓库扩容必须不可用。")
	assert_true(upgrade_carry.disabled, "余额 100 不够 300，带入栏扩容必须不可用。")

	# 400 只够带入栏：这一步同时证明刷新是按按钮各自判定的。
	wallet.call("SetGold", 400)
	assert_true(upgrade_warehouse.disabled, "余额 400 仍不够 500，仓库扩容必须保持不可用。")
	assert_false(upgrade_carry.disabled, "余额 400 已够 300，带入栏扩容必须立刻变为可用。")

	wallet.call("SetGold", 600)
	assert_false(upgrade_warehouse.disabled, "余额 600 已够 500，仓库扩容必须立刻变为可用。")
	assert_eq(upgrade_warehouse.text, "仓库扩容 500", "按钮文案必须继续显示真实价格。")


## 验证反复建立订阅不会产生重复连接。
##
## SceneManager 每次进入场景都会调用 init()，而仓库实例会被缓存复用；若订阅不做幂等判断，
## 一次余额变化就会触发多次刷新，且次数随进出场景的次数线性放大。
## 返回值：无。
func test_repeated_connect_keeps_a_single_subscription() -> void:
	var wallet: Node = track(FakeWallet.new()) as Node
	var controller: Node = _make_controller(wallet, track(FakeProgression.new()) as Node)

	controller.call("_connect_wallet")
	controller.call("_connect_wallet")
	controller.call("_connect_wallet")

	assert_eq(
		wallet.get_signal_connection_list("GoldChanged").size(),
		1,
		"重复订阅必须被幂等守卫拦下，否则一次余额变化会刷新多次。"
	)


## 验证离开仓库会解除订阅。
##
## 仓库实例被 SceneManager 缓存复用并长期驻留内存；不断开订阅，一个已经不在前台的界面会
## 继续接收钱包信号并刷新不可见的控件。
## 返回值：无。
func test_exit_disconnects_the_wallet_subscription() -> void:
	var wallet: Node = track(FakeWallet.new()) as Node
	var controller: Node = _make_controller(wallet, track(FakeProgression.new()) as Node)

	controller.call("_connect_wallet")
	assert_eq(
		wallet.get_signal_connection_list("GoldChanged").size(),
		1,
		"进入仓库必须先建立订阅。"
	)

	controller.call("exit")
	assert_eq(
		wallet.get_signal_connection_list("GoldChanged").size(),
		0,
		"离开仓库必须解除订阅。"
	)


## 验证钱包缺失时订阅与退订都退化为空操作而不崩溃。
##
## 钱包是跨语言 autoload，未装配时界面应当照常可用（金币显示 0），而不是整屏报错。
## 返回值：无。
func test_missing_wallet_is_tolerated() -> void:
	var controller: Node = _make_controller(null, track(FakeProgression.new()) as Node)

	controller.call("_connect_wallet")
	controller.call("_disconnect_wallet")
	controller.call("exit")

	var gold_label := controller.get("_gold_label") as Label
	assert_eq(gold_label.text, "", "没有钱包时不应凭空写出任何金币文本。")


## 验证订阅确实挂在「每次进入场景」的初始化路径上，并在离开时解除。
##
## 这条断言补的是行为测试够不到的一环：上面的用例都是直接调用 `_connect_wallet()` 的，
## 若有人把 `_apply_init()` 或 `exit()` 里的调用删掉，那些用例依旧全绿，而仓库会重新退回
## 「金币不刷新」。因此这里必须比对的是函数体而不是整份文件——整份文件里函数定义本身就
## 含有 `_connect_wallet()`，用整文件匹配会假通过。
## 返回值：无。
func test_lifecycle_wires_the_wallet_subscription() -> void:
	var source: String = FileAccess.get_file_as_string(WAREHOUSE_CONTROL_SOURCE_PATH)
	assert_false(source.is_empty(), "必须能读到 warehouse_control.gd。")

	var apply_init_body: String = _extract_function_body(source, "_apply_init")
	assert_false(apply_init_body.is_empty(), "必须能定位到 _apply_init() 的函数体。")
	assert_true(
		apply_init_body.contains("_connect_wallet()"),
		"_apply_init() 必须建立钱包订阅，否则缓存复用的仓库不会实时刷新金币。"
	)

	var exit_body: String = _extract_function_body(source, "exit")
	assert_false(exit_body.is_empty(), "必须能定位到 exit() 的函数体。")
	assert_true(
		exit_body.contains("_disconnect_wallet()"),
		"exit() 必须解除钱包订阅，否则离开后的仓库实例仍会接收余额信号。"
	)


## 构建一个脱离场景树的仓库控制器，并注入替身与控件引用。
##
## 刻意不把节点挂进场景树：warehouse_control 的 `_ready()` 会走完整初始化（建 34 个格子
## 视图、拉取仓库与带入栏权威），那需要整套生产场景。本套件要验证的只是
## 「订阅 → 回调 → 刷新」这条链路，因此直接注入依赖、绕开初始化。
##
## 控件作为控制器的子节点挂上，随控制器一起释放，避免测试留下游离对象。
## 参数 wallet：钱包替身；传 null 用于验证降级路径。
## 参数 progression：进度替身。
## 返回值：装配好的控制器，已登记到 track()，由套件自动释放。
func _make_controller(wallet: Node, progression: Node) -> Node:
	var controller: Node = track(WAREHOUSE_CONTROL_SCRIPT.new()) as Node

	var info_label: Label = Label.new()
	var gold_label: Label = Label.new()
	var upgrade_warehouse: Button = Button.new()
	var upgrade_carry: Button = Button.new()
	controller.add_child(info_label)
	controller.add_child(gold_label)
	controller.add_child(upgrade_warehouse)
	controller.add_child(upgrade_carry)

	controller.set("_info_label", info_label)
	controller.set("_gold_label", gold_label)
	controller.set("_upgrade_warehouse_button", upgrade_warehouse)
	controller.set("_upgrade_carry_button", upgrade_carry)
	controller.set("_wallet", wallet)
	controller.set("_progression", progression)
	return controller


## 抽取指定函数的主体源码。
##
## 判据是缩进：本项目的函数体一律比 `func` 声明多一层制表符，因此遇到下一个顶格行即结束。
## 只在函数体范围内比对，才能让「某个生命周期函数漏了某次调用」这类回归无法被函数定义
## 自身的同名文本蒙混过去。
## 参数 source：完整源码文本。
## 参数 function_name：要抽取的函数名，不含括号。
## 返回值：函数体文本；找不到该函数时返回空串。
func _extract_function_body(source: String, function_name: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var body: PackedStringArray = PackedStringArray()
	var header: String = "func %s(" % function_name
	var collecting: bool = false

	for line: String in lines:
		if not collecting:
			if line.begins_with(header):
				collecting = true
			continue

		# 顶格行意味着上一个函数已经结束；空行仍属于函数体，一并收下。
		if not line.is_empty() and not line.begins_with("\t") and not line.begins_with(" "):
			break

		body.append(line)

	return "\n".join(body)
