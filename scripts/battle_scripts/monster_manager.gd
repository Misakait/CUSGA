extends Node2D
class_name MonsterManager

@export var max_active_monsters: int = 5

@export_group("外显示与排布")
@export var monster_height: float = 150.0 ## 怪物所处的高度（Y坐标）
@export var monster_spacing: float = 200.0 ## 怪物排列的间距

var monster_scene = preload("res://scenes/monster_scenes/monster.tscn")

var upcoming_monsters: Array = []   # 待生成的怪物数据池
var active_monsters: Array = []     # 当前场上的怪物
var defeated_monsters: Array = []   # 已击败的怪物

func _ready() -> void:
	pass

# 初始化怪物池，并直接生成指定怪物
func initialize_monsters(starting_monsters_data: Array):
	upcoming_monsters = starting_monsters_data.duplicate()
	spawn_monsters()

# 生成怪物
func spawn_monsters():
	while not upcoming_monsters.is_empty():
		if active_monsters.size() >= max_active_monsters:
			print("场上怪物已满！")
			break
			
		var monster_data = upcoming_monsters.pop_front() # 从队列头取怪物
		_spawn_monster_instance(monster_data)
			
	print("生成了怪物。当前场上怪物数：", active_monsters.size())
	print_all_monsters()
	
func _process(delta: float) -> void:
	# 可选：如果需要在process里更新怪物状态或动画等可以在这里写
	pass

func _spawn_monster_instance(monster_data):
	# 实际生成怪物节点的逻辑
	var monster = monster_scene.instantiate()
	monster.BaseData = monster_data
	add_child(monster)
	active_monsters.append(monster)
	
	update_monsters_position()

# 自动排布场上的怪物
func update_monsters_position():
	var count = active_monsters.size()
	if count == 0:
		return
		
	# 自动获取当前屏幕（视口）的宽度并计算中心 X 坐标
	var center_x = get_viewport_rect().size.x / 2.0
		
	for i in range(count):
		var monster = active_monsters[i]
		
		# 自动居中对称计算公式：(当前索引 - (总数 - 1) / 2) * 间距
		var offset_x = (i - (count - 1.0) / 2.0) * monster_spacing
		var target_pos = Vector2(center_x + offset_x, monster_height)
		
		# 加入Tween动画平滑移动
		var tween = create_tween()
		tween.tween_property(monster, "position", target_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

# 怪物死亡
func on_monster_died(monster):
	# 处理怪物死亡逻辑
	into_defeated_pool(monster)

# 怪物进入已击败池
func into_defeated_pool(monster):
	if monster in active_monsters:
		active_monsters.erase(monster)
		# 假设monster有data属性
		# defeated_monsters.append(monster.data)
		print("怪物被击败")
	update_monsters_position() # 怪物死亡后重新排布队伍

# 调试打印所有怪物
func print_all_monsters():
	print_active_monsters()
	print_upcoming_monsters()
	print_defeated_monsters()

func print_active_monsters():
	var counts = active_monsters.size()
	print("【场上怪物】(", counts, "个)")

func print_upcoming_monsters():
	var counts = upcoming_monsters.size()
	print("【待生成怪物池】(", counts, "个)")

func print_defeated_monsters():
	var counts = defeated_monsters.size()
	print("【已击败怪物】(", counts, "个)")
