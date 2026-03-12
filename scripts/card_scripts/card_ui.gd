extends Control
class_name CardUI

# 获取 UI 节点的引用
@onready var name_label = $NameLabel
@onready var cost_label = $CostLabel
@onready var desc_label = $DescLabel

# 保存当前UI对应的卡牌数据
var card_data: CardData

# 这个函数由外部调用，用来把数据“装载”到 UI 上
func setup(data: CardData):
	card_data = data
	
	# 刷新UI显示
	name_label.text = card_data.card_name
	cost_label.text = str(card_data.energy_cost) # 能量是数字，转成字符串
	
	# 生成描述（你可以根据实际情况优化）
	var desc_text = ""
	if card_data.description != "":
		desc_text += card_data.description
		
	desc_label.text = desc_text
