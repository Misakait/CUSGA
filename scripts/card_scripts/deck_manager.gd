extends Node
class_name DeckManager

@onready var player_hand = $"../PlayerHand"
@onready var control_lock = $"../ControlLock"

var draw_pile_data: Array[SkillCardData] = []
var discard_pile_data: Array[SkillCardData] = []
var min_start_cards_count:int = 20 #最少卡牌数量，低于该值会被填充基础卡牌

#region 动画部分
@export_group("动画部分")
@export var draw_interval:float = 0.2 ##摸牌动画间隔
#endregion

func _ready() -> void:
	pass

# 初始化牌库
func initialize_deck(starting_deck_data: Array[SkillCardData]):
	draw_pile_data = starting_deck_data.duplicate()
	
	# 规则：卡牌数少于 x 张，补充低级卡
	if draw_pile_data.size() < min_start_cards_count:
		fill_with_basic_cards(min_start_cards_count - draw_pile_data.size())
		
	draw_pile_data.shuffle()

# 抽牌
func draw_cards(amount: int,need_draw_interval:bool = true):
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

# 打出卡牌
func play_card(card: Node2D, target = null):
	# 执行卡牌效果
	card.use(target)
	
	# 从手牌移除，进入弃牌堆
	into_discard_pile(card)

# 丢弃所有手牌
func discard_hand():
	for card in player_hand.player_hand_card.duplicate():
		discard(card)
	print("回合结束，手牌已清空进入弃牌堆。")
	print_all_card()

# 洗牌逻辑
func reshuffle_discard_into_draw():
	print("抽牌堆为空，洗切弃牌堆...")
	draw_pile_data = discard_pile_data.duplicate()
	discard_pile_data.clear()
	draw_pile_data.shuffle()

# 补充基础卡牌
func fill_with_basic_cards(amount: int):
	for i in range(amount):
		var basic_card = SkillCardData.new()
		basic_card.name = "填充卡牌测试001" # 这里最好加载你预设的基础卡 Resource
		basic_card.cost = 10
		draw_pile_data.append(basic_card)

# 调试用print卡牌
func print_all_card():
	print_hand()
	print_draw_pile()
	print_discard_pile()

func print_hand():
	var names: Array[String] = []
	for card in player_hand.player_hand_card:
		names.append(card.data.name)
	print("【手牌】(", player_hand.player_hand_card.size(), "张): ", names)
	
func print_draw_pile():
	var names: Array[String] = []
	for card in draw_pile_data:
		names.append(card.name)
	print("【抽牌堆】(", draw_pile_data.size(), "张): ", names)
	
func print_discard_pile():
	var names: Array[String] = []
	for card in discard_pile_data:
		names.append(card.name)
	print("【弃牌堆】(", discard_pile_data.size(), "张): ", names)

func discard(card):
	print(card.data.name,"被弃置")
	discard_pile_data.append(card.data)
	player_hand.remove_card_from_hand(card)
	
func into_discard_pile(card):
	print(card.data.name,"进入弃牌堆")
	discard_pile_data.append(card.data)
	player_hand.remove_card_from_hand(card)
