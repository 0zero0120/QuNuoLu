class_name State
extends Node

var state_machine: StateMachine
var state_name: String = ""

func enter(_data: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func handle_input(_event: InputEvent) -> void:
	pass
