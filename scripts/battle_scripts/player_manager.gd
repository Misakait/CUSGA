extends Node2D

var max_energy: int = 100
var energy: int = 100

var max_hp: int = 100
var hp:int = 100

## 速度越高，计算出的行动值 (action_value) 越低，在 ATB 机制下就能更快获得回合。
var speed: float = 100.0

## 玩家的行动值（决定回合顺序的内部计量尺）。
## BattleManager 每次会在 CALCULATE_TURN 中将全体人员的 action_value 逐步扣除，谁先归零谁先行动。
var action_value: float = 0.0

func _ready() -> void:
	refresh_energy()
	refresh_hp()
	reset_action_value()

## 回合开始时被 BattleManager 调用，用于重置该实体的行动条
func reset_action_value() -> void:
	# 核心公式：10000 / 速度
	action_value = 10000.0 / speed

func recover_hp(amount:int):
	hp = min(hp + amount, max_hp)
	refresh_hp()

func take_damage(amount:int):
	hp = max(hp - amount, 0)
	refresh_hp()

func lose_hp(amount:int):
	hp = max(hp - amount, 0)
	refresh_hp()

func recover_energy(amount:int):
	energy = min(energy + amount, max_energy)
	refresh_energy()

func consume_energy(amount:int):
	energy = max(energy - amount, 0)
	refresh_energy()

func refresh_energy():
	var bar = $"../UI/EnergyBar"
	bar.max_value = max_energy
	bar.value = energy
	$"../UI/EnergyBar/EnergyText".text = str(energy) + "/" + str(max_energy)

func refresh_hp():
	var bar = $"../UI/HpBar"
	bar.max_value = max_hp
	bar.value = hp
	$"../UI/HpBar/HpText".text = str(hp) + "/" + str(max_hp)
