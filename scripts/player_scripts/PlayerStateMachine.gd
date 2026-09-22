extends Node
class_name StateMachine

@export var initial_state: State

var current_state: State = null

var states:Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.state_machine = self
			child.player = owner
	
	current_state = initial_state
	
func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)
		
func change_state(target_state_name: String) -> void:
	target_state_name = target_state_name.to_lower()
	if not states.has(target_state_name) or current_state.name.to_lower() == target_state_name:
		return
	
	if current_state:
		current_state.exit()
	current_state = states[target_state_name]
	current_state.enter()
