extends Node
class_name State

var state_machine: StateMachine= null
var player: CharacterBody2D = null

func enter() -> void:
	pass
	
func exit() -> void:
	pass
	
func physics_update(_delta: float) -> void:
	pass

func transition_to(target_state_name : String) -> void:
	state_machine.change_state(target_state_name)
