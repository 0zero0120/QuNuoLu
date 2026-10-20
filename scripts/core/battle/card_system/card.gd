class_name Card
extends Control

signal card_clicked(card: Card)
signal card_hovered(card: Card)
signal card_unhovered(card: Card)
signal card_drag_started(card: Card)
signal card_drag_ended(card: Card, drop_global_position: Vector2)
signal card_long_pressed(card: Card)

const LONG_PRESS_DURATION: float = 0.3
const DRAG_THRESHOLD: float = 24.0

## 被点击选中时整张牌泛的暖光。选中就是在等玩家点敌人或按确认，得一眼看得出来。
const SELECTED_TINT := Color(1.0, 0.95, 0.6)

enum CardState { IN_HAND, HOVERED, SELECTED, BEING_PLAYED, DISCARDING, EXHAUSTING }

@export var card_data: CardData
var is_playable: bool = false
var state: CardState = CardState.IN_HAND
## 被「点击选中」了没有。单独记一份，不复用 state：state 一进 SELECTED，
## _on_mouse_entered 里那句 state != CardState.IN_HAND 就会把悬停动画挡掉。
var selected: bool = false
var description_owner: Node = null
var _target_position: Vector2
var _original_scale: Vector2
var _original_parent: Control = null
var _original_z_index: int = 0
var _root_control: Control = null
var _is_dragging: bool = false
var _is_pressed: bool = false
var _press_time: float = 0.0
var _press_start_position: Vector2
var _long_press_triggered: bool = false
var _enlarged: bool = false
var _drag_offset: Vector2

@onready var cost_label: Label = %CostLabel
@onready var name_label: Label = %NameLabel
@onready var desc_label: Label = %DescLabel
@onready var type_icon: TextureRect = %TypeIcon
@onready var card_bg: ColorRect = %CardBg
@onready var rarity_glow: ColorRect = %RarityGlow
@onready var play_key_label: Label = %PlayKeyLabel
@onready var art_slot: TextureRect = %ArtSlot

func _ready() -> void:
	_original_scale = scale
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	if card_data:
		_update_display()
	call_deferred("_save_position")
	call_deferred("_find_root_control")

func _find_root_control() -> void:
	var p: Node = self
	while p and p.get_parent():
		if p.get_parent() == get_tree().root:
			_root_control = p as Control
			break
		p = p.get_parent()

func _get_root_control() -> Control:
	if _root_control == null and is_inside_tree():
		_find_root_control()
	return _root_control

func _save_position() -> void:
	_target_position = position

func setup(data: CardData) -> void:
	card_data = data
	if is_inside_tree():
		_update_display()

func _update_display() -> void:
	if card_data == null:
		return
	cost_label.text = "X" if card_data.is_x_cost() else str(card_data.get_display_cost())
	name_label.text = card_data.card_name
	# 牌名装稀有度、边框装角色归属：两个信号各占一个位置，一眼分得开是「谁的牌」和「多稀有」。
	name_label.add_theme_color_override("font_color", card_data.get_text_color())
	desc_label.text = card_data.get_description(description_owner)
	card_bg.color = card_data.get_color()
	if rarity_glow:
		rarity_glow.color = card_data.get_rarity_glow()
	var border := get_node_or_null("CardBorder") as ColorRect
	if border:
		border.color = card_data.get_character_border_color()
	if type_icon:
		var icon_name := ""
		match card_data.card_type:
			CardData.CardType.ATTACK: icon_name = "icon_attack"
			CardData.CardType.SKILL: icon_name = "icon_skill"
			CardData.CardType.ABILITY: icon_name = "icon_ability"
		if not icon_name.is_empty():
			# 国风图先上；没有才退回 IconFactory 的程序像素画（icon_name 那三条映射还在，
			# 是给没图时期的兜底，不是死代码）——同 potion_button.gd 的写法。
			var type_tex := ArtIcons.load_or_null(card_data.get_type_icon_path())
			type_icon.texture = type_tex if type_tex != null else IconFactory.get_icon(icon_name)
	_update_art()

## 卡面插画。图和卡面文字一样是「取不到就退回原样」，不是错误：现在绝大多数卡还没有插画，
## 缺图时 ArtSlot 保持隐藏，卡面跟接线之前逐像素一致。
## exists() 和 as 两道都得留着——.import 在仓库里而 .godot/imported/ 的 ctex 缺失时，
## exists() 会返 true 而 load() 返 null，只判前者就会拿到一个空白的 ArtSlot。
func _update_art() -> void:
	var path: String = card_data.get_art_path()
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	art_slot.texture = tex
	art_slot.visible = tex != null

func refresh_display(owner: Node = null) -> void:
	description_owner = owner
	_update_display()

func set_playable(can_play: bool) -> void:
	is_playable = can_play
	mouse_filter = MOUSE_FILTER_STOP if can_play else MOUSE_FILTER_PASS
	if not can_play:
		# 打不出去的牌不该还留着选中高亮——留着玩家会以为按确认还能出。
		selected = false
	_refresh_tint()


## 点击选中/取消选中。
func set_selected(on: bool) -> void:
	selected = on
	_refresh_tint()


## 三种外观，优先级从高到低：打不出去（灰）> 选中（暖光）> 正常（白）。
func _refresh_tint() -> void:
	if not is_playable:
		modulate = Color(0.5, 0.5, 0.5, 1.0)
	elif selected:
		modulate = SELECTED_TINT
	else:
		modulate = Color.WHITE


## 右上角那个快捷键角标（1~9/0）。空串就是不显示——设定页关掉「显示快速选牌按键」时用。
func set_play_key(key_text: String) -> void:
	if play_key_label == null:
		return
	play_key_label.text = key_text
	play_key_label.visible = not key_text.is_empty()

func _process(_delta: float) -> void:
	if not _is_pressed:
		return
	if not is_inside_tree():
		_is_pressed = false
		return

	var mouse_pos := get_global_mouse_position()
	var still_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if not still_pressed:
		_on_release()
		return

	if _is_dragging:
		global_position = mouse_pos + _drag_offset
		return

	if _long_press_triggered:
		return

	var dist := _press_start_position.distance_to(mouse_pos)
	if dist > DRAG_THRESHOLD:
		_start_drag()
		return

	_press_time += _delta
	if _press_time >= LONG_PRESS_DURATION:
		_trigger_long_press()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()

func _on_press() -> void:
	if not is_playable:
		return
	if state == CardState.BEING_PLAYED or state == CardState.DISCARDING or state == CardState.EXHAUSTING:
		return
	_is_pressed = true
	_press_time = 0.0
	_long_press_triggered = false
	_is_dragging = false
	_press_start_position = get_global_mouse_position()

func _on_release() -> void:
	if _enlarged:
		_dismiss_enlarged()
		_is_pressed = false
		return
	if _is_dragging:
		var drop_pos := global_position
		_end_drag()
		card_drag_ended.emit(self, drop_pos)
		_is_pressed = false
		return
	if _long_press_triggered:
		_is_pressed = false
		return
	_is_pressed = false
	if is_playable:
		card_clicked.emit(self)


func _start_drag() -> void:
	_is_dragging = true
	state = CardState.BEING_PLAYED
	_original_parent = get_parent() as Control
	_original_z_index = z_index
	_drag_offset = global_position - get_global_mouse_position()
	var saved_global := global_position
	var root := _get_root_control()
	if root and _original_parent:
		_original_parent.remove_child(self)
		root.add_child(self)
		global_position = saved_global
	z_index = 100
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _original_scale * 1.15, _dur(0.1))
	card_drag_started.emit(self)

func _end_drag() -> void:
	_is_dragging = false
	z_index = _original_z_index
	if _original_parent:
		var cur_parent := get_parent()
		if cur_parent and cur_parent != _original_parent:
			cur_parent.remove_child(self)
			_original_parent.add_child(self)
	call_deferred("_save_position")
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _original_scale, _dur(0.2))
	state = CardState.IN_HAND

func _trigger_long_press() -> void:
	_long_press_triggered = true
	_enlarged = true
	_original_parent = get_parent() as Control
	_original_z_index = z_index
	var saved_global := global_position
	var root := _get_root_control()
	if root and _original_parent:
		_original_parent.remove_child(self)
		root.add_child(self)
		global_position = saved_global
	z_index = 100
	var center := get_viewport().get_visible_rect().size / 2.0
	var target_pos := center - size * 1.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _original_scale * 2.0, _dur(0.2))
	tween.parallel().tween_property(self, "global_position", target_pos, _dur(0.2))
	card_long_pressed.emit(self)

func _dismiss_enlarged() -> void:
	_enlarged = false
	_long_press_triggered = false
	z_index = _original_z_index
	if _original_parent:
		var cur_parent := get_parent()
		if cur_parent and cur_parent != _original_parent:
			cur_parent.remove_child(self)
			_original_parent.add_child(self)
	call_deferred("_save_position")
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _original_scale, _dur(0.2))
	state = CardState.IN_HAND

func _on_mouse_entered() -> void:
	if _is_dragging or _enlarged:
		return
	if not is_playable or state != CardState.IN_HAND:
		return
	state = CardState.HOVERED
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _original_scale * 1.15, _dur(0.1))
	tween.parallel().tween_property(self, "position:y", _target_position.y - 30, _dur(0.1))
	card_hovered.emit(self)

func _on_mouse_exited() -> void:
	if _is_dragging or _enlarged:
		return
	if state != CardState.HOVERED:
		return
	state = CardState.IN_HAND
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _original_scale, _dur(0.1))
	tween.parallel().tween_property(self, "position:y", _target_position.y, _dur(0.1))
	card_unhovered.emit(self)

## 所有动画时长都过这一道，设定页开了「加速模式」就整体缩短。
func _dur(base: float) -> float:
	return base * SettingsManager.anim_scale()


func play_to_target_animation(target_position: Vector2) -> Tween:
	state = CardState.BEING_PLAYED
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", target_position, _dur(0.2))
	tween.parallel().tween_property(self, "scale", Vector2(0.01, 0.01), _dur(0.2))
	tween.finished.connect(queue_free)
	return tween

func discard_animation(discard_pos: Vector2) -> Tween:
	state = CardState.DISCARDING
	var tween := create_tween()
	tween.tween_property(self, "global_position", discard_pos, _dur(0.3))
	tween.parallel().tween_property(self, "modulate", Color(1, 1, 1, 0), _dur(0.3))
	tween.finished.connect(queue_free)
	return tween

func set_target_position(pos: Vector2) -> void:
	_target_position = pos
