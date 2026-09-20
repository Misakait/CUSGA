## 牌库管理器 (DeckManager)
## 负责管理玩家的抽牌堆、弃牌堆以及在战斗中的抽牌/洗牌/弃牌流转。
## 同时在玩家拖动卡牌时，将“打出卡牌”行为装载为 Action 发送给战斗状态机。
extends Node
class_name DeckManager

@onready var player_hand = $"../PlayerHand"
@onready var control_lock = $"../ControlLock"

var draw_pile_data: Array[Resource] = []     ## 当前战斗的抽牌堆（只存技能卡 Resource，不存节点）
var discard_pile_data: Array[Resource] = []  ## 当前战斗的弃牌堆
var min_start_cards_count:int = 20 ## 最少卡牌数量，低于该值会被填充基础卡牌

const BASIC_CARD_PATHS := [
	"res://resources/skill_cards/metal_phys_jinji.tres",
	"res://resources/skill_cards/wood_phys_muji.tres",
	"res://resources/skill_cards/water_phys_shuiji.tres",
	"res://resources/skill_cards/fire_phys_huoji.tres",
	"res://resources/skill_cards/earth_phys_tuji.tres",
	"res://resources/skill_cards/metal_magic_jinshu.tres",
	"res://resources/skill_cards/wood_magic_mushu.tres",
	"res://resources/skill_cards/water_magic_shuishu.tres",
	"res://resources/skill_cards/fire_magic_huoshu.tres",
	"res://resources/skill_cards/earth_magic_tushu.tres",
]

# 已结算出牌卡牌的节点元数据键。
# 同一张展示节点只能在行动完成出口写入一次弃牌堆，防止重复入堆与重复销毁。
const PLAYED_CARD_FINALIZED_METADATA_KEY: StringName = &"deck_manager_played_card_finalized"

var _basic_card_pool: Array[Resource] = []
var _rng := RandomNumberGenerator.new()

#region 动画部分
@export_group("动画部分")
@export var draw_interval:float = 0.2 ##摸牌动画间隔
#endregion

func _ready() -> void:
	_rng.randomize()

## 战斗开始时初始化牌库
func initialize_deck(starting_deck_data: Array[Resource]):
	draw_pile_data = starting_deck_data.duplicate()

	# 规则：卡牌太少，补充低级卡
	if draw_pile_data.size() < min_start_cards_count:
		fill_with_basic_cards(min_start_cards_count - draw_pile_data.size())

	draw_pile_data.shuffle()

func draw_cards(amount: int, need_draw_interval: bool = true):
	control_lock.lock()

	for i in range(amount):
		if draw_pile_data.is_empty():
			if discard_pile_data.is_empty():
				print("没有牌可以抽了！")
				break
			else:
				reshuffle_discard_into_draw()

		var card_data = draw_pile_data.back()

		if player_hand.draw_card_data(card_data):
			draw_pile_data.pop_back()

		if need_draw_interval:
			await get_tree().create_timer(draw_interval).timeout

	print("抽了牌。当前手牌数：", player_hand.player_hand_card.size())
	#调试打印所有卡牌
	print_all_card()
	control_lock.unlock()

## 处理从手牌中打出的卡牌（由 CardManager 触发）。
## 卡牌节点会先脱离手牌布局、保留给行动队列表现，直到结算完成才写入弃牌堆并渐隐。
## @param card 需要施放的手牌节点。
## @param target 可选的显式目标节点。
## @return void 无返回值。
func play_card(card: Node2D, target = null) -> void:
	if not is_instance_valid(card):
		return

	# 将卡牌行动加入行动队列
	var source = $"../PlayerManager"
	var targets = []
	if target:
		targets.append(target)

	# 玩家卡牌的展示节点随 Action 一起保存，确保飞行期间不会被手牌移除逻辑提前销毁。
	var action = Action.new(source, targets, card.data, "", "CARD", card)

	# 先从手牌数据与布局中移除，但不播放弃牌动画；最终弃牌只能由行动完成出口触发。
	player_hand.remove_card_from_hand(card, false)

	# 推送给主状态机
	var battle_manager = get_parent()
	if battle_manager.has_method("enqueue_action"):
		battle_manager.enqueue_action(action)
	else:
		# 容错：如果找不到对应方法直接执行旧版逻辑
		card.use(target)
		complete_played_card(card)

## 播放一次已施放卡牌的最终弃牌表现，并将其数据写入弃牌堆。
## 只有 BattleManager 在行动表现与效果结算后调用此方法，保证节点不会过早销毁。
## @param card 已从手牌布局移除、等待收尾的展示卡牌节点。
## @return void 无返回值。
func complete_played_card(card: Node2D) -> void:
	if not is_instance_valid(card):
		return
	if card.get_meta(PLAYED_CARD_FINALIZED_METADATA_KEY, false):
		return

	# 元数据在写入牌堆前设置，确保同一帧内的重复调用也不会造成双重弃牌。
	card.set_meta(PLAYED_CARD_FINALIZED_METADATA_KEY, true)
	if card.data:
		print(card.data.CardName,"进入弃牌堆")
		discard_pile_data.append(card.data)
	else:
		push_warning("已施放卡牌缺少数据，跳过弃牌堆写入。")

	await player_hand.play_discard_animation(card)

## 将一张展示卡牌飞向仍存活的敌人。
## 飞行动画集中复用 CardAnimations，避免在行动调度层复制时长与缓动参数。
## @param card 需要飞行的展示卡牌节点。
## @param target 作为飞行终点的怪物节点。
## @return void 无返回值。
func play_card_to_enemy(card: Node2D, target: Node2D) -> void:
	if not is_instance_valid(card) or not is_instance_valid(target) or target.is_queued_for_deletion():
		return

	await CardAnimations.play_card(card, target.global_position).finished

## 播放敌人命中反馈。
## 优先使用目标贴图的闪白与目标节点抖动；没有贴图时仍保留节点抖动作为可靠反馈。
## @param target 命中的怪物节点。
## @return void 无返回值。
func play_enemy_hit_feedback(target: Node2D) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return

	# 怪物场景的可视主体；可选查找使未来的特殊怪物节点仍能安全播放抖动。
	var target_sprite: Sprite2D = target.get_node_or_null("Sprite2D") as Sprite2D
	if target_sprite:
		await CardAnimations.hit(target, target_sprite)
	else:
		await CardAnimations.shake_x(target).finished

## 回合结束时丢弃所有手牌
func discard_hand():
	for card in player_hand.player_hand_card.duplicate():
		discard(card)
	print("回合结束，手牌已清空进入弃牌堆。")
	print_all_card()

## 将弃牌堆的数据复制回抽牌堆，打乱顺序，并清空弃牌堆（俗称洗牌）
func reshuffle_discard_into_draw():
	print("抽牌堆为空，洗切弃牌堆...")
	draw_pile_data = discard_pile_data.duplicate()
	discard_pile_data.clear()
	draw_pile_data.shuffle()

## 补充基础卡牌
func fill_with_basic_cards(amount: int):
	var basic_cards = _get_basic_card_pool()
	if basic_cards.is_empty():
		push_warning("基础卡牌池为空，无法填充起始牌库。")
		return

	for i in range(amount):
		var index = _rng.randi_range(0, basic_cards.size() - 1)
		draw_pile_data.append(basic_cards[index])

func _get_basic_card_pool() -> Array[Resource]:
	if _basic_card_pool.is_empty():
		for path in BASIC_CARD_PATHS:
			var card := load(path) as Resource
			if card != null and card.has_method("ApplyEffect"):
				_basic_card_pool.append(card)
			else:
				push_warning("无法加载基础卡牌资源：" + path)
	return _basic_card_pool

## 调试与控制台日志打印，能够清晰看出场上三种牌堆的变化
func print_all_card():
	print_hand()
	print_draw_pile()
	print_discard_pile()

func print_hand():
	var names: Array[String] = []
	for card in player_hand.player_hand_card:
		names.append(card.data.CardName)
	print("【手牌】(", player_hand.player_hand_card.size(), "张): ", names)

func print_draw_pile():
	var names: Array[String] = []
	for card in draw_pile_data:
		names.append(card.CardName)
	print("【抽牌堆】(", draw_pile_data.size(), "张): ", names)

func print_discard_pile():
	var names: Array[String] = []
	for card in discard_pile_data:
		names.append(card.CardName)
	print("【弃牌堆】(", discard_pile_data.size(), "张): ", names)

func discard(card):
	print(card.data.CardName,"被弃置")
	discard_pile_data.append(card.data)
	player_hand.remove_card_from_hand(card)

func into_discard_pile(card):
	print(card.data.CardName,"进入弃牌堆")
	discard_pile_data.append(card.data)
	player_hand.remove_card_from_hand(card)
