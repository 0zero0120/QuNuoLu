class_name EnergySystem
extends RefCounted

var current_energy: int = 0
var max_energy: int = 3
var permanent_energy: int = 0

func _init(p_max_energy: int = 3) -> void:
	max_energy = p_max_energy

func reset(base_energy: int = -1) -> void:
	if base_energy >= 0:
		max_energy = base_energy
	current_energy = max_energy + permanent_energy
	EventBus.energy_changed.emit(current_energy, max_energy + permanent_energy)

func can_spend(amount: int) -> bool:
	return current_energy >= amount

func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if current_energy < amount:
		return false
	current_energy -= amount
	EventBus.energy_changed.emit(current_energy, max_energy + permanent_energy)
	return true

func add(amount: int) -> void:
	current_energy += amount
	EventBus.energy_changed.emit(current_energy, max_energy + permanent_energy)

func add_permanent(amount: int) -> void:
	permanent_energy += amount

func get_current() -> int:
	return current_energy

func get_max() -> int:
	return max_energy + permanent_energy
