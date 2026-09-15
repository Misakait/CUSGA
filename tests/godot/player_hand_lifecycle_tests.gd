extends SceneTree

const PLAYER_HAND_SCRIPT := preload("res://scripts/card_scripts/player_hand.gd")
const SKILL_CARD_SCENE := preload("res://scenes/skill_card_scenes/SkillCard.tscn")

# 累积断言失败信息，使节点释放与后续重排能在同一次运行中完整报告。
var _failures: Array[String] = []


# 最小化 CardManager 替身，只满足 SkillCard 进入树时注册信号的依赖。
class TestCardManager extends Node2D:
	## 接收卡牌就绪时的注册请求；本回归测试不需要实际输入信号。
	## @param _card 进入测试场景树的卡牌节点。
	## @return void 无返回值。
	func connect_card_signals(_card: Node2D) -> void:
		pass


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_layout_discards_freed_card_reference()
	_finish()


## 验证已释放卡牌残留在缓存时，下一次手牌重排会先清理它而不是写入其位置属性。
## @return void 无返回值。
func _test_layout_discards_freed_card_reference() -> void:
	# 独立根节点隔离正式战斗场景，避免测试依赖任何回合状态。
	var test_root: Node2D = Node2D.new()
	test_root.name = "PlayerHandLifecycleHarness"
	root.add_child(test_root)

	# SkillCard 需要同级 CardManager 提供信号注册接口才能完成正式的 _ready 生命周期。
	var card_manager: TestCardManager = TestCardManager.new()
	card_manager.name = "CardManager"
	test_root.add_child(card_manager)
	# PlayerHand 的正式场景依赖同级 DeckManager，此处仅提供路径占位且不参与测试逻辑。
	var deck_manager_placeholder: Node = Node.new()
	deck_manager_placeholder.name = "DeckManager"
	test_root.add_child(deck_manager_placeholder)
	# PlayerHand 的正式场景依赖同级 ControlLock，此处仅提供路径占位且不参与测试逻辑。
	var control_lock_placeholder: Node = Node.new()
	control_lock_placeholder.name = "ControlLock"
	test_root.add_child(control_lock_placeholder)

	# PlayerHand 依旧从正式脚本创建，以覆盖真实的缓存清理和位置计算入口。
	var player_hand: Node2D = PLAYER_HAND_SCRIPT.new()
	player_hand.name = "PlayerHand"
	test_root.add_child(player_hand)

	# 有效卡牌用于确认清理过期引用后仍会正常获得新的手牌位置。
	var valid_card: SkillCard = SKILL_CARD_SCENE.instantiate() as SkillCard
	card_manager.add_child(valid_card)
	# 过期卡牌模拟弃牌动画完成后，外部缓存尚未同步移除的引用。
	var freed_card: SkillCard = SKILL_CARD_SCENE.instantiate() as SkillCard
	card_manager.add_child(freed_card)
	await process_frame

	# 缓存数组是 PlayerHand 的公开运行时状态，测试直接注入两张卡牌以构造释放边界。
	var hand_cards: Array = player_hand.get("player_hand_card")
	hand_cards.append(valid_card)
	hand_cards.append(freed_card)
	freed_card.queue_free()
	await process_frame

	player_hand.call("update_hand_positions")
	# 重排后的缓存只能保留仍有效的卡牌节点。
	var remaining_cards: Array = player_hand.get("player_hand_card")
	_assert(remaining_cards.size() == 1, "手牌重排应清理已释放卡牌的缓存引用。")
	if remaining_cards.size() == 1:
		_assert(remaining_cards[0] == valid_card, "手牌重排应保留仍有效的卡牌节点。")
		# 位置断言确保修复不会以跳过整个布局为代价。
		var expected_position: Vector2 = player_hand.call("calculate_card_position", 0)
		_assert(valid_card.hand_position == expected_position, "清理过期引用后，剩余卡牌仍应写入正确的手牌位置。")

	test_root.queue_free()
	await process_frame


## 记录失败断言，保证全部检查完成后再以退出码通知测试运行器。
## @param condition 断言条件。
## @param message 断言失败时输出的说明。
## @return void 无返回值。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 根据累计断言结果结束测试进程。
## @return void 无返回值。
func _finish() -> void:
	if _failures.is_empty():
		print("All player hand lifecycle Godot tests passed.")
		quit(0)
		return

	for failure: String in _failures:
		push_error(failure)
	quit(1)
