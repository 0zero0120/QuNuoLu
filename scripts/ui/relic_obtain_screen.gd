extends ColorRect

@onready var icon_slot: CenterContainer = $Panel/VBox/IconSlot
@onready var name_label: Label = $Panel/VBox/RelicNameLabel
@onready var desc_label: Label = $Panel/VBox/RelicDescLabel
@onready var confirm_button: Button = $Panel/VBox/ConfirmButton

const ICON_SIZE: float = 96.0

## 调用方是「先 setup 再 add_child」（shop_screen 就这个顺序），那时候 @onready 还是 null。
## 所以 setup 只把数据收下，真正往标签上写放到 _apply()，入树后由 _ready 补一次。
var _relic: RelicData = null

func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm)
	_apply()

func setup(relic: RelicData) -> void:
	if relic == null:
		return
	_relic = relic
	if is_node_ready():
		_apply()

func _apply() -> void:
	if _relic == null:
		return
	name_label.text = _relic.relic_name
	desc_label.text = _relic.description
	# _apply() 会被 _ready 与 setup 各调一次，先清空再插，免得叠出两个图标。
	for child in icon_slot.get_children():
		icon_slot.remove_child(child)
		child.queue_free()
	icon_slot.add_child(CodexIcon.make_relic_slot(_relic, ICON_SIZE))

func _on_confirm() -> void:
	queue_free()
