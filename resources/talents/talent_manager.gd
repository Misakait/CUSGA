extends CanvasLayer

## 天赋选择界面的 GDScript 管理器。
##
## 管理器继续只负责任选池、暂停界面和选择转发；TalentData、效果应用、
## 时间推进与玩家状态仍由现有 C# Resource、Player 和 TimeSystem 负责。

## 所有尚可抽取的旧 C# 或未来 GDScript TalentData Resource。
@export var AllTalentsPool: Array[Resource] = []

## 单张天赋卡的生产场景。
@export var CardScenePrefab: PackedScene

## 放置本轮天赋卡的容器。
@export var CardsContainer: HBoxContainer

## 当前尚未选择的天赋池。
var _available_talents: Array[Resource] = []

## 保持独立洗牌状态，避免改变项目其它随机序列。
var _random := RandomNumberGenerator.new()

## 当前 TimeSystem Autoload；只依赖稳定的天赋触发信号。
var _time_system: Node


## 初始化可选池并订阅原天赋选择信号。
## 返回值：无。
func _ready() -> void:
	hide()
	_available_talents.assign(AllTalentsPool)
	_random.randomize()
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
## 参数 selected_talent：卡片返回的旧 C# 或未来 GDScript TalentData。
## 返回值：无。
func OnTalentSelected(selected_talent: Resource) -> void:
	print("玩家选择了天赋：" + str(selected_talent.get("TalentName")))
	_available_talents.erase(selected_talent)
	get_node("/root/GlobalEventBus").emit_signal(&"on_player_acquired_talent", selected_talent)
	hide()
	get_tree().paused = false


## 暂停游戏并展示本轮最多三张天赋卡。
## 返回值：无。
func _pop_up_talent_selection() -> void:
	if _available_talents.is_empty():
		print("天赋已全部学完，没有可用的天赋卡了！")
		return

	get_tree().paused = true
	show()
	_draw_three_talents()


## 原地洗牌可选池，并生成本轮最多三张卡片。
## 返回值：无。
func _draw_three_talents() -> void:
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
		new_card.connect(&"OnCardClicked", OnTalentSelected)
