class_name CodexIcon
extends RefCounted

## 百科大全的图标槽与挂锁，卡牌总览 / 遗物收集 / 药水研究所共用。
## 有美术资源就画 icon_texture，没有就画底色 + 首字占位；
## 玩家还没遇见过的条目一律画挂锁。

const SLOT_BG := Color(0.11, 0.11, 0.17, 1.0)
const LOCK_BG := Color(0.16, 0.16, 0.22, 1.0)
const LOCK_METAL := Color(0.42, 0.42, 0.50, 1.0)
const LOCK_BODY := Color(0.30, 0.30, 0.38, 1.0)


## 遗物图标槽：图走 ArtIcons 探路，缺图退回「底色 + 名首字」。
## 首字口径与百科编目一致（codex_grid_page.gd 的 _make_entry：name.substr(0,1)，空名给 "?"）。
static func make_relic_slot(relic: RelicData, box_size: float) -> Control:
	var name_text := relic.relic_name if relic != null else ""
	var letter := name_text.substr(0, 1) if not name_text.is_empty() else "?"
	var tint: Color = relic.get_color() if relic != null else Color(0.5, 0.5, 0.5)
	var tex: Texture2D = ArtIcons.load_or_null(relic.get_icon_path()) if relic != null else null
	return make_slot(tex, letter, tint, true, box_size)


## 图标槽。known 为 false 时画挂锁并忽略 icon/fallback_text。
## tint 管槽边框；槽里那个首字另给一份 letter_color（卡牌上「边框=角色、字=稀有度」就靠它分开），
## 不传（透明）就沿用 tint——遗物/药水/敌人/成就那几处都是一个颜色到底。
static func make_slot(icon: Texture2D, fallback_text: String, tint: Color,
		known: bool, box_size: float, letter_color: Color = Color(0, 0, 0, 0)) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(box_size, box_size)
	holder.add_theme_stylebox_override("panel", _round_box(LOCK_BG if not known else SLOT_BG,
		tint if known else LOCK_METAL, 2))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not known:
		holder.add_child(_make_lock(box_size))
		return holder

	if icon != null:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.anchors_preset = Control.PRESET_FULL_RECT
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		rect.offset_left = 6.0
		rect.offset_top = 6.0
		rect.offset_right = -6.0
		rect.offset_bottom = -6.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
		return holder

	var letter := Label.new()
	letter.text = fallback_text
	letter.anchors_preset = Control.PRESET_FULL_RECT
	letter.anchor_right = 1.0
	letter.anchor_bottom = 1.0
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", int(box_size * 0.44))
	letter.add_theme_color_override("font_color", letter_color if letter_color.a > 0.0 else tint)
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(letter)
	return holder


## 挂锁：上面一个开口向下的锁梁，下面一个锁体。
static func _make_lock(box_size: float) -> Control:
	var lock := VBoxContainer.new()
	lock.anchors_preset = Control.PRESET_CENTER
	lock.anchor_left = 0.5
	lock.anchor_top = 0.5
	lock.anchor_right = 0.5
	lock.anchor_bottom = 0.5
	lock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lock.grow_vertical = Control.GROW_DIRECTION_BOTH
	lock.alignment = BoxContainer.ALIGNMENT_CENTER
	lock.add_theme_constant_override("separation", 0)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shackle_h := box_size * 0.22
	var shackle := Panel.new()
	shackle.custom_minimum_size = Vector2(box_size * 0.36, shackle_h)
	var shackle_box := StyleBoxFlat.new()
	shackle_box.bg_color = Color(0, 0, 0, 0)
	shackle_box.border_color = LOCK_METAL
	shackle_box.set_border_width_all(maxi(2, int(box_size * 0.05)))
	shackle_box.set_corner_radius_all(int(box_size * 0.18))
	shackle_box.corner_radius_bottom_left = 0
	shackle_box.corner_radius_bottom_right = 0
	shackle.add_theme_stylebox_override("panel", shackle_box)
	shackle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.add_child(shackle)

	var body := Panel.new()
	body.custom_minimum_size = Vector2(box_size * 0.52, box_size * 0.38)
	body.add_theme_stylebox_override("panel", _round_box(LOCK_BODY, LOCK_METAL, 2))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.add_child(body)

	return lock


static func _round_box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(6)
	return box
