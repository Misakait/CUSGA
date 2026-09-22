@tool
extends McpTestSuite

## 手牌缓存失效引用清理契约套件。
##
## PlayerHand 的手牌缓存允许残留“已释放”或“已排队删除”的卡牌节点
## （弃牌动画在上一帧结束、外部提前释放节点等），因此重排与抽牌入口都必须
## 先清理这些引用，再计算布局与容量。
##
## 本套件锁定两件事：清理确实发生，且清理过程本身不产生 SCRIPT ERROR。
## McpTestRunner 会把测试期间捕获到的 SCRIPT ERROR 直接判为失败，
## 因此“把悬空实例赋给类型化变量”这类缺陷会被当场抓出来，
## 而不会像旧式 SceneTree runner 那样只留下一条运行期错误日志。

## 待验证的正式手牌脚本。
const PLAYER_HAND_SCRIPT: GDScript = preload("res://scripts/card_scripts/player_hand.gd")

## 卡牌脚本；缓存清理与布局写入都依赖它的 hand_position 字段。
const SKILL_CARD_SCRIPT: GDScript = preload("res://scripts/card_scripts/skill_card.gd")


## 只满足 SkillCard 进入场景树时注册信号依赖的最小 CardManager 替身。
class FakeCardManager extends Node2D:
	## 接收卡牌就绪时的注册请求；本套件不验证输入信号。
	## @param _card 进入测试场景树的卡牌节点。
	## @return void 无返回值。
	func connect_card_signals(_card: Node2D) -> void:
		pass


## 返回 GodotAI 使用的稳定套件名称。
## @return String 手牌缓存契约套件名。
func suite_name() -> String:
	return "player_hand_cache_contract"


## 验证已释放卡牌残留在缓存时，重排会先清掉它并继续为有效卡牌布局。
## @return void 无返回值。
func test_freed_reference_is_cleared_before_relayout() -> void:
	var player_hand: Node2D = _build_hand_harness()
	var card_manager: Node = player_hand.get_parent().get_node("CardManager")

	# 有效卡牌用于证明清理不是以“跳过整轮布局”为代价的。
	var valid_card: Node2D = _new_card(card_manager)
	var freed_card: Node2D = _new_card(card_manager)

	var hand_cards: Array = player_hand.get("player_hand_card")
	hand_cards.append(valid_card)
	hand_cards.append(freed_card)
	# free() 立即销毁节点，缓存中的引用随之变成 previously freed instance，
	# 这正是运行期报出 “Trying to assign invalid previously freed instance” 的路径。
	freed_card.free()

	player_hand.call("update_hand_positions")

	var remaining_cards: Array = player_hand.get("player_hand_card")
	assert_eq(remaining_cards.size(), 1, "手牌重排必须先清除已释放卡牌的缓存引用。")
	if remaining_cards.size() == 1:
		assert_true(remaining_cards[0] == valid_card, "手牌重排必须保留仍有效的卡牌节点。")
		# 位置断言确保修复不会退化成“遇到悬空引用就整轮跳过”。
		var expected_position: Vector2 = player_hand.call("calculate_card_position", 0)
		assert_true(
			valid_card.get("hand_position") == expected_position,
			"清理过期引用后，剩余卡牌仍必须写入正确的手牌位置。"
		)


## 验证已进入删除队列的卡牌同样会立即退出手牌缓存。
## @return void 无返回值。
func test_queued_for_deletion_reference_is_cleared() -> void:
	var player_hand: Node2D = _build_hand_harness()
	var card_manager: Node = player_hand.get_parent().get_node("CardManager")
	var queued_card: Node2D = _new_card(card_manager)

	var hand_cards: Array = player_hand.get("player_hand_card")
	hand_cards.append(queued_card)
	# queue_free 后节点在同一帧内仍可读取，但必须被视为已经失效，不能再参与布局。
	queued_card.queue_free()

	player_hand.call("update_hand_positions")

	assert_eq(
		(player_hand.get("player_hand_card") as Array).size(),
		0,
		"已排队删除的卡牌必须立即退出手牌缓存。"
	)


## 验证清理函数单独调用时也会移除失效引用。
## 抽牌入口在容量判断之前直接调用它，因此该路径需要独立锁定。
## @return void 无返回值。
func test_cleanup_entry_removes_freed_reference_directly() -> void:
	var player_hand: Node2D = _build_hand_harness()
	var card_manager: Node = player_hand.get_parent().get_node("CardManager")
	var freed_card: Node2D = _new_card(card_manager)

	var hand_cards: Array = player_hand.get("player_hand_card")
	hand_cards.append(freed_card)
	freed_card.free()

	player_hand.call("_remove_invalid_hand_cards")

	assert_eq(
		(player_hand.get("player_hand_card") as Array).size(),
		0,
		"清理入口必须直接移除已释放卡牌的缓存引用。"
	)


## 建立隔离的手牌测试环境：占位依存节点 + 正式 PlayerHand 脚本。
## @return Node2D 已进入场景树的 PlayerHand 实例。
func _build_hand_harness() -> Node2D:
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var harness: Node2D = Node2D.new()
	harness.name = "PlayerHandCacheHarness"
	track(harness)
	scene_tree.root.add_child(harness)

	# PlayerHand 的 @onready 依赖同级 CardManager、DeckManager 与 ControlLock。
	var card_manager: FakeCardManager = FakeCardManager.new()
	card_manager.name = "CardManager"
	harness.add_child(card_manager)
	var deck_placeholder: Node = Node.new()
	deck_placeholder.name = "DeckManager"
	harness.add_child(deck_placeholder)
	var control_lock_placeholder: Node = Node.new()
	control_lock_placeholder.name = "ControlLock"
	harness.add_child(control_lock_placeholder)

	# 手牌仍由正式脚本创建，覆盖真实的缓存清理与布局计算入口。
	var player_hand: Node2D = PLAYER_HAND_SCRIPT.new()
	player_hand.name = "PlayerHand"
	harness.add_child(player_hand)
	return player_hand


## 创建一张只用于手牌缓存的卡牌节点。
## 该脚本提供 hand_position 字段与可释放的节点身份，无需卡牌数据。
## @param parent 卡牌的挂载父节点。
## @return Node2D 新的手牌节点。
func _new_card(parent: Node) -> Node2D:
	var card: Node2D = SKILL_CARD_SCRIPT.new()
	parent.add_child(card)
	return card
