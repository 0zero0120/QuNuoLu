class_name PotionConfirm
extends ColorRect

signal confirmed
signal cancelled

@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var icon_rect: TextureRect = %PotionIcon
@onready var name_label: Label = %PotionName
@onready var desc_label: Label = %PotionDesc
@onready var hint_label: Label = %PotionHint

func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


## 必须在 add_child() 之后再调：@onready 那几个节点要等节点进树、_ready 跑完才有值。
## 以前这个框只写一句「确定使用药水吗？」，玩家在横条上看到一个 44px 的小图标，
## 点开还是不知道它到底干什么——介绍、名字、图一起摆进来。
func setup(potion: PotionData) -> void:
	if potion == null:
		name_label.text = "药水"
		desc_label.text = ""
		return
	name_label.text = potion.potion_name
	name_label.add_theme_color_override("font_color", potion.get_color())
	desc_label.text = potion.description
	icon_rect.texture = PotionButton.icon_for(potion)
	if potion.is_targeted:
		confirm_button.text = "选择目标"
		hint_label.text = "确认后点击一名敌人使用；再点一次药水或按 ESC 取消。"
	else:
		confirm_button.text = "确认使用"
		hint_label.text = "确认后立即使用。"


## ESC 等于点「取消」。这里**只发信号**，不自己 queue_free：这个框的生死归 RunHud 管，
## 自己删掉会让它那边记着的待用槽位留在原地。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()

func _on_confirm_pressed() -> void:
	confirmed.emit()

func _on_cancel_pressed() -> void:
	cancelled.emit()
