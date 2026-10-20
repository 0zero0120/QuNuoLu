class_name StateMachine
extends Node

var states: Dictionary = {}
var current_state: State = null

func add_state(name: String, state: State) -> void:
	state.state_name = name
	state.state_machine = self
	add_child(state)
	states[name] = state

func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if not states.has(state_name):
		push_error("StateMachine: unknown state: " + state_name)
		return
	if current_state:
		current_state.exit()
	current_state = states[state_name]
	current_state.enter(data)

func start(initial: String, data: Dictionary = {}) -> void:
	transition_to(initial, data)

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func get_current_state_name() -> String:
	if current_state:
		return current_state.state_name
	return ""
