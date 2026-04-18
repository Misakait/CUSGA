## 牌库管理器 (DeckManager)
## 负责管理玩家的抽牌堆、弃牌堆以及在战斗中的抽牌/洗牌/弃牌流转。
## 同时在玩家拖动卡牌时，将“打出卡牌”行为装载为 Action 发送给战斗状态机。
extends Node
class_name DeckManager

@onready var player_hand = $"../PlayerHand"
@onready var control_lock = $"../ControlLock"

var draw_pile_data: Array[SkillCardData] = []     ## 当前战斗的抽牌堆（只存数据不存节点）
var discard_pile_data: Array[SkillCardData] = []  ## 当前战斗的弃牌堆
var min_start_cards_count:int = 20 ## 最少卡牌数量，低于该值会被填充基础卡牌

#region 动画部分
@export_group("动画部分")
@export var draw_interval:float = 0.2 ##摸牌动画间隔
#endregion

func _ready() -> void:
	pass

## 战斗开始时初始化牌库
func initialize_deck(starting_deck_data: Array[SkillCardData]):
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

## 处理从手牌中拖出打出的牌（由 CardManager 触发）
## 将打出该卡牌的行为打包为一条 Action 放进 BattleManager 的待执行队列 (action_queue)
func play_card(card: Node2D, target = null):
	# 将卡牌行动加入行动队列
	var source = $"../PlayerManager"
	var targets = []
	if target:
		targets.append(target)

	# 实例化行动封装。因为卡牌不应该在这里立即产生效果，而是要排队（也许会接在敌人的行动后面，或等待前一个动画结束）。
	var action = Action.new(source, targets, card.data, "", "CARD")

	# 推送给主状态机
	var battle_manager = get_parent()
	if battle_manager.has_method("enqueue_action"):
		battle_manager.enqueue_action(action)
	else:
		# 容错：如果找不到对应方法直接执行旧版逻辑
		card.use(target)

	# 从手牌中物理移除该节点，并将其数据丢入弃牌堆
	into_discard_pile(card)

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
	for i in range(amount):
		var basic_card = SkillCardData.new()
		basic_card.CardName = "填充卡牌测试001"
		basic_card.cost = 10
		draw_pile_data.append(basic_card)

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
