extends Node
class_name DeckManager

var draw_pile: Array[SkillCardData] = []
var hand: Array[SkillCardData] = []
var discard_pile: Array[SkillCardData] = []

# 初始化牌库
func initialize_deck(starting_deck: Array[SkillCardData]):
	draw_pile = starting_deck.duplicate()
	
	# 规则：卡牌数少于 10 张，补充低级卡
	if draw_pile.size() < 10:
		fill_with_basic_cards(10 - draw_pile.size())
		
	draw_pile.shuffle()

# 抽牌
func draw_cards(amount: int):
	for i in range(amount):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				print("没有牌可以抽了！")
				break
			else:
				reshuffle_discard_into_draw()
		
		var card = draw_pile.pop_back()
		hand.append(card)
	print("抽了牌。当前手牌数：", hand.size())
	#调试打印所有卡牌
	print_all_card()

# 打出卡牌
func play_card(card: SkillCardData, target):
	if not card in hand: return
	
	# 执行卡牌效果
	card.apply_effect(target)
	
	# 从手牌移除，进入弃牌堆
	hand.erase(card)
	discard_pile.append(card)

# 丢弃所有手牌
func discard_hand():
	discard_pile.append_array(hand)
	hand.clear()
	print("回合结束，手牌已清空进入弃牌堆。")

# 洗牌逻辑
func reshuffle_discard_into_draw():
	print("抽牌堆为空，洗切弃牌堆...")
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	draw_pile.shuffle()

# 补充基础卡牌
func fill_with_basic_cards(amount: int):
	for i in range(amount):
		var basic_card = SkillCardData.new()
		basic_card.card_name = "填充卡牌测试001" # 这里最好加载你预设的基础卡 Resource
		basic_card.energy_cost = 10
		draw_pile.append(basic_card)

# 调试用print卡牌
func print_all_card():
	print_hand()
	print_draw_pile()
	print_discard_pile()

func print_hand():
	var names: Array[String] = []
	for card in hand:
		names.append(card.card_name)
	print("【手牌】(", hand.size(), "张): ", names)
	
func print_draw_pile():
	var names: Array[String] = []
	for card in draw_pile:
		names.append(card.card_name)
	print("【抽牌堆】(", draw_pile.size(), "张): ", names)
	
func print_discard_pile():
	var names: Array[String] = []
	for card in discard_pile:
		names.append(card.card_name)
	print("【弃牌堆】(", discard_pile.size(), "张): ", names)
