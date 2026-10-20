class_name CardTargeting
extends Control

signal target_selected(target: Node)
signal targeting_cancelled

var _valid_targets: Array[Node] = []
var _arrow_points: Array[Vector2] = []
var _is_targeting: bool = false
var _card: Card = null

@export var arrow_color: Color = Color(1, 0.3, 0.3, 0.8)
@export var arrow_width: float = 3.0

func start_targeting(card: Card, valid_targets: Array[Node]) -> void:
	_card = card
	_valid_targets = valid_targets
	_is_targeting = true
	show()

func cancel_targeting() -> void:
	_is_targeting = false
	_card = null
	_valid_targets.clear()
	_queue_draw_arrow()
	targeting_cancelled.emit()
	hide()

func _draw() -> void:
	if not _is_targeting or _card == null:
		return
	var from_pos := _card.global_position + _card.size / 2
	var mouse_pos := get_global_mouse_position()
	draw_line(from_pos, mouse_pos, arrow_color, arrow_width)

func _process(_delta: float) -> void:
	if _is_targeting:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not _is_targeting:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos := get_global_mouse_position()
		for target in _valid_targets:
			var target_rect := Rect2(target.global_position, target.size)
			if target_rect.has_point(mouse_pos):
				target_selected.emit(target)
				_is_targeting = false
				hide()
				return
	if event.is_action_pressed("ui_cancel"):
		cancel_targeting()

func _queue_draw_arrow() -> void:
	queue_redraw()
