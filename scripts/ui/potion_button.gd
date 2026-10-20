class_name PotionButton
extends Control

signal potion_clicked(slot_index: int)

var slot_index: int = -1
var potion_data: PotionData = null
var is_empty: bool = true
var is_active: bool = true

@onready var icon: TextureRect = $Icon
@onready var bg: ColorRect = $Bg

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh_display()

func setup(index: int, potion: PotionData = null) -> void:
	slot_index = index
	potion_data = potion
	is_empty = (potion == null)
	mouse_filter = Control.MOUSE_FILTER_STOP if not is_empty else Control.MOUSE_FILTER_IGNORE
	refresh_display()

## 图标按 effect_type 认，不按 potion_id：新药水只要用的是现成效果就自动有图，
## 加一种新效果才需要在这里补一行 + IconFactory 补一个图案。
const ICON_BY_EFFECT: Dictionary = {
	"heal": "icon_health_potion",
	"gain_strength": "icon_strength_potion",
	"gain_dexterity": "icon_dexterity_potion",
	"gain_block": "icon_block_potion",
	"gain_energy": "icon_energy_potion",
	"deal_damage_all": "icon_explosive_potion",
	"deal_damage_single": "icon_throw_potion",
	"gain_gold": "icon_gold_potion",
	"apply_poison": "icon_venom_potion",
	"apply_burn": "icon_ember_potion",
	"apply_weak": "icon_weak_potion",
	"apply_vulnerable": "icon_ruin_potion",
	"draw_cards": "icon_insight_potion",
}
## 有几种效果被不止一瓶用（heal 三瓶、gain_block/gain_strength/deal_damage_all 各两瓶），
## 同效果的兄弟瓶只看调色是分不清的，这几瓶在这里按 potion_id 点名换图案。
## 点名的这瓶走自己的图，没点名的照旧走 effect_type 映射。
const ICON_BY_ID: Dictionary = {
	"mend_potion": "icon_mend_potion",
	"phoenix_potion": "icon_phoenix_potion",
	"boulder_potion": "icon_boulder_potion",
	"rage_potion": "icon_rage_potion",
	"annihilation_potion": "icon_annihilation_potion",
	"frost_needle_potion": "icon_frost_needle_potion",
	"plague_flask": "icon_plague_flask",
	"doom_flask": "icon_doom_flask",
	"inferno_flask": "icon_inferno_flask",
	"titan_potion": "icon_titan_potion",
	"aegis_potion": "icon_aegis_potion",
}
## 效果类型拼错了也别留空图标——一个看不太出所以然的瓶子好过两个看起来一模一样的空槽。
const FALLBACK_ICON: String = "icon_potion"

## 界面和测试都得按同一套规则算图案名，各写一份的话改一处忘一处就会让两边的认知分家。
static func icon_name_for(potion: PotionData) -> String:
	if potion == null:
		return ""
	if ICON_BY_ID.has(potion.potion_id):
		return str(ICON_BY_ID[potion.potion_id])
	return str(ICON_BY_EFFECT.get(potion.effect_type, FALLBACK_ICON))

func _get_icon_name() -> String:
	return icon_name_for(potion_data)


## 横条的小槽和确认框的大图走同一条取图规则：先国风图，没有再退回程序像素画。
## 两边各写一份的话，以后补了新图或者新效果，总有一边还停在旧图案上。
static func icon_for(potion: PotionData) -> Texture2D:
	if potion == null:
		return null
	var tex := ArtIcons.load_or_null(potion.get_icon_path())
	if tex == null:
		tex = IconFactory.get_icon(icon_name_for(potion))
	return tex

func refresh_display() -> void:
	if not bg:
		return
	if is_empty:
		bg.color = Color(0.2, 0.2, 0.2, 0.4)
		icon.texture = null
		tooltip_text = "空药水槽"
	else:
		bg.color = Color(0.3, 0.4, 0.6, 0.7)
		tooltip_text = "%s\n%s" % [potion_data.potion_name, potion_data.description]
		if icon:
			# 国风图先上；没有才退回 IconFactory 的程序像素画（icon_name_for 那套映射还在，
			# 是给没图时期的兜底，不是死代码）。
			icon.texture = icon_for(potion_data)

func set_active(active: bool) -> void:
	is_active = active
	modulate = Color.WHITE if active else Color(0.5, 0.5, 0.5, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP if active and not is_empty else Control.MOUSE_FILTER_IGNORE

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not is_empty and is_active:
			potion_clicked.emit(slot_index)

func _on_mouse_entered() -> void:
	if not is_empty and is_active and bg:
		bg.color = Color(0.5, 0.6, 0.9, 0.8)

func _on_mouse_exited() -> void:
	if not bg:
		return
	if is_empty:
		bg.color = Color(0.2, 0.2, 0.2, 0.4)
	else:
		bg.color = Color(0.3, 0.4, 0.6, 0.7)
