extends Node2D

var max_energy: int = 100
var energy: int = 100
var max_hp: int = 100
var hp:int = 100

func _ready() -> void:
	refresh_energy()
	refresh_hp()

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
	$"../UI/Energy".text = "能量："+str(energy)+"/"+str(max_energy)
	
func refresh_hp():
	$"../UI/Hp".text = "血量："+str(hp)+"/"+str(max_hp)
